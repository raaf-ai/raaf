# frozen_string_literal: true

require_relative "../../dsl/evaluator"

module RAAF
  module Eval
    module Evaluators
      module Performance
        # Evaluates response latency
        class Latency
          include RAAF::Eval::DSL::Evaluator

          evaluator_name :latency

          # Evaluate response latency
          # @param field_context [FieldContext] The field context containing value and baseline
          # @param options [Hash] Options including :max_ms (default 2000)
          # @return [Hash] Evaluation result
          def evaluate(field_context, **options)
            max_ms = options[:max_ms] || 2000
            current_latency = field_context.value

            # Handle invalid latency values
            unless current_latency && current_latency.is_a?(Numeric) && current_latency >= 0
              return {
                passed: false,
                score: 0.0,
                details: { current_latency: current_latency, error: "Invalid latency value" },
                message: "Invalid latency value: #{current_latency}"
              }
            end

            passed = current_latency <= max_ms

            {
              passed: passed,
              score: calculate_score(current_latency, max_ms),
              details: {
                current_latency: current_latency,
                max_ms: max_ms,
                baseline_latency: field_context.baseline_value
              },
              message: "Latency: #{current_latency}ms (max: #{max_ms}ms)"
            }
          end

          private

          def calculate_score(latency, max_ms)
            return 1.0 if latency <= max_ms / 2 # Excellent if under half threshold
            return 0.0 if latency >= max_ms * 2 # Poor if over double threshold

            # Linear scale between half and double threshold
            1.0 - ((latency - max_ms / 2.0) / (max_ms * 1.5)).clamp(0, 1)
          end
        end
      end
    end
  end
end
