# frozen_string_literal: true

module RAAF

  ##
  # Registry for decision model ("System One") providers
  #
  # This is deliberately separate from {RAAF::ProviderRegistry}. Decision
  # models answer typed questions and return probabilities; they cannot hold a
  # conversation, call a tool or stream. Listing +jev+ next to +gpt-4o+ would
  # let a chat caller be handed a model that cannot answer it, so the two kinds
  # of model get two registries.
  #
  # @example Creating a provider by name
  #   provider = DecisionRegistry.create(:jev, api_key: ENV["TYPESAFE_API_KEY"])
  #
  # @example Taking whatever is configured
  #   provider = DecisionRegistry.default
  #
  # @example Registering your own
  #   DecisionRegistry.register(:laya, MyApp::LayaProvider)
  #
  class DecisionRegistry

    # Mutex for thread-safe access to custom providers
    @providers_mutex = Mutex.new

    # Map of provider short names to provider class paths
    #
    # Vendor providers live in the raaf-providers gem and are resolved lazily,
    # so core does not depend on it.
    PROVIDER_CLASSES = {
      jev: "RAAF::Models::JevProvider",
      typesafe: "RAAF::Models::JevProvider",
      llm: "RAAF::Models::Decision::LLMBackedProvider"
    }.freeze

    # Map of model name patterns to provider short names
    MODEL_PATTERNS = {
      /^jev/i => :jev
    }.freeze

    # Environment variable naming the provider {.default} should build
    DEFAULT_PROVIDER_ENV = "RAAF_DECISION_PROVIDER"

    class << self

      ##
      # Detect the provider for a decision model name
      #
      # @param model_name [String, nil] The model name
      # @return [Symbol, nil] The provider short name, or nil if not detected
      #
      # @example
      #   DecisionRegistry.detect("jev-latest") # => :jev
      #
      def detect(model_name)
        return nil unless model_name

        MODEL_PATTERNS.each do |pattern, provider|
          return provider if model_name.match?(pattern)
        end

        nil
      end

      ##
      # Create a decision provider instance
      #
      # @param provider_name [Symbol, String] Short name of the provider
      # @param options [Hash] Options passed to the provider constructor
      # @return [RAAF::Models::DecisionInterface]
      # @raise [ArgumentError] If the provider name is not registered
      #
      def create(provider_name, **)
        provider_name = provider_name.to_sym

        class_path = PROVIDER_CLASSES[provider_name] || custom_provider_path(provider_name)
        raise ArgumentError, "Unknown decision provider: #{provider_name}. Available: #{providers.join(", ")}" unless class_path

        resolve_class(class_path).new(**)
      end

      ##
      # Create the provider for a decision model name
      #
      # @param model_name [String] The model name
      # @param options [Hash] Options passed to the provider constructor
      # @return [RAAF::Models::DecisionInterface]
      # @raise [ArgumentError] If no provider matches the model name
      #
      def for_model(model_name, **)
        provider = detect(model_name)
        raise ArgumentError, "No decision provider matches model: #{model_name.inspect}" unless provider

        create(provider, model: model_name, **)
      end

      ##
      # Build the configured decision provider
      #
      # Uses +RAAF_DECISION_PROVIDER+ when it is set. Otherwise it picks the
      # vendor provider whose API key is present, and falls back to
      # {RAAF::Models::Decision::LLMBackedProvider} so that code written
      # against the decision interface still runs with no decision API key.
      #
      # @param options [Hash] Options passed to the provider constructor
      # @return [RAAF::Models::DecisionInterface]
      #
      def default(**)
        configured = ENV.fetch(DEFAULT_PROVIDER_ENV, nil)
        return create(configured, **) if configured && !configured.strip.empty?

        return create(:jev, **) if ENV["TYPESAFE_API_KEY"] && defined?(RAAF::Models::JevProvider)

        create(:llm, **)
      end

      ##
      # Register a custom decision provider
      #
      # @param name [Symbol] Short name for the provider
      # @param class_path [String, Class] Provider class or class path
      # @return [void]
      #
      def register(name, class_path)
        name = name.to_sym
        class_path_str = class_path.is_a?(Class) ? class_path.name : class_path.to_s

        @providers_mutex.synchronize do
          @custom_providers ||= {}
          @custom_providers[name] = class_path_str
        end
      end

      ##
      # @return [Array<Symbol>] All registered provider short names
      #
      def providers
        custom = @providers_mutex.synchronize do
          @custom_providers ? @custom_providers.keys : []
        end

        (PROVIDER_CLASSES.keys + custom).uniq
      end

      ##
      # @param name [Symbol, String] Provider short name
      # @return [Boolean] Whether the provider is registered
      #
      def registered?(name)
        name = name.to_sym
        return true if PROVIDER_CLASSES.key?(name)

        @providers_mutex.synchronize do
          @custom_providers ? @custom_providers.key?(name) : false
        end
      end

      private

      ##
      # @param name [Symbol] Provider short name
      # @return [String, nil] Registered class path, or nil
      #
      def custom_provider_path(name)
        @providers_mutex.synchronize do
          @custom_providers && @custom_providers[name]
        end
      end

      ##
      # @param class_path [String] Class path like "RAAF::Models::JevProvider"
      # @return [Class]
      # @raise [NameError] If the class cannot be found
      #
      def resolve_class(class_path)
        class_path.split("::").reduce(Object) { |mod, name| mod.const_get(name) }
      rescue NameError => e
        raise NameError, "Could not load decision provider class: #{class_path}. Error: #{e.message}"
      end

    end

  end

end
