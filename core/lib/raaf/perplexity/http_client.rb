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
      # @param api_type [String] API endpoint type: "chat" for /chat/completions or "search" for /search (default: "chat")
      # @return [ActiveSupport::HashWithIndifferentAccess] Parsed response
      # @raise [AuthenticationError] for 401 errors
      # @raise [RateLimitError] for 429 errors
      # @raise [ServiceUnavailableError] for 503 errors
      # @raise [APIError] for other HTTP errors
      # @raise [Net::OpenTimeout, Net::ReadTimeout] for network timeouts
      #
      def make_api_call(body, api_type: "chat")
        # Determine endpoint based on api_type
        endpoint = api_type == "search" ? "/search" : "/chat/completions"
        uri = URI("#{@api_base}#{endpoint}")
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
      # @raise [ServiceUnavailableError] for 502/503/504 errors
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
        when 502
          # Bad Gateway - typically CloudFlare or proxy issues
          raise RAAF::ServiceUnavailableError,
                "Perplexity gateway error (502) - service temporarily unavailable"
        when 503
          raise RAAF::ServiceUnavailableError,
                "Perplexity service temporarily unavailable (503)"
        when 504
          # Gateway Timeout - proxy/infrastructure issue
          raise RAAF::ServiceUnavailableError,
                "Perplexity gateway timeout (504) - service temporarily unavailable"
        else
          error_message = extract_error_message(response.body)
          raise RAAF::APIError,
                "Perplexity API error (#{response.code}): #{error_message}"
        end
      end

      ##
      # Extracts error message from API response body
      #
      # Handles both JSON and HTML responses gracefully. For HTML responses
      # (like CloudFlare error pages), extracts meaningful text and truncates.
      #
      # @param response_body [String] Raw response body
      # @return [String] Extracted error message (max 200 chars)
      # @private
      #
      def extract_error_message(response_body)
        return "Empty response" if response_body.nil? || response_body.empty?

        # Try JSON parsing first
        error_data = JSON.parse(response_body)
        message = error_data.dig("error", "message") || response_body
        truncate_message(message)
      rescue JSON::ParserError, StandardError
        # Handle HTML error pages (CloudFlare, proxy errors, etc.)
        if html_response?(response_body)
          extract_html_error(response_body)
        else
          # Non-JSON, non-HTML response - truncate and return
          truncate_message(response_body)
        end
      end

      ##
      # Checks if response body is HTML
      #
      # @param body [String] Response body
      # @return [Boolean] True if response appears to be HTML
      # @private
      #
      def html_response?(body)
        return false if body.nil? || body.empty?

        # Check for common HTML markers
        body.strip.start_with?("<!DOCTYPE", "<html", "<HTML") ||
          body.include?("<head>") ||
          body.include?("<body>")
      end

      ##
      # Extracts meaningful error from HTML response
      #
      # Attempts to extract title or first heading from HTML error pages.
      # Falls back to generic message if extraction fails.
      #
      # @param html_body [String] HTML response body
      # @return [String] Extracted and truncated error message
      # @private
      #
      def extract_html_error(html_body)
        # Try to extract title
        if html_body =~ /<title[^>]*>(.*?)<\/title>/mi
          title = Regexp.last_match(1).strip
          return truncate_message("HTML error: #{title}") unless title.empty?
        end

        # Try to extract first h1
        if html_body =~ /<h1[^>]*>(.*?)<\/h1>/mi
          heading = Regexp.last_match(1).strip
          return truncate_message("HTML error: #{heading}") unless heading.empty?
        end

        # Fallback for CloudFlare and other proxy errors
        if html_body.include?("cloudflare") || html_body.include?("Cloudflare")
          "HTML error: CloudFlare gateway error"
        else
          "HTML error: Proxy or gateway issue"
        end
      end

      ##
      # Truncates error message to reasonable length
      #
      # @param message [String] Error message to truncate
      # @param max_length [Integer] Maximum message length (default: 200)
      # @return [String] Truncated message
      # @private
      #
      def truncate_message(message, max_length = 200)
        return message if message.nil? || message.length <= max_length

        "#{message[0...max_length]}... (truncated)"
      end
    end
  end
end
