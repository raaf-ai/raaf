# frozen_string_literal: true

module RAAF
  module Rails
    module Continuous
      ##
      # StaleJobCleanupJob detects and resets stuck evaluation jobs.
      #
      # Jobs can get stuck in 'running' status if:
      # - Worker process crashes mid-execution
      # - Network timeout not handled properly
      # - Database connection issues
      #
      # This job runs periodically to find stale jobs (running longer than threshold)
      # and either reschedules them for retry or marks them as failed.
      #
      # Recommended schedule: Every 5 minutes via cron or recurring job
      class StaleJobCleanupJob < RAAF::Rails::ApplicationJob
        queue_as :raaf_maintenance

        # Jobs running longer than this are considered stale
        STALE_THRESHOLD = 30.minutes

        def perform
          stale_items = find_stale_items
          return if stale_items.empty?

          RAAF.logger.info "[ContinuousEval] Found #{stale_items.count} stale jobs to process"

          stale_items.find_each do |item|
            process_stale_item(item)
          end
        end

        private

        def find_stale_items
          RAAF::Eval::Models::EvaluationQueueItem
            .where(status: "running")
            .where("started_at < ?", STALE_THRESHOLD.ago)
        end

        def process_stale_item(item)
          if item.attempts < item.max_attempts
            # Reschedule for retry
            item.update!(
              status: "pending",
              next_retry_at: Time.current,
              error_message: "Reset: job exceeded #{STALE_THRESHOLD.inspect} threshold after #{item.attempts} attempts"
            )
            RAAF.logger.warn "[ContinuousEval] Reset stale job #{item.id} for retry (attempt #{item.attempts + 1}/#{item.max_attempts})"
          else
            # Max retries exceeded, mark as failed
            item.update!(
              status: "failed",
              completed_at: Time.current,
              error_message: "Failed: exceeded #{STALE_THRESHOLD.inspect} threshold after #{item.max_attempts} attempts"
            )
            RAAF.logger.error "[ContinuousEval] Marked stale job #{item.id} as failed (max retries exceeded)"
          end
        rescue => e
          RAAF.logger.error "[ContinuousEval] Error processing stale item #{item.id}: #{e.message}"
        end
      end
    end
  end
end
