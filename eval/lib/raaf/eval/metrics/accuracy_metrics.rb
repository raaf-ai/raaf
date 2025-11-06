# frozen_string_literal: true

module RAAF
  module Eval
    module Metrics
      ##
      # AccuracyMetrics calculates accuracy-related metrics
      class AccuracyMetrics
        class << self
          ##
          # Calculate accuracy metrics
          # @param expected [String] Expected output
          # @param actual [String] Actual output
          # @return [Hash] Accuracy metrics
          def calculate(expected, actual)
            {
              exact_match: exact_match?(expected, actual),
              fuzzy_match: fuzzy_match_score(expected, actual),
              length_ratio: length_ratio(expected, actual)
            }
          end

          private

          def exact_match?(expected, actual)
            expected.to_s.strip == actual.to_s.strip
          end

          def fuzzy_match_score(expected, actual)
            return 1.0 if exact_match?(expected, actual)

            # Simple character overlap scoring
            exp_chars = expected.to_s.downcase.chars.to_set
            act_chars = actual.to_s.downcase.chars.to_set
            
            intersection = exp_chars & act_chars
            union = exp_chars | act_chars

            return 0.0 if union.empty?
            (intersection.size.to_f / union.size).round(3)
          end

          def length_ratio(expected, actual)
            exp_len = expected.to_s.length
            return 1.0 if exp_len.zero?
            (actual.to_s.length.to_f / exp_len).round(3)
          end
        end
      end
    end
  end
end
