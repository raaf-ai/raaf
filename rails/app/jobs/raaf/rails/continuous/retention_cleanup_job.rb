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
        # Clean up old evaluation results
        def cleanup_evaluation_results(retention_period)
          cutoff = retention_period.ago

          deleted = RAAF::Eval::Models::ContinuousEvaluationResult
            .where("created_at < ?", cutoff)
            .delete_all

          RAAF.logger.info "[ContinuousEval] Deleted #{deleted} evaluation results older than #{retention_period.inspect}"
          deleted
        end

        ##
        # Clean up old queue items
        def cleanup_queue_items(retention)
          completed_cutoff = retention[:queue_items_completed].ago
          failed_cutoff = retention[:queue_items_failed].ago

          # Delete completed items older than threshold
          completed_deleted = RAAF::Eval::Models::EvaluationQueueItem
            .where(status: %w[completed partial])
            .where("completed_at < ?", completed_cutoff)
            .delete_all

          # Delete failed/cancelled items older than threshold
          failed_deleted = RAAF::Eval::Models::EvaluationQueueItem
            .where(status: %w[failed cancelled])
            .where("completed_at < ?", failed_cutoff)
            .delete_all

          total = completed_deleted + failed_deleted
          RAAF.logger.info "[ContinuousEval] Deleted #{total} queue items (#{completed_deleted} completed, #{failed_deleted} failed)"
          total
        end

        ##
        # Clean up old resolved alerts
        def cleanup_alerts(retention_period)
          cutoff = retention_period.ago

          deleted = RAAF::Eval::Models::EvaluationAlert
            .where(status: 'resolved')
            .where("resolved_at < ?", cutoff)
            .delete_all

          RAAF.logger.info "[ContinuousEval] Deleted #{deleted} resolved alerts older than #{retention_period.inspect}"
          deleted
        end

        ##
        # Clean up old metrics based on granularity
        def cleanup_metrics(retention)
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
