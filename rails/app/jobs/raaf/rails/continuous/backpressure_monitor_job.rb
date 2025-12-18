# frozen_string_literal: true

module RAAF
  module Rails
    module Continuous
      ##
      # BackpressureMonitorJob monitors the evaluation queue and activates/deactivates
      # backpressure based on queue depth thresholds.
      #
      # When backpressure is active:
      # - New span evaluations are skipped (policy matcher returns empty)
      # - Existing queued items continue processing
      # - Prevents queue from growing unbounded during high load
      #
      # Recommended schedule: Every 1-2 minutes via cron or recurring job
      class BackpressureMonitorJob < RAAF::Rails::ApplicationJob
        queue_as :raaf_maintenance

        # Hysteresis thresholds to prevent rapid toggling
        # Activate backpressure when queue exceeds HIGH threshold
        # Deactivate when queue drops below LOW threshold
        HIGH_THRESHOLD_MULTIPLIER = 1.0
        LOW_THRESHOLD_MULTIPLIER = 0.7

        def perform
          config = RAAF::Eval::Continuous.configuration
          return unless config.enabled

          current_depth = calculate_queue_depth
          threshold = config.backpressure_threshold
          was_active = config.backpressure_active

          high_threshold = (threshold * HIGH_THRESHOLD_MULTIPLIER).to_i
          low_threshold = (threshold * LOW_THRESHOLD_MULTIPLIER).to_i

          if current_depth >= high_threshold && !was_active
            activate_backpressure!(current_depth, high_threshold)
          elsif current_depth <= low_threshold && was_active
            deactivate_backpressure!(current_depth, low_threshold)
          else
            log_status(current_depth, was_active)
          end

          # Store metrics for monitoring
          store_queue_metrics(current_depth, config.backpressure_active)
        end

        private

        ##
        # Calculate current queue depth (pending + running items)
        def calculate_queue_depth
          RAAF::Eval::Models::EvaluationQueueItem
            .where(status: %w[pending running])
            .count
        end

        ##
        # Activate backpressure mode
        def activate_backpressure!(current_depth, threshold)
          RAAF::Eval::Continuous.configuration.backpressure_active = true

          RAAF.logger.warn(
            "[ContinuousEval] BACKPRESSURE ACTIVATED: " \
            "Queue depth #{current_depth} exceeded threshold #{threshold}. " \
            "New evaluations will be skipped until queue drains."
          )
        end

        ##
        # Deactivate backpressure mode
        def deactivate_backpressure!(current_depth, threshold)
          RAAF::Eval::Continuous.configuration.backpressure_active = false

          RAAF.logger.info(
            "[ContinuousEval] BACKPRESSURE DEACTIVATED: " \
            "Queue depth #{current_depth} dropped below threshold #{threshold}. " \
            "Normal evaluation processing resumed."
          )
        end

        ##
        # Log current status without changes
        def log_status(current_depth, backpressure_active)
          status = backpressure_active ? "ACTIVE (draining)" : "inactive"
          RAAF.logger.debug(
            "[ContinuousEval] Backpressure monitor: depth=#{current_depth}, status=#{status}"
          )
        end

        ##
        # Store queue metrics for monitoring dashboard
        def store_queue_metrics(queue_depth, backpressure_active)
          # Calculate additional metrics
          pending_count = RAAF::Eval::Models::EvaluationQueueItem.pending.count
          running_count = RAAF::Eval::Models::EvaluationQueueItem.running.count
          failed_count = RAAF::Eval::Models::EvaluationQueueItem.failed.count

          # Calculate processing rate (completed in last 5 minutes)
          completed_recent = RAAF::Eval::Models::EvaluationQueueItem
            .completed
            .where("completed_at > ?", 5.minutes.ago)
            .count
          processing_rate = completed_recent / 5.0 # per minute

          # Store as EvaluationMetric if available
          if defined?(RAAF::Eval::Models::EvaluationMetric)
            RAAF::Eval::Models::EvaluationMetric.create!(
              name: "queue_health",
              value: queue_depth,
              metric_type: "gauge",
              tags: {
                pending: pending_count,
                running: running_count,
                failed: failed_count,
                processing_rate_per_minute: processing_rate.round(2),
                backpressure_active: backpressure_active
              },
              recorded_at: Time.current
            )
          end
        rescue StandardError => e
          # Don't fail the job if metrics storage fails
          RAAF.logger.debug "[ContinuousEval] Could not store queue metrics: #{e.message}"
        end
      end
    end
  end
end
