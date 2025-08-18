# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require_relative "../tool"

module RAAF
  class Tool
    # Base class for API-based tools
    #
    # Provides HTTP helper methods and common patterns for tools that
    # interact with external APIs. Includes retry logic, error handling,
    # and API key management.
    #
    # @example Basic API tool
    #   class WeatherTool < RAAF::Tool::API
    #     endpoint "https://api.weather.com/v1"
    #     api_key_env "WEATHER_API_KEY"
    #     
    #     def call(city:)
    #       get("/weather", params: { q: city })
    #     end
    #   end
    #
    class API < Tool
      class RequestError < StandardError; end
      class RateLimitError < RequestError; end

      class << self
        attr_accessor :api_endpoint, :api_method, :api_headers, :api_timeout
        attr_accessor :api_key_value, :api_key_env_var
        attr_accessor :retry_count, :retry_delay_value

        def endpoint(url)
          @api_endpoint = url
        end

        def method(http_method)
          @api_method = http_method
        end

        def headers(headers_hash)
          @api_headers = headers_hash
        end

        def timeout(seconds)
          @api_timeout = seconds
        end

        def api_key(key)
          @api_key_value = key
        end

        def api_key_env(env_var)
          @api_key_env_var = env_var
        end

        def retries(count)
          @retry_count = count
        end

        def retry_delay(seconds)
          @retry_delay_value = seconds
        end
      end

      def initialize(**options)
        super
        @api_key_override = options[:api_key]
      end

      # Get the API key from various sources
      def api_key
        @api_key_override ||
          self.class.api_key_value ||
          (self.class.api_key_env_var && ENV[self.class.api_key_env_var])
      end

      protected

      # Make GET request
      def get(path, params: nil, headers: {})
        make_request(:get, path, params: params, headers: headers)
      end

      # Make POST request
      def post(path, json: nil, body: nil, headers: {})
        make_request(:post, path, json: json, body: body, headers: headers)
      end

      # Make PUT request
      def put(path, json: nil, body: nil, headers: {})
        make_request(:put, path, json: json, body: body, headers: headers)
      end

      # Make DELETE request
      def delete(path, headers: {})
        make_request(:delete, path, headers: headers)
      end

      private

      def make_request(method, path, params: nil, json: nil, body: nil, headers: {})
        uri = build_uri(path, params)
        request = build_request(method, uri, json, body, headers)
        
        retries_left = self.class.retry_count || 0
        delay = self.class.retry_delay_value || 1

        begin
          response = execute_request(uri, request)
          handle_response(response)
        rescue RequestError => e
          if retries_left > 0
            log_debug_tools("Retrying request", path: path, retries_left: retries_left)
            sleep delay
            retries_left -= 1
            retry
          else
            raise
          end
        end
      end

      def build_uri(path, params)
        base_url = self.class.api_endpoint || raise("No endpoint configured")
        uri = URI.join(base_url, path)
        uri.query = URI.encode_www_form(params) if params
        uri
      end

      def build_request(method, uri, json, body, headers)
        request_class = case method
                       when :get then Net::HTTP::Get
                       when :post then Net::HTTP::Post
                       when :put then Net::HTTP::Put
                       when :delete then Net::HTTP::Delete
                       else raise "Unsupported method: #{method}"
                       end

        request = request_class.new(uri)
        
        # Add default headers
        default_headers = self.class.api_headers || {}
        default_headers.each { |k, v| request[k] = v }
        
        # Add custom headers
        headers.each { |k, v| request[k] = v }
        
        # Add API key if available
        if api_key
          request["Authorization"] = "Bearer #{api_key}"
        end

        # Set body
        if json
          request["Content-Type"] = "application/json"
          request.body = json.to_json
        elsif body
          request.body = body
        end

        request
      end

      def execute_request(uri, request)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.read_timeout = self.class.api_timeout || 30
        
        log_debug_tools("Making API request", method: request.method, uri: uri.to_s)
        http.request(request)
      end

      def handle_response(response)
        case response.code.to_i
        when 200..299
          parse_response_body(response)
        when 429
          raise RateLimitError, "Rate limit exceeded"
        when 400..499
          raise RequestError, "Client error: #{response.code} - #{response.body}"
        when 500..599
          raise RequestError, "Server error: #{response.code} - #{response.body}"
        else
          raise RequestError, "Unexpected response: #{response.code}"
        end
      end

      def parse_response_body(response)
        return nil if response.body.nil? || response.body.empty?
        
        content_type = response["Content-Type"]
        if content_type&.include?("application/json")
          JSON.parse(response.body)
        else
          response.body
        end
      rescue JSON::ParserError => e
        log_debug_tools("Failed to parse JSON response", error: e.message)
        response.body
      end
    end
  end
end