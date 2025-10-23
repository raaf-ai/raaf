# frozen_string_literal: true

module RAAF
  ##
  # Registry for mapping provider short names to provider classes
  # and auto-detecting providers based on model names
  #
  # This class provides a centralized way to:
  # - Map short symbolic names (like :anthropic) to provider classes
  # - Auto-detect the appropriate provider based on model name patterns
  # - Create provider instances with configuration options
  # - Register custom providers
  #
  # @example Basic provider detection
  #   provider = ProviderRegistry.detect("gpt-4o")
  #   # => :openai
  #
  # @example Creating a provider instance
  #   instance = ProviderRegistry.create(:anthropic, api_key: "key")
  #   # => #<RAAF::Models::AnthropicProvider>
  #
  # @example Registering a custom provider
  #   ProviderRegistry.register(:custom, MyCustomProvider)
  #   ProviderRegistry.create(:custom, api_key: "key")
  #
  class ProviderRegistry

    # Mutex for thread-safe access to custom providers
    @providers_mutex = Mutex.new

    # Map of provider short names to provider class paths
    PROVIDER_CLASSES = {
      openai: "RAAF::Models::ResponsesProvider",
      responses: "RAAF::Models::ResponsesProvider",
      anthropic: "RAAF::Models::AnthropicProvider",
      cohere: "RAAF::Models::CohereProvider",
      groq: "RAAF::Models::GroqProvider",
      perplexity: "RAAF::Models::PerplexityProvider",
      together: "RAAF::Models::TogetherProvider",
      litellm: "RAAF::Models::LiteLLMProvider"
    }.freeze

    # Map of model name patterns to provider short names
    # Patterns are checked in order, first match wins
    MODEL_PATTERNS = {
      /^gpt-/i => :openai,
      /^o1-/i => :openai,
      /^o3-/i => :openai,
      /^claude-/i => :anthropic,
      /^command-/i => :cohere,
      /^mixtral-/i => :groq,
      /^llama-/i => :groq,
      /^gemma-/i => :groq,
      /^sonar-/i => :perplexity,
      /^sonar$/i => :perplexity,  # Support plain "sonar" as model name
      /^perplexity$/i => :perplexity  # Support plain "perplexity" as model name
    }.freeze

    class << self

      ##
      # Detect provider from model name
      #
      # @param model_name [String] The model name to detect provider for
      # @return [Symbol, nil] The provider short name, or nil if not detected
      #
      # @example
      #   ProviderRegistry.detect("gpt-4o") # => :openai
      #   ProviderRegistry.detect("claude-3-5-sonnet-20241022") # => :anthropic
      #   ProviderRegistry.detect("unknown-model") # => nil
      #
      def detect(model_name)
        return nil unless model_name

        MODEL_PATTERNS.each do |pattern, provider|
          return provider if model_name.match?(pattern)
        end

        nil
      end

      ##
      # Create a provider instance
      #
      # @param provider_name [Symbol, String] Short name of the provider
      # @param options [Hash] Configuration options to pass to provider constructor
      # @return [Object] Provider instance
      # @raise [ArgumentError] If provider name is not registered
      #
      # @example
      #   provider = ProviderRegistry.create(:anthropic, api_key: ENV['ANTHROPIC_API_KEY'])
      #   provider = ProviderRegistry.create(:openai, api_key: ENV['OPENAI_API_KEY'])
      #
      def create(provider_name, **options)
        provider_name = provider_name.to_sym

        class_path = PROVIDER_CLASSES[provider_name]
        raise ArgumentError, "Unknown provider: #{provider_name}. Available: #{PROVIDER_CLASSES.keys.join(', ')}" unless class_path

        # Get the provider class
        provider_class = resolve_class(class_path)

        # Create and return instance
        provider_class.new(**options)
      end

      ##
      # Register a custom provider
      #
      # @param name [Symbol] Short name for the provider
      # @param class_path [String, Class] Provider class or class path
      #
      # @example
      #   ProviderRegistry.register(:custom, MyApp::CustomProvider)
      #   ProviderRegistry.register(:custom, "MyApp::CustomProvider")
      #
      def register(name, class_path)
        name = name.to_sym

        # Store as string for consistent handling
        class_path_str = class_path.is_a?(Class) ? class_path.name : class_path.to_s

        # Thread-safe registration with mutex protection
        @providers_mutex.synchronize do
          @custom_providers ||= {}
          @custom_providers[name] = class_path_str
        end
      end

      ##
      # Get all registered provider names
      #
      # @return [Array<Symbol>] List of registered provider short names
      #
      def providers
        base_providers = PROVIDER_CLASSES.keys
        custom_providers = @providers_mutex.synchronize do
          @custom_providers ? @custom_providers.keys : []
        end
        (base_providers + custom_providers).uniq
      end

      ##
      # Check if a provider is registered
      #
      # @param name [Symbol, String] Provider short name
      # @return [Boolean] True if provider is registered
      #
      def registered?(name)
        name = name.to_sym
        is_built_in = PROVIDER_CLASSES.key?(name)

        is_custom = @providers_mutex.synchronize do
          @custom_providers && @custom_providers.key?(name)
        end

        is_built_in || is_custom
      end

      private

      ##
      # Resolve a class from a string path
      #
      # @param class_path [String] Class path like "RAAF::Models::AnthropicProvider"
      # @return [Class] The resolved class
      # @raise [NameError] If class cannot be found
      #
      def resolve_class(class_path)
        # Check if it's a custom provider first (with thread-safe access)
        is_custom = @providers_mutex.synchronize do
          @custom_providers && @custom_providers.value?(class_path)
        end

        # Try to constantize the path
        parts = class_path.split('::')
        parts.reduce(Object) { |mod, name| mod.const_get(name) }
      rescue NameError => e
        raise NameError, "Could not load provider class: #{class_path}. Error: #{e.message}"
      end

    end
  end
end
