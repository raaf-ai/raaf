# frozen_string_literal: true

require_relative "../../dsl/evaluator"
require 'json'

module RAAF
  module Eval
    module Evaluators
      module Structural
        # Validates JSON format
        class JsonValidity
          include RAAF::Eval::DSL::Evaluator

          evaluator_name :json_validity

          # Evaluate JSON validity
          # @param field_context [FieldContext] The field context containing value and baseline
          # @param options [Hash] Options (currently unused)
          # @return [Hash] Evaluation result
          def evaluate(field_context, **options)
            value = field_context.value
            
            # Convert to string if necessary
            json_string = value.is_a?(String) ? value : value.to_json
            
            begin
              parsed = JSON.parse(json_string)
              
              {
                passed: true,
                score: 1.0,
                details: {
                  valid_json: true,
                  structure_type: parsed.class.name,
                  size: json_string.length
                },
                message: "Valid JSON structure"
              }
            rescue JSON::ParserError => e
              {
                passed: false,
                score: 0.0,
                details: {
                  valid_json: false,
                  error: e.message,
                  error_position: extract_error_position(e.message)
                },
                message: "Invalid JSON: #{e.message.split("\n").first}"
              }
            end
          end

          private

          def extract_error_position(error_message)
            # Try to extract position from error message
            if error_message =~ /at (\d+)/
              $1.to_i
            else
              nil
            end
          end
        end
      end
    end
  end
end
