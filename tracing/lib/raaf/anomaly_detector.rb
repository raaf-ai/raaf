# frozen_string_literal: true

module RAAF
  module Tracing
    # rubocop:disable Metrics/ClassLength
    class AnomalyDetector
      # Statistical anomaly detection using various algorithms

      def initialize(config = {})
        @config = {
          # Z-score threshold for outlier detection
          z_score_threshold: config[:z_score_threshold] || 3.0,

          # Minimum samples needed for analysis
          min_samples: config[:min_samples] || 20,

          # Historical data window for baseline calculation
          baseline_days: config[:baseline_days] || 7,

          # Sensitivity for change point detection
          change_point_sensitivity: config[:change_point_sensitivity] || 0.7,

          # Seasonal adjustment (day of week, hour patterns)
          seasonal_adjustment: config[:seasonal_adjustment] || true,

          # Cache results for performance
          cache_results: config[:cache_results] || true,
          cache_ttl: config[:cache_ttl] || 300 # 5 minutes
        }

        @cache = {}
        setup_algorithms
      end

      def detect_performance_anomalies(timeframe = 24.hours)
        end_time = Time.current
        start_time = end_time - timeframe

        results = {
          timestamp: end_time,
          timeframe: timeframe,
          anomalies: [],
          summary: {}
        }

        # Detect duration anomalies
        duration_anomalies = detect_duration_anomalies(start_time, end_time)
        results[:anomalies].concat(duration_anomalies)

        # Detect error rate anomalies
        error_anomalies = detect_error_rate_anomalies(start_time, end_time)
        results[:anomalies].concat(error_anomalies)

        # Detect throughput anomalies
        throughput_anomalies = detect_throughput_anomalies(start_time, end_time)
        results[:anomalies].concat(throughput_anomalies)

        # Detect workflow-specific anomalies
        workflow_anomalies = detect_workflow_anomalies(start_time, end_time)
        results[:anomalies].concat(workflow_anomalies)

        results[:summary] = generate_anomaly_summary(results[:anomalies])
        results
      end

      def detect_cost_anomalies(timeframe = 24.hours)
        end_time = Time.current
        start_time = end_time - timeframe

        results = {
          timestamp: end_time,
          timeframe: timeframe,
          anomalies: [],
          summary: {}
        }

        # Detect token usage spikes
        token_anomalies = detect_token_usage_anomalies(start_time, end_time)
        results[:anomalies].concat(token_anomalies)

        # Detect cost per request anomalies
        cost_anomalies = detect_cost_per_request_anomalies(start_time, end_time)
        results[:anomalies].concat(cost_anomalies)

        # Detect model usage pattern changes
        model_anomalies = detect_model_usage_anomalies(start_time, end_time)
        results[:anomalies].concat(model_anomalies)

        results[:summary] = generate_anomaly_summary(results[:anomalies])
        results
      end

      def detect_pattern_changes(metric, data_points, baseline_data = nil)
        return [] if data_points.size < @config[:min_samples]

        anomalies = []
        baseline_data ||= get_baseline_data(metric)

        # Statistical outlier detection
        outliers = detect_statistical_outliers(data_points, baseline_data)
        anomalies.concat(outliers)

        # Change point detection
        change_points = detect_change_points(data_points)
        anomalies.concat(change_points)

        # Trend analysis
        trend_changes = detect_trend_changes(data_points, baseline_data)
        anomalies.concat(trend_changes)

        # Seasonal anomalies (if enabled)
        if @config[:seasonal_adjustment]
          seasonal_anomalies = detect_seasonal_anomalies(data_points, baseline_data)
          anomalies.concat(seasonal_anomalies)
        end

        anomalies.uniq { |a| [a[:type], a[:timestamp]] }
      end

      def get_anomaly_insights(anomalies)
        insights = {
          total_anomalies: anomalies.size,
          by_severity: group_by_severity(anomalies),
          by_type: group_by_type(anomalies),
          recommendations: generate_recommendations(anomalies),
          potential_causes: identify_potential_causes(anomalies)
        }

        insights[:trend_analysis] = analyze_anomaly_trends(anomalies)
        insights[:correlation_analysis] = find_correlated_anomalies(anomalies)

        insights
      end

      private

      def setup_algorithms
        @algorithms = {
          z_score: method(:z_score_outlier_detection),
          iqr: method(:iqr_outlier_detection),
          isolation_forest: method(:isolation_forest_detection),
          change_point: method(:cusum_change_detection)
        }
      end

      def detect_duration_anomalies(start_time, end_time)
        durations_by_hour = get_hourly_durations(start_time, end_time)
        baseline_durations = get_baseline_durations(start_time)

        anomalies = []

        durations_by_hour.each do |hour, durations|
          next if durations.empty?

          avg_duration = durations.sum / durations.size
          baseline_avg = get_baseline_average(baseline_durations, hour)

          # Check for significant deviation
          if baseline_avg > 0
            deviation_ratio = avg_duration / baseline_avg
            if deviation_ratio > 2.0 || deviation_ratio < 0.5
              anomalies << {
                type: "duration_anomaly",
                severity: deviation_ratio > 3.0 ? "critical" : "warning",
                timestamp: hour,
                metric: "avg_duration_ms",
                value: avg_duration,
                baseline: baseline_avg,
                deviation_ratio: deviation_ratio.round(2),
                description: "Average duration #{deviation_ratio > 1 ? "increased" : "decreased"} " \
                             "by #{((deviation_ratio - 1) * 100).abs.round(1)}%",
                sample_count: durations.size
              }
            end
          end

          # Check for individual outliers
          outliers = detect_statistical_outliers(durations, baseline_durations[hour.hour] || [])
          outliers.each do |outlier|
            anomalies << {
              type: "duration_outlier",
              severity: "warning",
              timestamp: hour,
              metric: "duration_ms",
              value: outlier[:value],
              z_score: outlier[:z_score],
              description: "Unusually #{outlier[:z_score] > 0 ? "high" : "low"} duration detected"
            }
          end
        end

        anomalies
      end

      def detect_error_rate_anomalies(start_time, end_time)
        error_rates_by_hour = get_hourly_error_rates(start_time, end_time)
        baseline_error_rates = get_baseline_error_rates(start_time)

        anomalies = []

        error_rates_by_hour.each do |hour, error_rate|
          baseline_rate = baseline_error_rates[hour.hour] || 0

          # Significant increase in error rate
          next unless error_rate > baseline_rate + 5.0 && error_rate > 2.0 # At least 5% increase and >2% total

          severity = error_rate > baseline_rate + 15.0 ? "critical" : "warning"

          anomalies << {
            type: "error_rate_spike",
            severity: severity,
            timestamp: hour,
            metric: "error_rate_percent",
            value: error_rate,
            baseline: baseline_rate,
            increase: (error_rate - baseline_rate).round(2),
            description: "Error rate increased by #{(error_rate - baseline_rate).round(1)}% from baseline"
          }
        end

        anomalies
      end

      def detect_throughput_anomalies(start_time, end_time)
        throughput_by_hour = get_hourly_throughput(start_time, end_time)
        baseline_throughput = get_baseline_throughput(start_time)

        anomalies = []

        throughput_by_hour.each do |hour, count|
          baseline_count = baseline_throughput[hour.hour] || 0
          next if baseline_count == 0

          ratio = count.to_f / baseline_count

          # Significant change in throughput
          next unless ratio > 2.0 || ratio < 0.3

          severity = ratio > 5.0 || ratio < 0.1 ? "critical" : "warning"

          anomalies << {
            type: "throughput_anomaly",
            severity: severity,
            timestamp: hour,
            metric: "traces_per_hour",
            value: count,
            baseline: baseline_count,
            ratio: ratio.round(2),
            description: "Throughput #{ratio > 1 ? "increased" : "decreased"} by #{((ratio - 1) * 100).abs.round(1)}%"
          }
        end

        anomalies
      end

      def detect_workflow_anomalies(start_time, end_time)
        anomalies = []

        # Get top workflows
        workflows = Trace.within_timeframe(start_time, end_time)
                         .group(:workflow_name)
                         .count
                         .sort_by { |_, count| -count }
                         .first(10)
                         .to_h

        workflows.each_key do |workflow_name|
          workflow_traces = Trace.within_timeframe(start_time, end_time)
                                 .where(workflow_name: workflow_name)

          # Check for workflow-specific duration anomalies
          durations = workflow_traces.where.not(ended_at: nil)
                                     .pluck("EXTRACT(EPOCH FROM (ended_at - started_at)) * 1000")

          if durations.size >= @config[:min_samples]
            baseline_durations = get_workflow_baseline_durations(workflow_name, start_time)
            outliers = detect_statistical_outliers(durations, baseline_durations)

            outliers.each do |outlier|
              anomalies << {
                type: "workflow_duration_anomaly",
                severity: "warning",
                timestamp: start_time,
                workflow: workflow_name,
                metric: "duration_ms",
                value: outlier[:value],
                z_score: outlier[:z_score],
                description: "Unusual duration in #{workflow_name} workflow"
              }
            end
          end

          # Check for workflow error spikes
          error_rate = workflow_traces.failed.count.to_f / workflow_traces.count * 100
          baseline_error_rate = get_workflow_baseline_error_rate(workflow_name, start_time)

          next unless error_rate > baseline_error_rate + 10.0

          anomalies << {
            type: "workflow_error_spike",
            severity: error_rate > baseline_error_rate + 20.0 ? "critical" : "warning",
            timestamp: start_time,
            workflow: workflow_name,
            metric: "error_rate_percent",
            value: error_rate,
            baseline: baseline_error_rate,
            description: "Error spike in #{workflow_name} workflow"
          }
        end

        anomalies
      end

      def detect_token_usage_anomalies(start_time, end_time)
        token_usage_by_hour = get_hourly_token_usage(start_time, end_time)
        baseline_usage = get_baseline_token_usage(start_time)

        anomalies = []

        token_usage_by_hour.each do |hour, usage|
          baseline = baseline_usage[hour.hour] || {}

          %w[input_tokens output_tokens].each do |token_type|
            current_tokens = usage[token_type] || 0
            baseline_tokens = baseline[token_type] || 0

            next if baseline_tokens == 0

            ratio = current_tokens.to_f / baseline_tokens

            next unless ratio > 3.0 || ratio < 0.2

            anomalies << {
              type: "token_usage_anomaly",
              severity: ratio > 5.0 ? "critical" : "warning",
              timestamp: hour,
              metric: token_type,
              value: current_tokens,
              baseline: baseline_tokens,
              ratio: ratio.round(2),
              description: "#{token_type.humanize} usage #{ratio > 1 ? "spike" : "drop"} detected"
            }
          end
        end

        anomalies
      end

      def detect_cost_per_request_anomalies(start_time, end_time)
        costs_by_hour = get_hourly_costs_per_request(start_time, end_time)
        baseline_costs = get_baseline_costs_per_request(start_time)

        anomalies = []

        costs_by_hour.each do |hour, cost_per_request|
          baseline_cost = baseline_costs[hour.hour] || 0
          next if baseline_cost == 0

          ratio = cost_per_request / baseline_cost

          next unless ratio > 2.0

          anomalies << {
            type: "cost_per_request_spike",
            severity: ratio > 5.0 ? "critical" : "warning",
            timestamp: hour,
            metric: "cost_per_request",
            value: cost_per_request,
            baseline: baseline_cost,
            ratio: ratio.round(2),
            description: "Cost per request increased by #{((ratio - 1) * 100).round(1)}%"
          }
        end

        anomalies
      end

      def detect_model_usage_anomalies(start_time, end_time)
        current_usage = get_model_usage_distribution(start_time, end_time)
        baseline_usage = get_baseline_model_usage(start_time)

        anomalies = []

        current_usage.each do |model, percentage|
          baseline_percentage = baseline_usage[model] || 0
          difference = percentage - baseline_percentage

          # Significant shift in model usage
          next unless difference.abs > 20.0 # 20% change

          anomalies << {
            type: "model_usage_shift",
            severity: difference.abs > 40.0 ? "warning" : "info",
            timestamp: start_time,
            metric: "model_usage_percent",
            model: model,
            value: percentage,
            baseline: baseline_percentage,
            change: difference.round(2),
            description: "#{model} usage #{difference > 0 ? "increased" : "decreased"} by #{difference.abs.round(1)}%"
          }
        end

        anomalies
      end

      def detect_statistical_outliers(data_points, baseline_data = [])
        return [] if data_points.size < @config[:min_samples]

        combined_data = (data_points + baseline_data).compact
        return [] if combined_data.empty?

        mean = combined_data.sum.to_f / combined_data.size
        std_dev = Math.sqrt(combined_data.map { |x| (x - mean)**2 }.sum / combined_data.size)

        return [] if std_dev == 0

        outliers = []

        data_points.each_with_index do |value, index|
          z_score = (value - mean) / std_dev

          next unless z_score.abs > @config[:z_score_threshold]

          outliers << {
            index: index,
            value: value,
            z_score: z_score.round(3),
            threshold: @config[:z_score_threshold]
          }
        end

        outliers
      end

      def detect_change_points(data_points)
        return [] if data_points.size < @config[:min_samples]

        change_points = []
        window_size = [data_points.size / 4, 5].max

        (window_size...(data_points.size - window_size)).each do |i|
          before = data_points[(i - window_size)...i]
          after = data_points[i...(i + window_size)]

          before_mean = before.sum.to_f / before.size
          after_mean = after.sum.to_f / after.size

          # Calculate change magnitude
          change_ratio = after_mean / before_mean if before_mean > 0
          next unless change_ratio

          next unless change_ratio > 1 + @config[:change_point_sensitivity] ||
                      change_ratio < 1 - @config[:change_point_sensitivity]

          change_points << {
            index: i,
            before_mean: before_mean,
            after_mean: after_mean,
            change_ratio: change_ratio.round(3),
            magnitude: ((change_ratio - 1) * 100).abs.round(1)
          }
        end

        change_points
      end

      def detect_trend_changes(data_points, baseline_data)
        return [] if data_points.size < @config[:min_samples]

        current_trend = calculate_trend(data_points)
        calculate_trend(baseline_data) if baseline_data.any?

        trends = []

        if current_trend[:slope].abs > 0.1
          trends << {
            type: "trend_change",
            direction: current_trend[:slope] > 0 ? "increasing" : "decreasing",
            slope: current_trend[:slope].round(4),
            r_squared: current_trend[:r_squared].round(3),
            confidence: trend_confidence(current_trend[:r_squared])
          }
        end

        trends
      end

      def detect_seasonal_anomalies(data_points, baseline_data)
        # Simplified seasonal detection - would need more sophisticated implementation
        # for production use with proper time series decomposition
        []
      end

      # Data retrieval methods
      def get_hourly_durations(start_time, end_time)
        durations = {}

        Trace.within_timeframe(start_time, end_time)
             .where.not(ended_at: nil)
             .pluck(:started_at, "EXTRACT(EPOCH FROM (ended_at - started_at)) * 1000")
             .each do |started_at, duration|
               hour = started_at.beginning_of_hour
               durations[hour] ||= []
               durations[hour] << duration
             end

        durations
      end

      def get_baseline_durations(current_start)
        baseline_start = current_start - @config[:baseline_days].days
        baseline_end = current_start

        durations = {}

        Trace.within_timeframe(baseline_start, baseline_end)
             .where.not(ended_at: nil)
             .pluck(:started_at, "EXTRACT(EPOCH FROM (ended_at - started_at)) * 1000")
             .each do |started_at, duration|
               hour = started_at.hour
               durations[hour] ||= []
               durations[hour] << duration
             end

        durations
      end

      def get_baseline_average(baseline_data, hour)
        hour_data = baseline_data[hour.hour] || []
        return 0 if hour_data.empty?

        hour_data.sum / hour_data.size
      end

      def get_hourly_error_rates(start_time, end_time)
        error_rates = {}

        start_time.to_i.step(end_time.to_i, 1.hour) do |timestamp|
          hour_start = Time.at(timestamp)
          hour_end = hour_start + 1.hour

          traces = Trace.within_timeframe(hour_start, hour_end)
          total = traces.count
          errors = traces.failed.count

          error_rates[hour_start] = total > 0 ? (errors.to_f / total * 100) : 0
        end

        error_rates
      end

      def get_baseline_error_rates(current_start)
        baseline_start = current_start - @config[:baseline_days].days
        baseline_end = current_start

        error_rates = Hash.new { |h, k| h[k] = [] }

        baseline_start.to_i.step(baseline_end.to_i, 1.hour) do |timestamp|
          hour_start = Time.at(timestamp)
          hour_end = hour_start + 1.hour

          traces = Trace.within_timeframe(hour_start, hour_end)
          total = traces.count
          errors = traces.failed.count

          rate = total > 0 ? (errors.to_f / total * 100) : 0
          error_rates[hour_start.hour] << rate
        end

        # Average the error rates by hour of day
        error_rates.transform_values { |rates| rates.sum / rates.size if rates.any? }.compact
      end

      # Additional helper methods would continue here...
      # This is a substantial implementation showing the core concepts

      def generate_anomaly_summary(anomalies)
        {
          total: anomalies.size,
          critical: anomalies.count { |a| a[:severity] == "critical" },
          warning: anomalies.count { |a| a[:severity] == "warning" },
          most_common_type: anomalies.group_by { |a| a[:type] }.max_by { |_, v| v.size }&.first,
          time_distribution: group_anomalies_by_time(anomalies)
        }
      end

      def group_by_severity(anomalies)
        anomalies.group_by { |a| a[:severity] }
                 .transform_values(&:size)
      end

      def group_by_type(anomalies)
        anomalies.group_by { |a| a[:type] }
                 .transform_values(&:size)
      end

      def calculate_trend(data_points)
        return { slope: 0, r_squared: 0 } if data_points.size < 2

        n = data_points.size
        x_values = (0...n).to_a
        y_values = data_points

        x_mean = x_values.sum.to_f / n
        y_mean = y_values.sum.to_f / n

        numerator = x_values.zip(y_values).map { |x, y| (x - x_mean) * (y - y_mean) }.sum
        denominator = x_values.map { |x| (x - x_mean)**2 }.sum

        slope = denominator > 0 ? numerator / denominator : 0

        # Calculate R-squared
        y_pred = x_values.map { |x| (slope * (x - x_mean)) + y_mean }
        ss_res = y_values.zip(y_pred).map { |y, yp| (y - yp)**2 }.sum
        ss_tot = y_values.map { |y| (y - y_mean)**2 }.sum

        r_squared = ss_tot > 0 ? 1 - (ss_res / ss_tot) : 0

        { slope: slope, r_squared: r_squared }
      end

      def trend_confidence(r_squared)
        case r_squared
        when 0.8..1.0 then "high"
        when 0.5..0.8 then "medium"
        else "low"
        end
      end

      # Placeholder methods for additional functionality
      def get_hourly_throughput(start_time, end_time)
        {}
      end

      def get_baseline_throughput(current_start)
        {}
      end

      def get_hourly_token_usage(start_time, end_time)
        {}
      end

      def get_baseline_token_usage(current_start)
        {}
      end

      def get_hourly_costs_per_request(start_time, end_time)
        {}
      end

      def get_baseline_costs_per_request(current_start)
        {}
      end

      def get_model_usage_distribution(start_time, end_time)
        {}
      end

      def get_baseline_model_usage(current_start)
        {}
      end

      def get_workflow_baseline_durations(workflow_name, current_start)
        []
      end

      def get_workflow_baseline_error_rate(workflow_name, current_start)
        0
      end

      def generate_recommendations(anomalies)
        []
      end

      def identify_potential_causes(anomalies)
        []
      end

      def analyze_anomaly_trends(anomalies)
        {}
      end

      def find_correlated_anomalies(anomalies)
        {}
      end

      def group_anomalies_by_time(anomalies)
        {}
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
