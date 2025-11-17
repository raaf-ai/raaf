# frozen_string_literal: true

require_relative "../../dsl/evaluator"
require 'json'

module RAAF
  module Eval
    module Evaluators
      module Structural
        # Validates against JSON schema
        class SchemaMatch
          include RAAF::Eval::DSL::Evaluator

          evaluator_name :schema_match

          # Evaluate schema match
          # @param field_context [FieldContext] The field context containing value and baseline
          # @param options [Hash] Options including :schema (required)
          # @return [Hash] Evaluation result
          def evaluate(field_context, **options)
            schema = options[:schema]
            good_threshold = options[:good_threshold] || 0.9
            average_threshold = options[:average_threshold] || 0.7

            unless schema
              return {
                label: "bad",
                score: 0.0,
                details: {
                  error: "No schema provided",
                  threshold_good: good_threshold,
                  threshold_average: average_threshold
                },
                message: "[BAD] Schema validation requires :schema parameter"
              }
            end

            value = field_context.value
            validation_errors = validate_against_schema(value, schema)

            score = calculate_score(validation_errors)
            label = calculate_label(score, good_threshold: good_threshold, average_threshold: average_threshold)

            {
              label: label,
              score: score,
              details: {
                validation_errors: validation_errors,
                schema_keys: schema.keys,
                value_type: value.class.name,
                threshold_good: good_threshold,
                threshold_average: average_threshold
              },
              message: validation_errors.empty? ?
                "[#{label.upcase}] Matches schema" :
                "[#{label.upcase}] Schema violations: #{validation_errors.join(', ')}"
            }
          end

          private

          def validate_against_schema(value, schema)
            errors = []
            
            # Basic schema validation
            if schema[:type]
              unless validate_type(value, schema[:type])
                errors << "type mismatch: expected #{schema[:type]}, got #{value.class.name.downcase}"
              end
            end

            if schema[:required] && value.is_a?(Hash)
              schema[:required].each do |key|
                unless value.key?(key.to_s) || value.key?(key.to_sym)
                  errors << "missing required field: #{key}"
                end
              end
            end

            if schema[:properties] && value.is_a?(Hash)
              schema[:properties].each do |key, prop_schema|
                if value.key?(key.to_s) || value.key?(key.to_sym)
                  prop_value = value[key.to_s] || value[key.to_sym]
                  prop_errors = validate_against_schema(prop_value, prop_schema)
                  errors.concat(prop_errors.map { |e| "#{key}.#{e}" })
                end
              end
            end

            if schema[:items] && value.is_a?(Array)
              value.each_with_index do |item, index|
                item_errors = validate_against_schema(item, schema[:items])
                errors.concat(item_errors.map { |e| "[#{index}].#{e}" })
              end
            end

            errors
          end

          def validate_type(value, expected_type)
            case expected_type
            when "string"
              value.is_a?(String)
            when "number"
              value.is_a?(Numeric)
            when "integer"
              value.is_a?(Integer)
            when "boolean"
              [true, false].include?(value)
            when "array"
              value.is_a?(Array)
            when "object"
              value.is_a?(Hash)
            when "null"
              value.nil?
            else
              true
            end
          end

          def calculate_score(errors)
            return 1.0 if errors.empty?
            return 0.0 if errors.size >= 5

            1.0 - (errors.size / 5.0)
          end
        end
      end
    end
  end
end
