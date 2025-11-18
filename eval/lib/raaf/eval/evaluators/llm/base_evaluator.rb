# frozen_string_literal: true

module RAAF
  module Eval
    module Evaluators
      module LLM
        # Base class for LLM-oriented evaluators with user-configurable thresholds
        #
        # Provides:
        # - Three-tier threshold configuration (call-time > instance > class defaults)
        # - Threshold validation (good > average, 0.0-1.0 range)
        # - Standardized result formatting with threshold metadata
        # - Integration with RAAF Eval's good/average/bad labeling pattern
        #
        # @example Basic usage with class defaults
        #   class MyEvaluator < BaseEvaluator
        #     DEFAULT_GOOD_THRESHOLD = 0.80
        #     DEFAULT_AVERAGE_THRESHOLD = 0.60
        #
        #     def evaluate(field_context, **options)
        #       good_threshold, average_threshold = resolve_thresholds(options)
        #       score = calculate_score(field_context)
        #       label = calculate_label(score, good_threshold: good_threshold, average_threshold: average_threshold)
        #       build_result(score, label, good_threshold, average_threshold)
        #     end
        #   end
        #
        # @example Custom instance thresholds
        #   evaluator = MyEvaluator.new(good_threshold: 0.95, average_threshold: 0.80)
        #   result = evaluator.evaluate(field_context)
        #
        # @example Per-call threshold override
        #   evaluator = MyEvaluator.new
        #   result = evaluator.evaluate(field_context, good_threshold: 0.98, average_threshold: 0.90)
        #
        class BaseEvaluator
          include RAAF::Eval::DSL::Evaluator

          attr_reader :default_good_threshold, :default_average_threshold

          # Initialize evaluator with optional instance-level thresholds
          #
          # @param good_threshold [Float, nil] Instance-level "good" threshold (0.0-1.0)
          # @param average_threshold [Float, nil] Instance-level "average" threshold (0.0-1.0)
          # @param options [Hash] Additional options passed to parent module
          def initialize(good_threshold: nil, average_threshold: nil, **options)
            @default_good_threshold = good_threshold
            @default_average_threshold = average_threshold
            validate_thresholds!(@default_good_threshold, @default_average_threshold) if @default_good_threshold
          end

          protected

          # Resolve thresholds with three-tier precedence:
          # 1. Call-time options (highest priority)
          # 2. Instance defaults
          # 3. Class constants (lowest priority)
          #
          # @param options [Hash] Options passed to evaluate()
          # @return [Array<Float, Float>] [good_threshold, average_threshold]
          def resolve_thresholds(options)
            good = options[:good_threshold] ||
                   @default_good_threshold ||
                   self.class::DEFAULT_GOOD_THRESHOLD

            avg = options[:average_threshold] ||
                  @default_average_threshold ||
                  self.class::DEFAULT_AVERAGE_THRESHOLD

            validate_thresholds!(good, avg)
            [good, avg]
          end

          # Validate that thresholds are properly configured
          #
          # @param good [Float] Good threshold
          # @param avg [Float] Average threshold
          # @raise [ArgumentError] if thresholds are invalid
          def validate_thresholds!(good, avg)
            if good <= avg
              raise ArgumentError,
                    "good_threshold (#{good}) must be > average_threshold (#{avg})"
            end

            unless (0.0..1.0).cover?(good) && (0.0..1.0).cover?(avg)
              raise ArgumentError,
                    "Thresholds must be between 0.0 and 1.0, got good: #{good}, avg: #{avg}"
            end
          end

          # Build standardized result hash with threshold metadata
          #
          # @param score [Float] Evaluation score (0.0-1.0)
          # @param label [String] Quality label ("good", "average", or "bad")
          # @param good_threshold [Float] Good threshold used
          # @param average_threshold [Float] Average threshold used
          # @param details [Hash] Additional evaluator-specific details
          # @return [Hash] Standardized result hash
          def build_result(score, label, good_threshold, average_threshold, **details)
            evaluator_name = self.class.name.split("::").last

            {
              label: label,
              score: score,
              message: "[#{label.upcase}] #{evaluator_name}: #{(score * 100).round}%",
              details: details.merge(
                thresholds: {
                  good: good_threshold,
                  average: average_threshold,
                  used: label_from_score(score, good_threshold, average_threshold)
                }
              )
            }
          end

          private

          # Helper to determine which threshold was actually used
          #
          # @param score [Float] Score to evaluate
          # @param good_threshold [Float] Good threshold
          # @param average_threshold [Float] Average threshold
          # @return [String] Threshold category that score fell into
          def label_from_score(score, good_threshold, average_threshold)
            return "good (≥#{good_threshold})" if score >= good_threshold
            return "average (≥#{average_threshold})" if score >= average_threshold
            "bad (<#{average_threshold})"
          end
        end
      end
    end
  end
end
