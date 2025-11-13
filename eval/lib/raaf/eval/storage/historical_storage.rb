# frozen_string_literal: true

require_relative "evaluation_run"
require_relative "retention_policy"
require_relative "query_builder"

module RAAF
  module Eval
    module Storage
      # Main historical storage interface for evaluation results
      # Provides save, query, and cleanup operations
      class HistoricalStorage
        class << self
          # Save evaluation result to storage
          # @param evaluator_name [String] Name of the evaluator
          # @param configuration_name [String, Symbol] Configuration name
          # @param span_id [String] RAAF span ID
          # @param result [DSL::EvaluationResult] Evaluation result object
          # @param tags [Hash] Custom metadata tags
          # @param duration_ms [Float] Evaluation duration in milliseconds
          # @return [EvaluationRun] The saved run
          def save(evaluator_name:, configuration_name:, span_id:, result:, tags: {}, duration_ms: 0)
            EvaluationRun.create!(
              evaluator_name: evaluator_name,
              configuration_name: configuration_name.to_s,
              span_id: span_id,
              tags: tags,
              result_data: result.to_h,
              field_results: result.field_results,
              overall_passed: result.passed?,
              aggregate_score: result.average_score,
              duration_ms: duration_ms,
              created_at: Time.now
            )
          end

          # Query evaluation runs with filters
          # @param filters [Hash] Query filters
          # @option filters [String] :evaluator_name Filter by evaluator name
          # @option filters [String, Symbol] :configuration_name Filter by configuration
          # @option filters [Time] :start_date Filter by start date
          # @option filters [Time] :end_date Filter by end date
          # @option filters [Hash] :tags Filter by tags
          # @return [Array<EvaluationRun>] Matching runs sorted by date desc
          def query(**filters)
            QueryBuilder.new(filters).execute
          end

          # Get latest N evaluation runs
          # @param limit [Integer] Number of runs to return
          # @return [Array<EvaluationRun>] Most recent N runs
          def latest(limit: 10)
            EvaluationRun.order(created_at: :desc).limit(limit)
          end

          # Cleanup old results based on retention policy
          # @param retention_days [Integer, nil] Keep runs within this many days
          # @param retention_count [Integer, nil] Keep this many most recent runs
          # @return [Integer] Number of runs deleted
          def cleanup_retention(retention_days: nil, retention_count: nil)
            RetentionPolicy.new(retention_days, retention_count).cleanup
          end

          # Delete specific run by ID
          # @param run_id [Integer] The run ID to delete
          def delete(run_id)
            run = EvaluationRun.find(run_id)
            run.destroy if run
          end

          # Clear all evaluation runs (for testing)
          def clear_all
            EvaluationRun.destroy_all
          end
        end
      end
    end
  end
end
