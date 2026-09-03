# frozen_string_literal: true

module RAAF
  module Rails
    module Continuous
      ##
      # RetentionCleanupJob removes old evaluation data based on retention policies.
      # This prevents unbounded growth of evaluation results and queue items.
      #
      # Default Retention Periods:
      # - Evaluation results: 30 days
      # - Queue items (completed): 7 days
      # - Queue items (failed): 14 days
      # - Alerts (resolved): 30 days
      # - Metrics (hourly): 7 days
      # - Metrics (daily): 90 days
      #
      # Recommended schedule: Daily (off-peak hours)
      class RetentionCleanupJob < RAAF::Rails::ApplicationJob
        queue_as :raaf_maintenance

        # Configurable retention periods
        RETENTION_PERIODS = {
          evaluation_results: 30.days,
          queue_items_completed: 7.days,
          queue_items_failed: 14.days,
          alerts_resolved: 30.days,
          metrics_hourly: 7.days,
          metrics_daily: 90.days,
          metrics_weekly: 365.days
        }.freeze

        def perform(options = {})
          retention = RETENTION_PERIODS.merge(options.symbolize_keys)

          stats = {
            results_deleted: cleanup_evaluation_results(retention[:evaluation_results]),
            queue_items_deleted: cleanup_queue_items(retention),
            alerts_deleted: cleanup_alerts(retention[:alerts_resolved]),
            metrics_deleted: cleanup_metrics(retention)
          }

          log_cleanup_results(stats)
          stats
        end

        private

        ##
        # Clean up old evaluation results, honouring each policy's own
        # retention_days before falling back to the job-wide default.
        #
        # A policy declares how long its results are worth keeping, and that
        # declaration is the reviewable one: it sits beside the sampling rate in
        # the policy registry, where the person choosing to evaluate an agent
        # also chooses how long to remember the answers. Deleting everything on
        # one hard-coded period silently overrode it — a policy asking for 90
        # days lost its results at 30.
        #
        # Results whose policy was deleted, or which never had one, fall back to
        # the default period. Nothing is immortal.
        #
        # @param default_period [ActiveSupport::Duration] fallback retention
        # @return [Integer] rows deleted
        def cleanup_evaluation_results(default_period)
          deleted = each_policy_retention do |policy, cutoff|
            RAAF::Eval::Models::ContinuousEvaluationResult
              .where(evaluation_policy_id: policy.id)
              .where("created_at < ?", cutoff)
              .delete_all
          end

          deleted += RAAF::Eval::Models::ContinuousEvaluationResult
            .where(evaluation_policy_id: [ nil ] + policies_without_retention_ids)
            .where("created_at < ?", default_period.ago)
            .delete_all

          RAAF.logger.info "[ContinuousEval] Deleted #{deleted} evaluation results (per-policy retention_days, default #{default_period.inspect})"
          deleted
        end

        ##
        # Clean up old queue items. A finished queue item is the record that an
        # evaluation happened at all, so it lives as long as the results it
        # produced — same retention_days, same fallback. Failed and cancelled
        # items keep their own shorter default, since nothing downstream reads
        # them once somebody has looked.
        def cleanup_queue_items(retention)
          finished_deleted = each_policy_retention do |policy, cutoff|
            RAAF::Eval::Models::EvaluationQueueItem
              .where(evaluation_policy_id: policy.id, status: %w[completed partial])
              .where("completed_at < ?", cutoff)
              .delete_all
          end

          finished_deleted += RAAF::Eval::Models::EvaluationQueueItem
            .where(evaluation_policy_id: [ nil ] + policies_without_retention_ids, status: %w[completed partial])
            .where("completed_at < ?", retention[:queue_items_completed].ago)
            .delete_all

          failed_deleted = RAAF::Eval::Models::EvaluationQueueItem
            .where(status: %w[failed cancelled])
            .where("completed_at < ?", retention[:queue_items_failed].ago)
            .delete_all

          total = finished_deleted + failed_deleted
          RAAF.logger.info "[ContinuousEval] Deleted #{total} queue items (#{finished_deleted} finished, #{failed_deleted} failed)"
          total
        end

        ##
        # Yield each policy that declares a retention_days along with its cutoff,
        # summing what the block deletes.
        #
        # @yieldparam policy [RAAF::Eval::Models::EvaluationPolicy]
        # @yieldparam cutoff [Time]
        # @return [Integer] rows deleted across all policies
        def each_policy_retention
          policies_with_retention.inject(0) do |deleted, policy|
            deleted + yield(policy, policy.retention_days.days.ago)
          end
        end

        def policies_with_retention
          @policies_with_retention ||= RAAF::Eval::Models::EvaluationPolicy
            .where.not(retention_days: nil).to_a
        end

        def policies_without_retention_ids
          @policies_without_retention_ids ||= RAAF::Eval::Models::EvaluationPolicy
            .where(retention_days: nil).pluck(:id)
        end

        ##
        # Clean up old resolved alerts.
        #
        # Skipped where the table was never migrated. The alerts table is
        # optional — an application can adopt continuous evaluation without
        # adopting alerting, and several have — and an unguarded delete_all
        # there raised StatementInvalid, which ApplicationJob's blanket
        # retry_on swallowed. The visible effect was that results and queue
        # items were never swept at all, because this ran before them and took
        # the whole job down. cleanup_metrics already had this guard.
        def cleanup_alerts(retention_period)
          return 0 unless table_present?(RAAF::Eval::Models::EvaluationAlert)

          cutoff = retention_period.ago

          deleted = RAAF::Eval::Models::EvaluationAlert
            .where(status: 'resolved')
            .where("resolved_at < ?", cutoff)
            .delete_all

          RAAF.logger.info "[ContinuousEval] Deleted #{deleted} resolved alerts older than #{retention_period.inspect}"
          deleted
        rescue StandardError => e
          RAAF.logger.debug "[ContinuousEval] Skipped alert cleanup: #{e.message}"
          0
        end

        ##
        # Clean up old metrics based on granularity
        def cleanup_metrics(retention)
          return 0 unless table_present?(RAAF::Eval::Models::EvaluationMetric)

          total_deleted = 0

          # Clean hourly metrics
          hourly_cutoff = retention[:metrics_hourly].ago
          hourly_deleted = RAAF::Eval::Models::EvaluationMetric
            .where(period_type: 'hourly')
            .where("period_start < ?", hourly_cutoff)
            .delete_all
          total_deleted += hourly_deleted

          # Clean daily metrics
          daily_cutoff = retention[:metrics_daily].ago
          daily_deleted = RAAF::Eval::Models::EvaluationMetric
            .where(period_type: 'daily')
            .where("period_start < ?", daily_cutoff)
            .delete_all
          total_deleted += daily_deleted

          # Clean weekly metrics
          weekly_cutoff = retention[:metrics_weekly].ago
          weekly_deleted = RAAF::Eval::Models::EvaluationMetric
            .where(period_type: 'weekly')
            .where("period_start < ?", weekly_cutoff)
            .delete_all
          total_deleted += weekly_deleted

          RAAF.logger.info "[ContinuousEval] Deleted #{total_deleted} metrics (hourly: #{hourly_deleted}, daily: #{daily_deleted}, weekly: #{weekly_deleted})"
          total_deleted
        rescue StandardError => e
          # Don't fail if metrics table doesn't exist yet
          RAAF.logger.debug "[ContinuousEval] Skipped metrics cleanup: #{e.message}"
          0
        end

        ##
        # Whether a table this sweep touches was ever migrated.
        #
        # Asked before the query rather than rescued after it: a statement that
        # fails inside a transaction aborts the whole transaction, so every
        # later delete in the same sweep fails too with
        # "current transaction is aborted". Rescuing the first failure hides its
        # cause and keeps none of its consequences.
        #
        # @param model [Class] an ActiveRecord model
        # @return [Boolean]
        def table_present?(model)
          @table_present ||= {}
          return @table_present[model] if @table_present.key?(model)

          @table_present[model] = model.table_exists?
        rescue StandardError
          false
        end

        ##
        # Log overall cleanup results
        def log_cleanup_results(stats)
          total = stats.values.sum
          RAAF.logger.info(
            "[ContinuousEval] Retention cleanup complete: " \
            "#{total} total records deleted " \
            "(results: #{stats[:results_deleted]}, " \
            "queue: #{stats[:queue_items_deleted]}, " \
            "alerts: #{stats[:alerts_deleted]}, " \
            "metrics: #{stats[:metrics_deleted]})"
          )
        end
      end
    end
  end
end
