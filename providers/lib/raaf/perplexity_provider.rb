# frozen_string_literal: true

require "json"
require "raaf/perplexity/common"
require "raaf/perplexity/search_options"
require "raaf/perplexity/result_parser"
require "raaf/perplexity/http_client"

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

      # Perplexity's available models (delegated to common code)
      # sonar-pro and sonar-reasoning-pro support JSON schema
      SUPPORTED_MODELS = RAAF::Perplexity::Common::SUPPORTED_MODELS

      ##
      # Initialize a new Perplexity provider
      #
      # @param api_key [String, nil] Perplexity API key (defaults to PERPLEXITY_API_KEY env var)
      # @param api_base [String, nil] API base URL (defaults to standard Perplexity endpoint)
      # @param timeout [Integer, nil] Read timeout in seconds (default: 180)
      # @param open_timeout [Integer, nil] Connection timeout in seconds (default: 30)
      # @param options [Hash] Additional options for the provider
      # @raise [AuthenticationError] if API key is not provided
      #
      def initialize(api_key: nil, api_base: nil, timeout: nil, open_timeout: nil, **options)
        super
        @api_key ||= ENV.fetch("PERPLEXITY_API_KEY", nil)

        raise AuthenticationError, "Perplexity API key is required" unless @api_key

        # Create shared HTTP client
        @http_client = RAAF::Perplexity::HttpClient.new(
          api_key: @api_key,
          api_base: api_base || API_BASE,
          timeout: timeout || ENV.fetch("PERPLEXITY_TIMEOUT", "180").to_i,
          open_timeout: open_timeout || ENV.fetch("PERPLEXITY_OPEN_TIMEOUT", "30").to_i
        )
      end

      ##
      # Performs a chat completion using Perplexity's API
      #
      # Perplexity's API is OpenAI-compatible, supporting most standard parameters.
      # JSON schema support is available on sonar-pro and sonar-reasoning-pro models.
      #
      # NOTE: Retry logic is handled automatically by the base class ModelInterface.
      # The base class's `chat_completion` method wraps this `perform_chat_completion`
      # with exponential backoff retry logic, so no manual retry wrapper is needed here.
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

        body = build_request_body(messages, model, stream, **kwargs)

        if stream
          raise NotImplementedError, "Streaming not yet implemented for PerplexityProvider"
        else
          make_api_call(body)
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
      # Validates model is supported (delegates to common code)
      #
      # @param model [String] Model name to validate
      # @raise [ArgumentError] if model is not supported
      # @private
      #
      def validate_model(model)
        RAAF::Perplexity::Common.validate_model(model)
      end

      ##
      # Builds the request body for Perplexity API
      #
      # Constructs the request body with model, messages, optional parameters,
      # and Perplexity-specific features like web_search_options.
      #
      # @param messages [Array<Hash>] Conversation messages
      # @param model [String] Model to use
      # @param stream [Boolean] Whether to stream response
      # @param kwargs [Hash] Additional parameters
      # @return [Hash] Complete request body
      # @private
      #
      def build_request_body(messages, model, stream, **kwargs)
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

        # Handle response_format with unwrapping for JSON schema support
        if kwargs[:response_format]
          validate_schema_support(model)
          body[:response_format] = unwrap_response_format(kwargs[:response_format])
        end

        # Add Perplexity-specific web_search_options (use common code if domain/recency filters)
        if kwargs[:web_search_options]
          body[:web_search_options] = kwargs[:web_search_options]
        elsif kwargs[:search_domain_filter] || kwargs[:search_recency_filter]
          # Build web search options from individual parameters using common code
          options = RAAF::Perplexity::SearchOptions.build(
            domain_filter: kwargs[:search_domain_filter],
            recency_filter: kwargs[:search_recency_filter]
          )
          body[:web_search_options] = options if options
        end

        body
      end

      ##
      # Unwraps response_format to extract schema
      #
      # Handles both OpenAI-wrapped format (from DSL agents) and raw schemas.
      # Wraps the extracted schema in Perplexity's expected format.
      #
      # @param response_format [Hash] Response format specification
      # @return [Hash] Perplexity-formatted response_format
      # @private
      #
      def unwrap_response_format(response_format)
        # Detect if response_format is OpenAI-wrapped format from DSL agents
        # DSL agents send: { type: "json_schema", json_schema: { name: "...", strict: true, schema: {...} } }
        if response_format.is_a?(Hash) &&
           response_format[:type] == "json_schema" &&
           response_format[:json_schema]
          # Extract the schema from OpenAI format
          schema = response_format[:json_schema][:schema]
        else
          # Use raw schema as-is
          schema = response_format
        end

        # Wrap in Perplexity format
        {
          type: "json_schema",
          json_schema: {
            schema: schema
          }
        }
      end

      ##
      # Validates that the model supports JSON schema (delegates to common code)
      #
      # @param model [String] Model name
      # @raise [ArgumentError] if model doesn't support JSON schema
      # @private
      #
      def validate_schema_support(model)
        RAAF::Perplexity::Common.validate_schema_support(model)
      end

      ##
      # Makes an API call to Perplexity using shared HTTP client
      #
      # This method delegates to the shared HTTP client. Retry logic is handled
      # automatically by the base class ModelInterface which wraps perform_chat_completion
      # with exponential backoff.
      #
      # @param body [Hash] Request body
      # @return [Hash] Parsed response with indifferent access
      # @raise [APIError] on request failure
      # @private
      #
      def make_api_call(body)
        @http_client.make_api_call(body)
      end
    end
  end
end
