# frozen_string_literal: true

module RAAF
  module Tracing
    class TracesChannel < ApplicationCable::Channel
      def subscribed
        return reject unless authorized?

        stream_from "traces_updates"

        # Send initial data on subscription
        transmit({
                   type: "initial_data",
                   traces: recent_traces_data,
                   stats: dashboard_stats
                 })
      end

      def unsubscribed
        # Cleanup when channel is unsubscribed
      end

      def request_trace_details(data)
        trace_id = data["trace_id"]
        trace = TraceRecord.find_by(trace_id: trace_id)

        return unless trace

        transmit({
                   type: "trace_details",
                   trace: trace_details_data(trace)
                 })
      end

      def request_performance_update
        transmit({
                   type: "performance_update",
                   stats: dashboard_stats,
                   metrics: performance_metrics
                 })
      end

      private

      def authorized?
        # Override this method to implement your authorization logic
        # For development, always allow. In production, check user permissions.
        Rails.env.development? || current_user&.admin?
      end

      def recent_traces_data
        TraceRecord.recent(20).includes(:spans).map do |trace|
          {
            trace_id: trace.trace_id,
            workflow_name: trace.workflow_name,
            status: trace.status,
            started_at: trace.started_at&.iso8601,
            duration_ms: trace.duration_ms,
            span_count: trace.spans.count,
            error_count: trace.spans.errors.count
          }
        end
      end

      def trace_details_data(trace)
        {
          trace_id: trace.trace_id,
          workflow_name: trace.workflow_name,
          status: trace.status,
          started_at: trace.started_at&.iso8601,
          ended_at: trace.ended_at&.iso8601,
          duration_ms: trace.duration_ms,
          metadata: trace.metadata,
          spans: trace.spans.order(:start_time).map do |span|
            {
              span_id: span.span_id,
              name: span.name,
              kind: span.kind,
              status: span.status,
              start_time: span.start_time&.iso8601,
              end_time: span.end_time&.iso8601,
              duration_ms: span.duration_ms,
              attributes: span.attributes,
              parent_span_id: span.parent_span_id
            }
          end
        }
      end

      def dashboard_stats
        {
          total_traces: TraceRecord.count,
          active_traces: TraceRecord.where(status: "running").count,
          error_rate: calculate_error_rate,
          avg_duration: calculate_avg_duration,
          updated_at: Time.current.iso8601
        }
      end

      def performance_metrics
        {
          traces_per_hour: traces_per_hour,
          error_trends: error_trends,
          duration_percentiles: duration_percentiles,
          top_workflows: top_workflows_performance
        }
      end

      def calculate_error_rate
        window = 1.hour.ago..Time.current
        total = TraceRecord.within_timeframe(window.begin, window.end).count
        errors = TraceRecord.within_timeframe(window.begin, window.end).failed.count

        total.positive? ? (errors.to_f / total * 100).round(2) : 0
      end

      def calculate_avg_duration
        TraceRecord.where(started_at: 1.hour.ago..Time.current)
                   .where.not(ended_at: nil)
                   .average("EXTRACT(EPOCH FROM (ended_at - started_at)) * 1000")&.round(2) || 0
      end

      def traces_per_hour
        24.times.map do |hours_ago|
          start_time = hours_ago.hours.ago.beginning_of_hour
          end_time = start_time.end_of_hour

          {
            hour: start_time.strftime("%H:00"),
            count: TraceRecord.within_timeframe(start_time, end_time).count
          }
        end.reverse
      end

      def error_trends
        7.days.ago.to_date.upto(Date.current).map do |date|
          traces = TraceRecord.where(started_at: date.all_day)
          total = traces.count
          errors = traces.failed.count

          {
            date: date.strftime("%Y-%m-%d"),
            total: total,
            errors: errors,
            error_rate: total.positive? ? (errors.to_f / total * 100).round(2) : 0
          }
        end
      end

      def duration_percentiles
        durations = TraceRecord.where(started_at: 24.hours.ago..Time.current)
                               .where.not(ended_at: nil)
                               .pluck("EXTRACT(EPOCH FROM (ended_at - started_at)) * 1000")
                               .sort

        return {} if durations.empty?

        {
          p50: percentile(durations, 50),
          p90: percentile(durations, 90),
          p95: percentile(durations, 95),
          p99: percentile(durations, 99)
        }
      end

      def percentile(sorted_array, percentile)
        return 0 if sorted_array.empty?

        index = (percentile / 100.0 * (sorted_array.length - 1)).round
        sorted_array[index].round(2)
      end

      def top_workflows_performance
        # Get the raw data without ordering first
        workflow_stats = TraceRecord.where(started_at: 24.hours.ago..Time.current)
                                    .select(:workflow_name, :status, :ended_at)
                                    .to_a

        # Process the data in Ruby
        workflow_counts = workflow_stats.each_with_object({}) do |trace, acc|
          workflow = trace.workflow_name
          acc[workflow] ||= { workflow_name: workflow, completed: 0, failed: 0, running: 0 }

          status = if trace.ended_at.nil?
                     :running
                   elsif trace.status == "failed"
                     :failed
                   else
                     :completed
                   end

          acc[workflow][status] += 1
        end

        workflow_counts.values
                       .sort_by { |w| -(w[:completed] + w[:failed] + w[:running]) }
                       .first(10)
      end
    end
  end
end
