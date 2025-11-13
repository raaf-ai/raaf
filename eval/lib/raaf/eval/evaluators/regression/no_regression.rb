# frozen_string_literal: true

require_relative "../../dsl/evaluator"

module RAAF
  module Eval
    module Evaluators
      module Regression
        # Ensures no regression from baseline
        class NoRegression
          include RAAF::Eval::DSL::Evaluator

          evaluator_name :no_regression

          # Evaluate that there's no regression from baseline
          # @param field_context [FieldContext] The field context containing value and baseline
          # @param options [Hash] Options (currently unused)
          # @return [Hash] Evaluation result
          def evaluate(field_context, **options)
            current_value = field_context.value
            baseline_value = field_context.baseline_value

            # Handle missing baseline
            unless baseline_value
              return {
                passed: true,
                score: 1.0,
                details: { current_value: current_value, no_baseline: true },
                message: "No baseline available for regression check"
              }
            end

            # For numeric values, check if current is not worse
            if numeric?(current_value) && numeric?(baseline_value)
              passed = current_value >= baseline_value
              score = passed ? 1.0 : calculate_regression_score(current_value, baseline_value)
            else
              # For non-numeric, check equality
              passed = current_value == baseline_value
              score = passed ? 1.0 : 0.5
            end

            {
              passed: passed,
              score: score,
              details: {
                current_value: current_value,
                baseline_value: baseline_value,
                delta: field_context.delta
              },
              message: passed ? "No regression detected" : "Regression detected from baseline"
            }
          end

          private

          def numeric?(value)
            value.is_a?(Numeric)
          end

          def calculate_regression_score(current, baseline)
            return 0.0 if baseline == 0
            
            # Calculate how much worse current is compared to baseline
            regression_pct = ((baseline - current).to_f / baseline).abs
            
            # Score decreases as regression increases
            [1.0 - regression_pct, 0.0].max
          end
        end
      end
    end
  end
end
