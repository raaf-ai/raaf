# frozen_string_literal: true

require_relative "../../dsl/evaluator"

module RAAF
  module Eval
    module Evaluators
      module Statistical
        # Evaluates consistency across multiple runs
        class Consistency
          include RAAF::Eval::DSL::Evaluator

          evaluator_name :consistency

          # Evaluate consistency of results
          # @param field_context [FieldContext] The field context containing value and baseline
          # @param options [Hash] Options including :std_dev (default 0.1)
          # @return [Hash] Evaluation result
          def evaluate(field_context, **options)
            max_std_dev = options[:std_dev] || 0.1
            good_threshold = options[:good_threshold] || 0.8
            average_threshold = options[:average_threshold] || 0.6

            # Expect value to be an array of results from multiple runs
            values = field_context.value

            unless values.is_a?(Array) && !values.empty?
              return {
                label: "bad",
                score: 0.0,
                details: {
                  error: "Expected array of values from multiple runs",
                  threshold_good: good_threshold,
                  threshold_average: average_threshold
                },
                message: "[BAD] Invalid input: expected array of values"
              }
            end

            # Calculate standard deviation
            std_dev = calculate_std_dev(values)
            mean = calculate_mean(values)

            # Normalize standard deviation by mean for coefficient of variation
            cv = mean == 0 ? 0 : std_dev / mean.abs

            score = calculate_score(cv, max_std_dev)
            label = calculate_label(score, good_threshold: good_threshold, average_threshold: average_threshold)

            {
              label: label,
              score: score,
              details: {
                values: values,
                mean: mean.round(3),
                std_dev: std_dev.round(3),
                coefficient_of_variation: cv.round(3),
                max_std_dev: max_std_dev,
                threshold_good: good_threshold,
                threshold_average: average_threshold
              },
              message: "[#{label.upcase}] Consistency CV: #{cv.round(3)} (max: #{max_std_dev})"
            }
          end

          private

          def calculate_mean(values)
            return 0 if values.empty?
            
            numeric_values = values.map { |v| v.is_a?(Numeric) ? v : v.to_s.length }
            numeric_values.sum.to_f / numeric_values.size
          end

          def calculate_std_dev(values)
            numeric_values = values.map { |v| v.is_a?(Numeric) ? v : v.to_s.length }
            mean = calculate_mean(values)
            
            variance = numeric_values.sum { |v| (v - mean)**2 } / numeric_values.size
            Math.sqrt(variance)
          end

          def calculate_score(cv, max_std_dev)
            return 1.0 if cv <= max_std_dev / 2
            return 0.0 if cv >= max_std_dev * 2

            1.0 - ((cv - max_std_dev / 2) / (max_std_dev * 1.5)).clamp(0, 1)
          end
        end
      end
    end
  end
end
