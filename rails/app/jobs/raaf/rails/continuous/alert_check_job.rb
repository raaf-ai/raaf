# frozen_string_literal: true

module RAAF
  module Rails
    module Continuous
      ##
      # AlertCheckJob periodically checks evaluation results and system health
      # to detect anomalies and trigger alerts.
      #
      # Alert Types Detected:
      # - quality_degradation: Score drops below threshold
      # - failure_spike: Error rate exceeds threshold
      # - queue_backlog: Queue depth exceeds threshold
      # - evaluator_error: Specific evaluator failing consistently
      #
      # Recommended schedule: Every 5-10 minutes via cron or recurring job
      class AlertCheckJob < RAAF::Rails::ApplicationJob
        queue_as :raaf_maintenance

        # Configuration thresholds
        QUALITY_DROP_THRESHOLD = 0.15      # 15% score drop triggers alert
        FAILURE_RATE_THRESHOLD = 0.20      # 20% failure rate triggers alert
        QUEUE_BACKLOG_THRESHOLD = 500      # 500 pending items triggers alert
        EVALUATOR_FAILURE_THRESHOLD = 0.50 # 50% evaluator failure rate triggers alert
        LOOKBACK_PERIOD = 1.hour           # Period to analyze

        def perform
          return unless RAAF::Eval::Continuous.enabled?

          check_quality_degradation
          check_failure_spike
          check_queue_backlog
          check_evaluator_errors

          # Auto-resolve alerts that are no longer applicable
          auto_resolve_stale_alerts
        end

        private

        ##
        # Check for quality score degradation across agents
        def check_quality_degradation
          # Get agents with recent evaluations
          recent_results = recent_evaluation_results

          # Group by agent and calculate metrics
          by_agent = recent_results.group_by(&:agent_name)

          by_agent.each do |agent_name, results|
            next if results.empty?

            # Calculate average score
            scores = results.map(&:score).compact
            next if scores.empty?

            avg_score = scores.sum / scores.count.to_f

            # Get baseline (previous period)
            baseline_results = baseline_evaluation_results(agent_name)
            baseline_scores = baseline_results.map(&:score).compact
            next if baseline_scores.empty?

            baseline_avg = baseline_scores.sum / baseline_scores.count.to_f

            # Check for significant drop
            score_drop = baseline_avg - avg_score
            if score_drop > QUALITY_DROP_THRESHOLD && baseline_avg > 0
              trigger_quality_alert(agent_name, baseline_avg, avg_score, score_drop)
            end
          end
        end

        ##
        # Check for spike in evaluation failures
        def check_failure_spike
          recent_results = recent_evaluation_results

          # Group by agent
          by_agent = recent_results.group_by(&:agent_name)

          by_agent.each do |agent_name, results|
            next if results.count < 10 # Need sufficient sample

            failed_count = results.count { |r| %w[failed error].include?(r.status) }
            failure_rate = failed_count / results.count.to_f

            if failure_rate > FAILURE_RATE_THRESHOLD
              trigger_failure_alert(agent_name, failure_rate, failed_count, results.count)
            end
          end
        end

        ##
        # Check for queue backlog
        def check_queue_backlog
          pending_count = RAAF::Eval::Models::EvaluationQueueItem.pending.count
          running_count = RAAF::Eval::Models::EvaluationQueueItem.running.count
          total_backlog = pending_count + running_count

          if total_backlog > QUEUE_BACKLOG_THRESHOLD
            trigger_queue_alert(total_backlog, pending_count, running_count)
          end
        end

        ##
        # Check for specific evaluators failing consistently
        def check_evaluator_errors
          recent_results = recent_evaluation_results.where(status: 'error')

          # Group by evaluator
          by_evaluator = recent_results.group(:evaluator_name).count
          total_by_evaluator = recent_evaluation_results.group(:evaluator_name).count

          by_evaluator.each do |evaluator_name, error_count|
            total_count = total_by_evaluator[evaluator_name] || 0
            next if total_count < 5 # Need sufficient sample

            failure_rate = error_count / total_count.to_f

            if failure_rate > EVALUATOR_FAILURE_THRESHOLD
              trigger_evaluator_alert(evaluator_name, failure_rate, error_count, total_count)
            end
          end
        end

        ##
        # Auto-resolve alerts that are no longer applicable
        def auto_resolve_stale_alerts
          # Resolve queue backlog alerts if queue is healthy
          current_backlog = RAAF::Eval::Models::EvaluationQueueItem.pending.count
          if current_backlog < QUEUE_BACKLOG_THRESHOLD * 0.5
            RAAF::Eval::Models::EvaluationAlert
              .active
              .where(alert_type: 'queue_backlog')
              .find_each do |alert|
                alert.resolve!(by: 'system', notes: "Queue backlog resolved: #{current_backlog} items")
              end
          end
        end

        # Helper methods

        def recent_evaluation_results
          RAAF::Eval::Models::ContinuousEvaluationResult
            .where("created_at > ?", LOOKBACK_PERIOD.ago)
        end

        def baseline_evaluation_results(agent_name)
          RAAF::Eval::Models::ContinuousEvaluationResult
            .where(agent_name: agent_name)
            .where("created_at > ? AND created_at <= ?", 2 * LOOKBACK_PERIOD.ago, LOOKBACK_PERIOD.ago)
        end

        def trigger_quality_alert(agent_name, baseline, current, drop)
          RAAF::Eval::Models::EvaluationAlert.trigger!(
            alert_type: 'quality_degradation',
            severity: drop > 0.25 ? 'critical' : 'warning',
            agent_name: agent_name,
            title: "Quality degradation detected for #{agent_name}",
            message: "Average score dropped from #{(baseline * 100).round(1)}% to #{(current * 100).round(1)}% " \
                     "(#{(drop * 100).round(1)}% decrease) in the last #{LOOKBACK_PERIOD.inspect}",
            threshold_value: baseline,
            actual_value: current,
            metric_name: 'avg_score',
            details: {
              baseline_score: baseline.round(4),
              current_score: current.round(4),
              score_drop: drop.round(4),
              lookback_period: LOOKBACK_PERIOD.inspect
            }
          )
          RAAF.logger.warn "[ContinuousEval] Quality alert triggered for #{agent_name}: #{(drop * 100).round(1)}% drop"
        end

        def trigger_failure_alert(agent_name, failure_rate, failed_count, total_count)
          RAAF::Eval::Models::EvaluationAlert.trigger!(
            alert_type: 'failure_spike',
            severity: failure_rate > 0.5 ? 'critical' : 'warning',
            agent_name: agent_name,
            title: "Evaluation failure spike for #{agent_name}",
            message: "#{failed_count}/#{total_count} evaluations failed (#{(failure_rate * 100).round(1)}% failure rate) " \
                     "in the last #{LOOKBACK_PERIOD.inspect}",
            threshold_value: FAILURE_RATE_THRESHOLD,
            actual_value: failure_rate,
            metric_name: 'failure_rate',
            details: {
              failed_count: failed_count,
              total_count: total_count,
              failure_rate: failure_rate.round(4),
              threshold: FAILURE_RATE_THRESHOLD
            }
          )
          RAAF.logger.warn "[ContinuousEval] Failure alert triggered for #{agent_name}: #{(failure_rate * 100).round(1)}% failure rate"
        end

        def trigger_queue_alert(total_backlog, pending, running)
          RAAF::Eval::Models::EvaluationAlert.trigger!(
            alert_type: 'queue_backlog',
            severity: total_backlog > QUEUE_BACKLOG_THRESHOLD * 2 ? 'critical' : 'warning',
            title: "Evaluation queue backlog detected",
            message: "#{total_backlog} items in queue (#{pending} pending, #{running} running). " \
                     "Threshold: #{QUEUE_BACKLOG_THRESHOLD}",
            threshold_value: QUEUE_BACKLOG_THRESHOLD,
            actual_value: total_backlog,
            metric_name: 'queue_depth',
            details: {
              pending_count: pending,
              running_count: running,
              total_backlog: total_backlog,
              threshold: QUEUE_BACKLOG_THRESHOLD
            }
          )
          RAAF.logger.warn "[ContinuousEval] Queue backlog alert: #{total_backlog} items"
        end

        def trigger_evaluator_alert(evaluator_name, failure_rate, error_count, total_count)
          RAAF::Eval::Models::EvaluationAlert.trigger!(
            alert_type: 'evaluator_error',
            severity: 'warning',
            evaluator_name: evaluator_name,
            title: "Evaluator '#{evaluator_name}' failing frequently",
            message: "#{error_count}/#{total_count} executions errored (#{(failure_rate * 100).round(1)}% failure rate)",
            threshold_value: EVALUATOR_FAILURE_THRESHOLD,
            actual_value: failure_rate,
            metric_name: 'evaluator_failure_rate',
            details: {
              error_count: error_count,
              total_count: total_count,
              failure_rate: failure_rate.round(4)
            }
          )
          RAAF.logger.warn "[ContinuousEval] Evaluator alert: #{evaluator_name} has #{(failure_rate * 100).round(1)}% failure rate"
        end
      end
    end
  end
end
