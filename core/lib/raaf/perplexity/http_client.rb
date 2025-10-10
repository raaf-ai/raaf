# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module RAAF
  module Perplexity
    ##
    # Shared HTTP client for Perplexity API communication
    #
    # This module provides centralized HTTP communication logic for both
    # PerplexityProvider and PerplexitySearch DSL tool, ensuring consistency
    # and eliminating code duplication.
    #
    # Features:
    # - Direct Net::HTTP communication with Perplexity API
    # - Configurable timeouts and connection settings
    # - Comprehensive error handling with specific exception types
    # - Automatic JSON parsing with indifferent access
    #
    # @example Basic usage
    #   client = RAAF::Perplexity::HttpClient.new(api_key: ENV["PERPLEXITY_API_KEY"])
    #   result = client.make_api_call({
    #     model: "sonar-pro",
    #     messages: [{ role: "user", content: "Latest Ruby news" }]
    #   })
    #
    # @example With custom configuration
    #   client = RAAF::Perplexity::HttpClient.new(
    #     api_key: "your-key",
    #     api_base: "https://custom.api.com",
    #     timeout: 120,
    #     open_timeout: 20
    #   )
    #
    class HttpClient
      # Perplexity API base URL
      DEFAULT_API_BASE = "https://api.perplexity.ai"

      # Default timeout values
      DEFAULT_TIMEOUT = 180 # seconds
      DEFAULT_OPEN_TIMEOUT = 30 # seconds

      ##
      # Initialize HTTP client for Perplexity API
      #
      # @param api_key [String] Perplexity API key (required)
      # @param api_base [String, nil] API base URL (defaults to api.perplexity.ai)
      # @param timeout [Integer, nil] Read timeout in seconds (default: 180)
      # @param open_timeout [Integer, nil] Connection timeout in seconds (default: 30)
      # @raise [ArgumentError] if API key is not provided
      #
      def initialize(api_key:, api_base: nil, timeout: nil, open_timeout: nil)
        raise ArgumentError, "Perplexity API key is required" unless api_key

        @api_key = api_key
        @api_base = api_base || DEFAULT_API_BASE
        @timeout = timeout || DEFAULT_TIMEOUT
        @open_timeout = open_timeout || DEFAULT_OPEN_TIMEOUT
      end

      ##
      # Makes an API call to Perplexity
      #
      # This method handles the complete HTTP request/response cycle:
      # 1. Builds the HTTP client with SSL and timeout configuration
      # 2. Constructs the HTTP request with auth headers
      # 3. Sends the request and handles the response
      # 4. Parses JSON and converts to HashWithIndifferentAccess
      # 5. Raises specific errors based on HTTP status codes
      #
      # @param body [Hash] Request body (will be converted to JSON)
      # @return [ActiveSupport::HashWithIndifferentAccess] Parsed response
      # @raise [AuthenticationError] for 401 errors
      # @raise [RateLimitError] for 429 errors
      # @raise [ServiceUnavailableError] for 503 errors
      # @raise [APIError] for other HTTP errors
      # @raise [Net::OpenTimeout, Net::ReadTimeout] for network timeouts
      #
      def make_api_call(body)
        uri = URI("#{@api_base}/chat/completions")
        http = configure_http_client(uri)
        request = build_http_request(uri, body)

        response = http.request(request)

        handle_api_error(response) unless response.code.start_with?("2")

        RAAF::Utils.parse_json(response.body)
      end

      private

      ##
      # Configures HTTP client with Perplexity-specific settings
      #
      # @param uri [URI] Target URI
      # @return [Net::HTTP] Configured HTTP client
      # @private
      #
      def configure_http_client(uri)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = @timeout
        http.open_timeout = @open_timeout
        http
      end

      ##
      # Builds HTTP request with authentication headers
      #
      # @param uri [URI] Target URI
      # @param body [Hash] Request body
      # @return [Net::HTTP::Post] Configured HTTP request
      # @private
      #
      def build_http_request(uri, body)
        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{@api_key}"
        request["Content-Type"] = "application/json"
        request.body = body.to_json
        request
      end

      ##
      # Handles Perplexity-specific API errors
      #
      # Maps HTTP status codes to specific RAAF error types for proper
      # error handling and retry logic.
      #
      # @param response [HTTPResponse] API response
      # @raise [AuthenticationError] for 401 errors
      # @raise [RateLimitError] for 429 errors with reset time
      # @raise [ServiceUnavailableError] for 503 errors
      # @raise [APIError] for other HTTP errors
      # @private
      #
      def handle_api_error(response)
        case response.code.to_i
        when 401
          raise RAAF::AuthenticationError, "Invalid Perplexity API key"
        when 429
          # Extract retry-after information if available
          retry_after = response["x-ratelimit-reset"] || response["retry-after"]
          message = "Perplexity rate limit exceeded"
          message += ". Reset at: #{retry_after}" if retry_after
          raise RAAF::RateLimitError, message
        when 400
          # Parse error message from response body
          error_message = extract_error_message(response.body)
          raise RAAF::APIError, "Perplexity API error: #{error_message}"
        when 503
          raise RAAF::ServiceUnavailableError,
                "Perplexity service temporarily unavailable"
        else
          error_message = extract_error_message(response.body)
          raise RAAF::APIError,
                "Perplexity API error (#{response.code}): #{error_message}"
        end
      end

      ##
      # Extracts error message from API response body
      #
      # @param response_body [String] Raw response body
      # @return [String] Extracted error message or original body
      # @private
      #
      def extract_error_message(response_body)
        error_data = JSON.parse(response_body)
        error_data.dig("error", "message") || response_body
      rescue JSON::ParserError, StandardError
        response_body
      end
    end
  end
end
