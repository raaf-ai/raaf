# frozen_string_literal: true

module RAAF
  module Perplexity
    ##
    # Common constants and validation methods for Perplexity integration
    #
    # Provides shared functionality used by both PerplexityProvider and PerplexityTool
    # to ensure consistency in model validation, schema support checks, and
    # recency filter handling.
    #
    # @example Model validation
    #   RAAF::Perplexity::Common.validate_model("sonar-pro")  # => nil (valid)
    #   RAAF::Perplexity::Common.validate_model("invalid")    # => raises ArgumentError
    #
    # @example Schema support validation
    #   RAAF::Perplexity::Common.validate_schema_support("sonar-pro")  # => nil (valid)
    #   RAAF::Perplexity::Common.validate_schema_support("sonar")      # => raises ArgumentError
    #
    module Common
      # All supported Perplexity models
      SUPPORTED_MODELS = %w[
        sonar
        sonar-pro
        sonar-reasoning
        sonar-reasoning-pro
        sonar-deep-research
      ].freeze

      # Models that support JSON schema (response_format parameter)
      SCHEMA_SUPPORTED_MODELS = %w[
        sonar-pro
        sonar-reasoning-pro
      ].freeze

      # Valid recency filter values for web search
      RECENCY_FILTERS = %w[
        hour
        day
        week
        month
        year
      ].freeze

      ##
      # Validates that a model is supported by Perplexity
      #
      # @param model [String] Model name to validate
      # @raise [ArgumentError] if model is not supported
      # @return [void]
      #
      def self.validate_model(model)
        return if SUPPORTED_MODELS.include?(model)

        raise ArgumentError,
              "Model '#{model}' is not supported. " \
              "Supported models: #{SUPPORTED_MODELS.join(', ')}"
      end

      ##
      # Validates that a model supports JSON schema (response_format)
      #
      # Only sonar-pro and sonar-reasoning-pro models support structured outputs
      # with JSON schema validation.
      #
      # @param model [String] Model name to validate
      # @raise [ArgumentError] if model doesn't support JSON schema
      # @return [void]
      #
      def self.validate_schema_support(model)
        return if SCHEMA_SUPPORTED_MODELS.include?(model)

        raise ArgumentError,
              "JSON schema (response_format) is only supported on #{SCHEMA_SUPPORTED_MODELS.join(', ')}. " \
              "Current model: #{model}"
      end

      ##
      # Validates a recency filter value for web search
      #
      # @param filter [String, nil] Recency filter to validate
      # @raise [ArgumentError] if filter is invalid
      # @return [void]
      #
      def self.validate_recency_filter(filter)
        return unless filter
        return if RECENCY_FILTERS.include?(filter)

        raise ArgumentError,
              "Invalid recency filter '#{filter}'. " \
              "Supported: #{RECENCY_FILTERS.join(', ')}"
      end
    end
  end
end
