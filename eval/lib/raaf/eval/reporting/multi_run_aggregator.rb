# frozen_string_literal: true

module RAAF
  module Eval
    module Reporting
      # Aggregates results from multiple evaluation runs for consistency analysis
      #
      # @example
      #   results = 3.times.map { agent.run }
      #   aggregator = MultiRunAggregator.new(results)
      #   aggregator.field_values(:individual_scores) # => [78, 79, 80]
      #
      class MultiRunAggregator
        attr_reader :runs

        # Initialize aggregator with evaluation results
        #
        # @param evaluation_results [Array<Hash>] Array of evaluation run results
        def initialize(evaluation_results = [])
          @runs = evaluation_results
        end

        # Add a run result to the aggregator
        #
        # @param result [Hash] Evaluation run result with :evaluation key
        def add_run(result)
          @runs << result
        end

        # Extract all values for a specific field across runs
        #
        # @param field_name [Symbol, String] Field name to extract
        # @return [Array] All values for the field across runs
        def field_values(field_name)
          @runs.flat_map do |run|
            evaluation = run[:evaluation]
            next [] unless evaluation

            field_result = evaluation.field_results[field_name.to_sym]
            next [] unless field_result

            # Extract values from field result details
            extract_field_values(field_result)
          end.compact
        end

        # Get performance metrics across all runs
        #
        # @return [Hash] Performance summary with latencies, tokens, success_rate
        def performance_summary
          latencies = @runs.map { |r| r[:latency_ms] }.compact
          tokens = @runs.map { |r| r.dig(:agent_result, :usage, :total_tokens) }.compact
          success_count = @runs.count do |r|
            evaluation = r[:evaluation]
            evaluation && evaluation.passed?
          end

          {
            latencies: latencies,
            tokens: tokens,
            success_rate: success_count.to_f / @runs.size,
            total_runs: @runs.size,
            successful_runs: success_count
          }
        end

        # Group field results by field name for analysis
        #
        # @return [Hash<Symbol, Array>] Field results grouped by field name
        def results_by_field
          first_evaluation = @runs.first&.[](:evaluation)
          field_names = first_evaluation&.field_results&.keys || []

          field_names.each_with_object({}) do |field_name, hash|
            hash[field_name] = @runs.map do |run|
              evaluation = run[:evaluation]
              evaluation&.field_results&.[](field_name)
            end.compact
          end
        end

        private

        # Extract actual values from field result
        #
        # @param field_result [Hash] Field evaluation result
        # @return [Array] Extracted values
        def extract_field_values(field_result)
          # Handle different field result structures
          if field_result[:current_value].is_a?(Array)
            field_result[:current_value]
          elsif field_result[:score]
            [field_result[:score]]
          elsif field_result[:details]&.is_a?(Hash)
            [field_result[:details][:current_value]].compact
          else
            []
          end
        end
      end
    end
  end
end
