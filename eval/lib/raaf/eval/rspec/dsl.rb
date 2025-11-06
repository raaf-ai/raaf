# frozen_string_literal: true

module RAAF
  module Eval
    module RSpec
      ##
      # DSL for defining evaluation scenarios in RSpec
      #
      # This module provides a declarative syntax for defining evaluations
      # within RSpec describe/context blocks.
      module DSL
        ##
        # Class methods added to RSpec example groups
        module ClassMethods
          ##
          # Defines an evaluation scenario
          #
          # @yield block containing evaluation configuration
          #
          # @example
          #   evaluation do
          #     span baseline_span
          #     configuration :gpt4, model: "gpt-4o"
          #     configuration :claude, model: "claude-3-5-sonnet"
          #     run_async true
          #   end
          def evaluation(&block)
            builder = EvaluationBuilder.new
            builder.instance_eval(&block)

            # Store evaluation definition for use in examples
            metadata[:evaluation_definition] = builder.build

            # Create a let variable for the evaluation result
            let(:evaluation) do
              definition = self.class.metadata[:evaluation_definition]
              runner = EvaluationRunner.new(definition)
              runner.execute
            end

            # Create individual configuration accessors
            builder.configuration_names.each do |name|
              let(:"evaluation_#{name}") do
                evaluation[name]
              end
            end
          end
        end

        ##
        # Instance methods added to RSpec examples
        module InstanceMethods
          ##
          # Runs an evaluation manually (when not using declarative DSL)
          #
          # @param span [Hash] the span to evaluate
          # @param configurations [Hash] configurations to test
          # @param async [Boolean] whether to run asynchronously
          # @return [EvaluationResult] the evaluation result
          def run_evaluation(span:, configurations:, async: false)
            run_object = EvaluationRun.new(
              span: span,
              configurations: configurations
            )

            run_object.execute(async: async)

            EvaluationResult.new(run: run_object, baseline: span)
          end

          ##
          # Gets the baseline result from the evaluation
          #
          # @return [Hash] baseline span data
          def baseline_result
            return nil unless defined?(evaluation)

            evaluation.baseline
          end

          ##
          # Gets all configuration results
          #
          # @return [Hash] results by configuration name
          def configuration_results
            return {} unless defined?(evaluation)

            evaluation.results
          end

          ##
          # Gets the evaluation result (alias for clarity)
          #
          # @return [EvaluationResult] the evaluation result
          def evaluation_result
            return nil unless defined?(evaluation)

            evaluation
          end
        end

        ##
        # Builder for evaluation definitions
        #
        # This class provides the DSL methods available within evaluation blocks.
        class EvaluationBuilder
          attr_reader :configuration_names

          def initialize
            @span_source = nil
            @configurations = {}
            @run_async = false
            @configuration_names = []
          end

          ##
          # Sets the span to evaluate
          #
          # @param span_source [Hash, String, Proc] span data, ID, or lazy evaluator
          def span(span_source = nil, &block)
            @span_source = block || span_source
          end

          ##
          # Defines a configuration to evaluate
          #
          # @param name [Symbol] configuration name
          # @param config [Hash] configuration settings
          def configuration(name, **config)
            @configurations[name.to_sym] = config
            @configuration_names << name.to_sym
          end

          ##
          # Sets whether to run asynchronously
          #
          # @param value [Boolean] async flag
          def run_async(value)
            @run_async = value
          end

          ##
          # Builds the evaluation definition
          #
          # @return [Hash] evaluation definition
          def build
            {
              span_source: @span_source,
              configurations: @configurations,
              run_async: @run_async
            }
          end
        end
      end
    end
  end
end
