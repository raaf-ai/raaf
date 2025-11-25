# frozen_string_literal: true

require_relative "evaluation_run"
require_relative "retention_policy"
require_relative "query_builder"

module RAAF
  module Eval
    module Storage
      # @deprecated HistoricalStorage is deprecated and will be removed in a future version.
      #   Use the new database-driven continuous evaluation system instead:
      #   - Use EvaluationPolicy for configuration
      #   - Use ContinuousEvaluationResult for results storage
      #   - See docs/CONTINUOUS_EVAL_MIGRATION.md for migration guide
      #
      # Main historical storage interface for evaluation results
      # Provides save, query, and cleanup operations
      #
      # This class is maintained for backward compatibility during the transition
      # to the new continuous evaluation system. All methods emit deprecation warnings.
      class HistoricalStorage
        DEPRECATION_MESSAGE = <<~MSG.freeze
          [DEPRECATION WARNING] RAAF::Eval::Storage::HistoricalStorage is deprecated.

          The DSL-based history configuration has been replaced with database-driven
          continuous evaluation policies. Please migrate to the new system:

          1. Create EvaluationPolicy records in the database via the RAAF dashboard UI
          2. Results are automatically stored in raaf_continuous_evaluation_results
          3. Use RAAF::Eval::Models::Continuous::ContinuousEvaluationResult for queries

          See docs/CONTINUOUS_EVAL_MIGRATION.md for complete migration instructions.

          This class will be removed in RAAF Eval 3.0.
        MSG

        class << self
          # Emit deprecation warning (only once per method per process)
          # @param method_name [Symbol] The method being called
          def emit_deprecation_warning(method_name)
            @warned_methods ||= Set.new
            return if @warned_methods.include?(method_name)

            @warned_methods.add(method_name)
            warn "#{DEPRECATION_MESSAGE}\nCalled from: #{caller(2..2).first}"
          end

          # Reset deprecation warnings (for testing)
          def reset_deprecation_warnings!
            @warned_methods = Set.new
          end

          # @deprecated Use ContinuousEvaluationResult.create! instead
          # Save evaluation result to storage
          # @param evaluator_name [String] Name of the evaluator
          # @param configuration_name [String, Symbol] Configuration name
          # @param span_id [String] RAAF span ID
          # @param result [DSL::EvaluationResult] Evaluation result object
          # @param tags [Hash] Custom metadata tags
          # @param duration_ms [Float] Evaluation duration in milliseconds
          # @return [EvaluationRun] The saved run
          def save(evaluator_name:, configuration_name:, span_id:, result:, tags: {}, duration_ms: 0)
            emit_deprecation_warning(:save)

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

          # @deprecated Use ContinuousEvaluationResult.where(...) instead
          # Query evaluation runs with filters
          # @param filters [Hash] Query filters
          # @option filters [String] :evaluator_name Filter by evaluator name
          # @option filters [String, Symbol] :configuration_name Filter by configuration
          # @option filters [Time] :start_date Filter by start date
          # @option filters [Time] :end_date Filter by end date
          # @option filters [Hash] :tags Filter by tags
          # @return [Array<EvaluationRun>] Matching runs sorted by date desc
          def query(**filters)
            emit_deprecation_warning(:query)
            QueryBuilder.new(filters).execute
          end

          # @deprecated Use ContinuousEvaluationResult.order(created_at: :desc).limit(N) instead
          # Get latest N evaluation runs
          # @param limit [Integer] Number of runs to return
          # @return [Array<EvaluationRun>] Most recent N runs
          def latest(limit: 10)
            emit_deprecation_warning(:latest)
            EvaluationRun.order(created_at: :desc).limit(limit)
          end

          # @deprecated Retention is now managed via EvaluationPolicy.retention_days
          # Cleanup old results based on retention policy
          # @param retention_days [Integer, nil] Keep runs within this many days
          # @param retention_count [Integer, nil] Keep this many most recent runs
          # @return [Integer] Number of runs deleted
          def cleanup_retention(retention_days: nil, retention_count: nil)
            emit_deprecation_warning(:cleanup_retention)
            RetentionPolicy.new(retention_days, retention_count).cleanup
          end

          # @deprecated Use ContinuousEvaluationResult.find(id).destroy instead
          # Delete specific run by ID
          # @param run_id [Integer] The run ID to delete
          def delete(run_id)
            emit_deprecation_warning(:delete)
            run = EvaluationRun.find(run_id)
            run.destroy if run
          end

          # @deprecated For testing only - use database cleanup instead
          # Clear all evaluation runs (for testing)
          def clear_all
            emit_deprecation_warning(:clear_all)
            EvaluationRun.destroy_all
          end
        end
      end
    end
  end
end
