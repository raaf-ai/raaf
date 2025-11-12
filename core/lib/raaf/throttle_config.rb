# frozen_string_literal: true

module RAAF
  ##
  # ThrottleConfig provides centralized default RPM limits for all providers
  #
  # This module maintains a registry of default rate limits for each AI provider,
  # allowing automatic configuration based on provider type. Limits can be overridden
  # via environment variables using the pattern: RAAF_THROTTLE_<PROVIDER>_RPM
  #
  # @example Get default RPM for a provider
  #   ThrottleConfig.default_rpm_for(:gemini)
  #   # => 10
  #
  # @example Override with environment variable
  #   ENV['RAAF_THROTTLE_GEMINI_RPM'] = '60'
  #   ThrottleConfig.default_rpm_for(:gemini)
  #   # => 60
  #
  # @example Auto-detect provider from class
  #   ThrottleConfig.rpm_for_provider(MyGeminiProvider.new)
  #   # => 10
  #
  module ThrottleConfig
    ##
    # Default RPM limits for all providers
    #
    # These represent conservative defaults based on typical free/standard tiers.
    # Paid tiers with higher limits should override via configure_throttle() or env vars.
    #
    # Provider naming conventions:
    # - Use symbolic names matching ProviderRegistry keys
    # - nil values indicate no default limit (must be configured manually)
    #
    DEFAULT_RPM_LIMITS = {
      gemini: 10,            # Gemini free tier (very restrictive)
      perplexity: 20,        # Perplexity standard tier
      openai: 500,           # OpenAI tier 1
      responses: 500,        # ResponsesProvider (OpenAI-based)
      anthropic: 1000,       # Anthropic tier 1
      groq: 30,              # Groq free tier
      cohere: 100,           # Cohere trial tier
      xai: 60,               # xAI standard tier
      moonshot: 60,          # Moonshot standard tier
      huggingface: 1000,     # Hugging Face inference API
      together: 600,         # Together AI standard tier
      litellm: nil,          # LiteLLM depends on backend provider
      openrouter: nil        # OpenRouter depends on selected model
    }.freeze

    ##
    # Get default RPM limit for a provider
    #
    # Checks environment variables first, then falls back to DEFAULT_RPM_LIMITS.
    # Environment variable pattern: RAAF_THROTTLE_<PROVIDER>_RPM
    #
    # @param provider_key [Symbol, String] Provider key (e.g., :gemini, :openai)
    # @return [Integer, nil] RPM limit or nil if not configured
    #
    # @example
    #   ThrottleConfig.default_rpm_for(:gemini)
    #   # => 10
    #
    # @example With environment override
    #   ENV['RAAF_THROTTLE_GEMINI_RPM'] = '60'
    #   ThrottleConfig.default_rpm_for(:gemini)
    #   # => 60
    #
    def self.default_rpm_for(provider_key)
      provider_key = provider_key.to_sym

      # Check environment variable first
      env_key = "RAAF_THROTTLE_#{provider_key.to_s.upcase}_RPM"
      env_value = ENV[env_key]
      return env_value.to_i if env_value && !env_value.empty?

      # Fall back to default
      DEFAULT_RPM_LIMITS[provider_key]
    end

    ##
    # Detect provider type from class name and return default RPM
    #
    # Automatically detects the provider type by analyzing the class name.
    # Works with both Provider classes and instances.
    #
    # @param provider [Object] Provider instance or class
    # @return [Integer, nil] RPM limit or nil if provider type cannot be detected
    #
    # @example
    #   provider = RAAF::Models::GeminiProvider.new
    #   ThrottleConfig.rpm_for_provider(provider)
    #   # => 10
    #
    # @example
    #   ThrottleConfig.rpm_for_provider(RAAF::Models::OpenAIProvider)
    #   # => 500
    #
    def self.rpm_for_provider(provider)
      class_name = provider.is_a?(Class) ? provider.name : provider.class.name

      # Extract provider name from class (e.g., "RAAF::Models::GeminiProvider" => "gemini")
      if class_name =~ /(\w+)Provider$/i
        provider_name = ::Regexp.last_match(1).downcase.to_sym
        return default_rpm_for(provider_name)
      end

      # Handle ResponsesProvider specifically
      return default_rpm_for(:responses) if class_name =~ /ResponsesProvider/i

      # Cannot detect provider type
      nil
    end

    ##
    # Get all configured RPM limits
    #
    # Returns a hash of all provider limits, including environment variable overrides.
    #
    # @return [Hash{Symbol => Integer, nil}] All provider RPM limits
    #
    # @example
    #   ThrottleConfig.all_limits
    #   # => { gemini: 10, openai: 500, anthropic: 1000, ... }
    #
    def self.all_limits
      DEFAULT_RPM_LIMITS.transform_values do |default_value|
        provider_key = DEFAULT_RPM_LIMITS.key(default_value)
        default_rpm_for(provider_key) || default_value
      end
    end

    ##
    # Check if a provider has a default RPM limit configured
    #
    # @param provider_key [Symbol, String] Provider key
    # @return [Boolean] True if limit is configured
    #
    # @example
    #   ThrottleConfig.configured?(:gemini)
    #   # => true
    #
    #   ThrottleConfig.configured?(:litellm)
    #   # => false
    #
    def self.configured?(provider_key)
      !default_rpm_for(provider_key).nil?
    end
  end
end
