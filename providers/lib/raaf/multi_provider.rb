# frozen_string_literal: true

require_relative "anthropic_provider"
require_relative "cohere_provider"
require_relative "groq_provider"
require_relative "together_provider"
require_relative "litellm_provider"

module RAAF
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
    #   # => ["anthropic", "gemini", "cohere", "groq", "together", "litellm"]
    #
    # @example Provider detection for model
    #   provider_name = MultiProvider.get_provider_for_model("claude-3-sonnet")
    #   puts "Best provider for claude-3-sonnet: #{provider_name}"  # => "anthropic"
    #
    # @author RAAF (Ruby AI Agents Factory) Team
    # @since 0.1.0
    # @see RAAF::Models::AnthropicProvider For Anthropic-specific configuration
    # @see RAAF::Models::GroqProvider For Groq-specific configuration
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
          # Could be Groq or Together - default to Groq for speed
          "groq"
        when /^meta-llama/, /^mistralai/, /^NousResearch/, /^togethercomputer/, /^codellama/, /^phi/, /^orca/, /^vicuna/
          "together"
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

    # GeminiProvider now defined in gemini_provider.rb
    # See: raaf/providers/lib/raaf/gemini_provider.rb
  end
end
