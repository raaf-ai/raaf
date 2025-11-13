# frozen_string_literal: true

require_relative "../../dsl/evaluator"

module RAAF
  module Eval
    module Evaluators
      module Regression
        # Checks for token usage regression
        class TokenRegression
          include RAAF::Eval::DSL::Evaluator

          evaluator_name :token_regression

          # Evaluate token regression
          # @param field_context [FieldContext] The field context containing value and baseline
          # @param options [Hash] Options including :max_pct (default 10)
          # @return [Hash] Evaluation result
          def evaluate(field_context, **options)
            max_pct = options[:max_pct] || 10
            current_tokens = field_context.value
            baseline_tokens = field_context.baseline_value

            # Handle missing baseline
            unless baseline_tokens
              return {
                passed: true,
                score: 1.0,
                details: { current_tokens: current_tokens, no_baseline: true },
                message: "No baseline for token regression check"
              }
            end

            # Calculate percentage increase
            increase_pct = if baseline_tokens > 0
              [((current_tokens - baseline_tokens).to_f / baseline_tokens * 100), 0].max
            else
              current_tokens > 0 ? 100.0 : 0.0
            end

            passed = increase_pct <= max_pct

            {
              passed: passed,
              score: calculate_score(increase_pct, max_pct),
              details: {
                current_tokens: current_tokens,
                baseline_tokens: baseline_tokens,
                increase_pct: increase_pct.round(2),
                max_pct: max_pct
              },
              message: "Token increase: #{increase_pct.round(2)}% (max: #{max_pct}%)"
            }
          end

          private

          def calculate_score(increase_pct, max_pct)
            return 1.0 if increase_pct <= 0 # No regression
            return 0.0 if increase_pct >= max_pct * 2

            # Linear scale
            1.0 - (increase_pct / (max_pct * 2)).clamp(0, 1)
          end
        end
      end
    end
  end
end
