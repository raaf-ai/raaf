# frozen_string_literal: true

module RAAF
  module Eval
    ##
    # BaselineComparator compares evaluation results against baseline
    class BaselineComparator
      class << self
        ##
        # Compare result against baseline
        # @param baseline_span [Object] Baseline span
        # @param result_span [Object] Result span
        # @param token_metrics [Hash] Token metrics
        # @param latency_metrics [Hash] Latency metrics
        # @return [Hash] Comparison results
        def compare(baseline_span, result_span, token_metrics, latency_metrics)
          {
            token_delta: calculate_token_delta(token_metrics),
            latency_delta: calculate_latency_delta(latency_metrics),
            quality_change: determine_quality_change(token_metrics, latency_metrics),
            regression_detected: detect_regression(token_metrics, latency_metrics)
          }
        end

        private

        def calculate_token_delta(token_metrics)
          baseline = token_metrics[:baseline][:total]
          result = token_metrics[:result][:total]

          {
            absolute: result - baseline,
            percentage: token_metrics[:percentage_change]
          }
        end

        def calculate_latency_delta(latency_metrics)
          {
            absolute_ms: latency_metrics[:delta_ms],
            percentage: latency_metrics[:percentage_change]
          }
        end

        def determine_quality_change(token_metrics, latency_metrics)
          token_change = token_metrics[:percentage_change]
          latency_change = latency_metrics[:percentage_change]

          # Simple heuristic: lower tokens and latency is better
          if token_change < -10 && latency_change < -10
            "improved"
          elsif token_change > 20 || latency_change > 30
            "degraded"
          else
            "unchanged"
          end
        end

        def detect_regression(token_metrics, latency_metrics)
          # Flag as regression if tokens or latency increased significantly
          token_metrics[:percentage_change] > 50 || latency_metrics[:percentage_change] > 50
        end
      end
    end
  end
end
