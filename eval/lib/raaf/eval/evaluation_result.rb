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
        baseline[:latency_ms] || baseline.dig(:metadata, :latency_ms) || 0
      end

      ##
      # Gets the output produced by the evaluation itself
      #
      # Matchers assert on what the evaluated configuration returned, not on the span it
      # started from. With several configurations the first one stands in for the run;
      # matchers that need every configuration walk {#results} themselves. A run that has
      # produced nothing yet reports the baseline; a configuration that ran and returned
      # nothing reports nothing, so a failed evaluation does not read as the baseline.
      #
      # @return [String] evaluation output
      def evaluation_output
        return baseline_output unless first_result

        first_result[:output] || ""
      end

      ##
      # Gets the token usage of the evaluation itself
      #
      # @return [Hash] evaluation token usage
      def evaluation_usage
        return baseline_usage unless first_result

        first_result[:usage] || {}
      end

      ##
      # Gets the latency of the evaluation itself
      #
      # @return [Float] evaluation latency in milliseconds
      def evaluation_latency
        return baseline_latency unless first_result

        first_result[:latency_ms] || 0
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

      private

      ##
      # The result standing in for the run when a matcher asks for a single value
      #
      # @return [Hash, nil]
      def first_result
        run.results.values.first
      end
    end
  end
end
