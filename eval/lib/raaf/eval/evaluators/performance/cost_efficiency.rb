# frozen_string_literal: true

require_relative "../../dsl/evaluator"

module RAAF
  module Eval
    module Evaluators
      module Performance
        # Evaluates cost efficiency by checking cost increase
        class CostEfficiency
          include RAAF::Eval::DSL::Evaluator

          evaluator_name :cost_efficiency

          # Evaluate cost efficiency
          # @param field_context [FieldContext] The field context containing value and baseline
          # @param options [Hash] Options including:
          #   Discrete cost thresholds (RECOMMENDED):
          #     :good_threshold_cost - Cost threshold for "good" label (e.g., 0.40 for $0.40)
          #     :average_threshold_cost - Cost threshold for "average" label (e.g., 0.50 for $0.50)
          #   Score-based thresholds (LEGACY - requires max_increase_pct):
          #     :max_increase_pct (default 10) - Maximum percentage increase from baseline
          #     :threshold_good (default 0.85) - Score threshold for "good" label
          #     :threshold_average (default 0.7) - Score threshold for "average" label
          #     Legacy: :good_threshold, :average_threshold also supported
          # @return [Hash] Evaluation result
          def evaluate(field_context, **options)
            current_cost = field_context.value
            baseline_cost = field_context.baseline_value

            # Handle invalid cost values
            unless current_cost && current_cost.is_a?(Numeric) && current_cost >= 0
              return {
                label: :bad,
                score: 0.0,
                details: {
                  current_cost: current_cost,
                  error: "Invalid cost value"
                },
                message: "[BAD] Invalid cost value: #{current_cost}"
              }
            end

            # Handle missing baseline
            unless baseline_cost
              return {
                label: :good,
                score: 1.0,
                details: { current_cost: current_cost, no_baseline: true },
                message: "[GOOD] No baseline available for comparison"
              }
            end

            # Use discrete thresholds if provided (RECOMMENDED)
            if options[:good_threshold_cost] || options[:average_threshold_cost]
              label = calculate_label_from_discrete_thresholds(
                current_cost,
                good_threshold_cost: options[:good_threshold_cost],
                average_threshold_cost: options[:average_threshold_cost]
              )
              # Simple score mapping: good=1.0, average=0.5, bad=0.0
              score = case label
                      when :good then 1.0
                      when :average then 0.5
                      else 0.0
                      end
              details = {
                current_cost: current_cost,
                baseline_cost: baseline_cost,
                good_threshold_cost: options[:good_threshold_cost],
                average_threshold_cost: options[:average_threshold_cost]
              }
              message = "[#{label.upcase}] Cost: $#{current_cost.round(4)}"
            else
              # Legacy score-based approach (requires max_increase_pct)
              max_increase_pct = options[:max_increase_pct] || 10
              percentage_change = if baseline_cost > 0
                ((current_cost - baseline_cost).to_f / baseline_cost * 100).round(2)
              else
                current_cost > 0 ? 100.0 : 0.0
              end
              score = calculate_score(percentage_change, max_increase_pct)
              threshold_good = options[:threshold_good] || options[:good_threshold] || 0.85
              threshold_average = options[:threshold_average] || options[:average_threshold] || 0.7
              label = calculate_label(score, good_threshold: threshold_good, threshold_average: threshold_average)
              details = {
                current_cost: current_cost,
                baseline_cost: baseline_cost,
                percentage_change: percentage_change,
                threshold: max_increase_pct,
                threshold_good: threshold_good,
                threshold_average: threshold_average
              }
              message = "[#{label.upcase}] Cost: $#{current_cost.round(4)} (#{percentage_change}% change)"
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

          # Calculate label from discrete cost thresholds
          # @param cost [Numeric] Current cost in USD
          # @param good_threshold_cost [Numeric, nil] Threshold for "good" label
          # @param average_threshold_cost [Numeric, nil] Threshold for "average" label
          # @return [Symbol] :good, :average, or :bad
          def calculate_label_from_discrete_thresholds(cost, good_threshold_cost:, average_threshold_cost:)
            # If good_threshold_cost provided and cost is under it, return "good"
            return :good if good_threshold_cost && cost <= good_threshold_cost

            # If average_threshold_cost provided and cost is under it, return "average"
            return :average if average_threshold_cost && cost <= average_threshold_cost

            # Otherwise, return "bad"
            :bad
          end
        end
      end
    end
  end
end
