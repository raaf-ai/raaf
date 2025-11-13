# frozen_string_literal: true

module RAAF
  module Eval
    module DSL
      # Stores and manages evaluation results across configurations
      class EvaluationResult
        attr_reader :field_results, :configuration, :metadata

        # Initialize evaluation result
        # @param field_results [Hash] Results for each evaluated field
        # @param configuration [Hash] Configuration used for this evaluation
        # @param metadata [Hash] Execution metadata
        def initialize(field_results: {}, configuration: nil, metadata: nil)
          @field_results = field_results
          @configuration = configuration || {}
          @metadata = metadata || {}
        end

        # Check if all fields passed
        # @return [Boolean] true if all fields passed (or no fields evaluated)
        def passed?
          return true if @field_results.empty?

          @field_results.values.all? { |result| result[:passed] }
        end

        # Get result for a specific field
        # @param field_name [String] The field name
        # @return [Hash, nil] The field result or nil if not found
        def field_result(field_name)
          @field_results[field_name]
        end

        # Get list of fields that passed
        # @return [Array<String>] Field names that passed
        def passed_fields
          @field_results.select { |_field, result| result[:passed] }.keys
        end

        # Get list of fields that failed
        # @return [Array<String>] Field names that failed
        def failed_fields
          @field_results.reject { |_field, result| result[:passed] }.keys
        end

        # Get configuration name
        # @return [String, nil] The configuration name if set
        def configuration_name
          @configuration[:name]
        end

        # Get execution time in milliseconds
        # @return [Float, nil] The execution time or nil if not recorded
        def execution_time_ms
          @metadata[:execution_time_ms]
        end

        # Get evaluation timestamp
        # @return [String, nil] The timestamp or nil if not recorded
        def timestamp
          @metadata[:timestamp]
        end

        # Get evaluator name
        # @return [String, nil] The evaluator name or nil if not recorded
        def evaluator_name
          @metadata[:evaluator_name]
        end

        # Calculate average score across all fields
        # @return [Float, nil] The average score or nil if no scores available
        def average_score
          scores = @field_results.values.filter_map { |result| result[:score] }
          return nil if scores.empty?

          scores.sum.to_f / scores.size
        end

        # Get minimum score across all fields
        # @return [Float, nil] The minimum score or nil if no scores available
        def min_score
          scores = @field_results.values.filter_map { |result| result[:score] }
          scores.min
        end

        # Get maximum score across all fields
        # @return [Float, nil] The maximum score or nil if no scores available
        def max_score
          scores = @field_results.values.filter_map { |result| result[:score] }
          scores.max
        end

        # Generate a summary of the evaluation result
        # @return [Hash] Summary information
        def summary
          {
            passed: passed?,
            passed_fields: passed_fields.size,
            failed_fields: failed_fields.size,
            total_fields: @field_results.size,
            average_score: average_score,
            min_score: min_score,
            max_score: max_score,
            configuration_name: configuration_name,
            execution_time_ms: execution_time_ms,
            timestamp: timestamp,
            evaluator_name: evaluator_name
          }
        end
      end
    end
  end
end