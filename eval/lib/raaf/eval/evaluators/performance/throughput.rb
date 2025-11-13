# frozen_string_literal: true

require_relative "../../dsl/evaluator"

module RAAF
  module Eval
    module Evaluators
      module Performance
        # Evaluates tokens per second throughput
        class Throughput
          include RAAF::Eval::DSL::Evaluator

          evaluator_name :throughput

          # Evaluate throughput (tokens per second)
          # @param field_context [FieldContext] The field context containing value and baseline
          # @param options [Hash] Options including :min_tps (default 10)
          # @return [Hash] Evaluation result
          def evaluate(field_context, **options)
            min_tps = options[:min_tps] || 10
            current_tps = field_context.value

            # Handle invalid throughput values
            unless current_tps && current_tps.is_a?(Numeric) && current_tps >= 0
              return {
                passed: false,
                score: 0.0,
                details: { current_tps: current_tps, error: "Invalid throughput value" },
                message: "Invalid throughput value: #{current_tps}"
              }
            end

            passed = current_tps >= min_tps

            {
              passed: passed,
              score: calculate_score(current_tps, min_tps),
              details: {
                current_tps: current_tps,
                min_tps: min_tps,
                baseline_tps: field_context.baseline_value
              },
              message: "Throughput: #{current_tps.round(1)} tokens/sec (min: #{min_tps} tokens/sec)"
            }
          end

          private

          def calculate_score(tps, min_tps)
            return 1.0 if tps >= min_tps * 2 # Excellent if double the minimum
            return 0.0 if tps <= 0

            # Linear scale from 0 to double minimum
            (tps / (min_tps * 2.0)).clamp(0, 1)
          end
        end
      end
    end
  end
end
