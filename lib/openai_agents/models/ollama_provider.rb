# frozen_string_literal: true

require "json"
require_relative "interface"
require_relative "retryable_provider"
require_relative "../http_client"

module OpenAIAgents
  module Models
    # Ollama API provider implementation for local models
    #
    # Ollama allows running large language models locally. It provides a simple
    # API for interacting with models like Llama, Mistral, and others.
    #
    # @example Basic usage
    #   provider = OllamaProvider.new(api_base: "http://localhost:11434")
    #   response = provider.chat_completion(
    #     messages: [{ role: "user", content: "Hello!" }],
    #     model: "llama2"
    #   )
    #
    # @example With custom model
    #   provider.chat_completion(
    #     messages: messages,
    #     model: "codellama:13b"
    #   )
    class OllamaProvider < ModelInterface
      include RetryableProvider

      DEFAULT_API_BASE = "http://localhost:11434"

      # Common Ollama models (this list is dynamic based on what's installed)
      COMMON_MODELS = %w[
        llama2
        llama2:13b
        llama2:70b
        llama3
        llama3:70b
        codellama
        codellama:13b
        codellama:34b
        mistral
        mixtral
        mixtral:8x7b
        gemma:2b
        gemma:7b
        phi
        neural-chat
        starling-lm
        orca-mini
        vicuna
        deepseek-coder
        qwen
      ].freeze

      def initialize(api_key: nil, api_base: nil, **options)
        super
        @api_base = api_base || ENV["OLLAMA_API_BASE"] || DEFAULT_API_BASE
        # Ollama doesn't require API keys for local usage
        @api_key = api_key

        @http_client = HTTPClient.new(
          default_headers: {
            "Content-Type" => "application/json"
          },
          timeout: options[:timeout] || 300 # Longer timeout for local models
        )

        # Check if Ollama is running
        check_ollama_status
      end

      def chat_completion(messages:, model:, tools: nil, stream: false, **kwargs)
        # NOTE: Ollama doesn't support tools/functions natively yet
        if tools && !tools.empty?
          puts "[OllamaProvider] Warning: Ollama doesn't support function calling. Tools will be ignored."
        end

        # Convert messages to Ollama format
        ollama_messages = messages.map do |msg|
          {
            role: msg[:role] || msg["role"],
            content: msg[:content] || msg["content"]
          }
        end

        body = {
          model: model,
          messages: ollama_messages,
          stream: stream
        }

        # Add optional parameters that Ollama supports
        body[:options] = {}
        body[:options][:temperature] = kwargs[:temperature] if kwargs[:temperature]
        body[:options][:top_p] = kwargs[:top_p] if kwargs[:top_p]
        body[:options][:seed] = kwargs[:seed] if kwargs[:seed]
        body[:options][:num_predict] = kwargs[:max_tokens] if kwargs[:max_tokens]
        body[:options][:stop] = kwargs[:stop] if kwargs[:stop]

        # Add system prompt if present
        system_msg = messages.find { |m| (m[:role] || m["role"]) == "system" }
        body[:system] = system_msg[:content] || system_msg["content"] if system_msg

        if stream
          stream_response(body, model, &block)
        else
          with_retry("chat_completion") do
            response = @http_client.post("#{@api_base}/api/chat", body: body)

            if response.success?
              convert_to_openai_format(response.parsed_body, model)
            else
              handle_api_error(response, "Ollama")
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
        # Dynamically fetch available models from Ollama

        response = @http_client.get("#{@api_base}/api/tags")
        if response.success?
          models = response.parsed_body["models"] || []
          models.map { |m| m["name"] }
        else
          COMMON_MODELS
        end
      rescue StandardError => e
        puts "[OllamaProvider] Failed to fetch models: #{e.message}"
        COMMON_MODELS
      end

      def provider_name
        "Ollama"
      end

      # Pull a model if not already available
      def pull_model(model_name)
        puts "[OllamaProvider] Pulling model #{model_name}..."

        body = { name: model_name, stream: false }
        response = @http_client.post("#{@api_base}/api/pull", body: body)

        if response.success?
          puts "[OllamaProvider] Successfully pulled #{model_name}"
          true
        else
          puts "[OllamaProvider] Failed to pull #{model_name}: #{response.body}"
          false
        end
      end

      # List all available models
      def list_models
        response = @http_client.get("#{@api_base}/api/tags")

        if response.success?
          models = response.parsed_body["models"] || []
          models.map do |model|
            {
              name: model["name"],
              size: model["size"],
              modified: model["modified_at"],
              digest: model["digest"]
            }
          end
        else
          []
        end
      end

      private

      def check_ollama_status
        response = @http_client.get("#{@api_base}/")
        unless response.success?
          raise ConnectionError, "Cannot connect to Ollama at #{@api_base}. Make sure Ollama is running."
        end
      rescue StandardError => e
        raise ConnectionError, "Cannot connect to Ollama at #{@api_base}: #{e.message}"
      end

      def convert_to_openai_format(ollama_response, model)
        # Convert Ollama response to OpenAI format
        message = ollama_response["message"] || {}

        {
          "id" => "ollama-#{SecureRandom.hex(12)}",
          "object" => "chat.completion",
          "created" => ollama_response["created_at"] || Time.now.to_i,
          "model" => model,
          "choices" => [{
            "index" => 0,
            "message" => {
              "role" => message["role"] || "assistant",
              "content" => message["content"] || ""
            },
            "finish_reason" => ollama_response["done"] ? "stop" : "length"
          }],
          "usage" => {
            "prompt_tokens" => ollama_response["prompt_eval_count"] || 0,
            "completion_tokens" => ollama_response["eval_count"] || 0,
            "total_tokens" => (ollama_response["prompt_eval_count"] || 0) + (ollama_response["eval_count"] || 0)
          }
        }
      end

      def stream_response(body, _model)
        body[:stream] = true
        accumulated_content = ""

        with_retry("stream_completion") do
          @http_client.post_stream("#{@api_base}/api/chat", body: body) do |chunk|
            # Ollama streams JSON objects directly, not SSE
            parsed = JSON.parse(chunk)

            if parsed["message"]
              content = parsed["message"]["content"] || ""
              accumulated_content += content

              if block_given?
                yield({
                  type: "content",
                  content: content,
                  accumulated_content: accumulated_content
                })
              end
            end

            # Check if done
            if parsed["done"] && block_given? && block_given?
              yield({
                type: "done",
                content: accumulated_content,
                eval_count: parsed["eval_count"],
                eval_duration: parsed["eval_duration"]
              })
            end
          rescue JSON::ParserError => e
            # Log parse error but continue
            puts "[OllamaProvider] Failed to parse stream chunk: #{e.message}"
          end

          {
            content: accumulated_content,
            tool_calls: [] # Ollama doesn't support tool calls yet
          }
        end
      end

      # Override error handling for Ollama-specific errors
      def handle_api_error(response, provider)
        case response.code.to_i
        when 404
          # Model not found - suggest pulling it
          error_body = begin
            JSON.parse(response.body)
          rescue StandardError
            {}
          end
          model = error_body["model"] || "unknown"
          raise ModelNotFoundError, "Model '#{model}' not found. Try pulling it with: ollama pull #{model}"
        when 500
          error_body = begin
            JSON.parse(response.body)
          rescue StandardError
            {}
          end
          error_message = error_body["error"] || response.body
          raise ServerError, "Ollama server error: #{error_message}"
        else
          super
        end
      end
    end

    # Custom errors for Ollama
    class ConnectionError < Error; end
    class ModelNotFoundError < Error; end
  end
end
