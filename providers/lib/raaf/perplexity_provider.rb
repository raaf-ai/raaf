# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module RAAF
  module Models
    ##
    # Perplexity API provider implementation
    #
    # Perplexity provides web-grounded AI search capabilities through their Sonar API.
    # The API is OpenAI-compatible and specializes in real-time web search with citations.
    #
    # Features:
    # - Web-grounded search with real-time information
    # - Automatic citation and source tracking
    # - JSON schema support for structured outputs (sonar-pro, sonar-reasoning-pro)
    # - Multiple search models (sonar, sonar-pro, sonar-deep-research)
    # - Advanced web search filtering options
    #
    # @example Basic usage
    #   provider = PerplexityProvider.new(api_key: ENV["PERPLEXITY_API_KEY"])
    #   response = provider.chat_completion(
    #     messages: [{ role: "user", content: "Latest Ruby news" }],
    #     model: "sonar-pro"
    #   )
    #
    # @example With JSON schema
    #   schema = { type: "object", properties: { results: { type: "array" } } }
    #   response = provider.chat_completion(
    #     messages: messages,
    #     model: "sonar-pro",
    #     response_format: schema
    #   )
    #
    # @example With web search options
    #   response = provider.chat_completion(
    #     messages: messages,
    #     model: "sonar",
    #     web_search_options: { search_domain_filter: ["ruby-lang.org"] }
    #   )
    #
    class PerplexityProvider < ModelInterface
      # Perplexity API base URL
      API_BASE = "https://api.perplexity.ai"

      # Perplexity's available models
      # sonar-pro and sonar-reasoning-pro support JSON schema
      SUPPORTED_MODELS = %w[
        sonar
        sonar-pro
        sonar-reasoning-pro
        sonar-deep-research
      ].freeze

      ##
      # Initialize a new Perplexity provider
      #
      # @param api_key [String, nil] Perplexity API key (defaults to PERPLEXITY_API_KEY env var)
      # @param api_base [String, nil] API base URL (defaults to standard Perplexity endpoint)
      # @param options [Hash] Additional options for the provider
      # @raise [AuthenticationError] if API key is not provided
      #
      def initialize(api_key: nil, api_base: nil, **options)
        super
        @api_key ||= ENV.fetch("PERPLEXITY_API_KEY", nil)
        @api_base ||= api_base || API_BASE

        raise AuthenticationError, "Perplexity API key is required" unless @api_key
      end

      ##
      # Performs a chat completion using Perplexity's API
      #
      # Perplexity's API is OpenAI-compatible, supporting most standard parameters.
      # JSON schema support is available on sonar-pro and sonar-reasoning-pro models.
      #
      # @param messages [Array<Hash>] Conversation messages
      # @param model [String] Perplexity model to use
      # @param tools [Array<Hash>, nil] Not supported by Perplexity
      # @param stream [Boolean] Whether to stream the response (not implemented yet)
      # @param kwargs [Hash] Additional parameters (temperature, max_tokens, response_format, etc.)
      # @return [Hash] Response in OpenAI format with Perplexity-specific fields (citations, web_results)
      # @raise [ModelNotFoundError] if model is not supported
      # @raise [APIError] if the API request fails
      #
      def perform_chat_completion(messages:, model:, tools: nil, stream: false, **kwargs)
        validate_model(model)

        if tools && !tools.empty?
          log_warn("Perplexity does not support function/tool calling. Tools parameter will be ignored.",
                   provider: "PerplexityProvider", model: model)
        end

        body = {
          model: model,
          messages: messages,
          stream: stream
        }

        # Add optional parameters
        body[:temperature] = kwargs[:temperature] if kwargs[:temperature]
        body[:max_tokens] = kwargs[:max_tokens] if kwargs[:max_tokens]
        body[:top_p] = kwargs[:top_p] if kwargs[:top_p]
        body[:presence_penalty] = kwargs[:presence_penalty] if kwargs[:presence_penalty]
        body[:frequency_penalty] = kwargs[:frequency_penalty] if kwargs[:frequency_penalty]

        # Add response_format for JSON schema support (sonar-pro, sonar-reasoning-pro)
        if kwargs[:response_format]
          validate_schema_support(model)

          # Detect if response_format is already OpenAI-wrapped format from DSL agents
          # DSL agents send: { type: "json_schema", json_schema: { name: "...", strict: true, schema: {...} } }
          # We need to extract the nested schema to avoid double-wrapping
          if kwargs[:response_format].is_a?(Hash) &&
             kwargs[:response_format][:type] == "json_schema" &&
             kwargs[:response_format][:json_schema]
            # Extract the schema from OpenAI format (similar to Anthropic provider)
            schema = kwargs[:response_format][:json_schema][:schema]
          else
            # Use raw schema as-is
            schema = kwargs[:response_format]
          end

          # Wrap in Perplexity format
          body[:response_format] = {
            type: "json_schema",
            json_schema: {
              schema: schema
            }
          }
        end

        # Add web_search_options for Perplexity-specific search filtering
        body[:web_search_options] = kwargs[:web_search_options] if kwargs[:web_search_options]

        if stream
          raise NotImplementedError, "Streaming not yet implemented for PerplexityProvider"
        else
          with_retry("chat_completion") do
            make_request(body)
          end
        end
      end

      ##
      # Streams a chat completion (not yet implemented)
      #
      # @param messages [Array<Hash>] Conversation messages
      # @param model [String] Perplexity model to use
      # @param tools [Array<Hash>, nil] Not supported
      # @param kwargs [Hash] Additional parameters
      # @raise [NotImplementedError]
      #
      def perform_stream_completion(messages:, model:, tools: nil, **kwargs, &block)
        raise NotImplementedError, "Streaming not yet implemented for PerplexityProvider"
      end

      ##
      # Returns list of supported Perplexity models
      #
      # @return [Array<String>] Supported model names
      #
      def supported_models
        SUPPORTED_MODELS
      end

      ##
      # Returns the provider name
      #
      # @return [String] "Perplexity"
      #
      def provider_name
        "Perplexity"
      end

      private

      ##
      # Validates that the model supports JSON schema
      #
      # @param model [String] Model name
      # @raise [ArgumentError] if model doesn't support JSON schema
      # @private
      #
      def validate_schema_support(model)
        schema_models = %w[sonar-pro sonar-reasoning-pro]
        return if schema_models.include?(model)

        raise ArgumentError,
              "JSON schema (response_format) is only supported on #{schema_models.join(', ')}. " \
              "Current model: #{model}"
      end

      ##
      # Makes a request to the Perplexity API
      #
      # @param body [Hash] Request body
      # @return [Hash] Parsed response
      # @raise [APIError] on request failure
      # @private
      #
      def make_request(body)
        uri = URI("#{@api_base}/chat/completions")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{@api_key}"
        request["Content-Type"] = "application/json"
        request.body = body.to_json

        response = http.request(request)

        handle_api_error(response) unless response.code.start_with?("2")

        RAAF::Utils.parse_json(response.body)
      end

      ##
      # Handles Perplexity-specific API errors
      #
      # Perplexity uses standard HTTP error codes but may have specific rate limiting behavior.
      #
      # @param response [HTTPResponse] API response
      # @raise [AuthenticationError] for 401 errors
      # @raise [RateLimitError] for 429 errors with reset time
      # @raise [APIError] for other errors
      # @private
      #
      def handle_api_error(response)
        case response.code.to_i
        when 401
          raise AuthenticationError, "Invalid Perplexity API key"
        when 429
          # Perplexity rate limits - extract retry-after if available
          retry_after = response["x-ratelimit-reset"] || response["retry-after"]
          raise RateLimitError, "Perplexity rate limit exceeded. Reset at: #{retry_after}"
        when 400
          # Parse error message from response
          begin
            error_data = JSON.parse(response.body)
            error_message = error_data.dig("error", "message") || response.body
          rescue StandardError
            error_message = response.body
          end
          raise APIError, "Perplexity API error: #{error_message}"
        when 503
          raise ServiceUnavailableError, "Perplexity service temporarily unavailable"
        else
          super
        end
      end
    end
  end
end
