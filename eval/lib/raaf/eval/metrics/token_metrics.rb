# frozen_string_literal: true

module RAAF
  module Eval
    module Metrics
      ##
      # TokenMetrics calculates token-related metrics
      class TokenMetrics
        class << self
          ##
          # Calculate token metrics from baseline and result spans
          # @param baseline_span [Object] Baseline span
          # @param result_span [Object] Result span
          # @return [Hash] Token metrics
          def calculate(baseline_span, result_span)
            baseline_tokens = extract_tokens(baseline_span)
            result_tokens = extract_tokens(result_span)

            {
              baseline: baseline_tokens,
              result: result_tokens,
              delta: {
                total: result_tokens[:total] - baseline_tokens[:total],
                input: result_tokens[:input] - baseline_tokens[:input],
                output: result_tokens[:output] - baseline_tokens[:output]
              },
              percentage_change: calculate_percentage_change(baseline_tokens[:total], result_tokens[:total])
            }
          end

          private

          def extract_tokens(span)
            span_data = span.is_a?(Models::EvaluationSpan) ? span.span_data : span

            {
              total: span_data&.dig("metadata", "tokens") || 0,
              input: span_data&.dig("metadata", "input_tokens") || 0,
              output: span_data&.dig("metadata", "output_tokens") || 0,
              reasoning: span_data&.dig("metadata", "reasoning_tokens") || 0
            }
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
