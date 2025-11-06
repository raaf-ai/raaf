# frozen_string_literal: true

module RAAF
  module Eval
    module Metrics
      ##
      # StructuralMetrics validates output structure
      class StructuralMetrics
        class << self
          ##
          # Calculate structural metrics
          # @param output [String] Output to validate
          # @param expected_format [Symbol, nil] Expected format (:json, :xml, :text)
          # @return [Hash] Structural metrics
          def calculate(output, expected_format: nil)
            {
              output_length: output.to_s.length,
              format_valid: validate_format(output, expected_format),
              has_content: !output.to_s.strip.empty?
            }
          end

          private

          def validate_format(output, format)
            case format
            when :json
              JSON.parse(output)
              true
            when :xml
              # Simple XML validation
              output.include?("<") && output.include?(">")
            else
              true # Text format is always valid
            end
          rescue JSON::ParserError
            false
          end
        end
      end
    end
  end
end
