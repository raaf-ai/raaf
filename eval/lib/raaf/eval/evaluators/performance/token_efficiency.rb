# frozen_string_literal: true

require_relative "../../dsl/evaluator"

module RAAF
  module Eval
    module Evaluators
      module Performance
        # Evaluates token efficiency by checking token usage increase
        class TokenEfficiency
          include RAAF::Eval::DSL::Evaluator

          evaluator_name :token_efficiency

          # Evaluate token efficiency
          # @param field_context [FieldContext] The field context containing value and baseline
          # @param options [Hash] Options including :max_increase_pct (default 10),
          #   :good_threshold (default 0.85), :average_threshold (default 0.7)
          # @return [Hash] Evaluation result
          def evaluate(field_context, **options)
            max_increase_pct = options[:max_increase_pct] || 10
            good_threshold = options[:good_threshold] || 0.85
            average_threshold = options[:average_threshold] || 0.7
            current_tokens = field_context.value
            baseline_tokens = field_context.baseline_value

            # Handle missing baseline
            unless baseline_tokens
              return {
                label: :good,
                score: 1.0,
                details: { current_tokens: current_tokens, no_baseline: true },
                message: "[GOOD] No baseline available for comparison"
              }
            end

            # Calculate percentage change
            delta = field_context.delta
            percentage_change = if baseline_tokens > 0
              ((current_tokens - baseline_tokens).to_f / baseline_tokens * 100).round(2)
            else
              current_tokens > 0 ? 100.0 : 0.0
            end

            score = calculate_score(percentage_change, max_increase_pct)
            label = calculate_label(score, good_threshold: good_threshold, average_threshold: average_threshold)

            {
              label: label,
              score: score,
              details: {
                current_tokens: current_tokens,
                baseline_tokens: baseline_tokens,
                percentage_change: percentage_change,
                threshold: max_increase_pct,
                threshold_good: good_threshold,
                threshold_average: average_threshold
              },
              message: "[#{label.upcase}] Token usage: #{percentage_change}% change (max: #{max_increase_pct}%)"
            }
          end

          private

          def calculate_score(percentage_change, max_increase_pct)
            return 1.0 if percentage_change <= 0 # Improvement or no change
            return 0.0 if percentage_change >= max_increase_pct * 2 # Double the threshold

            # Linear scale between threshold and 2x threshold
            1.0 - ((percentage_change - max_increase_pct) / max_increase_pct).clamp(0, 1)
          end
        end
      end
    end
  end
end
