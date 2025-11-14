# frozen_string_literal: true

require "json"
require "net/http"
require "uri"
# Interface is required from raaf-core gem

module RAAF
  module Models
    ##
    # xAI API provider implementation for Grok models
    #
    # xAI (formerly Twitter AI) provides access to the Grok family of models,
    # known for their real-time knowledge, reasoning capabilities, and coding expertise.
    # The API is fully OpenAI-compatible, making integration straightforward.
    #
    # Features:
    # - OpenAI-compatible API for seamless integration
    # - Reasoning models with extended context (256k tokens)
    # - Function/tool calling with parallel execution support
    # - Vision capabilities (Grok 4)
    # - Structured outputs with JSON schema
    # - Streaming responses
    # - Real-time web search integration
    #
    # @example Basic usage
    #   provider = XAIProvider.new(api_key: ENV["XAI_API_KEY"])
    #   response = provider.chat_completion(
    #     messages: [{ role: "user", content: "Hello!" }],
    #     model: "grok-4"
    #   )
    #
    # @example With streaming
    #   provider.stream_completion(messages: messages, model: "grok-3") do |chunk|
    #     print chunk[:content]
    #   end
    #
    # @example With tools (function calling)
    #   provider.chat_completion(
    #     messages: messages,
    #     model: "grok-4",
    #     tools: [weather_tool, calculator_tool]
    #   )
    #
    # @example With vision (Grok 4)
    #   provider.chat_completion(
    #     messages: [{
    #       role: "user",
    #       content: [
    #         { type: "text", text: "What's in this image?" },
    #         { type: "image_url", image_url: { url: "https://..." } }
    #       ]
    #     }],
    #     model: "grok-4"
    #   )
    #
    class XAIProvider < ModelInterface
      # xAI API base URL
      API_BASE = "https://api.x.ai/v1"

      # xAI's available Grok models
      # All models support 256k context windows
      SUPPORTED_MODELS = %w[
        grok-4
        grok-3
        grok-3-mini
        grok-code-fast-1
      ].freeze

      # Models with vision capabilities
      VISION_MODELS = %w[
        grok-4
      ].freeze

      # Models optimized for coding
      CODING_MODELS = %w[
        grok-code-fast-1
        grok-4
      ].freeze

      ##
      # Initialize a new xAI provider
      #
      # @param api_key [String, nil] xAI API key (defaults to XAI_API_KEY env var)
      # @param api_base [String, nil] API base URL (defaults to standard xAI endpoint)
      # @param options [Hash] Additional options for the provider
      # @raise [AuthenticationError] if API key is not provided
      #
      def initialize(api_key: nil, api_base: nil, **options)
        super
        @api_key ||= ENV.fetch("XAI_API_KEY", nil)
        @api_base ||= api_base || API_BASE

        raise AuthenticationError, "xAI API key is required. Get one at https://console.x.ai" unless @api_key
      end

      ##
      # Performs a chat completion using xAI's API
      #
      # xAI's API is fully OpenAI-compatible, supporting all standard parameters.
      # All Grok models support function calling and structured outputs.
      #
      # @param messages [Array<Hash>] Conversation messages
      # @param model [String] Grok model to use (grok-4, grok-3, grok-3-mini, grok-code-fast-1)
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

        # Add tools if provided (all Grok models support function calling)
        if tools && !tools.empty?
          body[:tools] = prepare_tools(tools)
          body[:tool_choice] = kwargs[:tool_choice] if kwargs[:tool_choice]

          # xAI supports parallel tool calls
          body[:parallel_tool_calls] = kwargs[:parallel_tool_calls] unless kwargs[:parallel_tool_calls].nil?
        end

        # Add optional parameters (xAI supports all OpenAI parameters)
        body[:temperature] = kwargs[:temperature] if kwargs[:temperature]
        body[:max_tokens] = kwargs[:max_tokens] if kwargs[:max_tokens]
        body[:top_p] = kwargs[:top_p] if kwargs[:top_p]
        body[:stop] = kwargs[:stop] if kwargs[:stop]
        body[:presence_penalty] = kwargs[:presence_penalty] if kwargs[:presence_penalty]
        body[:frequency_penalty] = kwargs[:frequency_penalty] if kwargs[:frequency_penalty]
        body[:seed] = kwargs[:seed] if kwargs[:seed]
        body[:user] = kwargs[:user] if kwargs[:user]

        # Add response_format support for structured output
        # xAI supports JSON mode and JSON schema for structured outputs
        body[:response_format] = kwargs[:response_format] if kwargs[:response_format]

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
      # @param model [String] Grok model to use
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
      # Returns list of supported Grok models
      #
      # @return [Array<String>] Supported model names
      #
      def supported_models
        SUPPORTED_MODELS
      end

      ##
      # Returns the provider name
      #
      # @return [String] "xAI"
      #
      def provider_name
        "xAI"
      end

      ##
      # Check if model supports vision capabilities
      #
      # @param model [String] Model name
      # @return [Boolean] True if model supports vision
      #
      def vision_model?(model)
        VISION_MODELS.include?(model)
      end

      ##
      # Check if model is optimized for coding
      #
      # @param model [String] Model name
      # @return [Boolean] True if model is optimized for coding
      #
      def coding_model?(model)
        CODING_MODELS.include?(model)
      end

      private

      ##
      # Handles streaming responses from xAI API
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
                # Final chunk - return accumulated data
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
                  log_debug("Failed to parse streaming chunk: #{e.message}", provider: "XAIProvider",
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
      # Makes a request to the xAI API
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
        request.body = body.to_json

        response = http.request(request)

        handle_api_error(response, "xAI") unless response.code.start_with?("2")

        result = RAAF::Utils.parse_json(response.body)

        # Normalize token usage to canonical format
        if result["usage"]
          normalized_usage = RAAF::Usage::Normalizer.normalize(
            result,
            provider_name: "xai",
            model: result["model"] || body[:model]
          )
          result["usage"] = normalized_usage if normalized_usage
        end

        result
      end

      ##
      # Makes a streaming request to the xAI API
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
          request.body = body.to_json

          http.request(request) do |response|
            handle_api_error(response, "xAI") unless response.code.start_with?("2")

            response.read_body do |chunk|
              chunk.split("\n").each do |line|
                yield line if block_given?
              end
            end
          end
        end
      end

      ##
      # Handles xAI-specific API errors
      #
      # Provides specific error messages for xAI API errors,
      # including authentication, rate limits, and model availability.
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
          raise AuthenticationError, "Invalid xAI API key. Get one at https://console.x.ai"
        when 429
          # Rate limit - extract retry-after if available
          retry_after = response["retry-after"] || response["x-ratelimit-reset"]
          message = "xAI rate limit exceeded."
          message += " Retry after: #{retry_after}s" if retry_after
          raise RateLimitError, message
        when 400
          # Parse error message from response
          begin
            error_data = JSON.parse(response.body)
            error_message = error_data.dig("error", "message") || response.body
          rescue StandardError
            error_message = response.body
          end
          raise APIError, "xAI API error: #{error_message}"
        when 404
          raise ModelNotFoundError, "Model not found. Check that the model is available in your xAI account."
        else
          super
        end
      end
    end
  end
end
