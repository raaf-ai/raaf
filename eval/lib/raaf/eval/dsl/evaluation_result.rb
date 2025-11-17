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

        # Check if all fields passed (backward compatibility - checks for "good" or "average" labels)
        # @return [Boolean] true if all fields passed (or no fields evaluated)
        def passed?
          return true if @field_results.empty?

          @field_results.values.all? { |result|
            label = result[:label]
            label == "good" || label == "average"
          }
        end

        # Get result for a specific field
        # @param field_name [String] The field name
        # @return [Hash, nil] The field result or nil if not found
        def field_result(field_name)
          @field_results[field_name]
        end

        # Get list of fields that passed (good or average labels)
        # @return [Array<String>] Field names that passed
        def passed_fields
          @field_results.select { |_field, result|
            label = result[:label]
            label == "good" || label == "average"
          }.keys
        end

        # Get list of fields that failed (bad label)
        # @return [Array<String>] Field names that failed
        def failed_fields
          @field_results.select { |_field, result| result[:label] == "bad" }.keys
        end

        # Get list of fields with "good" label
        # @return [Array<String>] Field names rated as good
        def good_fields
          @field_results.select { |_field, result| result[:label] == "good" }.keys
        end

        # Get list of fields with "average" label
        # @return [Array<String>] Field names rated as average
        def average_fields
          @field_results.select { |_field, result| result[:label] == "average" }.keys
        end

        # Get list of fields with "bad" label
        # @return [Array<String>] Field names rated as bad
        def bad_fields
          @field_results.select { |_field, result| result[:label] == "bad" }.keys
        end

        # Calculate overall quality based on label distribution
        # @return [String] Overall quality: "good", "average", or "bad"
        def overall_quality
          return "bad" if @field_results.empty?

          good_count = good_fields.size
          average_count = average_fields.size
          bad_count = bad_fields.size
          total = @field_results.size

          # If majority are good (>50%), overall is good
          return "good" if good_count.to_f / total > 0.5

          # If no bad fields and some good fields, overall is average
          return "average" if bad_count.zero? && good_count.positive?

          # If majority are average or mixed, overall is average
          return "average" if (good_count + average_count).to_f / total >= 0.5

          # Otherwise, overall is bad
          "bad"
        end

        # Get configuration name
        # @return [String, nil] The configuration name if set
        def configuration_name
          # Handle both Symbol and Hash configuration formats
          @configuration.is_a?(Hash) ? @configuration[:name] : @configuration
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
            overall_quality: overall_quality,
            good_fields: good_fields.size,
            average_fields: average_fields.size,
            bad_fields: bad_fields.size,
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

        # Convert evaluation result to hash for serialization
        # @return [Hash] Complete result data
        def to_h
          {
            passed: passed?,
            field_results: @field_results,
            configuration: @configuration,
            metadata: @metadata,
            summary: summary
          }
        end
      end
    end
  end
end