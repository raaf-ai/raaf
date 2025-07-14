# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require_relative "interface"
require_relative "../errors"

module OpenAIAgents
  module Models
    ##
    # LiteLLM provider enables using any model via LiteLLM proxy
    #
    # LiteLLM provides a unified interface to 100+ LLM providers including OpenAI,
    # Anthropic, Google Gemini, AWS Bedrock, Azure, Cohere, Replicate, and many more.
    # It standardizes the API interface across all providers to OpenAI's format.
    #
    # Features:
    # - Support for 100+ LLM providers through a single interface
    # - Automatic provider detection from model prefix
    # - Provider-specific parameter handling
    # - Streaming support
    # - Function/tool calling
    # - Local model support via Ollama
    #
    # @example Basic usage with OpenAI model
    #   provider = LitellmProvider.new(model: "openai/gpt-4")
    #   response = provider.chat_completion(
    #     messages: [{ role: "user", content: "Hello!" }]
    #   )
    #
    # @example Using Anthropic through LiteLLM
    #   provider = LitellmProvider.new(model: "anthropic/claude-3-opus-20240229")
    #   response = provider.chat_completion(
    #     messages: messages,
    #     max_tokens: 1000
    #   )
    #
    # @example Using local Ollama model
    #   provider = LitellmProvider.new(
    #     model: "ollama/llama2",
    #     base_url: "http://localhost:8000"
    #   )
    #
    # See supported models at: https://docs.litellm.ai/docs/providers
    class LitellmProvider < ModelInterface
      # @!attribute [r] model
      #   @return [String] The model identifier with provider prefix
      # @!attribute [r] base_url
      #   @return [String] LiteLLM proxy URL
      # @!attribute [r] api_key
      #   @return [String, nil] API key for authentication
      attr_reader :model, :base_url, :api_key

      # Common LiteLLM model prefixes for different providers
      # Maps provider prefixes to human-readable provider names
      PROVIDER_PREFIXES = {
        "openai/" => "OpenAI",
        "anthropic/" => "Anthropic",
        "gemini/" => "Google Gemini",
        "bedrock/" => "AWS Bedrock",
        "azure/" => "Azure OpenAI",
        "vertex_ai/" => "Google Vertex AI",
        "palm/" => "Google PaLM",
        "cohere/" => "Cohere",
        "replicate/" => "Replicate",
        "huggingface/" => "Hugging Face",
        "together_ai/" => "Together AI",
        "openrouter/" => "OpenRouter",
        "ai21/" => "AI21 Labs",
        "baseten/" => "Baseten",
        "vllm/" => "vLLM",
        "nlp_cloud/" => "NLP Cloud",
        "aleph_alpha/" => "Aleph Alpha",
        "petals/" => "Petals",
        "ollama/" => "Ollama",
        "deepinfra/" => "DeepInfra",
        "perplexity/" => "Perplexity",
        "anyscale/" => "Anyscale",
        "groq/" => "Groq",
        "mistral/" => "Mistral AI",
        "claude-3" => "Anthropic Claude 3",
        "gpt-" => "OpenAI GPT"
      }.freeze

      ##
      # Initialize LiteLLM provider
      #
      # @param model [String] Model name with provider prefix (e.g., "openai/gpt-4", "anthropic/claude-3-opus")
      # @param base_url [String, nil] LiteLLM proxy URL (defaults to LITELLM_BASE_URL env var or http://localhost:8000)
      # @param api_key [String, nil] API key for the provider or LiteLLM proxy (defaults to LITELLM_API_KEY or OPENAI_API_KEY)
      #
      # @example
      #   provider = LitellmProvider.new(
      #     model: "gemini/gemini-pro",
      #     base_url: "http://litellm-proxy:8000",
      #     api_key: "your-api-key"
      #   )
      #
      def initialize(model:, base_url: nil, api_key: nil)
        @model = model
        @base_url = base_url || ENV["LITELLM_BASE_URL"] || "http://localhost:8000"
        @api_key = api_key || ENV["LITELLM_API_KEY"] || ENV.fetch("OPENAI_API_KEY", nil)

        # Ensure base_url doesn't end with /
        @base_url = @base_url.chomp("/")
      end

      ##
      # Get a human-readable provider name from the model string
      #
      # @return [String] Provider name (e.g., "OpenAI", "Anthropic", "Google Gemini")
      #
      def provider_name
        PROVIDER_PREFIXES.each do |prefix, name|
          return name if @model.start_with?(prefix)
        end
        "Unknown Provider"
      end

      ##
      # Chat completion using LiteLLM
      #
      # Sends a chat completion request through LiteLLM proxy. LiteLLM handles
      # the translation to the specific provider's API format.
      #
      # @param messages [Array<Hash>] Conversation messages
      # @param model [String, nil] Model to use (defaults to initialized model)
      # @param tools [Array<Hash>, nil] Tools/functions available to the model
      # @param stream [Boolean] Whether to stream the response
      # @param kwargs [Hash] Additional parameters (provider-specific)
      # @option kwargs [Float] :temperature Randomness in generation
      # @option kwargs [Integer] :max_tokens Maximum tokens to generate
      # @option kwargs [Hash] :extra_body Provider-specific parameters
      # @return [Hash] Response in OpenAI format
      # @raise [APIError] if the request fails
      #
      def chat_completion(messages:, model: nil, tools: nil, stream: false, **kwargs)
        model ||= @model

        # LiteLLM uses the standard OpenAI-compatible API format
        body = {
          model: model,
          messages: prepare_messages(messages)
        }

        # Add tools if provided
        if tools && !tools.empty?
          body[:tools] = prepare_tools(tools)
          body[:tool_choice] = kwargs[:tool_choice] if kwargs[:tool_choice]
        end

        # Add model-specific parameters
        add_model_parameters(body, kwargs)

        # Handle streaming
        if stream
          stream_completion(body)
        else
          make_request(body)
        end
      end

      ##
      # Check if provider supports prompts (for Responses API)
      #
      # LiteLLM primarily uses the chat completions format across all providers.
      #
      # @return [Boolean] Always false for LiteLLM
      #
      def supports_prompts?
        # Most providers through LiteLLM use chat completions format
        false
      end

      private

      ##
      # Makes a non-streaming request to LiteLLM
      #
      # @param body [Hash] Request body
      # @return [Hash] Parsed response
      # @raise [APIError] on request failure
      # @private
      #
      def make_request(body)
        uri = URI("#{@base_url}/v1/chat/completions")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.read_timeout = 120 # Longer timeout for some models

        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{@api_key}" if @api_key
        request["Content-Type"] = "application/json"
        request.body = body.to_json

        response = http.request(request)

        unless response.code.start_with?("2")
          error_body = begin
            JSON.parse(response.body)
          rescue StandardError
            { "error" => response.body }
          end
          handle_error(response.code.to_i, error_body)
        end

        JSON.parse(response.body)
      rescue Net::ReadTimeout => e
        raise APIError, "Request timeout: #{e.message}. Consider increasing timeout for large models."
      rescue StandardError => e
        raise APIError, "LiteLLM request failed: #{e.message}"
      end

      ##
      # Handles streaming completion requests
      #
      # @param body [Hash] Request body
      # @yield [Hash] Yields parsed streaming chunks
      # @private
      #
      def stream_completion(body)
        uri = URI("#{@base_url}/v1/chat/completions")
        body[:stream] = true

        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
          request = Net::HTTP::Post.new(uri)
          request["Authorization"] = "Bearer #{@api_key}" if @api_key
          request["Content-Type"] = "application/json"
          request["Accept"] = "text/event-stream"
          request.body = body.to_json

          http.request(request) do |response|
            unless response.code.start_with?("2")
              error_body = response.read_body
              handle_error(response.code.to_i, error_body)
            end

            response.read_body do |chunk|
              # Parse SSE format
              chunk.split("\n").each do |line|
                next if line.empty? || !line.start_with?("data: ")

                data = line[6..] # Remove "data: " prefix
                next if data == "[DONE]"

                begin
                  yield JSON.parse(data)
                rescue JSON::ParserError
                  # Skip invalid JSON
                end
              end
            end
          end
        end
      end

      ##
      # Prepares messages for LiteLLM format
      #
      # @param messages [Array<Hash>] Input messages
      # @return [Array<Hash>] Formatted messages
      # @private
      #
      def prepare_messages(messages)
        messages.map do |msg|
          role = msg[:role] || msg["role"]
          content = msg[:content] || msg["content"]

          # Handle tool messages
          if role == "tool"
            {
              role: "tool",
              content: content,
              tool_call_id: msg[:tool_call_id] || msg["tool_call_id"]
            }
          else
            base_msg = { role: role, content: content }

            # Add tool calls if present
            base_msg[:tool_calls] = msg[:tool_calls] || msg["tool_calls"] if msg[:tool_calls] || msg["tool_calls"]

            base_msg
          end
        end
      end

      ##
      # Prepares tools for OpenAI format
      #
      # @param tools [Array] Tools to prepare
      # @return [Array<Hash>] Formatted tools
      # @private
      #
      def prepare_tools(tools)
        tools.map do |tool|
          if tool.respond_to?(:to_h)
            tool_hash = tool.to_h
            {
              type: "function",
              function: {
                name: tool_hash[:name],
                description: tool_hash[:description],
                parameters: tool_hash[:parameters] || tool_hash[:input_schema]
              }
            }
          else
            tool
          end
        end
      end

      ##
      # Adds model parameters to request body
      #
      # Handles both standard OpenAI parameters and provider-specific parameters
      # passed through extra_body.
      #
      # @param body [Hash] Request body to modify
      # @param kwargs [Hash] Parameters to add
      # @private
      #
      def add_model_parameters(body, kwargs)
        # Standard OpenAI parameters
        body[:temperature] = kwargs[:temperature] if kwargs[:temperature]
        body[:max_tokens] = kwargs[:max_tokens] || kwargs[:max_completion_tokens]
        body[:top_p] = kwargs[:top_p] if kwargs[:top_p]
        body[:frequency_penalty] = kwargs[:frequency_penalty] if kwargs[:frequency_penalty]
        body[:presence_penalty] = kwargs[:presence_penalty] if kwargs[:presence_penalty]
        body[:stop] = kwargs[:stop] if kwargs[:stop]
        body[:seed] = kwargs[:seed] if kwargs[:seed]

        # Response format
        body[:response_format] = kwargs[:response_format] if kwargs[:response_format]

        # Provider-specific parameters can be passed through extra_body
        body.merge!(kwargs[:extra_body]) if kwargs[:extra_body].is_a?(Hash)

        # Some providers need special handling
        handle_provider_specifics(body, kwargs)
      end

      ##
      # Handles provider-specific parameter adjustments
      #
      # Different providers have different parameter requirements and formats.
      # This method adjusts the request body based on the provider.
      #
      # @param body [Hash] Request body to modify
      # @param kwargs [Hash] Additional parameters
      # @private
      #
      def handle_provider_specifics(body, kwargs)
        case @model
        when %r{^anthropic/}
          # Anthropic uses max_tokens instead of max_completion_tokens
          body[:max_tokens] ||= 4096

          # Anthropic-specific system prompt handling
          if body[:messages].first && body[:messages].first[:role] == "system"
            system_msg = body[:messages].shift
            body[:system] = system_msg[:content]
          end

        when %r{^gemini/}
          # Gemini specific adjustments
          body[:generation_config] = {
            temperature: body.delete(:temperature),
            max_output_tokens: body.delete(:max_tokens),
            top_p: body.delete(:top_p)
          }.compact

        when %r{^cohere/}
          # Cohere specific parameters
          body[:max_tokens] ||= 4000
          body[:connectors] = kwargs[:connectors] if kwargs[:connectors]

        when %r{^replicate/}
          # Replicate needs input wrapped
          body[:input] = {
            prompt: body[:messages].map { |m| "#{m[:role]}: #{m[:content]}" }.join("\n")
          }
          body.delete(:messages)
        end
      end

      ##
      # Handles API errors with appropriate exception types
      #
      # @param status_code [Integer] HTTP status code
      # @param error_body [Hash, String] Error response body
      # @raise [AuthenticationError, RateLimitError, ServerError, APIError]
      # @private
      #
      def handle_error(status_code, error_body)
        error_message = extract_error_message(error_body)

        case status_code
        when 400
          raise APIError, "Bad request: #{error_message}"
        when 401
          raise AuthenticationError, "Authentication failed: #{error_message}"
        when 403
          raise APIError, "Forbidden: #{error_message}"
        when 404
          raise APIError, "Model not found: #{@model}. #{error_message}"
        when 429
          raise RateLimitError, "Rate limit exceeded: #{error_message}"
        when 500..599
          raise ServerError, "LiteLLM server error: #{error_message}"
        else
          raise APIError, "LiteLLM error (#{status_code}): #{error_message}"
        end
      end

      ##
      # Extracts error message from various response formats
      #
      # @param error_body [Hash, String, Object] Error response
      # @return [String] Extracted error message
      # @private
      #
      def extract_error_message(error_body)
        case error_body
        when Hash
          error_body.dig("error", "message") ||
            error_body["error"] ||
            error_body["message"] ||
            error_body.to_s
        when String
          error_body
        else
          "Unknown error"
        end
      end
    end

    ##
    # Convenience class for easy setup with LiteLLM
    #
    # Provides predefined model configurations and helper methods for
    # common LiteLLM use cases.
    #
    # @example Using predefined model
    #   provider = LiteLLM.provider(:gpt4)
    #   # Equivalent to: LitellmProvider.new(model: "openai/gpt-4")
    #
    # @example Listing available models
    #   models = LiteLLM.available_models
    #   # => { gpt4: "openai/gpt-4", claude3_opus: "anthropic/claude-3-opus-20240229", ... }
    #
    class LiteLLM
      # List of popular models available through LiteLLM
      # Maps convenient symbols to full model identifiers
      MODELS = {
        # OpenAI
        gpt4o: "openai/gpt-4o",
        gpt4: "openai/gpt-4",
        gpt35: "openai/gpt-3.5-turbo",

        # Anthropic
        claude3_opus: "anthropic/claude-3-opus-20240229",
        claude3_sonnet: "anthropic/claude-3-sonnet-20240229",
        claude3_haiku: "anthropic/claude-3-haiku-20240307",
        claude2: "anthropic/claude-2.1",

        # Google
        gemini_pro: "gemini/gemini-pro",
        gemini_pro_vision: "gemini/gemini-pro-vision",
        palm2: "palm/chat-bison",

        # Cohere
        command: "cohere/command",
        command_light: "cohere/command-light",

        # Together AI
        llama2_70b: "together_ai/togethercomputer/llama-2-70b-chat",
        mistral_7b: "together_ai/mistralai/Mistral-7B-Instruct-v0.1",

        # Replicate
        llama2_13b: "replicate/meta/llama-2-13b-chat",

        # Ollama (local)
        ollama_llama2: "ollama/llama2",
        ollama_mistral: "ollama/mistral",
        ollama_codellama: "ollama/codellama"
      }.freeze

      ##
      # Create a LiteLLM provider for a specific model
      #
      # @param model_key_or_name [Symbol, String] Model key from MODELS hash or full model name
      # @param kwargs [Hash] Additional parameters for provider initialization
      # @return [LitellmProvider] Configured provider instance
      #
      # @example
      #   provider = LiteLLM.provider(:claude3_opus, api_key: "your-key")
      #   provider = LiteLLM.provider("custom/model-name")
      #
      def self.provider(model_key_or_name, **)
        model_name = MODELS[model_key_or_name] || model_key_or_name.to_s
        LitellmProvider.new(model: model_name, **)
      end

      ##
      # Get all available predefined models
      #
      # @return [Hash] Model key to identifier mapping
      #
      def self.available_models
        MODELS
      end
    end
  end
end
