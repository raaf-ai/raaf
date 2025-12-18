# frozen_string_literal: true

module RAAF
  module Rails
    module Continuous
      ##
      # HealthController provides health check and system status endpoints
      # for the continuous evaluation system.
      #
      # Endpoints:
      # - GET /raaf/continuous/health - JSON health check
      # - GET /raaf/continuous/health/dashboard - HTML dashboard
      class HealthController < BaseController
        # JSON health check endpoint
        # Returns system health status and metrics
        #
        # GET /raaf/continuous/health
        def show
          health_data = gather_health_data

          status_code = determine_status_code(health_data)

          respond_to do |format|
            format.json { render json: health_data, status: status_code }
            format.html { redirect_to dashboard_continuous_health_path }
          end
        end

        # HTML dashboard showing system health
        #
        # GET /raaf/continuous/health/dashboard
        def dashboard
          @health_data = gather_health_data
          @alerts = gather_recent_alerts
          @config = gather_configuration

          render_phlex RAAF::Rails::Continuous::SystemHealthPanel.new(
            health_data: @health_data,
            alerts: @alerts,
            config: @config
          )
        end

        private

        def gather_health_data
          queue_pending = RAAF::Eval::Models::EvaluationQueueItem.pending.count
          queue_running = RAAF::Eval::Models::EvaluationQueueItem.running.count
          queue_completed_1h = RAAF::Eval::Models::EvaluationQueueItem
            .completed
            .where("completed_at > ?", 1.hour.ago)
            .count
          queue_failed_1h = RAAF::Eval::Models::EvaluationQueueItem
            .failed
            .where("completed_at > ?", 1.hour.ago)
            .count

          # Calculate processing rate (per minute, last 5 minutes)
          completed_5m = RAAF::Eval::Models::EvaluationQueueItem
            .completed
            .where("completed_at > ?", 5.minutes.ago)
            .count
          processing_rate = completed_5m / 5.0

          config = RAAF::Eval::Continuous.configuration

          {
            status: determine_overall_status(config, queue_pending, queue_running),
            timestamp: Time.current.iso8601,
            enabled: config.enabled,
            hook_enabled: config.hook_enabled,
            backpressure_active: config.backpressure_active,
            backpressure_threshold: config.backpressure_threshold,
            queue_depth: queue_pending + queue_running,
            pending_count: queue_pending,
            running_count: queue_running,
            completed_1h: queue_completed_1h,
            failed_1h: queue_failed_1h,
            processing_rate: processing_rate.round(2),
            active_alerts: count_active_alerts,
            critical_alerts: count_critical_alerts
          }
        end

        def gather_recent_alerts
          RAAF::Eval::Models::EvaluationAlert
            .unresolved
            .recent
            .limit(10)
            .map(&:summary)
        rescue StandardError => e
          RAAF.logger.debug "[ContinuousEval] Could not load alerts: #{e.message}"
          []
        end

        def gather_configuration
          config = RAAF::Eval::Continuous.configuration
          {
            enabled: config.enabled,
            hook_enabled: config.hook_enabled,
            default_queue_name: config.default_queue_name,
            default_priority: config.default_priority,
            max_concurrent_evaluations: config.max_concurrent_evaluations,
            backpressure_threshold: config.backpressure_threshold
          }
        end

        def determine_overall_status(config, pending, running)
          return "disabled" unless config.enabled
          return "backpressure" if config.backpressure_active
          return "degraded" if count_critical_alerts > 0
          return "warning" if pending + running > config.backpressure_threshold * 0.7
          "healthy"
        end

        def determine_status_code(health_data)
          case health_data[:status]
          when "healthy"
            :ok
          when "warning", "backpressure"
            :ok # Still operational, just under load
          when "degraded"
            :service_unavailable
          when "disabled"
            :ok # Intentionally disabled is OK
          else
            :ok
          end
        end

        def count_active_alerts
          RAAF::Eval::Models::EvaluationAlert.active.count
        rescue StandardError
          0
        end

        def count_critical_alerts
          RAAF::Eval::Models::EvaluationAlert.active.critical.count
        rescue StandardError
          0
        end
      end
    end
  end
end
