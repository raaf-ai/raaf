# frozen_string_literal: true

module RAAF
  module Guardrails
    ##
    # Main validator class for guardrails
    #
    # Orchestrates multiple validation layers including toxicity detection,
    # PII detection, prompt injection prevention, and custom rules.
    #
    class Validator
      include RAAF::Logging

      # @return [Array<Object>] Validation providers
      attr_reader :providers

      # @return [Hash] Configuration options
      attr_reader :config

      ##
      # Initialize validator
      #
      # @param config [Hash] Configuration options
      #
      def initialize(**config)
        @config = RAAF::Guardrails.config.merge(config)
        @providers = []
        @custom_rules = nil
        @cache = {}
        
        setup_providers
      end

      ##
      # Add a validation provider
      #
      # @param provider [Object] Provider instance
      def add_provider(provider)
        @providers << provider
      end

      ##
      # Add custom rules
      #
      # @param rules [CustomRules] Custom rules instance
      def add_custom_rules(rules)
        @custom_rules = rules
      end

      ##
      # Validate content
      #
      # @param content [String] Content to validate
      # @param context [Hash] Additional context
      # @return [ValidationResult] Validation result
      def validate(content, context = {})
        start_time = Time.current
        
        # Check cache first
        cache_key = generate_cache_key(content, context)
        if @config[:cache_results] && (cached_result = @cache[cache_key])
          return cached_result if cached_result.fresh?
        end

        violations = []
        filtered_content = content.dup

        begin
          # Run all validations
          violations.concat(validate_toxicity(content, context)) if @config[:toxicity_detection]
          violations.concat(validate_pii(content, context)) if @config[:pii_detection]
          violations.concat(validate_prompt_injection(content, context)) if @config[:prompt_injection_detection]
          violations.concat(validate_content_filter(content, context)) if @config[:content_filtering]
          
          # Apply custom rules
          if @config[:custom_rules] && @custom_rules
            custom_result = @custom_rules.validate(content, context)
            violations.concat(custom_result.violations)
            filtered_content = custom_result.filtered_content
          end

          # Create result
          result = ValidationResult.new(
            content: content,
            filtered_content: filtered_content,
            violations: violations,
            safe: violations.empty?,
            context: context,
            timestamp: Time.current
          )

          # Cache result
          if @config[:cache_results]
            @cache[cache_key] = result
            clean_cache if @cache.size > 1000
          end

          # Update statistics
          response_time = Time.current - start_time
          RAAF::Guardrails.update_stats(response_time, violations.size)

          # Log violations
          violations.each do |violation|
            RAAF::Guardrails.log_violation(violation)
          end

          result
        rescue StandardError => e
          log_error("Validation error", error: e, content_length: content.length)
          
          # Return safe result on error to avoid blocking
          ValidationResult.new(
            content: content,
            filtered_content: content,
            violations: [],
            safe: true,
            error: e.message,
            context: context,
            timestamp: Time.current
          )
        end
      end

      ##
      # Quick safety check
      #
      # @param content [String] Content to check
      # @param context [Hash] Additional context
      # @return [Boolean] True if content is safe
      def safe?(content, context = {})
        validate(content, context).safe?
      end

      ##
      # Filter content and return safe version
      #
      # @param content [String] Content to filter
      # @param context [Hash] Additional context
      # @return [String] Filtered content
      def filter(content, context = {})
        result = validate(content, context)
        result.safe? ? content : result.filtered_content
      end

      private

      def setup_providers
        # Add default providers based on configuration
        if @config[:toxicity_detection]
          @providers << ToxicityDetector.new(**@config)
        end

        if @config[:pii_detection]
          @providers << PIIDetector.new(**@config)
        end

        if @config[:prompt_injection_detection]
          @providers << PromptInjectionDetector.new(**@config)
        end

        if @config[:content_filtering]
          @providers << ContentFilter.new(**@config)
        end
      end

      def validate_toxicity(content, context)
        provider = @providers.find { |p| p.is_a?(ToxicityDetector) }
        return [] unless provider

        result = provider.validate(content, context)
        result.violations
      end

      def validate_pii(content, context)
        provider = @providers.find { |p| p.is_a?(PIIDetector) }
        return [] unless provider

        result = provider.validate(content, context)
        result.violations
      end

      def validate_prompt_injection(content, context)
        provider = @providers.find { |p| p.is_a?(PromptInjectionDetector) }
        return [] unless provider

        result = provider.validate(content, context)
        result.violations
      end

      def validate_content_filter(content, context)
        provider = @providers.find { |p| p.is_a?(ContentFilter) }
        return [] unless provider

        result = provider.validate(content, context)
        result.violations
      end

      def generate_cache_key(content, context)
        key_data = {
          content: content,
          context: context,
          config: @config.slice(:toxicity_threshold, :pii_confidence_threshold, :prompt_injection_threshold)
        }
        
        Digest::SHA256.hexdigest(JSON.generate(key_data))
      end

      def clean_cache
        # Remove expired entries
        @cache.delete_if { |_, result| !result.fresh? }
        
        # If still too large, remove oldest entries
        if @cache.size > 1000
          sorted_entries = @cache.sort_by { |_, result| result.timestamp }
          entries_to_remove = sorted_entries.first(@cache.size - 500)
          entries_to_remove.each { |key, _| @cache.delete(key) }
        end
      end
    end

    ##
    # Validation result class
    #
    class ValidationResult
      # @return [String] Original content
      attr_reader :content

      # @return [String] Filtered content
      attr_reader :filtered_content

      # @return [Array<Hash>] Violations found
      attr_reader :violations

      # @return [Boolean] Whether content is safe
      attr_reader :safe

      # @return [Hash] Additional context
      attr_reader :context

      # @return [Time] Validation timestamp
      attr_reader :timestamp

      # @return [String, nil] Error message if validation failed
      attr_reader :error

      def initialize(content:, filtered_content:, violations:, safe:, context:, timestamp:, error: nil)
        @content = content
        @filtered_content = filtered_content
        @violations = violations
        @safe = safe
        @context = context
        @timestamp = timestamp
        @error = error
      end

      ##
      # Check if content is safe
      #
      # @return [Boolean] True if safe
      def safe?
        @safe
      end

      ##
      # Check if content was blocked
      #
      # @return [Boolean] True if blocked
      def blocked?
        !@safe
      end

      ##
      # Get violations by type
      #
      # @param type [Symbol] Violation type
      # @return [Array<Hash>] Violations of specified type
      def violations_by_type(type)
        @violations.select { |v| v[:type] == type }
      end

      ##
      # Get highest severity violation
      #
      # @return [Hash, nil] Highest severity violation
      def highest_severity_violation
        return nil if @violations.empty?

        @violations.max_by { |v| SEVERITY_LEVELS[v[:severity]] || 0 }
      end

      ##
      # Check if result is still fresh (within cache TTL)
      #
      # @return [Boolean] True if fresh
      def fresh?
        return true unless RAAF::Guardrails.config[:cache_ttl]

        Time.current - @timestamp < RAAF::Guardrails.config[:cache_ttl]
      end

      ##
      # Convert to hash
      #
      # @return [Hash] Result as hash
      def to_h
        {
          content: @content,
          filtered_content: @filtered_content,
          violations: @violations,
          safe: @safe,
          context: @context,
          timestamp: @timestamp.iso8601,
          error: @error
        }
      end

      ##
      # Convert to JSON
      #
      # @return [String] Result as JSON
      def to_json(*args)
        JSON.generate(to_h, *args)
      end
    end

    ##
    # Violation class
    #
    class Violation
      # @return [Symbol] Violation type
      attr_reader :type

      # @return [String] Violation message
      attr_reader :message

      # @return [Symbol] Severity level
      attr_reader :severity

      # @return [Hash] Additional metadata
      attr_reader :metadata

      # @return [Time] When violation occurred
      attr_reader :timestamp

      def initialize(type:, message:, severity: :medium, metadata: {})
        @type = type
        @message = message
        @severity = severity
        @metadata = metadata
        @timestamp = Time.current
      end

      ##
      # Convert to hash
      #
      # @return [Hash] Violation as hash
      def to_h
        {
          type: @type,
          message: @message,
          severity: @severity,
          metadata: @metadata,
          timestamp: @timestamp.iso8601
        }
      end

      ##
      # Convert to JSON
      #
      # @return [String] Violation as JSON
      def to_json(*args)
        JSON.generate(to_h, *args)
      end
    end
  end
end