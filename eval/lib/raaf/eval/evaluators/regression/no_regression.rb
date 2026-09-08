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

          # Format evaluation result as markdown
          # @param result [Hash] The evaluation result with :score and :details
          # @return [String] Markdown-formatted result
          def self.format_result(result)
            details = result[:details] || {}
            result[:score]

            no_baseline = details[:no_baseline] || details["no_baseline"]
            max_drop = details[:max_drop] || details["max_drop"]
            drop = details[:drop] || details["drop"]
            tolerance = details[:tolerance] || details["tolerance"] || 0

            md = String.new("### Regression Check\n\n")

            if no_baseline
              md << "- **Status:** ✓ Establishing baseline\n"
              md << "- **Note:** No previous data to compare. This run establishes the baseline.\n"
            else
              actual_drop = max_drop || drop || 0
              # Determine status based on drop relative to tolerance
              status = if actual_drop <= 0
                         "✓ Good"
                       elsif actual_drop <= tolerance
                         "◐ Average"
                       else
                         "✗ Bad"
                       end

              md << "| Metric | Value | Threshold | Result |\n"
              md << "|--------|------:|----------:|--------|\n"
              md << "| Max Score Drop | #{actual_drop} pts | ≤#{tolerance} pts | #{status} |\n"
              md << "\n"

              if status == "✗ Bad"
                md << "**Issue:** Score dropped by #{actual_drop} points, exceeding the "
                md << "#{tolerance} point threshold.\n"
              end
            end

            md
          end

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
                label: "good",
                score: 1.0,
                details: { current_value: current_value, no_baseline: true },
                message: "[GOOD] No baseline available for regression check"
              }
            end

            # Handle array values - check each element
            if current_value.is_a?(Array) && baseline_value.is_a?(Array)
              return evaluate_array_regression(current_value, baseline_value, tolerance, field_context)
            end

            # For numeric values, check if current is not worse (within tolerance)
            if numeric?(current_value) && numeric?(baseline_value)
              drop = baseline_value - current_value
              score = drop <= tolerance ? 1.0 : calculate_regression_score(current_value, baseline_value, tolerance)
              label = label_for_drop(drop, tolerance)
            else
              # For non-numeric, check equality
              same = current_value == baseline_value
              score = same ? 1.0 : 0.5
              label = same ? "good" : "bad"
            end

            {
              label: label,
              score: score,
              details: {
                current_value: current_value,
                baseline_value: baseline_value,
                delta: field_context.delta,
                tolerance: tolerance,
                drop: baseline_value - current_value
              },
              message: "[#{label.upcase}] #{label == "good" ? "No regression detected" : "Regression detected from baseline"}"
            }
          end

          private

          # Evaluate regression for array values (element-by-element comparison)
          def evaluate_array_regression(current_array, baseline_array, tolerance, field_context)
            # Ensure arrays are same length
            if current_array.length != baseline_array.length
              return {
                label: "bad",
                score: 0.0,
                details: {
                  current_value: current_array,
                  baseline_value: baseline_array,
                  error: "Array length mismatch"
                },
                message: "[BAD] Array length mismatch: cannot compare arrays of different sizes"
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

            # Calculate score based on worst regression
            if excessive_drops.empty?
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

            label = label_for_drop(max_drop, tolerance)

            {
              label: label,
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
              message: "[#{label.upcase}] #{label == "good" ? "No regression detected in array" : "Regression detected: #{excessive_drops.length} element(s) exceed tolerance"}"
            }
          end

          # The verdict this evaluator exists to give: nothing dropped is good, a drop the
          # caller declared tolerable is average, and a drop past that is the regression
          # the evaluator is named after.
          # @param drop [Numeric] How far the value fell below the baseline
          # @param tolerance [Numeric] The drop the caller declared acceptable
          # @return [String] "good", "average" or "bad"
          def label_for_drop(drop, tolerance)
            return "good" if drop <= 0
            return "average" if drop <= tolerance

            "bad"
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
