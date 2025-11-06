# frozen_string_literal: true

require_relative "eval/version"
require_relative "eval/configuration"
require_relative "eval/engine"
require_relative "eval/span_repository"
require_relative "eval/evaluation_run"
require_relative "eval/evaluation_result"
require_relative "eval/metrics"

module RAAF
  module Eval
    class Error < StandardError; end
    class ConfigurationError < Error; end
    class EvaluationError < Error; end
    class SpanNotFoundError < Error; end

    class << self
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
    end
  end
end
