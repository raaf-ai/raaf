# frozen_string_literal: true

module RAAF
  module Eval
    module RSpec
      ##
      # Helper methods for RSpec evaluation tests
      #
      # These methods are available in RSpec examples when the module is included.
      module Helpers
        ##
        # Evaluates a span with optional configuration overrides
        #
        # @param span_id_or_object [String, Hash, RAAF::RunResult] span ID, span object, or RunResult
        # @param span [Hash] span object (keyword argument alternative)
        # @param agent [RAAF::Agent, nil] optional agent for RunResult conversion
        # @return [SpanEvaluator] evaluator for method chaining
        #
        # @example Evaluate by ID
        #   evaluate_span("span_123")
        #     .with_configuration(temperature: 0.9)
        #     .run
        #
        # @example Evaluate with span object
        #   evaluate_span(span: my_span)
        #     .with_configuration(model: "gpt-4o")
        #     .run
        #
        # @example Evaluate RunResult
        #   result = runner.run("What is 2+2?")
        #   evaluate_span(result, agent: agent)
        #     .with_configuration(temperature: 0.9)
        #     .run
        def evaluate_span(span_id_or_object = nil, span: nil, agent: nil)
          span_data = resolve_span(span_id_or_object, span, agent)
          SpanEvaluator.new(span_data)
        end

        ##
        # Evaluates the latest span for an agent
        #
        # @param agent [String] agent name
        # @return [SpanEvaluator] evaluator for method chaining
        #
        # @example
        #   evaluate_latest_span(agent: "MyAgent")
        #     .with_configuration(model: "claude-3-5-sonnet")
        #     .run
        def evaluate_latest_span(agent:)
          span_data = RAAF::Eval.latest_span(agent: agent)
          SpanEvaluator.new(span_data)
        end

        ##
        # Finds a span by ID
        #
        # @param span_id [String] the span ID
        # @return [Hash] the span data
        def find_span(span_id)
          RAAF::Eval.find_span(span_id)
        end

        ##
        # Queries spans with filters
        #
        # @param filters [Hash] filtering criteria
        # @return [Array<Hash>] matching spans
        def query_spans(**filters)
          RAAF::Eval.query_spans(**filters)
        end

        ##
        # Gets the latest span for an agent
        #
        # @param agent [String] agent name
        # @return [Hash] the span data
        def latest_span_for(agent)
          RAAF::Eval.latest_span(agent: agent)
        end

        ##
        # Evaluates a RunResult with optional configuration overrides
        #
        # @param run_result [RAAF::RunResult] result from runner.run()
        # @param agent [RAAF::Agent, nil] optional agent for config extraction
        # @return [SpanEvaluator] evaluator for method chaining
        #
        # @example Evaluate RunResult
        #   result = runner.run("What is 2+2?")
        #   evaluate_run_result(result, agent: agent)
        #     .with_configuration(temperature: 0.9)
        #     .run
        #
        # @example Compare configurations
        #   result = runner.run("Explain AI")
        #   evaluate_run_result(result, agent: agent)
        #     .with_configurations([
        #       { name: :low_temp, temperature: 0.1 },
        #       { name: :high_temp, temperature: 0.9 }
        #     ])
        #     .run
        def evaluate_run_result(run_result, agent: nil)
          span_data = RunResultAdapter.to_span(run_result, agent: agent)
          SpanEvaluator.new(span_data)
        end

        private

        def resolve_span(span_id_or_object, span_kwarg, agent)
          span_data = span_kwarg || span_id_or_object

          if span_data.is_a?(String)
            RAAF::Eval.find_span(span_data)
          elsif span_data.is_a?(RAAF::RunResult)
            # Auto-convert RunResult to span format
            RunResultAdapter.to_span(span_data, agent: agent)
          elsif span_data.is_a?(Hash)
            span_data
          else
            raise ArgumentError, "Expected span ID (String), RunResult, or span Hash, got #{span_data.class}"
          end
        end
      end

      ##
      # Span evaluator for method chaining
      #
      # This class provides a fluent interface for configuring and running evaluations.
      class SpanEvaluator
        attr_reader :span, :configurations

        def initialize(span)
          @span = span
          @configurations = {}
        end

        ##
        # Adds a configuration to evaluate
        #
        # @param config_hash [Hash] configuration settings
        # @param name [String, Symbol] optional configuration name
        # @return [SpanEvaluator] self for chaining
        def with_configuration(config_hash, name: :default)
          @configurations[name.to_sym] = config_hash
          self
        end

        ##
        # Adds multiple configurations to evaluate
        #
        # @param configs [Array<Hash>, Hash] array of configs or hash of named configs
        # @return [SpanEvaluator] self for chaining
        def with_configurations(configs)
          if configs.is_a?(Array)
            configs.each_with_index do |config, index|
              name = config[:name] || "config_#{index}".to_sym
              @configurations[name.to_sym] = config
            end
          elsif configs.is_a?(Hash)
            @configurations.merge!(configs)
          else
            raise ArgumentError, "Expected Array or Hash, got #{configs.class}"
          end
          self
        end

        ##
        # Runs the evaluation
        #
        # @param async [Boolean] whether to run asynchronously
        # @return [EvaluationResult] the evaluation result
        def run(async: false)
          run_object = EvaluationRun.new(
            span: span,
            configurations: configurations
          )

          run_object.execute(async: async)

          EvaluationResult.new(run: run_object, baseline: span)
        end
      end
    end
  end
end
