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

          unless result.key?(:passed) && [true, false].include?(result[:passed])
            raise InvalidEvaluatorResultError, "Result must include :passed with boolean value"
          end

          if result.key?(:score)
            score = result[:score]
            unless score.is_a?(Numeric) && score >= 0.0 && score <= 1.0
              raise InvalidEvaluatorResultError, "Score must be between 0.0 and 1.0, got #{score}"
            end
          end

          unless result.key?(:message) || result.key?(:details)
            raise InvalidEvaluatorResultError, "Result must include at least :message or :details"
          end

          result
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