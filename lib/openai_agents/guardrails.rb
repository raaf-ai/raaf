# frozen_string_literal: true

require_relative "errors"

module OpenAIAgents
  module Guardrails
    class GuardrailError < Error; end
    class ValidationError < GuardrailError; end
    class SecurityError < GuardrailError; end

    # Base class for all guardrails
    class BaseGuardrail
      def initialize(options = {})
        @options = options
      end

      # Validate input before processing
      def validate_input(input)
        raise NotImplementedError, "Subclasses must implement validate_input"
      end

      # Validate output before returning
      def validate_output(output)
        raise NotImplementedError, "Subclasses must implement validate_output"
      end

      protected

      def fail_validation(message, type: :validation)
        case type
        when :security
          raise SecurityError, message
        else
          raise ValidationError, message
        end
      end
    end

    # Content safety guardrail
    class ContentSafetyGuardrail < BaseGuardrail
      HARMFUL_PATTERNS = [
        /violence|kill|murder|harm/i,
        /illegal|drugs|weapons/i,
        /hate|racist|discrimination/i,
        /sexual|explicit|adult/i,
        /personal\s+information|pii|ssn|credit\s+card/i
      ].freeze

      def validate_input(input)
        content = extract_content(input)

        HARMFUL_PATTERNS.each do |pattern|
          fail_validation("Content contains potentially harmful material", type: :security) if content.match?(pattern)
        end

        true
      end

      def validate_output(output)
        content = extract_content(output)

        HARMFUL_PATTERNS.each do |pattern|
          fail_validation("Output contains potentially harmful material", type: :security) if content.match?(pattern)
        end

        true
      end

      private

      def extract_content(data)
        case data
        when String
          data
        when Hash
          data.values.join(" ")
        when Array
          data.join(" ")
        else
          data.to_s
        end
      end
    end

    # Length validation guardrail
    class LengthGuardrail < BaseGuardrail
      def initialize(max_input_length: 10_000, max_output_length: 5000)
        super()
        @max_input_length = max_input_length
        @max_output_length = max_output_length
      end

      def validate_input(input)
        content = extract_content(input)

        if content.length > @max_input_length
          fail_validation("Input exceeds maximum length of #{@max_input_length} characters")
        end

        true
      end

      def validate_output(output)
        content = extract_content(output)

        if content.length > @max_output_length
          fail_validation("Output exceeds maximum length of #{@max_output_length} characters")
        end

        true
      end

      private

      def extract_content(data)
        case data
        when String
          data
        when Hash
          data.to_s
        # rubocop:disable Lint/DuplicateBranch
        when Array
          data.to_s
        else
          data.to_s
          # rubocop:enable Lint/DuplicateBranch
        end
      end
    end

    # Rate limiting guardrail
    class RateLimitGuardrail < BaseGuardrail
      def initialize(max_requests_per_minute: 60)
        super()
        @max_requests_per_minute = max_requests_per_minute
        @requests = []
      end

      def validate_input(_input)
        now = Time.now

        # Remove requests older than 1 minute
        @requests.reject! { |time| now - time > 60 }

        if @requests.length >= @max_requests_per_minute
          fail_validation("Rate limit exceeded: #{@max_requests_per_minute} requests per minute")
        end

        @requests << now
        true
      end

      def validate_output(_output)
        true # No output validation needed for rate limiting
      end
    end

    # Schema validation guardrail
    class SchemaGuardrail < BaseGuardrail
      def initialize(input_schema: nil, output_schema: nil)
        super()
        @input_schema = input_schema
        @output_schema = output_schema
      end

      def validate_input(input)
        return true unless @input_schema

        validate_against_schema(input, @input_schema, "input")
      end

      def validate_output(output)
        return true unless @output_schema

        validate_against_schema(output, @output_schema, "output")
      end

      private

      def validate_against_schema(data, schema, type)
        case schema[:type]
        when "object"
          validate_object(data, schema, type)
        when "array"
          validate_array(data, schema, type)
        when "string"
          validate_string(data, schema, type)
        when "number", "integer"
          validate_number(data, schema, type)
        when "boolean"
          validate_boolean(data, schema, type)
        else
          fail_validation("Unknown schema type: #{schema[:type]} for #{type}")
        end
      end

      def validate_object(data, schema, type)
        fail_validation("Expected object for #{type}, got #{data.class}") unless data.is_a?(Hash)

        schema[:required]&.each do |key|
          unless data.key?(key) || data.key?(key.to_s) || data.key?(key.to_sym)
            fail_validation("Missing required field '#{key}' in #{type}")
          end
        end

        schema[:properties]&.each do |key, prop_schema|
          if data.key?(key) || data.key?(key.to_s) || data.key?(key.to_sym)
            value = data[key] || data[key.to_s] || data[key.to_sym]
            validate_against_schema(value, prop_schema, "#{type}.#{key}")
          end
        end

        true
      end

      def validate_array(data, schema, type)
        fail_validation("Expected array for #{type}, got #{data.class}") unless data.is_a?(Array)

        if schema[:minItems] && data.length < schema[:minItems]
          fail_validation("Array #{type} has fewer than #{schema[:minItems]} items")
        end

        if schema[:maxItems] && data.length > schema[:maxItems]
          fail_validation("Array #{type} has more than #{schema[:maxItems]} items")
        end

        if schema[:items]
          data.each_with_index do |item, index|
            validate_against_schema(item, schema[:items], "#{type}[#{index}]")
          end
        end

        true
      end

      def validate_string(data, schema, type)
        fail_validation("Expected string for #{type}, got #{data.class}") unless data.is_a?(String)

        if schema[:minLength] && data.length < schema[:minLength]
          fail_validation("String #{type} is shorter than minimum length")
        end

        if schema[:maxLength] && data.length > schema[:maxLength]
          fail_validation("String #{type} is longer than #{schema[:maxLength]} characters")
        end

        if schema[:pattern] && !data.match?(Regexp.new(schema[:pattern]))
          fail_validation("String #{type} doesn't match pattern #{schema[:pattern]}")
        end

        true
      end

      def validate_number(data, schema, type)
        fail_validation("Expected number for #{type}, got #{data.class}") unless data.is_a?(Numeric)

        if schema[:minimum] && data < schema[:minimum]
          fail_validation("Number #{type} is less than minimum #{schema[:minimum]}")
        end

        if schema[:maximum] && data > schema[:maximum]
          fail_validation("Number #{type} is greater than maximum #{schema[:maximum]}")
        end

        true
      end

      def validate_boolean(data, _schema, type)
        unless data.is_a?(TrueClass) || data.is_a?(FalseClass)
          fail_validation("Expected boolean for #{type}, got #{data.class}")
        end

        true
      end
    end

    # Guardrail manager
    class GuardrailManager
      attr_reader :guardrails

      def initialize
        @guardrails = []
      end

      def add_guardrail(guardrail)
        raise ArgumentError, "Guardrail must inherit from BaseGuardrail" unless guardrail.is_a?(BaseGuardrail)

        @guardrails << guardrail
      end

      def validate_input(input)
        @guardrails.each do |guardrail|
          guardrail.validate_input(input)
        end
        true
      end

      def validate_output(output)
        @guardrails.each do |guardrail|
          guardrail.validate_output(output)
        end
        true
      end

      def clear
        @guardrails.clear
      end
    end
  end
end
