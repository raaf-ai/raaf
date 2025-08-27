# frozen_string_literal: true

require "json"
require "net/http"
require "uri"
# Interface is required from raaf-core gem

module RAAF
  module Models
    ##
    # Together AI provider implementation
    #
    # Together AI provides access to a wide range of open-source models with
    # fast inference. The API is OpenAI-compatible, making it easy to use
    # various open-source models like Llama, Mistral, and others with the same interface.
    #
    # Features:
    # - Access to 50+ open-source models
    # - OpenAI-compatible API
    # - Fast inference speeds
    # - Function calling support on select models
    # - Streaming responses
    # - Custom safety models
    # - Flexible model naming (supports full model paths)
    #
    # @example Basic usage
    #   provider = TogetherProvider.new(api_key: ENV["TOGETHER_API_KEY"])
    #   response = provider.chat_completion(
    #     messages: [{ role: "user", content: "Hello!" }],
    #     model: "meta-llama/Llama-3-70b-chat-hf"
    #   )
    #
    # @example With streaming
    #   provider.stream_completion(messages: messages, model: "mistralai/Mixtral-8x7B-Instruct-v0.1") do |chunk|
    #     print chunk[:content]
    #   end
    #
    # @example With custom parameters
    #   provider.chat_completion(
    #     messages: messages,
    #     model: "NousResearch/Nous-Hermes-2-Mixtral-8x7B-DPO",
    #     temperature: 0.7,
    #     max_tokens: 2000,
    #     repetition_penalty: 1.1
    #   )
    #
    class TogetherProvider < ModelInterface
      # Together AI API base URL
      API_BASE = "https://api.together.xyz/v1"

      # Popular models available on Together AI
      # This is a subset of available models - Together supports many more
      SUPPORTED_MODELS = %w[
        meta-llama/Llama-3-70b-chat-hf
        meta-llama/Llama-3-8b-chat-hf
        meta-llama/Llama-2-70b-chat-hf
        meta-llama/Llama-2-13b-chat-hf
        meta-llama/Llama-2-7b-chat-hf
        mistralai/Mixtral-8x7B-Instruct-v0.1
        mistralai/Mistral-7B-Instruct-v0.2
        NousResearch/Nous-Hermes-2-Mixtral-8x7B-DPO
        NousResearch/Nous-Hermes-2-Yi-34B
        togethercomputer/llama-2-70b-chat
        WizardLM/WizardLM-70B-V1.0
        teknium/OpenHermes-2.5-Mistral-7B
        openchat/openchat-3.5-1210
        Qwen/Qwen1.5-72B-Chat
        deepseek-ai/deepseek-coder-33b-instruct
        codellama/CodeLlama-70b-Instruct-hf
        codellama/CodeLlama-34b-Instruct-hf
        codellama/CodeLlama-13b-Instruct-hf
      ].freeze

      ##
      # Initialize a new Together provider
      #
      # @param api_key [String, nil] Together API key (defaults to TOGETHER_API_KEY env var)
      # @param api_base [String, nil] API base URL (defaults to Together endpoint)
      # @param options [Hash] Additional options for the provider
      # @raise [AuthenticationError] if API key is not provided
      #
      def initialize(api_key: nil, api_base: nil, **options)
        super
        @api_key ||= ENV.fetch("TOGETHER_API_KEY", nil)
        @api_base ||= api_base || API_BASE

        raise AuthenticationError, "Together API key is required" unless @api_key

        # HTTP client initialization removed - using Net::HTTP directly for Together API
      end

      ##
      # Performs a chat completion using Together's API
      #
      # Together's API is OpenAI-compatible but adds some specific parameters
      # like repetition_penalty and safety_model.
      #
      # @param messages [Array<Hash>] Conversation messages
      # @param model [String] Model identifier (e.g., "meta-llama/Llama-3-70b-chat-hf")
      # @param tools [Array<Hash>, nil] Tools/functions available to the model
      # @param stream [Boolean] Whether to stream the response
      # @param kwargs [Hash] Additional parameters
      # @option kwargs [Float] :temperature (0.0-2.0) Randomness in generation
      # @option kwargs [Integer] :max_tokens Maximum tokens to generate
      # @option kwargs [Float] :repetition_penalty Penalty for repetition
      # @option kwargs [String] :safety_model Optional safety model to use
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
        # Together AI supports function calling on select models
        if tools && !tools.empty?
          body[:tools] = prepare_tools(tools)
          body[:tool_choice] = kwargs[:tool_choice] if kwargs[:tool_choice]
        end

        # Add optional parameters
        body[:temperature] = kwargs[:temperature] if kwargs[:temperature]
        body[:max_tokens] = kwargs[:max_tokens] if kwargs[:max_tokens]
        body[:top_p] = kwargs[:top_p] if kwargs[:top_p]
        body[:top_k] = kwargs[:top_k] if kwargs[:top_k]
        body[:repetition_penalty] = kwargs[:repetition_penalty] if kwargs[:repetition_penalty]
        body[:stop] = kwargs[:stop] if kwargs[:stop]
        body[:seed] = kwargs[:seed] if kwargs[:seed]

        # Together-specific parameters
        body[:response_format] = kwargs[:response_format] if kwargs[:response_format]
        body[:safety_model] = kwargs[:safety_model] if kwargs[:safety_model]

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
      # Note: Together supports many more models than listed here.
      # Use list_available_models() for a complete list.
      #
      # @return [Array<String>] Supported model names
      #
      def supported_models
        SUPPORTED_MODELS
      end

      ##
      # Returns the provider name
      #
      # @return [String] "Together"
      #
      def provider_name
        "Together"
      end

      ##
      # Get available models from Together API
      #
      # Fetches the current list of available models from Together's API.
      # Filters for chat/instruct models suitable for conversation.
      #
      # @return [Array<String>] List of available model IDs
      #
      # @example
      #   models = provider.list_available_models
      #   # => ["meta-llama/Llama-3-70b-chat-hf", "mistralai/Mixtral-8x7B-Instruct-v0.1", ...]
      #
      def list_available_models
        with_retry("list_models") do
          uri = URI("#{@api_base}/models")
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true

          request = Net::HTTP::Get.new(uri)
          request["Authorization"] = "Bearer #{@api_key}"
          request["Content-Type"] = "application/json"

          response = http.request(request)

          if response.code.start_with?("2")
            models = JSON.parse(response.body)
            # Filter for chat/instruct models
            chat_models = models.select do |model|
              model["id"].downcase.include?("chat") ||
                model["id"].downcase.include?("instruct") ||
                model["id"].downcase.include?("hermes")
            end

            chat_models.map { |m| m["id"] }
          else
            SUPPORTED_MODELS
          end
        end
      end

      private

      ##
      # Makes a request to the Together API
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

        handle_api_error(response, "Together") unless response.code.start_with?("2")

        RAAF::Utils.parse_json(response.body)
      end

      ##
      # Makes a streaming request to the Together API
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
            handle_api_error(response, "Together") unless response.code.start_with?("2")

            response.read_body do |chunk|
              chunk.split("\n").each do |line|
                yield line if block_given?
              end
            end
          end
        end
      end

      ##
      # Handles streaming responses from Together API
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

                  # Handle tool calls
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
                  log_debug("Failed to parse streaming chunk: #{e.message}", provider: "TogetherProvider",
                                                                             error_class: e.class.name)
                end
              end
            end
          end

          {
            content: accumulated_content,
            tool_calls: accumulated_tool_calls
          }
        end
      end

      ##
      # Override validation to handle Together's model naming
      #
      # Together uses full model paths like "meta-llama/Llama-3-70b-chat-hf".
      # This method allows any model with a slash in the name, assuming it's
      # a valid model path.
      #
      # @param model [String] Model identifier
      # @raise [ModelNotFoundError] if model format is invalid
      # @private
      #
      def validate_model(model)
        # Together uses full model paths, so we check if it's a known pattern
        return if model.include?("/") # Assume it's a valid model path

        # Otherwise check against our list
        super
      end

      ##
      # Custom error handling for Together API
      #
      # Provides specific error messages for Together API errors,
      # including rate limit information and validation errors.
      #
      # @param response [HTTPResponse] API response
      # @param provider [String] Provider name (unused but required by interface)
      # @raise [AuthenticationError] for 401 errors
      # @raise [RateLimitError] for 429 errors with retry information
      # @raise [APIError] for validation and other errors
      # @private
      #
      def handle_api_error(response, provider)
        case response.code.to_i
        when 401
          raise AuthenticationError, "Invalid Together API key"
        when 429
          # Extract rate limit info
          retry_after = response["retry-after"]
          limit = response["x-ratelimit-limit"]
          remaining = response["x-ratelimit-remaining"]

          message = "Together rate limit exceeded."
          message += " Retry after: #{retry_after}s" if retry_after
          message += " (Limit: #{limit}, Remaining: #{remaining})" if limit

          raise RateLimitError, message
        when 422
          # Model-specific errors
          begin
            error_data = JSON.parse(response.body)
            error_message = error_data["error"] || response.body
          rescue StandardError
            error_message = response.body
          end
          raise APIError, "Together API validation error: #{error_message}"
        else
          super
        end
      end
    end
  end
end
