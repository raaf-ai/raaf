# frozen_string_literal: true

require "active_support/core_ext/hash/indifferent_access"

module RAAF
  module Eval
    module DSL
      # Error raised when a field is not found in the result
      class FieldNotFoundError < StandardError; end

      # Provides field-aware context for evaluators
      # Handles field value extraction, baseline detection, and delta calculations
      class FieldContext
        attr_reader :field_name

        # Initialize with a field name and full result hash
        # @param field_name [String, Symbol] The field being evaluated (supports dot notation)
        # @param result [Hash] The complete evaluation result hash
        def initialize(field_name, result)
          @field_name = field_name.to_s
          @result = ensure_indifferent_access(result)

          # Validate field exists
          unless field_exists?(@field_name)
            raise FieldNotFoundError, "Field '#{@field_name}' not found in result"
          end
        end

        # Get the value of the current field
        # @return [Object] The field value
        def value
          extract_field_value(@field_name)
        end

        # Get the baseline value for the current field (auto-detects baseline_ prefix)
        # @return [Object, nil] The baseline value or nil if not found
        def baseline_value
          baseline_field = determine_baseline_field(@field_name)
          return nil unless baseline_field && field_exists?(baseline_field)
          extract_field_value(baseline_field)
        end

        # Calculate the absolute delta between value and baseline_value
        # @return [Numeric, nil] The delta or nil if not applicable
        def delta
          return nil unless value.is_a?(Numeric) && baseline_value.is_a?(Numeric)
          value - baseline_value
        end

        # Calculate the percentage delta between value and baseline_value
        # @return [Float, nil] The percentage change or nil if not applicable
        def delta_percentage
          return nil unless value.is_a?(Numeric) && baseline_value.is_a?(Numeric)
          return nil if baseline_value.zero?
          ((value - baseline_value) / baseline_value.to_f) * 100
        end

        # Convenience accessors for common fields
        def output
          @result[:output]
        end

        def baseline_output
          @result[:baseline_output]
        end

        def usage
          @result[:usage]
        end

        def baseline_usage
          @result[:baseline_usage]
        end

        def latency_ms
          @result[:latency_ms]
        end

        def configuration
          @result[:configuration]
        end

        # Access any field from the result hash
        # @param field [String, Symbol] Field name (supports dot notation)
        # @return [Object] The field value
        def [](field)
          extract_field_value(field.to_s)
        end

        # Get the complete result hash
        # @return [Hash] The full result
        def full_result
          @result
        end

        # Check if a field exists in the result
        # @param field [String, Symbol] Field name (supports dot notation)
        # @return [Boolean] true if field exists
        def field_exists?(field)
          field = field.to_s

          # First check if the field exists at the top level (for pre-extracted values)
          # This handles cases where wildcard extraction has already been performed
          return true if @result.key?(field)

          # Otherwise check nested path
          parts = field.split(".")

          current = @result
          parts.each do |part|
            return false unless current.is_a?(Hash) && current.key?(part)
            current = current[part]
          end
          true
        end

        private

        # Ensure hash uses indifferent access
        def ensure_indifferent_access(hash)
          return hash if hash.is_a?(ActiveSupport::HashWithIndifferentAccess)
          ActiveSupport::HashWithIndifferentAccess.new(hash)
        end

        # Extract a field value using dot notation
        def extract_field_value(field_path)
          # First check if the field exists at the top level (for pre-extracted values)
          # This handles cases where wildcard extraction has already been performed
          return @result[field_path] if @result.key?(field_path)

          # Otherwise traverse nested path
          parts = field_path.split(".")

          current = @result
          parts.each do |part|
            if current.is_a?(Hash)
              current = current[part]
            else
              return nil
            end
          end
          current
        end

        # Determine the baseline field name for a given field
        def determine_baseline_field(field_path)
          parts = field_path.split(".")

          if parts.size == 1
            # Simple field: output -> baseline_output
            "baseline_#{parts[0]}"
          else
            # Nested field: usage.total_tokens -> baseline_usage.total_tokens
            first_part = parts[0]
            rest = parts[1..-1].join(".")
            "baseline_#{first_part}.#{rest}"
          end
        end
      end
    end
  end
end