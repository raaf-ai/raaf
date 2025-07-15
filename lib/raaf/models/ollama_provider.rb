# frozen_string_literal: true

require "json"
require_relative "interface"
require_relative "retryable_provider"
require_relative "../http_client"
require_relative "../logging"

module RubyAIAgentsFactory
  module Models
    ##
    # Ollama API provider implementation for local models
    #
    # Ollama allows running large language models locally on your own hardware.
    # It provides a simple API for interacting with models like Llama, Mistral,
    # CodeLlama, and many others. This provider translates between OpenAI's API
    # format and Ollama's local API.
    #
    # Features:
    # - Run models completely locally without internet
    # - Support for various open-source models
    # - Automatic model pulling if not available
    # - Streaming responses
    # - No API keys required for local usage
    # - Custom model parameters
    #
    # Note: Function calling is not yet supported by Ollama.
    #
    # @example Basic usage
    #   provider = OllamaProvider.new(api_base: "http://localhost:11434")
    #   response = provider.chat_completion(
    #     messages: [{ role: "user", content: "Hello!" }],
    #     model: "llama2"
    #   )
    #
    # @example With custom model and parameters
    #   provider.chat_completion(
    #     messages: messages,
    #     model: "codellama:13b",
    #     temperature: 0.7,
    #     max_tokens: 2000
    #   )
    #
    # @example Pulling a new model
    #   provider.pull_model("mixtral:8x7b")
    #   provider.chat_completion(messages: messages, model: "mixtral:8x7b")
    #
    class OllamaProvider < ModelInterface
      include Logger
      include RetryableProvider

      # Default Ollama API endpoint
      DEFAULT_API_BASE = "http://localhost:11434"

      # Common Ollama models (this list is dynamic based on what's installed)
      # These are just examples - many more models are available
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

      ##
      # Initialize a new Ollama provider
      #
      # @param api_key [String, nil] Not required for Ollama (kept for interface compatibility)
      # @param api_base [String, nil] Ollama API URL (defaults to OLLAMA_API_BASE env var or http://localhost:11434)
      # @param options [Hash] Additional options
      # @option options [Integer] :timeout Request timeout in seconds (default: 300)
      # @raise [ConnectionError] if cannot connect to Ollama
      #
      def initialize(api_key: nil, api_base: nil, **options)
        super
        @api_base = api_base || ENV["OLLAMA_API_BASE"] || DEFAULT_API_BASE
        # Ollama doesn't require API keys for local usage
        @api_key = api_key

        @http_client = HTTPClient::Client.new(
          api_key: @api_key || "not-required-for-ollama",
          base_url: @api_base,
          timeout: options[:timeout] || 300 # Longer timeout for local models
        )

        # Check if Ollama is running
        check_ollama_status
      end

      ##
      # Performs a chat completion using local Ollama model
      #
      # @param messages [Array<Hash>] Conversation messages
      # @param model [String] Ollama model name (e.g., "llama2", "codellama:13b")
      # @param tools [Array<Hash>, nil] Not supported by Ollama (will log warning)
      # @param stream [Boolean] Whether to stream the response
      # @param kwargs [Hash] Additional parameters
      # @option kwargs [Float] :temperature (0.0-2.0) Randomness in generation
      # @option kwargs [Integer] :max_tokens Maximum tokens to generate
      # @option kwargs [Float] :top_p Nucleus sampling parameter
      # @option kwargs [Integer] :seed Random seed for reproducibility
      # @return [Hash] Response in OpenAI format
      # @raise [ModelNotFoundError] if model is not pulled
      # @raise [ServerError] if Ollama server encounters an error
      #
      def chat_completion(messages:, model:, tools: nil, stream: false, **kwargs)
        # NOTE: Ollama doesn't support tools/functions natively yet
        if tools && !tools.empty?
          log_warn("Ollama doesn't support function calling. Tools will be ignored.", provider: "Ollama",
                                                                                      tool_count: tools&.size)
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

      ##
      # Streams a chat completion
      #
      # Convenience method that calls chat_completion with stream: true.
      #
      # @param messages [Array<Hash>] Conversation messages
      # @param model [String] Ollama model to use
      # @param tools [Array<Hash>, nil] Not supported
      # @param kwargs [Hash] Additional parameters
      # @yield [Hash] Yields streaming chunks
      # @return [Hash] Final accumulated response
      #
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

      ##
      # Returns list of available models
      #
      # Dynamically fetches the list of models currently available in Ollama.
      # Falls back to COMMON_MODELS if the API call fails.
      #
      # @return [Array<String>] Available model names
      #
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
        log_error("Failed to fetch models: #{e.message}", provider: "Ollama", error_class: e.class.name)
        COMMON_MODELS
      end

      ##
      # Returns the provider name
      #
      # @return [String] "Ollama"
      #
      def provider_name
        "Ollama"
      end

      ##
      # Pull a model if not already available
      #
      # Downloads and installs a model from the Ollama library.
      # This may take time depending on model size and internet speed.
      #
      # @param model_name [String] Name of the model to pull (e.g., "llama2:70b")
      # @return [Boolean] True if successful, false otherwise
      #
      # @example
      #   provider.pull_model("mixtral:8x7b")
      #
      def pull_model(model_name)
        log_info("Pulling model #{model_name}...", provider: "Ollama", model: model_name)

        body = { name: model_name, stream: false }
        response = @http_client.post("#{@api_base}/api/pull", body: body)

        if response.success?
          log_info("Successfully pulled #{model_name}", provider: "Ollama", model: model_name)
          true
        else
          log_error("Failed to pull #{model_name}: #{response.body}", provider: "Ollama", model: model_name,
                                                                      response_code: response.code)
          false
        end
      end

      ##
      # List all available models with metadata
      #
      # Returns detailed information about each available model including
      # size, modification date, and digest.
      #
      # @return [Array<Hash>] Model information
      #   - :name [String] Model name
      #   - :size [Integer] Model size in bytes
      #   - :modified [String] Last modification time
      #   - :digest [String] Model digest/hash
      #
      # @example
      #   models = provider.list_models
      #   # => [{ name: "llama2", size: 3826793497, modified: "2024-01-15T...", digest: "..." }]
      #
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

      ##
      # Checks if Ollama server is running and accessible
      #
      # @raise [ConnectionError] if cannot connect to Ollama
      # @private
      #
      def check_ollama_status
        response = @http_client.get("#{@api_base}/")
        unless response.success?
          raise ConnectionError, "Cannot connect to Ollama at #{@api_base}. Make sure Ollama is running."
        end
      rescue StandardError => e
        raise ConnectionError, "Cannot connect to Ollama at #{@api_base}: #{e.message}"
      end

      ##
      # Converts Ollama response to OpenAI format
      #
      # @param ollama_response [Hash] Response from Ollama API
      # @param model [String] Model name used
      # @return [Hash] Response in OpenAI format
      # @private
      #
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

      ##
      # Handles streaming responses from Ollama
      #
      # Ollama uses direct JSON streaming instead of Server-Sent Events.
      #
      # @param body [Hash] Request body
      # @param _model [String] Model name (unused)
      # @yield [Hash] Yields streaming chunks
      # @return [Hash] Final accumulated response
      # @private
      #
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
            log_debug("Failed to parse stream chunk: #{e.message}", provider: "Ollama", error_class: e.class.name)
          end

          {
            content: accumulated_content,
            tool_calls: [] # Ollama doesn't support tool calls yet
          }
        end
      end

      ##
      # Handles Ollama-specific API errors
      #
      # @param response [HTTPResponse] API response
      # @param provider [String] Provider name (unused)
      # @raise [ModelNotFoundError] if model needs to be pulled
      # @raise [ServerError] for server errors
      # @private
      #
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

    ##
    # Raised when cannot connect to Ollama server
    class ConnectionError < Error; end
    
    ##
    # Raised when requested model is not available locally
    class ModelNotFoundError < Error; end
  end
end
