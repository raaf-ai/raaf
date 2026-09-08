# frozen_string_literal: true

module RAAF
  module Rails
    module Continuous
      ##
      # Two different questions share this controller, and they are answered
      # from two different places.
      #
      # `show` in HTML is the console's **Evaluator health** screen: whether the
      # evaluators can still be trusted, read from the evaluations they have
      # produced. `show` in JSON, and the `dashboard` action, answer the
      # operational question — is the pipeline running, is the queue backed
      # up — from RAAF's own bookkeeping tables. A monitoring check may well be
      # pointed at the JSON, so its payload is left exactly as it was.
      #
      # Endpoints:
      # - GET /raaf/continuous/health - Evaluator health (HTML), health check (JSON)
      # - GET /raaf/continuous/health/dashboard - system status
      class HealthController < BaseController
        # GET /raaf/continuous/health
        def show
          respond_to do |format|
            format.html { render_scorer_health }
            format.json do
              health_data = gather_health_data
              render json: health_data, status: determine_status_code(health_data)
            end
          end
        end

        # The operational panel: queue depth, backpressure and the configuration
        # in force. It is the HTML face of the JSON above rather than a second
        # health screen.
        #
        # It had been calling `render_phlex`, which exists nowhere in this
        # engine, so every request to it raised `NoMethodError`. Nothing linked
        # to it, which is why that went unnoticed.
        #
        # GET /raaf/continuous/health/dashboard
        def dashboard
          @health_data = gather_health_data
          @alerts = gather_recent_alerts
          @config = gather_configuration

          panel = RAAF::Rails::Continuous::SystemHealthPanel.new(
            health_data: @health_data, alerts: @alerts, config: @config
          )

          render_in_layout panel, title: "System status", crumb: "Continuous",
                                  current: :health, live: false
        end

        private

        # The window is the topbar's range, so the reader can widen it when a
        # policy samples too thinly to say anything over a day.
        def render_scorer_health
          health = RAAF::Rails::Continuous::ScorerHealth.new(window: range_duration)
          dashboard = RAAF::Rails::Continuous::HealthDashboard.new(health: health,
                                                                   range: current_range)

          render_in_layout dashboard, title: "Evaluator health", crumb: "Continuous",
                                      current: :health, range: current_range, range_href: range_href
        end

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
