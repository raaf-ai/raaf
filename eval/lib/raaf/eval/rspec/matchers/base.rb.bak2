# frozen_string_literal: true

module RAAF
  module Eval
    module RSpec
      module Matchers
        ##
        # Base module for custom matchers
        #
        # Provides common utilities and helper methods for all matchers.
        module Base
          ##
          # Extracts output from an evaluation result or hash
          #
          # @param result [EvaluationResult, Hash] the result
          # @return [String] the output text
          def extract_output(result)
            case result
            when EvaluationResult
              result.baseline_output
            when Hash
              result[:output] || result.dig(:metadata, :output) || ""
            else
              result.to_s
            end
          end

          ##
          # Extracts usage stats from a result
          #
          # @param result [EvaluationResult, Hash] the result
          # @return [Hash] usage statistics
          def extract_usage(result)
            case result
            when EvaluationResult
              result.baseline_usage
            when Hash
              result[:usage] || result.dig(:metadata, :usage) || {}
            else
              {}
            end
          end

          ##
          # Extracts latency from a result
          #
          # @param result [EvaluationResult, Hash] the result
          # @return [Float] latency in milliseconds
          def extract_latency(result)
            case result
            when EvaluationResult
              result.baseline_latency
            when Hash
              result[:latency_ms] || 0
            else
              0
            end
          end

          ##
          # Formats a percentage
          #
          # @param value [Float] the percentage value
          # @return [String] formatted percentage
          def format_percent(value)
            format("%.2f%%", value)
          end

          ##
          # Formats a number with commas
          #
          # @param value [Numeric] the number
          # @return [String] formatted number
          def format_number(value)
            value.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
          end
        end
      end
    end
  end
end
