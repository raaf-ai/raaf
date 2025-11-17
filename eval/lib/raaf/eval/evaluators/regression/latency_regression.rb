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
          # @param options [Hash] Options including :max_ms (default 200),
          #   :good_threshold (default 0.8), :average_threshold (default 0.6)
          # @return [Hash] Evaluation result
          def evaluate(field_context, **options)
            max_ms = options[:max_ms] || 200
            good_threshold = options[:good_threshold] || 0.8
            average_threshold = options[:average_threshold] || 0.6
            current_latency = field_context.value
            baseline_latency = field_context.baseline_value

            # Handle missing baseline
            unless baseline_latency
              return {
                label: :good,
                score: 1.0,
                details: { current_latency: current_latency, no_baseline: true },
                message: "[GOOD] No baseline for latency regression check"
              }
            end

            # Calculate latency increase
            increase_ms = [current_latency - baseline_latency, 0].max

            score = calculate_score(increase_ms, max_ms)
            label = calculate_label(score, good_threshold: good_threshold, average_threshold: average_threshold)

            {
              label: label,
              score: score,
              details: {
                current_latency: current_latency,
                baseline_latency: baseline_latency,
                increase_ms: increase_ms,
                max_ms: max_ms,
                threshold_good: good_threshold,
                threshold_average: average_threshold
              },
              message: "[#{label.upcase}] Latency increase: #{increase_ms}ms (max: #{max_ms}ms)"
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
