# frozen_string_literal: true

require_relative "anthropic_provider"
require_relative "cohere_provider"
require_relative "groq_provider"
require_relative "ollama_provider"
require_relative "together_provider"
require_relative "litellm_provider"

module OpenAIAgents
  module Models
    ##
    # MultiProvider - Automatic provider selection and management
    #
    # The MultiProvider class provides automatic provider selection based on model names,
    # enabling seamless switching between different AI providers without manual configuration.
    # This class acts as a factory and registry for all supported AI providers.
    #
    # == Supported Providers
    #
    # * **Anthropic**: Claude models (claude-3-sonnet, claude-3-haiku, etc.)
    # * **Google Gemini**: Gemini models (gemini-1.5-pro, gemini-1.5-flash, etc.)
    # * **Cohere**: Command models (command-r, command-r-plus, etc.)
    # * **Groq**: Fast inference for Llama, Mixtral, Gemma models
    # * **Together AI**: Open-source models (Meta-Llama, Mistral, etc.)
    # * **Ollama**: Local models (CodeLlama, Phi, Orca, Vicuna, etc.)
    # * **LiteLLM**: Unified interface for OpenAI and other providers
    #
    # == Automatic Provider Selection
    #
    # The MultiProvider automatically selects the appropriate provider based on model naming
    # patterns, eliminating the need for manual provider configuration in most cases.
    #
    # @example Automatic provider selection
    #   # Automatically selects AnthropicProvider
    #   provider = MultiProvider.auto_provider(model: "claude-3-sonnet")
    #   
    #   # Automatically selects GeminiProvider
    #   provider = MultiProvider.auto_provider(model: "gemini-1.5-pro")
    #   
    #   # Automatically selects GroqProvider for fast inference
    #   provider = MultiProvider.auto_provider(model: "llama-3-70b")
    #
    # @example Manual provider creation
    #   # Create specific provider with custom options
    #   anthropic = MultiProvider.create_provider("anthropic", api_key: "custom-key")
    #   groq = MultiProvider.create_provider("groq", timeout: 30)
    #
    # @example List supported providers
    #   puts "Available providers: #{MultiProvider.supported_providers}"
    #   # => ["anthropic", "gemini", "cohere", "groq", "ollama", "together", "litellm"]
    #
    # @example Provider detection for model
    #   provider_name = MultiProvider.get_provider_for_model("claude-3-sonnet")
    #   puts "Best provider for claude-3-sonnet: #{provider_name}"  # => "anthropic"
    #
    # @author OpenAI Agents Ruby Team
    # @since 0.1.0
    # @see OpenAIAgents::Models::AnthropicProvider For Anthropic-specific configuration
    # @see OpenAIAgents::Models::GroqProvider For Groq-specific configuration
    class MultiProvider
      ##
      # Registry of all supported AI providers
      #
      # Returns a hash mapping provider names to their implementation classes.
      # This registry is used for provider discovery and instantiation.
      #
      # @return [Hash<String, Class>] mapping of provider names to classes
      #
      # @example Access provider registry
      #   MultiProvider.providers.each do |name, klass|
      #     puts "#{name}: #{klass}"
      #   end
      def self.providers
        @providers ||= {
          "anthropic" => AnthropicProvider,
          "gemini" => GeminiProvider,
          "cohere" => CohereProvider,
          "groq" => GroqProvider,
          "ollama" => OllamaProvider,
          "together" => TogetherProvider,
          "litellm" => LitellmProvider
        }
      end

      ##
      # Create a provider instance by name
      #
      # Creates and returns a new instance of the specified provider class
      # with the given configuration options.
      #
      # @param provider_name [String, Symbol] name of the provider to create
      # @param kwargs [Hash] configuration options passed to provider constructor
      # @return [ModelInterface] configured provider instance
      # @raise [ArgumentError] if provider_name is not supported
      #
      # @example Create Anthropic provider
      #   provider = MultiProvider.create_provider("anthropic", api_key: "sk-...")
      #
      # @example Create Groq provider with timeout
      #   provider = MultiProvider.create_provider(:groq, timeout: 30, max_retries: 3)
      def self.create_provider(provider_name, **kwargs)
        provider_class = providers[provider_name.to_s.downcase]
        raise ArgumentError, "Unknown provider: #{provider_name}" unless provider_class

        provider_class.new(**kwargs)
      end

      ##
      # List all supported provider names
      #
      # Returns an array of all provider names that can be used with
      # create_provider or auto_provider methods.
      #
      # @return [Array<String>] list of supported provider names
      #
      # @example Check if provider is supported
      #   if MultiProvider.supported_providers.include?("anthropic")
      #     puts "Anthropic is supported!"
      #   end
      def self.supported_providers
        providers.keys
      end

      ##
      # Determine the best provider for a given model
      #
      # Analyzes the model name and returns the most appropriate provider
      # based on model naming patterns and performance characteristics.
      #
      # @param model [String] the model name to analyze
      # @return [String] the recommended provider name
      #
      # @example Model-specific provider selection
      #   MultiProvider.get_provider_for_model("claude-3-sonnet")     # => "anthropic"
      #   MultiProvider.get_provider_for_model("gpt-4")              # => "litellm"
      #   MultiProvider.get_provider_for_model("llama-3-70b")        # => "groq"
      #   MultiProvider.get_provider_for_model("gemini-1.5-pro")     # => "gemini"
      #   MultiProvider.get_provider_for_model("unknown-model")      # => "groq"
      def self.get_provider_for_model(model)
        case model
        when /^gpt-/, /^o1-/
          # Use LiteLLM for OpenAI models to avoid deprecated OpenAIProvider
          "litellm"
        when /^claude-/
          "anthropic"
        when /^gemini-/
          "gemini"
        when /^command-/
          "cohere"
        when /^llama/, /^mixtral/, /^gemma/
          # Could be Groq, Together, or Ollama - default to Groq for speed
          "groq"
        when /^meta-llama/, /^mistralai/, /^NousResearch/, /^togethercomputer/
          "together"
        when /^codellama/, /^phi/, /^orca/, /^vicuna/
          "ollama"
        else
          # Default to a modern provider instead of deprecated OpenAI
          "groq"
        end
      end

      ##
      # Automatically create the best provider for a model
      #
      # This is the main method for automatic provider selection. It combines
      # model analysis and provider creation into a single convenient method.
      #
      # @param model [String] the model name to create a provider for
      # @param kwargs [Hash] configuration options passed to provider constructor
      # @return [ModelInterface] configured provider instance
      #
      # @example Automatic provider selection
      #   # Automatically selects and creates AnthropicProvider
      #   provider = MultiProvider.auto_provider(model: "claude-3-sonnet")
      #   
      #   # Automatically selects GroqProvider with custom options
      #   provider = MultiProvider.auto_provider(
      #     model: "llama-3-70b",
      #     api_key: "custom-key",
      #     timeout: 30
      #   )
      def self.auto_provider(model:, **kwargs)
        provider_name = get_provider_for_model(model)
        create_provider(provider_name, **kwargs)
      end
    end

    ##
    # Google Gemini Provider
    #
    # Provider implementation for Google's Gemini models, including Gemini 1.5 Pro,
    # Gemini 1.5 Flash, and Gemini 1.0 Pro. Supports text generation and basic
    # tool calling capabilities.
    #
    # @example Create Gemini provider
    #   provider = GeminiProvider.new(api_key: "your-gemini-key")
    #   
    # @example Use with auto-detection
    #   provider = MultiProvider.auto_provider(model: "gemini-1.5-pro")
    #
    # @see https://ai.google.dev/docs For Gemini API documentation
    class GeminiProvider < ModelInterface
      DEFAULT_API_BASE = "https://generativelanguage.googleapis.com"

      SUPPORTED_MODELS = %w[
        gemini-1.5-pro gemini-1.5-flash gemini-1.0-pro
      ].freeze

      # rubocop:disable Lint/MissingSuper
      def initialize(api_key: nil, api_base: nil, **options)
        @api_key = api_key || ENV.fetch("GEMINI_API_KEY", nil)
        @api_base = api_base || ENV["GEMINI_API_BASE"] || DEFAULT_API_BASE
        @options = options

        raise AuthenticationError, "Gemini API key is required" unless @api_key
      end
      # rubocop:enable Lint/MissingSuper

      # rubocop:disable Lint/UnusedMethodArgument
      def chat_completion(messages:, model:, tools: nil, stream: false, **_kwargs)
        validate_model(model)

        uri = URI("#{@api_base}/v1beta/models/#{model}:generateContent?key=#{@api_key}")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"

        body = {
          contents: convert_messages_to_gemini(messages)
        }
        body[:tools] = convert_tools_to_gemini(tools) if tools

        request.body = JSON.generate(body)

        response = http.request(request)

        handle_api_error(response, "Gemini") unless response.is_a?(Net::HTTPSuccess)

        result = JSON.parse(response.body)
        convert_gemini_to_openai_format(result)
      end

      def stream_completion(messages:, model:, tools: nil)
        # Simplified implementation - Gemini streaming is more complex
        result = chat_completion(messages: messages, model: model, tools: tools)
        content = result.dig("choices", 0, "message", "content") || ""

        # Simulate streaming by yielding chunks
        content.chars.each_slice(10) do |chunk_chars|
          chunk = chunk_chars.join
          next unless block_given?

          yield({
            type: "content",
            content: chunk,
            accumulated_content: content
          })
        end

        { content: content, tool_calls: [] }
      end

      def supported_models
        SUPPORTED_MODELS
      end

      def provider_name
        "Gemini"
      end

      private

      def convert_messages_to_gemini(messages)
        messages.map do |message|
          {
            role: message[:role] == "assistant" ? "model" : "user",
            parts: [{ text: message[:content] }]
          }
        end
      end

      def convert_tools_to_gemini(tools)
        return [] unless tools

        [{
          function_declarations: tools.map do |tool|
            if tool.is_a?(Hash) && tool[:type] == "function"
              {
                name: tool.dig(:function, :name),
                description: tool.dig(:function, :description),
                parameters: tool.dig(:function, :parameters) || {}
              }
            else
              tool
            end
          end
        }]
      end
      # rubocop:enable Lint/UnusedMethodArgument

      def convert_gemini_to_openai_format(result)
        content = result.dig("candidates", 0, "content", "parts", 0, "text") || ""

        {
          "choices" => [{
            "message" => {
              "role" => "assistant",
              "content" => content
            },
            "finish_reason" => result.dig("candidates", 0, "finishReason")&.downcase || "stop"
          }],
          "usage" => result["usageMetadata"],
          "model" => result["modelVersion"]
        }
      end
    end
  end
end
