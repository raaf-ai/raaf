# frozen_string_literal: true

require "json"
require_relative "interface"
require_relative "retryable_provider"
require_relative "../http_client"

module OpenAIAgents
  module Models
    # Groq API provider implementation
    #
    # Groq provides ultra-fast inference for open-source models like Llama, Mixtral, and Gemma.
    # The API is OpenAI-compatible, making integration straightforward.
    #
    # @example Basic usage
    #   provider = GroqProvider.new(api_key: ENV["GROQ_API_KEY"])
    #   response = provider.chat_completion(
    #     messages: [{ role: "user", content: "Hello!" }],
    #     model: "llama3-8b-8192"
    #   )
    #
    # @example With streaming
    #   provider.stream_completion(messages: messages, model: "mixtral-8x7b-32768") do |chunk|
    #     print chunk[:content]
    #   end
    class GroqProvider < ModelInterface
      include RetryableProvider

      API_BASE = "https://api.groq.com/openai/v1"

      # Groq's available models as of 2024
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

      def initialize(api_key: nil, api_base: nil, **options)
        super
        @api_key ||= ENV.fetch("GROQ_API_KEY", nil)
        @api_base ||= api_base || API_BASE

        raise AuthenticationError, "Groq API key is required" unless @api_key

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

        # Add tools if provided (Groq supports function calling on select models)
        if tools && !tools.empty?
          if model.include?("tool-use")
            body[:tools] = prepare_tools(tools)
            body[:tool_choice] = kwargs[:tool_choice] if kwargs[:tool_choice]
          else
            puts "[GroqProvider] Warning: Model #{model} may not support tools. Consider using a tool-use model."
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

        if stream
          stream_response(body, &block)
        else
          with_retry("chat_completion") do
            response = @http_client.post("#{@api_base}/chat/completions", body: body)

            if response.success?
              response.parsed_body
            else
              handle_api_error(response, "Groq")
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
        "Groq"
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
                  puts "[GroqProvider] Failed to parse streaming chunk: #{e.message}"
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

      # Override handle_api_error to add Groq-specific error handling
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
