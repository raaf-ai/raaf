# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module RAAF

  ##
  # HTTPClient - Local HTTP client implementation for OpenAI API calls
  #
  # This module provides a minimal, focused HTTP client implementation that replaces
  # the dependency on the openai-ruby gem. It handles only the necessary functionality
  # for RAAF while maintaining compatibility with the expected API.
  #
  # == Features
  #
  # * **Minimal Dependencies**: Uses only Ruby standard library (Net::HTTP)
  # * **Streaming Support**: Full support for Server-Sent Events streaming
  # * **Error Handling**: Comprehensive HTTP error handling with specific exceptions
  # * **Authentication**: Automatic Bearer token authentication
  # * **Timeouts**: Configurable request and connection timeouts
  # * **Resource Structure**: Familiar chat.completions.create API interface
  #
  # == Usage Patterns
  #
  # The client maintains API compatibility with the openai-ruby gem while
  # providing only the features needed by RAAF.
  #
  # @example Basic client usage
  #   client = HTTPClient::Client.new(api_key: "your-api-key")
  #   response = client.chat.completions.create(
  #     model: "gpt-4",
  #     messages: [{ role: "user", content: "Hello!" }]
  #   )
  #
  # @example Streaming completions
  #   client.chat.completions.stream_raw(
  #     model: "gpt-4",
  #     messages: messages
  #   ) do |chunk|
  #     puts chunk["choices"][0]["delta"]["content"]
  #   end
  #
  # @example Custom configuration
  #   client = HTTPClient::Client.new(
  #     api_key: "your-api-key",
  #     base_url: "https://api.openai.com/v1",
  #     timeout: 180,
  #     open_timeout: 60
  #   )
  #
  # @author RAAF (Ruby AI Agents Factory) Team
  # @since 0.1.0
  # @see Client For the main API client implementation
  class HTTPClient

    ##
    # OpenAI API Client
    #
    # The core HTTP client that handles authentication, request/response processing,
    # and error handling for OpenAI API interactions. Provides both synchronous
    # and streaming request capabilities.
    #
    # == Features
    #
    # * **Authentication**: Automatic Bearer token header management
    # * **Streaming**: Server-Sent Events streaming with chunk processing
    # * **Error Handling**: HTTP status code to exception mapping
    # * **Timeouts**: Configurable connection and read timeouts
    # * **JSON Processing**: Automatic request/response JSON handling
    #
    # @example Basic initialization
    #   client = Client.new(api_key: ENV["OPENAI_API_KEY"])
    #
    # @example With custom configuration
    #   client = Client.new(
    #     api_key: "your-key",
    #     base_url: "https://api.openai.com/v1",
    #     timeout: 120,
    #     open_timeout: 30
    #   )
    class Client

      attr_reader :api_key, :base_url

      def initialize(api_key:, base_url: "https://api.openai.com/v1", **options)
        @api_key = api_key
        @base_url = base_url
        @options = options
        @timeout = options[:timeout] || 120
        @open_timeout = options[:open_timeout] || 30
      end

      def chat
        @chat ||= ChatResource.new(self)
      end

      def make_request(method, path, body: nil, headers: {}, stream: false)
        uri = URI("#{@base_url}#{path}")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = @timeout
        http.open_timeout = @open_timeout

        request = case method.upcase
                  when "GET"
                    Net::HTTP::Get.new(uri.request_uri)
                  when "POST"
                    Net::HTTP::Post.new(uri.request_uri)
                  else
                    raise ArgumentError, "Unsupported HTTP method: #{method}"
                  end

        # Set headers
        request["Authorization"] = "Bearer #{@api_key}"
        request["Content-Type"] = "application/json"
        request["Accept"] = stream ? "text/event-stream" : "application/json"
        headers.each { |key, value| request[key] = value }

        # Set body for POST requests
        request.body = body.to_json if body && method.upcase == "POST"

        if stream
          # Handle streaming response
          String.new

          http.request(request) do |response|
            handle_error_response(response) unless response.is_a?(Net::HTTPSuccess)

            response.read_body do |chunk|
              chunk.split("\n").each do |line|
                next unless line.start_with?("data: ")

                data = line[6..].strip
                next if data.empty? || data == "[DONE]"

                begin
                  parsed_data = JSON.parse(data)
                  yield(parsed_data) if block_given?
                rescue JSON::ParserError
                  # Skip invalid JSON
                end
              end
            end
          end
        else
          # Handle regular response
          response = http.request(request)
          handle_error_response(response) unless response.is_a?(Net::HTTPSuccess)
          JSON.parse(response.body)
        end
      end

      private

      def handle_error_response(response)
        error_data = begin
          JSON.parse(response.body)
        rescue JSON::ParserError
          { "error" => { "message" => response.body } }
        end

        error_message = error_data.dig("error", "message") || "Unknown error"
        error_data.dig("error", "type") || "api_error"

        case response.code
        when "400"
          raise BadRequestError, error_message
        when "401"
          raise AuthenticationError, error_message
        when "403"
          raise PermissionDeniedError, error_message
        when "404"
          raise NotFoundError, error_message
        when "409"
          raise ConflictError, error_message
        when "422"
          raise UnprocessableEntityError, error_message
        when "429"
          raise RateLimitError, error_message
        when "500"
          raise InternalServerError, error_message
        when "502"
          raise BadGatewayError, error_message
        when "503"
          raise ServiceUnavailableError, error_message
        when "504"
          raise GatewayTimeoutError, error_message
        else
          raise APIError, "HTTP #{response.code}: #{error_message}"
        end
      end

    end

    ##
    # Chat resource for handling chat completions
    #
    class ChatResource

      def initialize(client)
        @client = client
      end

      def completions
        @completions ||= CompletionsResource.new(@client)
      end

    end

    ##
    # Completions resource for handling completions API
    #
    class CompletionsResource

      def initialize(client)
        @client = client
      end

      def create(**parameters)
        @client.make_request("POST", "/chat/completions", body: parameters)
      end

      def stream_raw(parameters, &)
        stream_parameters = parameters.merge(stream: true)
        @client.make_request("POST", "/chat/completions",
                             body: stream_parameters,
                             stream: true, &)
      end

    end

    # Error classes that match the OpenAI gem structure
    class Error < StandardError; end
    class APIError < Error; end
    class BadRequestError < APIError; end
    class AuthenticationError < APIError; end
    class PermissionDeniedError < APIError; end
    class NotFoundError < APIError; end
    class ConflictError < APIError; end
    class UnprocessableEntityError < APIError; end
    class RateLimitError < APIError; end
    class InternalServerError < APIError; end
    class BadGatewayError < APIError; end
    class ServiceUnavailableError < APIError; end
    class GatewayTimeoutError < APIError; end
    class APIConnectionError < APIError; end
    class APITimeoutError < APIError; end

  end

end
