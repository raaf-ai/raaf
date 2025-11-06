# frozen_string_literal: true

require "json"
require "net/http"
require "uri"
# Interface is required from raaf-core gem

module RAAF
  module Models
    ##
    # OpenRouter API provider implementation
    #
    # OpenRouter provides a unified API gateway for accessing multiple LLM providers
    # through a single OpenAI-compatible API. It supports models from OpenAI, Anthropic,
    # Google, Meta, Mistral, and many other providers with automatic routing.
    #
    # Features:
    # - Access to 100+ models from multiple providers
    # - OpenAI-compatible API for easy integration
    # - Automatic model routing and fallbacks
    # - Function calling support on compatible models
    # - Streaming responses
    # - Cost tracking and analytics
    # - Flexible model naming with provider prefixes
    #
    # @example Basic usage
    #   provider = OpenRouterProvider.new(api_key: ENV["OPENROUTER_API_KEY"])
    #   response = provider.chat_completion(
    #     messages: [{ role: "user", content: "Hello!" }],
    #     model: "anthropic/claude-3.5-sonnet"
    #   )
    #
    # @example With streaming
    #   provider.stream_completion(messages: messages, model: "openai/gpt-4-turbo") do |chunk|
    #     print chunk[:content]
    #   end
    #
    # @example With tools (function calling)
    #   provider.chat_completion(
    #     messages: messages,
    #     model: "openai/gpt-4o",
    #     tools: [weather_tool]
    #   )
    #
    class OpenRouterProvider < ModelInterface
      # OpenRouter API base URL
      API_BASE = "https://openrouter.ai/api/v1"

      # Popular models available on OpenRouter (subset of available models)
      # OpenRouter supports 100+ models - this is just a representative sample
      SUPPORTED_MODELS = %w[
        openai/gpt-4o
        openai/gpt-4-turbo
        openai/gpt-3.5-turbo
        anthropic/claude-3.5-sonnet
        anthropic/claude-3-opus
        anthropic/claude-3-sonnet
        anthropic/claude-3-haiku
        google/gemini-pro-1.5
        google/gemini-flash-1.5
        meta-llama/llama-3.1-405b-instruct
        meta-llama/llama-3.1-70b-instruct
        meta-llama/llama-3.1-8b-instruct
        mistralai/mixtral-8x7b-instruct
        mistralai/mistral-7b-instruct
        cohere/command-r-plus
        perplexity/llama-3.1-sonar-large-128k-online
        qwen/qwen-2-72b-instruct
        deepseek/deepseek-chat
      ].freeze

      ##
      # Initialize a new OpenRouter provider
      #
      # @param api_key [String, nil] OpenRouter API key (defaults to OPENROUTER_API_KEY env var)
      # @param api_base [String, nil] API base URL (defaults to OpenRouter endpoint)
      # @param site_url [String, nil] Your site URL (for OpenRouter rankings, defaults to OPENROUTER_SITE_URL env var)
      # @param site_name [String, nil] Your site name (for OpenRouter rankings, defaults to OPENROUTER_SITE_NAME env var)
      # @param options [Hash] Additional options for the provider
      # @raise [AuthenticationError] if API key is not provided
      #
      def initialize(api_key: nil, api_base: nil, site_url: nil, site_name: nil, **options)
        super
        @api_key ||= ENV.fetch("OPENROUTER_API_KEY", nil)
        @api_base ||= api_base || API_BASE
        @site_url = site_url || ENV.fetch("OPENROUTER_SITE_URL", nil)
        @site_name = site_name || ENV.fetch("OPENROUTER_SITE_NAME", nil)

        raise AuthenticationError, "OpenRouter API key is required" unless @api_key
      end

      ##
      # Performs a chat completion using OpenRouter's API
      #
      # OpenRouter's API is OpenAI-compatible, supporting most standard parameters.
      # Tool support depends on the underlying model being used.
      #
      # @param messages [Array<Hash>] Conversation messages
      # @param model [String] Model identifier (e.g., "anthropic/claude-3.5-sonnet")
      # @param tools [Array<Hash>, nil] Tools/functions available to the model
      # @param stream [Boolean] Whether to stream the response
      # @param kwargs [Hash] Additional parameters (temperature, max_tokens, etc.)
      # @return [Hash] Response in OpenAI format
      # @raise [ModelNotFoundError] if model is not supported
      # @raise [APIError] if the API request fails
      #
      def perform_chat_completion(messages:, model:, tools: nil, stream: false, **kwargs)
        validate_model(model)

        body = {
          model: model,
          messages: messages,
          stream: stream
        }

        # Add tools if provided
        # Tool support depends on the underlying model
        if tools && !tools.empty?
          body[:tools] = prepare_tools(tools)
          body[:tool_choice] = kwargs[:tool_choice] if kwargs[:tool_choice]
        end

        # Add optional parameters (OpenRouter supports most OpenAI parameters)
        body[:temperature] = kwargs[:temperature] if kwargs[:temperature]
        body[:max_tokens] = kwargs[:max_tokens] if kwargs[:max_tokens]
        body[:top_p] = kwargs[:top_p] if kwargs[:top_p]
        body[:top_k] = kwargs[:top_k] if kwargs[:top_k]
        body[:frequency_penalty] = kwargs[:frequency_penalty] if kwargs[:frequency_penalty]
        body[:presence_penalty] = kwargs[:presence_penalty] if kwargs[:presence_penalty]
        body[:repetition_penalty] = kwargs[:repetition_penalty] if kwargs[:repetition_penalty]
        body[:stop] = kwargs[:stop] if kwargs[:stop]
        body[:seed] = kwargs[:seed] if kwargs[:seed]

        # Add response_format support for structured output
        body[:response_format] = kwargs[:response_format] if kwargs[:response_format]

        # OpenRouter-specific parameters
        body[:transforms] = kwargs[:transforms] if kwargs[:transforms]
        body[:models] = kwargs[:models] if kwargs[:models] # Model fallback list
        body[:route] = kwargs[:route] if kwargs[:route] # Routing preference

        if stream
          stream_response(body, &block)
        else
          with_retry("chat_completion") do
            make_request(body)
          end
        end
      end

      ##
      # Streams a chat completion
      #
      # Convenience method that calls chat_completion with stream: true.
      #
      # @param messages [Array<Hash>] Conversation messages
      # @param model [String] Model to use
      # @param tools [Array<Hash>, nil] Available tools
      # @param kwargs [Hash] Additional parameters
      # @yield [Hash] Yields streaming chunks
      # @return [Hash] Final accumulated response
      #
      def perform_stream_completion(messages:, model:, tools: nil, **kwargs, &block)
        perform_chat_completion(
          messages: messages,
          model: model,
          tools: tools,
          stream: true,
          **kwargs,
          &block
        )
      end

      ##
      # Returns list of known supported models
      #
      # Note: OpenRouter supports 100+ models. Use list_available_models()
      # for the complete current list from the API.
      #
      # @return [Array<String>] Supported model names
      #
      def supported_models
        SUPPORTED_MODELS
      end

      ##
      # Returns the provider name
      #
      # @return [String] "OpenRouter"
      #
      def provider_name
        "OpenRouter"
      end

      ##
      # Get available models from OpenRouter API
      #
      # Fetches the current list of available models from OpenRouter's API.
      # Returns detailed model information including pricing and capabilities.
      #
      # @return [Array<Hash>] List of available models with metadata
      #
      # @example
      #   models = provider.list_available_models
      #   # => [{ "id" => "openai/gpt-4o", "pricing" => {...}, "context_length" => 128000 }, ...]
      #
      def list_available_models
        with_retry("list_models") do
          uri = URI("#{@api_base}/models")
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true

          request = Net::HTTP::Get.new(uri)
          request["Authorization"] = "Bearer #{@api_key}"
          request["Content-Type"] = "application/json"
          add_site_headers(request)

          response = http.request(request)

          if response.code.start_with?("2")
            result = RAAF::Utils.parse_json(response.body)
            result["data"] || []
          else
            handle_api_error(response, "OpenRouter")
            []
          end
        end
      end

      private

      ##
      # Makes a request to the OpenRouter API
      #
      # @param body [Hash] Request body
      # @return [Hash] Parsed response
      # @raise [APIError] on request failure
      #
      def make_request(body)
        uri = URI("#{@api_base}/chat/completions")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{@api_key}"
        request["Content-Type"] = "application/json"
        add_site_headers(request)
        request.body = body.to_json

        response = http.request(request)

        handle_api_error(response, "OpenRouter") unless response.code.start_with?("2")

        RAAF::Utils.parse_json(response.body)
      end

      ##
      # Makes a streaming request to the OpenRouter API
      #
      # @param body [Hash] Request body
      # @yield [String] Yields raw SSE chunks
      #
      def make_streaming_request(body)
        body[:stream] = true
        uri = URI("#{@api_base}/chat/completions")

        Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
          request = Net::HTTP::Post.new(uri)
          request["Authorization"] = "Bearer #{@api_key}"
          request["Content-Type"] = "application/json"
          request["Accept"] = "text/event-stream"
          add_site_headers(request)
          request.body = body.to_json

          http.request(request) do |response|
            handle_api_error(response, "OpenRouter") unless response.code.start_with?("2")

            response.read_body do |chunk|
              chunk.split("\n").each do |line|
                yield line if block_given?
              end
            end
          end
        end
      end

      ##
      # Handles streaming responses from OpenRouter API
      #
      # Processes Server-Sent Events (SSE) and yields chunks to the caller.
      # Accumulates content and tool calls for the final response.
      #
      # @param body [Hash] Request body
      # @yield [Hash] Yields streaming chunks with type and content
      # @return [Hash] Final accumulated response
      # @private
      #
      def stream_response(body)
        body[:stream] = true

        with_retry("stream_completion") do
          accumulated_content = ""
          accumulated_tool_calls = []

          make_streaming_request(body) do |chunk|
            # Parse SSE chunk
            if chunk.start_with?("data: ")
              data = chunk[6..].strip

              if data == "[DONE]"
                # Final chunk
                if block_given?
                  yield({
                    type: "done",
                    content: accumulated_content,
                    tool_calls: accumulated_tool_calls
                  })
                end
              else
                begin
                  parsed = RAAF::Utils.parse_json(data)

                  # Extract content from the chunk
                  if parsed.dig("choices", 0, "delta", "content")
                    content = parsed["choices"][0]["delta"]["content"]
                    accumulated_content += content

                    if block_given?
                      yield({
                        type: "content",
                        content: content,
                        accumulated_content: accumulated_content
                      })
                    end
                  end

                  # Handle tool calls in streaming
                  if parsed.dig("choices", 0, "delta", "tool_calls")
                    tool_calls = parsed["choices"][0]["delta"]["tool_calls"]
                    accumulated_tool_calls.concat(tool_calls)

                    if block_given?
                      yield({
                        type: "tool_calls",
                        tool_calls: tool_calls,
                        accumulated_tool_calls: accumulated_tool_calls
                      })
                    end
                  end

                  # Check for finish reason
                  if parsed.dig("choices", 0, "finish_reason") && block_given?
                    yield({
                      type: "finish",
                      finish_reason: parsed["choices"][0]["finish_reason"],
                      content: accumulated_content,
                      tool_calls: accumulated_tool_calls
                    })
                  end
                rescue JSON::ParserError => e
                  # Log but continue - some chunks might be partial
                  log_debug("Failed to parse streaming chunk: #{e.message}", provider: "OpenRouterProvider",
                                                                             error_class: e.class.name)
                end
              end
            end
          end

          # Return final accumulated data
          {
            content: accumulated_content,
            tool_calls: accumulated_tool_calls
          }
        end
      end

      ##
      # Override validation to handle OpenRouter's model naming
      #
      # OpenRouter uses provider-prefixed model names like "anthropic/claude-3.5-sonnet"
      # or "openai/gpt-4o". This method allows any model with a slash, assuming it's
      # a valid provider/model format.
      #
      # @param model [String] Model identifier
      # @raise [ModelNotFoundError] if model format is invalid
      # @private
      #
      def validate_model(model)
        # OpenRouter uses provider/model format, so we check for slash
        return if model.include?("/") # Assume it's a valid provider/model path

        # Otherwise check against our known list
        super
      end

      ##
      # Adds OpenRouter-specific site headers to requests
      #
      # These headers are used by OpenRouter for rankings and analytics.
      # They're optional but recommended.
      #
      # @param request [Net::HTTPRequest] The request to add headers to
      # @private
      #
      def add_site_headers(request)
        request["HTTP-Referer"] = @site_url if @site_url
        request["X-Title"] = @site_name if @site_name
      end

      ##
      # Custom error handling for OpenRouter API
      #
      # Provides specific error messages for OpenRouter API errors,
      # including rate limit information, model availability, and credits.
      #
      # @param response [HTTPResponse] API response
      # @param provider [String] Provider name (unused but required by interface)
      # @raise [AuthenticationError] for 401 errors
      # @raise [RateLimitError] for 429 errors
      # @raise [APIError] for other errors
      # @private
      #
      def handle_api_error(response, provider)
        case response.code.to_i
        when 401
          raise AuthenticationError, "Invalid OpenRouter API key"
        when 402
          # Payment/credits required
          begin
            error_data = JSON.parse(response.body)
            error_message = error_data.dig("error", "message") || "Insufficient credits"
          rescue StandardError
            error_message = "Insufficient credits"
          end
          raise APIError, "OpenRouter payment required: #{error_message}"
        when 429
          # Rate limit
          retry_after = response["retry-after"]
          message = "OpenRouter rate limit exceeded."
          message += " Retry after: #{retry_after}s" if retry_after
          raise RateLimitError, message
        when 400, 404
          # Model not available or bad request
          begin
            error_data = JSON.parse(response.body)
            error_message = error_data.dig("error", "message") || response.body
          rescue StandardError
            error_message = response.body
          end
          raise APIError, "OpenRouter API error: #{error_message}"
        else
          super
        end
      end
    end
  end
end
