# frozen_string_literal: true

module RAAF
  module Eval
    module RSpec
      ##
      # Evaluation runner for RSpec integration
      #
      # This class is responsible for executing evaluations defined via DSL
      # and integrating with RSpec's lifecycle.
      class EvaluationRunner
        attr_reader :definition, :result

        ##
        # Creates a new evaluation runner
        #
        # @param definition [Hash] evaluation definition from DSL
        def initialize(definition)
          @definition = definition
          @result = nil
          @executed = false
        end

        ##
        # Executes the evaluation
        #
        # @return [EvaluationResult] the evaluation result
        def execute
          return @result if @executed

          span = resolve_span(definition[:span_source])
          configurations = definition[:configurations]
          async = definition[:run_async]

          run = EvaluationRun.new(
            span: span,
            configurations: configurations
          )

          run.execute(async: async)

          @result = EvaluationResult.new(run: run, baseline: span)
          @executed = true
          @result
        rescue StandardError => e
          raise EvaluationError, "Evaluation failed: #{e.message}"
        end

        ##
        # Checks if evaluation has been executed
        #
        # @return [Boolean]
        def executed?
          @executed
        end

        private

        def resolve_span(span_source)
          case span_source
          when Hash
            span_source
          when String
            RAAF::Eval.find_span(span_source)
          when Proc
            resolved = span_source.call
            resolve_span(resolved)
          when NilClass
            raise EvaluationError, "Span source not defined in evaluation block"
          else
            raise EvaluationError, "Invalid span source type: #{span_source.class}"
          end
        end
      end
    end
  end
end
