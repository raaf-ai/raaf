# frozen_string_literal: true

module RAAF
  module Eval
    module Metrics
      ##
      # LatencyMetrics calculates latency-related metrics
      class LatencyMetrics
        class << self
          ##
          # Calculate latency metrics
          # @param baseline_span [Object] Baseline span
          # @param result_span [Object] Result span
          # @return [Hash] Latency metrics
          def calculate(baseline_span, result_span)
            baseline_latency = extract_latency(baseline_span)
            result_latency = extract_latency(result_span)

            {
              baseline_ms: baseline_latency,
              result_ms: result_latency,
              delta_ms: result_latency - baseline_latency,
              percentage_change: calculate_percentage_change(baseline_latency, result_latency)
            }
          end

          private

          def extract_latency(span)
            span_data = span.is_a?(Models::EvaluationSpan) ? span.span_data : span
            span_data&.dig("metadata", "latency_ms") || 0
          end

          def calculate_percentage_change(baseline, result)
            return 0 if baseline.zero?
            ((result - baseline).to_f / baseline * 100).round(2)
          end
        end
      end
    end
  end
end
