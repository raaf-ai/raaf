# frozen_string_literal: true

require "json"
require "net/http"
require "uri"
# Interface is required from raaf-core gem

module RAAF
  module Models
    ##
    # Groq API provider implementation
    #
    # Groq provides ultra-fast inference for open-source models like Llama, Mixtral, and Gemma.
    # The API is OpenAI-compatible, making integration straightforward. Groq specializes in
    # high-performance inference with their custom LPU (Language Processing Unit) hardware.
    #
    # Features:
    # - Ultra-fast inference speeds (up to 10x faster than traditional providers)
    # - Support for popular open-source models (Llama, Mixtral, Gemma)
    # - OpenAI-compatible API for easy integration
    # - Function calling support on select models
    # - Streaming responses
    # - JSON mode and structured output
    #
    # @example Basic usage
    #   provider = GroqProvider.new(api_key: ENV["GROQ_API_KEY"])
    #   response = provider.chat_completion(
    #     messages: [{ role: "user", content: "Hello!" }],
    #     model: "llama-3.1-70b-versatile"
    #   )
    #
    # @example With streaming
    #   provider.stream_completion(messages: messages, model: "mixtral-8x7b-32768") do |chunk|
    #     print chunk[:content]
    #   end
    #
    # @example With tools (function calling)
    #   provider.chat_completion(
    #     messages: messages,
    #     model: "llama3-groq-70b-8192-tool-use-preview",
    #     tools: [weather_tool]
    #   )
    #
    class GroqProvider < ModelInterface
      # Groq API base URL
      API_BASE = "https://api.groq.com/openai/v1"

      # Groq's available models as of 2024
      # Includes various Llama 3 models, Mixtral, and Gemma variants
      SUPPORTED_MODELS = %w[
        llama-3.3-70b-versatile
        llama-3.1-405b-reasoning
        llama-3.1-70b-versatile
        llama-3.1-8b-instant
        llama3-groq-70b-8192-tool-use-preview
        llama3-groq-8b-8192-tool-use-preview
        llama-3.2-1b-preview
        llama-3.2-3b-preview
        llama-3.2-11b-vision-preview
        llama-3.2-90b-vision-preview
        mixtral-8x7b-32768
        gemma-7b-it
        gemma2-9b-it
      ].freeze

      ##
      # Initialize a new Groq provider
      #
      # @param api_key [String, nil] Groq API key (defaults to GROQ_API_KEY env var)
      # @param api_base [String, nil] API base URL (defaults to standard Groq endpoint)
      # @param options [Hash] Additional options for the provider
      # @raise [AuthenticationError] if API key is not provided
      #
      def initialize(api_key: nil, api_base: nil, **options)
        super
        @api_key ||= ENV.fetch("GROQ_API_KEY", nil)
        @api_base ||= api_base || API_BASE

        raise AuthenticationError, "Groq API key is required" unless @api_key

        # HTTP client initialization removed - using Net::HTTP directly for Groq API
      end

      ##
      # Performs a chat completion using Groq's API
      #
      # Groq's API is OpenAI-compatible, supporting most standard parameters.
      # Tool support is available on models with "tool-use" in their name.
      #
      # @param messages [Array<Hash>] Conversation messages
      # @param model [String] Groq model to use
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

        # Add tools if provided (Groq supports function calling on select models)
        if tools && !tools.empty?
          if model.include?("tool-use")
            body[:tools] = prepare_tools(tools)
            body[:tool_choice] = kwargs[:tool_choice] if kwargs[:tool_choice]
          else
            log_warn("Model #{model} may not support tools. Consider using a tool-use model.",
                     provider: "GroqProvider", model: model)
          end
        end

        # Add optional parameters (Groq supports most OpenAI parameters)
        body[:temperature] = kwargs[:temperature] if kwargs[:temperature]
        body[:max_tokens] = kwargs[:max_tokens] if kwargs[:max_tokens]
        body[:top_p] = kwargs[:top_p] if kwargs[:top_p]
        body[:stop] = kwargs[:stop] if kwargs[:stop]
        body[:presence_penalty] = kwargs[:presence_penalty] if kwargs[:presence_penalty]
        body[:frequency_penalty] = kwargs[:frequency_penalty] if kwargs[:frequency_penalty]
        body[:seed] = kwargs[:seed] if kwargs[:seed]
        body[:user] = kwargs[:user] if kwargs[:user]

        # Add response_format support for structured output
        # Groq supports JSON mode and some structured output features
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
      # @param model [String] Groq model to use
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
      # Returns list of supported Groq models
      #
      # @return [Array<String>] Supported model names
      #
      def supported_models
        SUPPORTED_MODELS
      end

      ##
      # Returns the provider name
      #
      # @return [String] "Groq"
      #
      def provider_name
        "Groq"
      end

      private

      ##
      # Handles streaming responses from Groq API
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
                  parsed = JSON.parse(data)

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
                  if parsed.dig("choices", 0, "finish_reason") && block_given? && block_given?
                    yield({
                      type: "finish",
                      finish_reason: parsed["choices"][0]["finish_reason"],
                      content: accumulated_content,
                      tool_calls: accumulated_tool_calls
                    })
                  end
                rescue JSON::ParserError => e
                  # Log but continue - some chunks might be partial
                  log_debug("Failed to parse streaming chunk: #{e.message}", provider: "GroqProvider",
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
      # Makes a request to the Groq API
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

        handle_api_error(response, "Groq") unless response.code.start_with?("2")

        JSON.parse(response.body)
      end

      ##
      # Makes a streaming request to the Groq API
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
            handle_api_error(response, "Groq") unless response.code.start_with?("2")

            response.read_body do |chunk|
              chunk.split("\n").each do |line|
                yield line if block_given?
              end
            end
          end
        end
      end

      ##
      # Handles Groq-specific API errors
      #
      # Groq has aggressive rate limits due to their high-performance infrastructure.
      # This method provides specific error messages for common Groq errors.
      #
      # @param response [HTTPResponse] API response
      # @param provider [String] Provider name (unused but required by interface)
      # @raise [AuthenticationError] for 401 errors
      # @raise [RateLimitError] for 429 errors with reset time
      # @raise [APIError] for other errors
      # @private
      #
      def handle_api_error(response, provider)
        case response.code.to_i
        when 401
          raise AuthenticationError, "Invalid Groq API key"
        when 429
          # Groq has aggressive rate limits, extract retry-after if available
          retry_after = response["x-ratelimit-reset"]
          raise RateLimitError, "Groq rate limit exceeded. Reset at: #{retry_after}"
        when 400
          # Parse error message from response
          begin
            error_data = JSON.parse(response.body)
            error_message = error_data.dig("error", "message") || response.body
          rescue StandardError
            error_message = response.body
          end
          raise APIError, "Groq API error: #{error_message}"
        else
          super
        end
      end
    end
  end
end
