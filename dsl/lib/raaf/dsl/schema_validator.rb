# frozen_string_literal: true

require_relative 'json_repair'

module RAAF
  module DSL
    # Fault-tolerant schema validation with tiered validation modes
    # Provides graceful degradation and repair capabilities for AI responses
    class SchemaValidator
      attr_reader :schema, :mode, :repair_attempts, :metrics

      # Validation modes
      STRICT_MODE = :strict      # All fields must match exactly (current behavior)
      TOLERANT_MODE = :tolerant  # Required fields strict, others flexible (recommended)
      PARTIAL_MODE = :partial    # Use whatever validates, ignore the rest (most flexible)

      # @param schema [Hash] JSON schema definition with properties and required fields
      # @param mode [Symbol] Validation mode (:strict, :tolerant, :partial)
      # @param repair_attempts [Integer] Number of repair attempts for failed parsing
      def initialize(schema, mode: TOLERANT_MODE, repair_attempts: 2)
        @schema = schema || {}
        @mode = mode
        @repair_attempts = repair_attempts
        @metrics = { 
          parse_attempts: 0, 
          repairs: 0, 
          failures: 0, 
          partial_successes: 0,
          field_errors: Hash.new(0)
        }
      end

      # Validate data against schema with fault tolerance
      # @param data [Hash, String] Data to validate (Hash) or JSON string to parse and validate
      # @param attempt [Integer] Current repair attempt (internal use)
      # @return [Hash] Validation result with :valid, :data, :errors, :warnings, :partial flags
      def validate(data, attempt: 0)
        @metrics[:parse_attempts] += 1
        
        # Parse JSON if string provided
        if data.is_a?(String)
          parsed = JsonRepair.repair(data)
          unless parsed
            return {
              valid: false,
              data: {},
              errors: ["Unable to parse JSON from input"],
              warnings: [],
              partial: false
            }
          end
          data = parsed
        end
        
        case @mode
        when STRICT_MODE
          validate_strict(data)
        when TOLERANT_MODE
          validate_tolerant(data, attempt)
        when PARTIAL_MODE
          validate_partial(data)
        else
          raise ArgumentError, "Unknown validation mode: #{@mode}"
        end
      end

      # Get validation statistics for observability
      # @return [Hash] Metrics including success rates and error patterns
      def statistics
        total_attempts = @metrics[:parse_attempts]
        return { no_data: true } if total_attempts.zero?
        
        {
          total_attempts: total_attempts,
          success_rate: (total_attempts - @metrics[:failures]) / total_attempts.to_f,
          repair_rate: @metrics[:repairs] / total_attempts.to_f,
          partial_rate: @metrics[:partial_successes] / total_attempts.to_f,
          common_field_errors: @metrics[:field_errors].sort_by { |_, count| -count }.first(5).to_h,
          mode: @mode
        }
      end

      private

      # Strict validation - all fields must match exactly (backward compatible)
      def validate_strict(data)
        result = { valid: true, data: {}, errors: [], warnings: [], partial: false }
        
        required_fields = @schema[:required] || []
        properties = @schema[:properties] || {}
        
        # Check required fields
        required_fields.each do |field_name|
          field_key = field_name.to_sym
          if data[field_key].nil? && data[field_name.to_s].nil?
            result[:errors] << "Missing required field: #{field_name}"
            result[:valid] = false
            @metrics[:field_errors][field_name] += 1
          end
        end
        
        # Validate present fields strictly
        data.each do |key, value|
          field_schema = properties[key.to_sym] || properties[key.to_s]
          if field_schema
            unless type_matches_strict?(value, field_schema[:type])
              result[:errors] << "Field #{key} type mismatch: expected #{field_schema[:type]}"
              result[:valid] = false
              @metrics[:field_errors][key] += 1
            else
              result[:data][key.to_sym] = value
            end
          elsif @schema[:additionalProperties] == false
            result[:errors] << "Unknown field not allowed: #{key}"
            result[:valid] = false
          else
            result[:data][key.to_sym] = value
          end
        end
        
        @metrics[:failures] += 1 unless result[:valid]
        result
      end

      # Tolerant validation - required fields strict, others flexible
      def validate_tolerant(data, attempt)
        result = { valid: true, data: {}, errors: [], warnings: [], partial: false }
        
        required_fields = @schema[:required] || []
        properties = @schema[:properties] || {}
        
        # Process required fields with strict validation
        required_fields.each do |field_name|
          field_key = field_name.to_sym
          field_value = data[field_key] || data[field_name.to_s]
          field_schema = properties[field_key] || properties[field_name.to_s] || {}
          
          if field_value.nil?
            # Check for default value
            if field_schema[:default]
              default_val = field_schema[:default]
              default_val = default_val.call if default_val.is_a?(Proc)
              result[:data][field_key] = default_val
              result[:warnings] << "Using default value for required field: #{field_name}"
            else
              result[:errors] << "Missing required field: #{field_name}"
              result[:valid] = false
              @metrics[:field_errors][field_name] += 1
            end
          else
            # Validate required field
            validated_value = validate_field_tolerant(field_name, field_value, field_schema, result)
            result[:data][field_key] = validated_value unless validated_value.nil?
          end
        end
        
        # Process optional fields with flexible validation
        data.each do |key, value|
          field_key = key.to_sym
          next if required_fields.include?(key.to_s) || required_fields.include?(key.to_sym)
          
          field_schema = properties[field_key] || properties[key.to_s] || {}
          
          if field_schema.empty? && @schema[:additionalProperties] != false
            # Unknown field - capture with warning
            result[:data][field_key] = value
            result[:warnings] << "Unknown field captured: #{key}"
          else
            # Validate optional field flexibly
            validated_value = validate_field_tolerant(key, value, field_schema, result, strict: false)
            result[:data][field_key] = validated_value unless validated_value.nil?
          end
        end
        
        # Add missing optional fields with defaults
        properties.each do |field_name, field_schema|
          field_key = field_name.to_sym
          next if required_fields.include?(field_name.to_s)
          next if result[:data].key?(field_key)
          
          if field_schema[:default]
            default_val = field_schema[:default]
            default_val = default_val.call if default_val.is_a?(Proc)
            result[:data][field_key] = default_val
          end
        end
        
        # If validation failed and we have repair attempts left, try to repair the input
        if !result[:valid] && attempt < @repair_attempts
          @metrics[:repairs] += 1
          
          # Create a repaired version by filling in missing required fields
          repaired_data = repair_missing_fields(data, result[:errors])
          if repaired_data != data
            return validate(repaired_data, attempt: attempt + 1)
          end
        end
        
        @metrics[:failures] += 1 unless result[:valid]
        result
      end

      # Partial validation - use whatever validates, ignore invalid fields
      def validate_partial(data)
        result = { valid: true, data: {}, errors: [], warnings: [], partial: true }
        
        required_fields = @schema[:required] || []
        properties = @schema[:properties] || {}
        
        # Try to validate each field, but don't fail completely
        data.each do |key, value|
          field_key = key.to_sym
          field_schema = properties[field_key] || properties[key.to_s] || {}
          
          begin
            if field_schema.empty?
              # Unknown field - include with warning
              result[:data][field_key] = value
              result[:warnings] << "Unknown field included: #{key}"
            else
              # Try to validate and coerce
              validated_value = validate_field_tolerant(key, value, field_schema, result, strict: false)
              if validated_value
                result[:data][field_key] = validated_value
              else
                result[:warnings] << "Field #{key} failed validation, skipping"
              end
            end
          rescue StandardError => e
            result[:warnings] << "Field #{key} validation error: #{e.message}"
          end
        end
        
        # Add defaults for missing required fields
        required_fields.each do |field_name|
          field_key = field_name.to_sym
          unless result[:data].key?(field_key)
            field_schema = properties[field_key] || properties[field_name.to_s] || {}
            if field_schema[:default]
              default_val = field_schema[:default]
              default_val = default_val.call if default_val.is_a?(Proc)
              result[:data][field_key] = default_val
              result[:warnings] << "Using default for missing required field: #{field_name}"
            else
              result[:warnings] << "Missing required field with no default: #{field_name}"
            end
          end
        end
        
        @metrics[:partial_successes] += 1
        result
      end

      # Validate individual field with tolerance options
      def validate_field_tolerant(field_name, value, field_schema, result, strict: true)
        # Handle passthrough fields (accept any structure)
        return value if field_schema[:passthrough]
        
        field_type = field_schema[:type]
        
        # Handle flexible fields (attempt type coercion)
        if field_schema[:flexible] && !strict
          coerced = coerce_value(value, field_type)
          return coerced if coerced
        end
        
        # Handle enum validation
        if field_schema[:enum] && !field_schema[:enum].include?(value)
          if strict
            result[:errors] << "Field #{field_name} value not in allowed enum: #{field_schema[:enum]}"
            @metrics[:field_errors][field_name] += 1
            return nil
          else
            result[:warnings] << "Field #{field_name} value not in enum, using as-is"
            return value
          end
        end
        
        # Type validation
        if field_type && !type_matches_flexible?(value, field_type)
          if strict
            result[:errors] << "Field #{field_name} type mismatch: expected #{field_type}, got #{value.class}"
            @metrics[:field_errors][field_name] += 1
            return nil
          else
            result[:warnings] << "Field #{field_name} type mismatch, using as-is"
            return value
          end
        end
        
        value
      end

      # Attempt to repair data by adding default values for missing required fields
      def repair_missing_fields(data, errors)
        repaired = data.dup
        properties = @schema[:properties] || {}
        
        errors.each do |error|
          if error.start_with?("Missing required field:")
            field_name = error.split(": ").last
            field_schema = properties[field_name.to_sym] || properties[field_name.to_s]
            
            if field_schema&.dig(:default)
              default_val = field_schema[:default]
              default_val = default_val.call if default_val.is_a?(Proc)
              repaired[field_name.to_sym] = default_val
            end
          end
        end
        
        repaired
      end

      # Strict type checking (for strict mode)
      def type_matches_strict?(value, expected_type)
        case expected_type.to_s
        when 'string'
          value.is_a?(String)
        when 'integer'
          value.is_a?(Integer)
        when 'number'
          value.is_a?(Numeric)
        when 'boolean'
          value.is_a?(TrueClass) || value.is_a?(FalseClass)
        when 'array'
          value.is_a?(Array)
        when 'object'
          value.is_a?(Hash)
        when 'null'
          value.nil?
        else
          true  # Unknown type, allow anything
        end
      end

      # Flexible type checking (for tolerant/partial modes)
      def type_matches_flexible?(value, expected_type)
        return true if type_matches_strict?(value, expected_type)
        
        # Allow some flexibility
        case expected_type.to_s
        when 'string'
          !value.nil?  # Most things can be converted to string
        when 'integer'
          value.is_a?(Numeric) || (value.is_a?(String) && value.match?(/^\d+$/))
        when 'number'
          value.is_a?(Numeric) || (value.is_a?(String) && value.match?(/^\d*\.?\d+$/))
        when 'boolean'
          [true, false, 'true', 'false', 1, 0, '1', '0'].include?(value)
        when 'array'
          value.respond_to?(:to_a)
        when 'object'
          value.respond_to?(:to_h)
        else
          true
        end
      end

      # Attempt to coerce value to expected type
      def coerce_value(value, expected_type)
        return value if type_matches_strict?(value, expected_type)
        
        case expected_type.to_s
        when 'string'
          value.to_s
        when 'integer'
          if value.is_a?(String) && value.match?(/^\d+$/)
            value.to_i
          elsif value.is_a?(Numeric)
            value.to_i
          else
            value
          end
        when 'number'
          if value.is_a?(String) && value.match?(/^\d*\.?\d+$/)
            value.include?('.') ? value.to_f : value.to_i
          elsif value.is_a?(Numeric)
            value
          else
            value
          end
        when 'boolean'
          case value
          when 'true', 1, '1' then true
          when 'false', 0, '0' then false
          else value
          end
        when 'array'
          value.respond_to?(:to_a) ? value.to_a : [value]
        when 'object'
          value.respond_to?(:to_h) ? value.to_h : value
        else
          value
        end
      end
    end
  end
end