# frozen_string_literal: true

module RAAF
  module Eval
    module DSL
      # Error raised when evaluator result doesn't match contract
      class InvalidEvaluatorResultError < StandardError; end

      # Base module for all evaluators
      # Defines the interface contract for evaluators
      module Evaluator
        def self.included(base)
          base.extend(ClassMethods)
        end

        module ClassMethods
          # Define the evaluator name for DSL reference
          def evaluator_name(name = nil)
            if name
              @evaluator_name = name.to_sym
            else
              @evaluator_name
            end
          end
        end

        # Validate that result matches the evaluator contract
        # @param result [Hash] The result to validate
        # @raise [InvalidEvaluatorResultError] if result is invalid
        def validate_result!(result)
          unless result.is_a?(Hash)
            raise InvalidEvaluatorResultError, "Result must be a Hash, got #{result.class}"
          end

          # Validate label (required)
          unless result.key?(:label)
            raise InvalidEvaluatorResultError, "Result must include :label field"
          end

          valid_labels = ["good", "average", "bad"]
          unless valid_labels.include?(result[:label])
            raise InvalidEvaluatorResultError,
              "Label must be one of #{valid_labels.inspect}, got #{result[:label].inspect}"
          end

          # Validate score (optional but must be valid if present)
          if result.key?(:score)
            score = result[:score]
            unless score.is_a?(Numeric) && score >= 0.0 && score <= 1.0
              raise InvalidEvaluatorResultError, "Score must be between 0.0 and 1.0, got #{score}"
            end
          end

          # Require at least message or details for context
          unless result.key?(:message) || result.key?(:details)
            raise InvalidEvaluatorResultError, "Result must include at least :message or :details"
          end

          result
        end

        # Helper method to calculate label from score and thresholds
        # @param score [Float] Score between 0.0 and 1.0
        # @param threshold_good [Float] Minimum score for "good" label (default 0.8)
        # @param threshold_average [Float] Minimum score for "average" label (default 0.6)
        # @param good_threshold [Float] DEPRECATED: Use threshold_good instead
        # @param average_threshold [Float] DEPRECATED: Use threshold_average instead
        # @return [String] Label: "good", "average", or "bad"
        def calculate_label(score, threshold_good: nil, threshold_average: nil, good_threshold: nil, average_threshold: nil)
          # Support both new naming (threshold_good/threshold_average) and legacy naming (good_threshold/average_threshold)
          good_thresh = threshold_good || good_threshold || 0.8
          avg_thresh = threshold_average || average_threshold || 0.6

          return "good" if score >= good_thresh
          return "average" if score >= avg_thresh
          "bad"
        end

        # Subclasses must implement this method
        # @param field_context [FieldContext] Context with field value and result access
        # @param options [Hash] Additional options for the evaluator
        # @return [Hash] Result with :passed, :score (optional), :details (optional), :message (optional)
        def evaluate(field_context, **options)
          raise NotImplementedError, "Subclasses must implement evaluate(field_context, **options)"
        end
      end
    end
  end
end