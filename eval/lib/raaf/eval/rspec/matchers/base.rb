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
          # Applies a matcher module's defaults the moment it is mixed in.
          #
          # `RSpec::Matchers.define` runs its block with `instance_exec` against a matcher
          # that has already been constructed, so an `include` inside that block lands on
          # the matcher's singleton class and the included module's own `#initialize` never
          # runs. Every default it would have set stays nil. Matcher modules therefore put
          # their defaults in `#matcher_defaults`, and this hook calls it on the matcher as
          # soon as the module is attached.
          module ApplyDefaultsOnInclude
            def included(target)
              super
              return unless target.singleton_class?

              target.attached_object.send(:matcher_defaults)
            end
          end

          def self.included(base)
            super
            base.extend(ApplyDefaultsOnInclude)
          end

          ##
          # Defaults for a matcher instance. Modules override this; the base is a no-op so
          # that a matcher without defaults still satisfies the include hook.
          def matcher_defaults; end

          ##
          # Extracts output from an evaluation result or hash
          #
          # @param result [EvaluationResult, Hash] the result
          # @return [String] the output text
          def extract_output(result)
            case result
            when EvaluationResult
              result.evaluation_output
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
              result.evaluation_usage
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
              result.evaluation_latency
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
