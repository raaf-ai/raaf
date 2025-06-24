# frozen_string_literal: true

require "json"
require_relative "interface"
require_relative "retryable_provider"
require_relative "../http_client"

module OpenAIAgents
  module Models
    # Together AI provider implementation
    #
    # Together AI provides access to a wide range of open-source models with
    # fast inference. The API is OpenAI-compatible.
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
    class TogetherProvider < ModelInterface
      include RetryableProvider

      API_BASE = "https://api.together.xyz/v1"

      # Popular models available on Together AI
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

      def initialize(api_key: nil, api_base: nil, **options)
        super
        @api_key ||= ENV.fetch("TOGETHER_API_KEY", nil)
        @api_base ||= api_base || API_BASE

        raise AuthenticationError, "Together API key is required" unless @api_key

        @http_client = HTTPClient.new(default_headers: {
                                        "Authorization" => "Bearer #{@api_key}",
                                        "Content-Type" => "application/json"
                                      })
      end

      def chat_completion(messages:, model:, tools: nil, stream: false, **kwargs)
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
            response = @http_client.post("#{@api_base}/chat/completions", body: body)

            if response.success?
              response.parsed_body
            else
              handle_api_error(response, "Together")
            end
          end
        end
      end

      def stream_completion(messages:, model:, tools: nil, **kwargs)
        chat_completion(
          messages: messages,
          model: model,
          tools: tools,
          stream: true,
          **kwargs
        ) do |chunk|
          yield chunk if block_given?
        end
      end

      def supported_models
        SUPPORTED_MODELS
      end

      def provider_name
        "Together"
      end

      # Get available models from Together API
      def list_available_models
        with_retry("list_models") do
          response = @http_client.get("#{@api_base}/models")

          if response.success?
            models = response.parsed_body
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

      def stream_response(body)
        body[:stream] = true

        with_retry("stream_completion") do
          accumulated_content = ""
          accumulated_tool_calls = []

          @http_client.post_stream("#{@api_base}/chat/completions", body: body) do |chunk|
            # Parse SSE chunk
            if chunk.start_with?("data: ")
              data = chunk[6..-1].strip

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
                  if parsed.dig("choices", 0, "finish_reason") && block_given? && block_given?
                    yield({
                      type: "finish",
                      finish_reason: parsed["choices"][0]["finish_reason"],
                      content: accumulated_content,
                      tool_calls: accumulated_tool_calls
                    })
                  end
                rescue JSON::ParserError => e
                  puts "[TogetherProvider] Failed to parse streaming chunk: #{e.message}"
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

      # Override validation to handle Together's model naming
      def validate_model(model)
        # Together uses full model paths, so we check if it's a known pattern
        return if model.include?("/") # Assume it's a valid model path

        # Otherwise check against our list
        super
      end

      # Custom error handling for Together API
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
