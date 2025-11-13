# frozen_string_literal: true

require_relative "eval/version"
require_relative "eval/configuration"
require_relative "eval/engine"
require_relative "eval/span_repository"
require_relative "eval/evaluation_run"
require_relative "eval/evaluation_result"
require_relative "eval/metrics"
require_relative "eval/dsl/evaluator_registry"
require_relative "eval/dsl/combination_logic"
require_relative "eval/dsl/field_evaluator_set"
require_relative "eval/dsl/builder"
require_relative "eval/dsl_engine/evaluator"
require_relative "eval/comparison/field_delta_calculator"
require_relative "eval/comparison/ranking_engine"
require_relative "eval/comparison/improvement_detector"
require_relative "eval/comparison/best_configuration_selector"
require_relative "eval/comparison/comparison_result"

module RAAF
  module Eval
    class Error < StandardError; end
    class ConfigurationError < Error; end
    class EvaluationError < Error; end
    class SpanNotFoundError < Error; end

    class << self
      ##
      # Define a new evaluator using DSL
      #
      # @yield DSL block for evaluator configuration
      # @return [Engine::Evaluator] Configured evaluator instance
      # @raise [ArgumentError] if no block given
      # @example
      #   evaluator = RAAF::Eval.define do
      #     select 'output', as: :output
      #     select 'usage.total_tokens', as: :tokens
      #
      #     evaluate_field :output do
      #       evaluate_with :semantic_similarity, threshold: 0.85
      #       combine_with :and
      #     end
      #
      #     on_progress do |event|
      #       puts "#{event.status}: #{event.progress}%"
      #     end
      #   end
      def define(&block)
        raise ArgumentError, "no block given" unless block_given?

        builder = DSL::Builder.new
        builder.instance_eval(&block)

        DslEngine::Evaluator.new(builder.build_definition)
      end
      ##
      # Returns the global configuration object
      #
      # @return [RAAF::Eval::Configuration]
      def configuration
        @configuration ||= Configuration.new
      end

      ##
      # Configures RAAF Eval
      #
      # @yield [Configuration] the configuration object
      # @example
      #   RAAF::Eval.configure do |config|
      #     config.database_url = "postgresql://localhost/raaf_eval"
      #   end
      def configure
        yield(configuration) if block_given?
      end

      ##
      # Finds a span by ID
      #
      # @param span_id [String] the span ID
      # @return [Hash] the span data
      # @raise [SpanNotFoundError] if span not found
      def find_span(span_id)
        SpanRepository.find(span_id)
      end

      ##
      # Finds the latest span for an agent
      #
      # @param agent [String] the agent name
      # @return [Hash] the span data
      # @raise [SpanNotFoundError] if no span found
      def latest_span(agent:)
        SpanRepository.latest(agent: agent)
      end

      ##
      # Queries spans with filters
      #
      # @param filters [Hash] filtering criteria
      # @return [Array<Hash>] matching spans
      def query_spans(**filters)
        SpanRepository.query(**filters)
      end

      ##
      # Registers a custom evaluator globally
      #
      # @param name [Symbol, String] The evaluator name
      # @param evaluator_class [Class] The evaluator class
      # @return [Class] The registered evaluator class
      # @raise [RAAF::Eval::DSL::EvaluatorRegistry::DuplicateEvaluatorError] if already registered
      # @raise [RAAF::Eval::DSL::EvaluatorRegistry::InvalidEvaluatorError] if evaluator invalid
      # @example
      #   RAAF::Eval.register_evaluator(:citation_grounding, CitationGroundingEvaluator)
      def register_evaluator(name, evaluator_class)
        DSL::EvaluatorRegistry.instance.register(name, evaluator_class)
      end

      ##
      # Gets a registered evaluator by name
      #
      # @param name [Symbol, String] The evaluator name
      # @return [Class] The evaluator class
      # @raise [RAAF::Eval::DSL::EvaluatorRegistry::UnregisteredEvaluatorError] if not found
      # @example
      #   evaluator_class = RAAF::Eval.get_evaluator(:citation_grounding)
      def get_evaluator(name)
        DSL::EvaluatorRegistry.instance.get(name)
      end

      ##
      # Returns all registered evaluator names
      #
      # @return [Array<Symbol>] Array of evaluator names
      # @example
      #   RAAF::Eval.registered_evaluators #=> [:semantic_similarity, :token_efficiency, ...]
      def registered_evaluators
        DSL::EvaluatorRegistry.instance.all_names
      end
    end
  end
end
