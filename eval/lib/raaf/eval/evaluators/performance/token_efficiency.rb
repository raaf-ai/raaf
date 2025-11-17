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
          # @param options [Hash] Options including:
          #   Discrete token thresholds (RECOMMENDED):
          #     :good_threshold_tokens - Token threshold for "good" label (e.g., 2800 for 2800 tokens)
          #     :average_threshold_tokens - Token threshold for "average" label (e.g., 3500 for 3500 tokens)
          #   Score-based thresholds (LEGACY - requires max_increase_pct):
          #     :max_increase_pct (default 10) - Maximum percentage increase from baseline
          #     :threshold_good (default 0.85) - Score threshold for "good" label
          #     :threshold_average (default 0.7) - Score threshold for "average" label
          #     Legacy: :good_threshold, :average_threshold also supported
          # @return [Hash] Evaluation result
          def evaluate(field_context, **options)
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

            # Use discrete thresholds if provided (RECOMMENDED)
            if options[:good_threshold_tokens] || options[:average_threshold_tokens]
              label = calculate_label_from_discrete_thresholds(
                current_tokens,
                good_threshold_tokens: options[:good_threshold_tokens],
                average_threshold_tokens: options[:average_threshold_tokens]
              )
              # Simple score mapping: good=1.0, average=0.5, bad=0.0
              score = case label
                      when :good then 1.0
                      when :average then 0.5
                      else 0.0
                      end
              details = {
                current_tokens: current_tokens,
                baseline_tokens: baseline_tokens,
                good_threshold_tokens: options[:good_threshold_tokens],
                average_threshold_tokens: options[:average_threshold_tokens]
              }
              message = "[#{label.upcase}] Token usage: #{current_tokens} tokens"
            else
              # Legacy score-based approach (requires max_increase_pct)
              max_increase_pct = options[:max_increase_pct] || 10
              percentage_change = if baseline_tokens > 0
                ((current_tokens - baseline_tokens).to_f / baseline_tokens * 100).round(2)
              else
                current_tokens > 0 ? 100.0 : 0.0
              end
              score = calculate_score(percentage_change, max_increase_pct)
              threshold_good = options[:threshold_good] || options[:good_threshold] || 0.85
              threshold_average = options[:threshold_average] || options[:average_threshold] || 0.7
              label = calculate_label(score, good_threshold: threshold_good, threshold_average: threshold_average)
              details = {
                current_tokens: current_tokens,
                baseline_tokens: baseline_tokens,
                percentage_change: percentage_change,
                threshold: max_increase_pct,
                threshold_good: threshold_good,
                threshold_average: threshold_average
              }
              message = "[#{label.upcase}] Token usage: #{current_tokens} tokens (#{percentage_change}% change)"
            end

            {
              label: label,
              score: score,
              details: details,
              message: message
            }
          end

          private

          def calculate_score(percentage_change, max_increase_pct)
            return 1.0 if percentage_change <= 0 # Improvement or no change
            return 0.0 if percentage_change >= max_increase_pct * 2 # Double the threshold

            # Linear scale between threshold and 2x threshold
            1.0 - ((percentage_change - max_increase_pct) / max_increase_pct).clamp(0, 1)
          end

          # Calculate label from discrete token thresholds
          # @param tokens [Numeric] Current token usage
          # @param good_threshold_tokens [Numeric, nil] Threshold for "good" label
          # @param average_threshold_tokens [Numeric, nil] Threshold for "average" label
          # @return [Symbol] :good, :average, or :bad
          def calculate_label_from_discrete_thresholds(tokens, good_threshold_tokens:, average_threshold_tokens:)
            # If good_threshold_tokens provided and tokens are under it, return "good"
            return :good if good_threshold_tokens && tokens <= good_threshold_tokens

            # If average_threshold_tokens provided and tokens are under it, return "average"
            return :average if average_threshold_tokens && tokens <= average_threshold_tokens

            # Otherwise, return "bad"
            :bad
          end
        end
      end
    end
  end
end
