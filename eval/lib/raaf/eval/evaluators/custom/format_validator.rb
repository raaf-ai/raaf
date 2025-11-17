# frozen_string_literal: true

require_relative "../../dsl/evaluator"

module RAAF
  module Eval
    module Evaluators
      module Custom
        # Example custom evaluator: Format Validator
        # Validates output against expected format patterns
        #
        # This is a reference implementation showing best practices for:
        # - Simple pattern matching validation
        # - Regex-based format checking
        # - Clear pass/fail messaging
        # - Minimal cross-field dependencies
        #
        # @example Register and use
        #   RAAF::Eval.register_evaluator(:format_validator, FormatValidatorEvaluator)
        #   
        #   evaluator = RAAF::Eval.define do
        #     evaluate_field :output do
        #       evaluate_with :format_validator, expected_format: /^\d{3}-\d{3}$/
        #     end
        #   end
        class FormatValidator
          include RAAF::Eval::DSL::Evaluator

          evaluator_name :format_validator

          # Validate output format against pattern
          # @param field_context [FieldContext] The field context containing value
          # @param options [Hash] Options including :expected_format (regex or string)
          # @return [Hash] Evaluation result with :passed, :score, :details, :message
          def evaluate(field_context, **options)
            output = field_context.value.to_s
            expected_format = options[:expected_format]
            good_threshold = options[:good_threshold] || 0.8
            average_threshold = options[:average_threshold] || 0.6

            unless expected_format
              return {
                label: "bad",
                score: 0.0,
                details: {
                  field: field_context.field_name,
                  error: "expected_format option is required",
                  threshold_good: good_threshold,
                  threshold_average: average_threshold
                },
                message: "[BAD] Format validation failed: expected_format not provided"
              }
            end

            # Perform validation
            matches = validate_format(output, expected_format)

            score = matches ? 1.0 : 0.0
            label = calculate_label(score, good_threshold: good_threshold, average_threshold: average_threshold)

            {
              label: label,
              score: score,
              details: {
                field: field_context.field_name,
                output: output,
                expected_format: format_description(expected_format),
                matched: matches,
                threshold_good: good_threshold,
                threshold_average: average_threshold
              },
              message: matches ?
                "[#{label.upcase}] Output matches expected format" :
                "[#{label.upcase}] Output does not match expected format #{format_description(expected_format)}"
            }
          end

          private

          # Validate output against format
          # @param output [String] The output to validate
          # @param format [Regexp, String] Expected format pattern
          # @return [Boolean] true if matches, false otherwise
          def validate_format(output, format)
            case format
            when Regexp
              !!(output =~ format)
            when String
              output == format
            else
              false
            end
          end

          # Get human-readable format description
          # @param format [Regexp, String] Format pattern
          # @return [String] Description of format
          def format_description(format)
            case format
            when Regexp
              format.inspect
            when String
              "\"#{format}\""
            else
              format.to_s
            end
          end
        end
      end
    end
  end
end
