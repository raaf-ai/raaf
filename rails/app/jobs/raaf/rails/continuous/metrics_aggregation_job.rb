# frozen_string_literal: true

module RAAF
  module Rails
    module Continuous
      ##
      # MetricsAggregationJob pre-computes evaluation metrics for fast dashboard queries.
      # Runs periodically to aggregate results into time-series metrics.
      #
      # Aggregation Types:
      # - hourly: Detailed metrics for recent data (kept 7 days)
      # - daily: Standard metrics (kept 90 days)
      # - weekly: Long-term trends (kept indefinitely)
      #
      # Metrics Computed:
      # - Pass/fail counts
      # - Average scores with percentiles
      # - Score distributions
      # - Performance metrics (duration, cost)
      #
      # Uses EvaluationMetric.aggregate_from_results for actual aggregation logic.
      class MetricsAggregationJob < RAAF::Rails::ApplicationJob
        queue_as :raaf_evaluations_low

        # Don't retry aggregation failures aggressively
        retry_on StandardError, wait: 1.hour, attempts: 2

        ##
        # Aggregate metrics for a specific period type
        # @param period_type [String] 'hourly', 'daily', or 'weekly'
        def perform(period_type: 'hourly')
          case period_type
          when 'hourly'
            aggregate_hourly_metrics
          when 'daily'
            aggregate_daily_metrics
          when 'weekly'
            aggregate_weekly_metrics
          else
            raise ArgumentError, "Invalid period_type: #{period_type}. Must be 'hourly', 'daily', or 'weekly'"
          end
        end

        private

        ##
        # Aggregate hourly metrics for the last 2 hours (overlap for safety)
        def aggregate_hourly_metrics
          start_time = 2.hours.ago.beginning_of_hour
          end_time = Time.current.end_of_hour

          aggregate_for_period('hourly', start_time, end_time, 1.hour)
        end

        ##
        # Aggregate daily metrics for yesterday and today
        def aggregate_daily_metrics
          # Aggregate yesterday (full day)
          yesterday = 1.day.ago.beginning_of_day
          aggregate_for_period('daily', yesterday, yesterday.end_of_day, 1.day)

          # Aggregate today (partial day)
          today = Time.current.beginning_of_day
          aggregate_for_period('daily', today, Time.current.end_of_day, 1.day)
        end

        ##
        # Aggregate weekly metrics for last week and current week
        def aggregate_weekly_metrics
          # Aggregate last week (full week)
          last_week = 1.week.ago.beginning_of_week
          aggregate_for_period('weekly', last_week, last_week.end_of_week, 1.week)

          # Aggregate current week (partial)
          this_week = Time.current.beginning_of_week
          aggregate_for_period('weekly', this_week, Time.current.end_of_week, 1.week)
        end

        ##
        # Aggregate metrics for a specific time period
        # @param period_type [String] Type of period
        # @param start_time [Time] Period start
        # @param end_time [Time] Period end
        # @param interval [ActiveSupport::Duration] Time interval for grouping
        def aggregate_for_period(period_type, start_time, end_time, interval)
          # Get all results in the time range
          results = RAAF::Eval::Models::ContinuousEvaluationResult
            .where(created_at: start_time..end_time)

          # Group results by dimensions
          grouped_results = group_results_by_dimensions(results)

          # Aggregate each group
          grouped_results.each do |dimensions, group_results|
            aggregate_group(period_type, dimensions, group_results, start_time)
          end
        end

        ##
        # Group results by aggregation dimensions
        # @param results [ActiveRecord::Relation] Results to group
        # @return [Hash] Results grouped by dimensions
        def group_results_by_dimensions(results)
          results.group_by do |result|
            {
              agent_name: result.agent_name,
              environment: result.environment,
              model: result.model,
              evaluator_name: result.evaluator_name
            }
          end
        end

        ##
        # Aggregate a group of results into a metric record
        # @param period_type [String] Type of period
        # @param dimensions [Hash] Grouping dimensions
        # @param results [Array] Results to aggregate
        # @param period_start [Time] Start of period
        def aggregate_group(period_type, dimensions, results, period_start)
          return if results.empty?

          # Calculate aggregate statistics
          stats = calculate_statistics(results)

          # Upsert metric record
          RAAF::Eval::Models::EvaluationMetric.upsert(
            {
              agent_name: dimensions[:agent_name],
              environment: dimensions[:environment],
              model: dimensions[:model],
              evaluator_name: dimensions[:evaluator_name],
              period_type: period_type,
              period_start: period_start,
              total_evaluations: stats[:total_evaluations],
              passed_count: stats[:passed_count],
              failed_count: stats[:failed_count],
              warning_count: stats[:warning_count],
              error_count: stats[:error_count],
              avg_score: stats[:avg_score],
              min_score: stats[:min_score],
              max_score: stats[:max_score],
              stddev_score: stats[:stddev_score],
              p50_score: stats[:p50_score],
              p90_score: stats[:p90_score],
              p95_score: stats[:p95_score],
              score_distribution: stats[:score_distribution],
              avg_evaluation_duration_ms: stats[:avg_duration_ms],
              total_evaluation_cost: stats[:total_cost],
              additional_metrics: {},
              updated_at: Time.current
            },
            unique_by: [:agent_name, :environment, :model, :evaluator_name, :period_type, :period_start]
          )
        end

        ##
        # Calculate aggregate statistics for a group of results
        # @param results [Array] Results to analyze
        # @return [Hash] Computed statistics
        def calculate_statistics(results)
          scores = results.map(&:score).compact
          durations = results.map(&:evaluation_duration_ms).compact

          {
            total_evaluations: results.size,
            passed_count: results.count { |r| r.status == 'passed' },
            failed_count: results.count { |r| r.status == 'failed' },
            warning_count: results.count { |r| r.status == 'warning' },
            error_count: results.count { |r| r.status == 'error' },
            avg_score: calculate_average(scores),
            min_score: scores.min,
            max_score: scores.max,
            stddev_score: calculate_stddev(scores),
            p50_score: calculate_percentile(scores, 50),
            p90_score: calculate_percentile(scores, 90),
            p95_score: calculate_percentile(scores, 95),
            score_distribution: calculate_score_distribution(scores),
            avg_duration_ms: calculate_average(durations),
            total_cost: results.sum { |r| r.metrics.dig('cost') || 0 }
          }
        end

        def calculate_average(values)
          return nil if values.empty?
          values.sum.to_f / values.size
        end

        def calculate_stddev(values)
          return nil if values.size < 2
          mean = calculate_average(values)
          variance = values.sum { |v| (v - mean) ** 2 } / values.size
          Math.sqrt(variance)
        end

        def calculate_percentile(values, percentile)
          return nil if values.empty?
          sorted = values.sort
          index = (percentile / 100.0 * (sorted.size - 1)).round
          sorted[index]
        end

        def calculate_score_distribution(scores)
          return {} if scores.empty?

          # Create 10 buckets: 0.0-0.1, 0.1-0.2, ..., 0.9-1.0
          distribution = Hash.new(0)
          scores.each do |score|
            bucket = (score * 10).floor
            bucket = 9 if bucket >= 10 # Handle 1.0 score
            bucket_label = "#{bucket / 10.0}-#{(bucket + 1) / 10.0}"
            distribution[bucket_label] += 1
          end

          distribution
        end
      end
    end
  end
end
