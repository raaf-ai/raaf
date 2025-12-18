# frozen_string_literal: true

module RAAF
  module Eval
    # Base error class for RAAF Eval
    class Error < StandardError; end

    # Error raised when span serialization fails
    class SerializationError < Error; end

    # Error raised when span deserialization fails
    class DeserializationError < Error; end

    # Error raised when evaluation execution fails
    class ExecutionError < Error; end

    # Error raised when metric calculation fails
    class MetricError < Error; end

    # Error raised when configuration is invalid
    class ConfigurationError < Error; end

    # Error raised when database operations fail
    class DatabaseError < Error; end

    # Error raised when an invalid state transition is attempted
    class InvalidStateTransition < Error; end

    # Error raised during evaluation processing
    class EvaluationError < Error; end

    # Error raised when deprecated DSL features are used
    # @since 2.0.0
    class DeprecatedDSLError < Error
      def initialize(feature_name, migration_guide_url = nil)
        message = "The '#{feature_name}' DSL feature has been removed. " \
                  "Evaluation configuration is now managed via database-backed policies. " \
                  "Use the RAAF dashboard UI or EvaluationPolicy model to configure evaluations."

        if migration_guide_url
          message += " See migration guide: #{migration_guide_url}"
        else
          message += " See docs/CONTINUOUS_EVAL_MIGRATION.md for migration instructions."
        end

        super(message)
      end
    end

    # Error raised when trying to use unknown evaluator
    class UnknownEvaluatorError < Error; end

    # Error raised when API rate limit is exceeded
    class RateLimitError < Error; end

    # Error raised when a span cannot be found
    class SpanNotFoundError < Error; end
  end
end
