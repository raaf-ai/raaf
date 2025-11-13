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
          # @param options [Hash] Options:
          #   - :tolerance [Numeric] Maximum allowed drop from baseline (default: 0)
          #   - :alert_on_drop [Boolean] Alert on any drop (default: true)
          #   - :severity [Symbol] Severity level (unused, for compatibility)
          # @return [Hash] Evaluation result
          def evaluate(field_context, **options)
            current_value = field_context.value
            baseline_value = field_context.baseline_value
            tolerance = options[:tolerance] || 0

            # Handle missing baseline
            unless baseline_value
              return {
                passed: true,
                score: 1.0,
                details: { current_value: current_value, no_baseline: true },
                message: "No baseline available for regression check"
              }
            end

            # Handle array values - check each element
            if current_value.is_a?(Array) && baseline_value.is_a?(Array)
              return evaluate_array_regression(current_value, baseline_value, tolerance, field_context)
            end

            # For numeric values, check if current is not worse (within tolerance)
            if numeric?(current_value) && numeric?(baseline_value)
              drop = baseline_value - current_value
              passed = drop <= tolerance
              score = passed ? 1.0 : calculate_regression_score(current_value, baseline_value, tolerance)
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
                delta: field_context.delta,
                tolerance: tolerance,
                drop: baseline_value - current_value
              },
              message: passed ? "No regression detected" : "Regression detected from baseline"
            }
          end

          private

          # Evaluate regression for array values (element-by-element comparison)
          def evaluate_array_regression(current_array, baseline_array, tolerance, field_context)
            # Ensure arrays are same length
            if current_array.length != baseline_array.length
              return {
                passed: false,
                score: 0.0,
                details: {
                  current_value: current_array,
                  baseline_value: baseline_array,
                  error: "Array length mismatch"
                },
                message: "Array length mismatch: cannot compare arrays of different sizes"
              }
            end

            # Calculate drops for each element
            drops = baseline_array.zip(current_array).map do |baseline_elem, current_elem|
              next nil unless numeric?(baseline_elem) && numeric?(current_elem)
              baseline_elem - current_elem
            end

            # Check if any drop exceeds tolerance
            max_drop = drops.compact.max || 0
            excessive_drops = drops.compact.select { |drop| drop > tolerance }
            passed = excessive_drops.empty?

            # Calculate score based on worst regression
            if passed
              score = 1.0
            elsif max_drop > 0
              # Score based on how much the worst drop exceeds tolerance
              excess_drop = max_drop - tolerance
              baseline_max = baseline_array.compact.max || 1
              regression_pct = (excess_drop.to_f / baseline_max).abs
              score = [1.0 - regression_pct, 0.0].max
            else
              score = 0.5
            end

            {
              passed: passed,
              score: score,
              details: {
                current_value: current_array,
                baseline_value: baseline_array,
                delta: field_context.delta,
                tolerance: tolerance,
                drops: drops,
                max_drop: max_drop,
                excessive_drops_count: excessive_drops.length
              },
              message: passed ? "No regression detected in array" : "Regression detected: #{excessive_drops.length} element(s) exceed tolerance"
            }
          end

          def numeric?(value)
            value.is_a?(Numeric)
          end

          def calculate_regression_score(current, baseline, tolerance)
            return 0.0 if baseline == 0

            drop = baseline - current

            # If within tolerance, score is 1.0
            return 1.0 if drop <= tolerance

            # Calculate how much the drop exceeds tolerance
            excess_drop = drop - tolerance
            regression_pct = (excess_drop.to_f / baseline).abs

            # Score decreases as regression beyond tolerance increases
            [1.0 - regression_pct, 0.0].max
          end
        end
      end
    end
  end
end
