# frozen_string_literal: true

module RAAF
  module Eval
    ##
    # Wrapper for evaluation results with convenience methods
    #
    # This class provides a clean interface for accessing evaluation results
    # and comparing against baseline.
    class EvaluationResult
      attr_reader :run, :baseline

      ##
      # Creates a new evaluation result
      #
      # @param run [EvaluationRun] the evaluation run
      # @param baseline [Hash] baseline span data
      def initialize(run:, baseline:)
        @run = run
        @baseline = baseline
      end

      ##
      # Gets result for a configuration
      #
      # @param config_name [Symbol] configuration name
      # @return [Hash] the result
      def [](config_name)
        run.result_for(config_name)
      end

      ##
      # Gets all configuration results
      #
      # @return [Hash] results by configuration name
      def results
        run.results
      end

      ##
      # Gets baseline output
      #
      # @return [String] baseline output
      def baseline_output
        baseline[:output] || baseline.dig(:metadata, :output) || ""
      end

      ##
      # Gets baseline usage
      #
      # @return [Hash] baseline token usage
      def baseline_usage
        baseline[:usage] || baseline.dig(:metadata, :usage) || {}
      end

      ##
      # Gets baseline latency
      #
      # @return [Float] baseline latency in milliseconds
      def baseline_latency
        baseline[:latency_ms] || 0
      end

      ##
      # Checks if all configurations succeeded
      #
      # @return [Boolean]
      def all_success?
        run.results.values.all? { |r| r[:success] }
      end

      ##
      # Gets list of failed configurations
      #
      # @return [Array<Symbol>] failed configuration names
      def failures
        run.results.select { |_name, result| !result[:success] }.keys
      end
    end
  end
end
