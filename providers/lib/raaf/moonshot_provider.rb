# frozen_string_literal: true

require "json"
require "net/http"
require "uri"
# Interface is required from raaf-core gem

module RAAF
  module Models
    ##
    # Moonshot AI (Kimi K2) API provider implementation
    #
    # Moonshot AI provides the Kimi K2 model series, including both Kimi-K2-Instruct
    # and Kimi-K2-Thinking (reasoning model). The API is OpenAI-compatible and features
    # exceptional agentic capabilities with automatic tool selection and long-context support.
    #
    # Features:
    # - Strong tool-calling capabilities (can autonomously select 200-300 tools)
    # - Long-context support (up to 128K tokens)
    # - OpenAI-compatible API for easy integration
    # - Advanced reasoning capabilities (Kimi-K2-Thinking model)
    # - MoE architecture with 1 trillion parameters (32B activated)
    # - Optimized for agentic workflows and multi-step tasks
    #
    # @example Basic usage
    #   provider = MoonshotProvider.new(api_key: ENV["MOONSHOT_API_KEY"])
    #   response = provider.chat_completion(
    #     messages: [{ role: "user", content: "Hello!" }],
    #     model: "kimi-k2-instruct"
    #   )
    #
    # @example With tools (strong tool-calling support)
    #   provider.chat_completion(
    #     messages: messages,
    #     model: "kimi-k2-instruct",
    #     tools: [search_tool, calculator_tool]
    #   )
    #
    # @example With reasoning model
    #   provider.chat_completion(
    #     messages: messages,
    #     model: "kimi-k2-thinking",
    #     temperature: 0.7
    #   )
    #
    class MoonshotProvider < ModelInterface
      # Moonshot API base URL (OpenAI-compatible endpoint)
      API_BASE = "https://api.moonshot.cn/v1"

      # Kimi K2 available models
      # Includes both instruction-following and reasoning variants
      SUPPORTED_MODELS = %w[
        kimi-k2-instruct
        kimi-k2-thinking
        moonshot-v1-8k
        moonshot-v1-32k
        moonshot-v1-128k
      ].freeze

      ##
      # Initialize a new Moonshot provider
      #
      # @param api_key [String, nil] Moonshot API key (defaults to MOONSHOT_API_KEY env var)
      # @param api_base [String, nil] API base URL (defaults to standard Moonshot endpoint)
      # @param options [Hash] Additional options for the provider
      # @raise [AuthenticationError] if API key is not provided
      #
      def initialize(api_key: nil, api_base: nil, **options)
        super
        @api_key ||= ENV.fetch("MOONSHOT_API_KEY", nil)
        @api_base ||= api_base || API_BASE

        raise AuthenticationError, "Moonshot API key is required" unless @api_key
      end

      ##
      # Performs a chat completion using Moonshot's API
      #
      # Moonshot's API is OpenAI-compatible, supporting standard parameters.
      # All Kimi K2 models have strong tool-calling capabilities.
      #
      # @param messages [Array<Hash>] Conversation messages
      # @param model [String] Kimi K2 model to use
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

        # Add tools if provided (Kimi K2 has strong tool-calling capabilities)
        if tools && !tools.empty?
          body[:tools] = prepare_tools(tools)
          body[:tool_choice] = kwargs[:tool_choice] if kwargs[:tool_choice]
        end

        # Add optional parameters (Moonshot supports most OpenAI parameters)
        body[:temperature] = kwargs[:temperature] if kwargs[:temperature]
        body[:max_tokens] = kwargs[:max_tokens] if kwargs[:max_tokens]
        body[:top_p] = kwargs[:top_p] if kwargs[:top_p]
        body[:stop] = kwargs[:stop] if kwargs[:stop]
        body[:presence_penalty] = kwargs[:presence_penalty] if kwargs[:presence_penalty]
        body[:frequency_penalty] = kwargs[:frequency_penalty] if kwargs[:frequency_penalty]
        body[:user] = kwargs[:user] if kwargs[:user]

        # Add response_format support for structured output
        body[:response_format] = kwargs[:response_format] if kwargs[:response_format]

        if stream
          stream_response(body, &block)
        else
          make_request(body)
        end
      end

      ##
      # Streams a chat completion
      #
      # Convenience method that calls chat_completion with stream: true.
      #
      # @param messages [Array<Hash>] Conversation messages
      # @param model [String] Kimi K2 model to use
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
      # Returns list of supported Kimi K2 models
      #
      # @return [Array<String>] Supported model names
      #
      def supported_models
        SUPPORTED_MODELS
      end

      ##
      # Returns the provider name
      #
      # @return [String] "Moonshot"
      #
      def provider_name
        "Moonshot"
      end

      private

      ##
      # Handles streaming responses from Moonshot API
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
                log_debug("Failed to parse streaming chunk: #{e.message}",
                         provider: "MoonshotProvider",
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

      ##
      # Makes a request to the Moonshot API
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

        handle_api_error(response, "Moonshot") unless response.code.start_with?("2")

        RAAF::Utils.parse_json(response.body)
      end

      ##
      # Makes a streaming request to the Moonshot API
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
            handle_api_error(response, "Moonshot") unless response.code.start_with?("2")

            response.read_body do |chunk|
              chunk.split("\n").each do |line|
                yield line if block_given?
              end
            end
          end
        end
      end

      ##
      # Handles Moonshot-specific API errors
      #
      # @param response [HTTPResponse] API response
      # @param provider [String] Provider name
      # @raise [AuthenticationError] for 401 errors
      # @raise [RateLimitError] for 429 errors
      # @raise [APIError] for other errors
      # @private
      #
      def handle_api_error(response, provider)
        case response.code.to_i
        when 401
          raise AuthenticationError, "Invalid Moonshot API key"
        when 429
          retry_after = response["x-ratelimit-reset"]
          raise RateLimitError, "Moonshot rate limit exceeded. Reset at: #{retry_after}"
        when 400
          # Parse error message from response
          begin
            error_data = JSON.parse(response.body)
            error_message = error_data.dig("error", "message") || response.body
          rescue StandardError
            error_message = response.body
          end
          raise APIError, "Moonshot API error: #{error_message}"
        else
          super
        end
      end
    end
  end
end
