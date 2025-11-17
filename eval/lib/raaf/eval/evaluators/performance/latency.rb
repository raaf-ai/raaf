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
          # @param options [Hash] Options including:
          #   Discrete millisecond thresholds (RECOMMENDED):
          #     :good_threshold_ms - Latency threshold for "good" label (e.g., 96000 for 96s)
          #     :average_threshold_ms - Latency threshold for "average" label (e.g., 132000 for 132s)
          #   Score-based thresholds (LEGACY - requires max_ms):
          #     :max_ms (default 2000) - Maximum acceptable latency
          #     :threshold_good (default 0.85) - Score threshold for "good" label
          #     :threshold_average (default 0.7) - Score threshold for "average" label
          #     Legacy: :good_threshold, :average_threshold also supported
          # @return [Hash] Evaluation result
          def evaluate(field_context, **options)
            current_latency = field_context.value

            # Handle invalid latency values
            unless current_latency && current_latency.is_a?(Numeric) && current_latency >= 0
              return {
                label: :bad,
                score: 0.0,
                details: {
                  current_latency: current_latency,
                  error: "Invalid latency value"
                },
                message: "[BAD] Invalid latency value: #{current_latency}"
              }
            end

            # Use discrete thresholds if provided (RECOMMENDED)
            if options[:good_threshold_ms] || options[:average_threshold_ms]
              label = calculate_label_from_discrete_thresholds(
                current_latency,
                good_threshold_ms: options[:good_threshold_ms],
                average_threshold_ms: options[:average_threshold_ms]
              )
              # Simple score mapping: good=1.0, average=0.5, bad=0.0
              score = case label
                      when :good then 1.0
                      when :average then 0.5
                      else 0.0
                      end
              details = {
                current_latency: current_latency,
                baseline_latency: field_context.baseline_value,
                good_threshold_ms: options[:good_threshold_ms],
                average_threshold_ms: options[:average_threshold_ms]
              }
              message = "[#{label.upcase}] Latency: #{current_latency}ms"
            else
              # Legacy score-based approach (requires max_ms)
              max_ms = options[:max_ms] || 2000
              score = calculate_score(current_latency, max_ms)
              threshold_good = options[:threshold_good] || options[:good_threshold] || 0.85
              threshold_average = options[:threshold_average] || options[:average_threshold] || 0.7
              label = calculate_label(score, threshold_good: threshold_good, threshold_average: threshold_average)
              details = {
                current_latency: current_latency,
                max_ms: max_ms,
                baseline_latency: field_context.baseline_value,
                threshold_good: threshold_good,
                threshold_average: threshold_average
              }
              message = "[#{label.upcase}] Latency: #{current_latency}ms (max: #{max_ms}ms)"
            end

            {
              label: label,
              score: score,
              details: details,
              message: message
            }
          end

          private

          def calculate_score(latency, max_ms)
            return 1.0 if latency <= max_ms / 2 # Excellent if under half threshold
            return 0.0 if latency >= max_ms * 2 # Poor if over double threshold

            # Linear scale between half and double threshold
            1.0 - ((latency - max_ms / 2.0) / (max_ms * 1.5)).clamp(0, 1)
          end

          # Calculate label from discrete millisecond thresholds
          # @param latency [Numeric] Current latency in milliseconds
          # @param good_threshold_ms [Numeric, nil] Threshold for "good" label
          # @param average_threshold_ms [Numeric, nil] Threshold for "average" label
          # @return [Symbol] :good, :average, or :bad
          def calculate_label_from_discrete_thresholds(latency, good_threshold_ms:, average_threshold_ms:)
            # If good_threshold_ms provided and latency is under it, return "good"
            return :good if good_threshold_ms && latency <= good_threshold_ms

            # If average_threshold_ms provided and latency is under it, return "average"
            return :average if average_threshold_ms && latency <= average_threshold_ms

            # Otherwise, return "bad"
            :bad
          end
        end
      end
    end
  end
end
