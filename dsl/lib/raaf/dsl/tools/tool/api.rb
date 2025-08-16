# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

# Tool::API for external API tools in RAAF DSL framework
#
# This class provides a specialized base for tools that interact with external
# APIs. It includes built-in support for HTTP requests, authentication,
# endpoint configuration, and response handling.
#
# The API class provides DSL methods for configuring endpoints, API keys,
# headers, and request parameters. It handles common API patterns like
# authentication, error handling, and response parsing.
#
# @example Basic API tool
#   class WeatherTool < RAAF::DSL::Tools::Tool::API
#     endpoint "https://api.weather.com/v1/current"
#     api_key ENV['WEATHER_API_KEY']
#     
#     def call(city:)
#       get(params: { q: city, key: api_key })
#     end
#   end
#
# @example Advanced API tool with custom headers
#   class SlackTool < RAAF::DSL::Tools::Tool::API
#     endpoint "https://slack.com/api"
#     
#     def call(channel:, message:)
#       post("/chat.postMessage", 
#            json: { channel: channel, text: message },
#            headers: { "Authorization" => "Bearer #{ENV['SLACK_TOKEN']}" })
#     end
#   end
#
# @see RAAF::DSL::Tools::Tool Base tool class
# @since 1.0.0
#
module RAAF
  module DSL
    module Tools
      class Tool
        class API < Tool
          attr_reader :base_url, :api_key_value, :default_headers

          # Initialize API tool with configuration
          #
          # @param options [Hash] Configuration options
          # @option options [String] :endpoint Base URL for API
          # @option options [String] :api_key API key for authentication
          # @option options [Hash] :headers Default headers for requests
          # @option options [Integer] :timeout Request timeout in seconds
          #
          def initialize(options = {})
            super(options)
            @base_url = options[:endpoint] || self.class.endpoint_url
            @api_key_value = options[:api_key] || self.class.api_key_value
            @default_headers = (self.class.default_headers || {}).merge(options[:headers] || {})
            @timeout = options[:timeout] || self.class.timeout_value || 30
          end

          # Perform GET request
          #
          # @param path [String] API endpoint path (optional if full URL in endpoint)
          # @param params [Hash] Query parameters
          # @param headers [Hash] Additional headers
          # @return [Hash] Parsed response
          #
          def get(path = "", params: {}, headers: {})
            request(:get, path, params: params, headers: headers)
          end

          # Perform POST request
          #
          # @param path [String] API endpoint path
          # @param json [Hash] JSON body data
          # @param params [Hash] Query parameters
          # @param headers [Hash] Additional headers
          # @return [Hash] Parsed response
          #
          def post(path = "", json: nil, params: {}, headers: {})
            request(:post, path, json: json, params: params, headers: headers)
          end

          # Perform PUT request
          #
          # @param path [String] API endpoint path
          # @param json [Hash] JSON body data
          # @param params [Hash] Query parameters
          # @param headers [Hash] Additional headers
          # @return [Hash] Parsed response
          #
          def put(path = "", json: nil, params: {}, headers: {})
            request(:put, path, json: json, params: params, headers: headers)
          end

          # Perform DELETE request
          #
          # @param path [String] API endpoint path
          # @param params [Hash] Query parameters
          # @param headers [Hash] Additional headers
          # @return [Hash] Parsed response
          #
          def delete(path = "", params: {}, headers: {})
            request(:delete, path, params: params, headers: headers)
          end

          # Get the API key value
          #
          # @return [String, nil] API key value
          #
          def api_key
            @api_key_value
          end

          private

          # Perform HTTP request
          #
          # @param method [Symbol] HTTP method (:get, :post, :put, :delete)
          # @param path [String] API endpoint path
          # @param json [Hash] JSON body data
          # @param params [Hash] Query parameters
          # @param headers [Hash] Additional headers
          # @return [Hash] Parsed response
          #
          def request(method, path, json: nil, params: {}, headers: {})
            url = build_url(path, params)
            uri = URI(url)
            
            http = Net::HTTP.new(uri.host, uri.port)
            http.use_ssl = uri.scheme == 'https'
            http.read_timeout = @timeout
            http.open_timeout = @timeout

            request_headers = build_headers(headers)
            
            case method
            when :get
              request = Net::HTTP::Get.new(uri.request_uri, request_headers)
            when :post
              request = Net::HTTP::Post.new(uri.request_uri, request_headers)
              request.body = json.to_json if json
            when :put
              request = Net::HTTP::Put.new(uri.request_uri, request_headers)
              request.body = json.to_json if json
            when :delete
              request = Net::HTTP::Delete.new(uri.request_uri, request_headers)
            else
              raise ArgumentError, "Unsupported HTTP method: #{method}"
            end

            response = http.request(request)
            handle_response(response)
          rescue => e
            handle_error(e)
          end

          # Build complete URL with path and query parameters
          #
          # @param path [String] API endpoint path
          # @param params [Hash] Query parameters
          # @return [String] Complete URL
          #
          def build_url(path, params)
            url = if path.start_with?('http')
                    path
                  else
                    "#{@base_url.chomp('/')}/#{path.sub(/^\//, '')}"
                  end

            unless params.empty?
              query = URI.encode_www_form(params)
              url += url.include?('?') ? "&#{query}" : "?#{query}"
            end

            url
          end

          # Build request headers
          #
          # @param additional_headers [Hash] Additional headers for this request
          # @return [Hash] Complete headers hash
          #
          def build_headers(additional_headers)
            headers = @default_headers.dup
            headers["Content-Type"] = "application/json" if additional_headers[:json] || headers[:json]
            headers.merge(additional_headers)
          end

          # Handle HTTP response
          #
          # @param response [Net::HTTPResponse] HTTP response object
          # @return [Hash] Parsed response data
          #
          def handle_response(response)
            case response.code.to_i
            when 200..299
              parse_response(response)
            when 400..499
              { error: "Client error: #{response.code}", message: response.body }
            when 500..599
              { error: "Server error: #{response.code}", message: response.body }
            else
              { error: "Unexpected response: #{response.code}", message: response.body }
            end
          end

          # Parse response body
          #
          # @param response [Net::HTTPResponse] HTTP response object
          # @return [Hash] Parsed response data
          #
          def parse_response(response)
            return {} if response.body.nil? || response.body.empty?

            content_type = response['content-type'] || ''
            
            if content_type.include?('application/json')
              JSON.parse(response.body)
            else
              { body: response.body, content_type: content_type }
            end
          rescue JSON::ParserError
            { body: response.body, content_type: content_type }
          end

          # Handle request errors
          #
          # @param error [Exception] Request error
          # @return [Hash] Error response
          #
          def handle_error(error)
            {
              error: error.class.name,
              message: error.message,
              backtrace: error.backtrace&.first(5)
            }
          end

          class << self
            # Configure API endpoint
            #
            # @param url [String] Base URL for API endpoints
            #
            def endpoint(url)
              @endpoint_url = url
            end

            # Configure API key
            #
            # @param key [String] API key value
            #
            def api_key(key)
              @api_key_value = key
            end

            # Configure default headers
            #
            # @param headers [Hash] Default headers for all requests
            #
            def headers(headers = {})
              @default_headers = headers
            end

            # Configure request timeout
            #
            # @param seconds [Integer] Timeout in seconds
            #
            def timeout(seconds)
              @timeout_value = seconds
            end

            # Get configured endpoint URL
            #
            # @return [String, nil] Configured endpoint URL
            #
            def endpoint_url
              @endpoint_url
            end

            # Get configured API key
            #
            # @return [String, nil] Configured API key
            #
            def api_key_value
              @api_key_value
            end

            # Get configured default headers
            #
            # @return [Hash] Configured default headers
            #
            def default_headers
              @default_headers
            end

            # Get configured timeout
            #
            # @return [Integer, nil] Configured timeout
            #
            def timeout_value
              @timeout_value
            end
          end
        end
      end
    end
  end
end