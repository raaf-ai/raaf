# frozen_string_literal: true

require_relative "../../dsl/evaluator"

module RAAF
  module Eval
    module Evaluators
      module Regression
        # Checks for latency regression
        class LatencyRegression
          include RAAF::Eval::DSL::Evaluator

          evaluator_name :latency_regression

          # Evaluate latency regression
          # @param field_context [FieldContext] The field context containing value and baseline
          # @param options [Hash] Options including :max_ms (default 200)
          # @return [Hash] Evaluation result
          def evaluate(field_context, **options)
            max_ms = options[:max_ms] || 200
            current_latency = field_context.value
            baseline_latency = field_context.baseline_value

            # Handle missing baseline
            unless baseline_latency
              return {
                passed: true,
                score: 1.0,
                details: { current_latency: current_latency, no_baseline: true },
                message: "No baseline for latency regression check"
              }
            end

            # Calculate latency increase
            increase_ms = [current_latency - baseline_latency, 0].max

            passed = increase_ms <= max_ms

            {
              passed: passed,
              score: calculate_score(increase_ms, max_ms),
              details: {
                current_latency: current_latency,
                baseline_latency: baseline_latency,
                increase_ms: increase_ms,
                max_ms: max_ms
              },
              message: "Latency increase: #{increase_ms}ms (max: #{max_ms}ms)"
            }
          end

          private

          def calculate_score(increase_ms, max_ms)
            return 1.0 if increase_ms <= 0 # No regression
            return 0.0 if increase_ms >= max_ms * 2

            # Linear scale
            1.0 - (increase_ms.to_f / (max_ms * 2)).clamp(0, 1)
          end
        end
      end
    end
  end
end
