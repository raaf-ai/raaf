# frozen_string_literal: true

module RAAF
  module Tracing
    # rubocop:disable Metrics/ClassLength
    class TimelineController < ApplicationController
      before_action :set_trace, only: %i[show gantt_data timeline_data]

      def show
        @spans = @trace.spans.includes(:trace).order(:start_time)
        @timeline_data = generate_timeline_data(@spans)
        @gantt_data = generate_gantt_data(@spans)
        @performance_stats = calculate_performance_stats(@spans)

        respond_to do |format|
          format.html
          format.json { render json: { timeline: @timeline_data, gantt: @gantt_data, stats: @performance_stats } }
        end
      end

      def gantt_data
        spans = @trace.spans.includes(:trace).order(:start_time)
        gantt_data = generate_gantt_data(spans)

        render json: gantt_data
      end

      def timeline_data
        spans = @trace.spans.includes(:trace).order(:start_time)
        timeline_data = generate_timeline_data(spans)

        render json: timeline_data
      end

      def compare
        @trace_ids = params[:trace_ids]&.split(",") || []
        @traces = TraceRecord.where(trace_id: @trace_ids).includes(:spans)

        comparison_data = generate_comparison_data(@traces)

        respond_to do |format|
          format.html { @comparison_data = comparison_data }
          format.json { render json: comparison_data }
        end
      end

      def critical_path
        @trace = TraceRecord.find_by!(trace_id: params[:trace_id])
        spans = @trace.spans.includes(:trace).order(:start_time)

        critical_path_data = calculate_critical_path(spans)

        respond_to do |format|
          format.html { @critical_path_data = critical_path_data }
          format.json { render json: critical_path_data }
        end
      end

      def performance_analysis
        @trace = TraceRecord.find_by!(trace_id: params[:trace_id])
        spans = @trace.spans.includes(:trace)

        analysis = {
          trace_overview: trace_overview(@trace),
          span_analysis: analyze_spans(spans),
          bottlenecks: identify_bottlenecks(spans),
          recommendations: generate_recommendations(spans),
          concurrency_analysis: analyze_concurrency(spans)
        }

        respond_to do |format|
          format.html { @analysis = analysis }
          format.json { render json: analysis }
        end
      end

      private

      def set_trace
        @trace = TraceRecord.find_by!(trace_id: params[:trace_id])
      end

      def generate_timeline_data(spans)
        return [] if spans.empty?

        trace_start = spans.minimum(:start_time)
        trace_end = spans.maximum(:end_time) || spans.maximum(:start_time)
        total_duration = ((trace_end - trace_start) * 1000).to_i # Convert to milliseconds

        timeline_items = []

        spans.each do |span|
          next unless span.start_time

          start_offset = ((span.start_time - trace_start) * 1000).to_i
          duration = span.duration_ms || 0
          start_offset + duration

          timeline_items << {
            id: span.span_id,
            name: span.name,
            kind: span.kind,
            status: span.status,
            start_time: span.start_time.iso8601(3),
            end_time: span.end_time&.iso8601(3),
            start_offset_ms: start_offset,
            duration_ms: duration,
            parent_span_id: span.parent_span_id,
            depth: calculate_span_depth(span, spans),
            percentage_start: (start_offset.to_f / total_duration * 100).round(2),
            percentage_width: duration.positive? ? (duration.to_f / total_duration * 100).round(2) : 0.1,
            attributes: sanitize_attributes(span.span_attributes),
            error_details: span.status == "error" ? extract_error_details(span) : nil
          }
        end

        {
          trace_id: @trace.trace_id,
          workflow_name: @trace.workflow_name,
          total_duration_ms: total_duration,
          trace_start: trace_start.iso8601(3),
          trace_end: trace_end.iso8601(3),
          span_count: spans.count,
          items: timeline_items.sort_by { |item| [item[:start_offset_ms], item[:depth]] }
        }
      end

      def generate_gantt_data(spans)
        return { tasks: [], links: [] } if spans.empty?

        spans.minimum(:start_time)

        tasks = []
        links = []

        spans.each_with_index do |span, _index|
          next unless span.start_time

          start_date = span.start_time
          end_date = span.end_time || span.start_time
          duration_hours = [(end_date - start_date) / 1.hour, 0.01].max # Minimum 0.01 hours for visibility

          # Determine task type and color based on span kind
          task_type = determine_task_type(span)
          color = determine_task_color(span)

          task = {
            id: span.span_id,
            text: span.name,
            start_date: start_date.strftime("%Y-%m-%d %H:%M:%S"),
            end_date: end_date.strftime("%Y-%m-%d %H:%M:%S"),
            duration: duration_hours.round(3),
            progress: if span.status == "ok"
                        1.0
                      else
                        (span.status == "error" ? 0.0 : 0.5)
                      end,
            type: task_type,
            color: color,
            parent: span.parent_span_id,
            span_kind: span.kind,
            span_status: span.status,
            details: {
              span_id: span.span_id,
              kind: span.kind,
              status: span.status,
              duration_ms: span.duration_ms,
              attributes: sanitize_attributes(span.span_attributes),
              error_details: span.status == "error" ? extract_error_details(span) : nil
            }
          }

          tasks << task

          # Create dependency links
          next unless span.parent_span_id

          links << {
            id: "#{span.parent_span_id}_#{span.span_id}",
            source: span.parent_span_id,
            target: span.span_id,
            type: "finish_to_start"
          }
        end

        {
          tasks: tasks,
          links: links,
          trace_info: {
            trace_id: @trace.trace_id,
            workflow_name: @trace.workflow_name,
            total_duration_ms: @trace.duration_ms,
            status: @trace.status
          }
        }
      end

      def generate_comparison_data(traces)
        return { traces: [], comparison: {} } if traces.empty?

        comparison_data = {
          traces: [],
          comparison: {
            duration_comparison: {},
            span_count_comparison: {},
            error_rate_comparison: {},
            performance_diff: {}
          }
        }

        traces.each do |trace|
          spans = trace.spans.order(:start_time)

          trace_data = {
            trace_id: trace.trace_id,
            workflow_name: trace.workflow_name,
            status: trace.status,
            duration_ms: trace.duration_ms,
            span_count: spans.count,
            timeline: generate_timeline_data(spans),
            performance_stats: calculate_performance_stats(spans)
          }

          comparison_data[:traces] << trace_data
        end

        # Generate comparison metrics
        comparison_data[:comparison] = compare_trace_metrics(comparison_data[:traces]) if traces.size >= 2

        comparison_data
      end

      def calculate_critical_path(spans)
        # Build dependency graph
        span_map = spans.index_by(&:span_id)

        # Calculate the critical path through the trace
        root_spans = spans.select { |s| s.parent_span_id.nil? }
        critical_path = []

        root_spans.each do |root_span|
          path = find_longest_path(root_span, span_map)
          critical_path = path if path.sum { |s| s.duration_ms || 0 } > critical_path.sum { |s| s.duration_ms || 0 }
        end

        {
          critical_path: critical_path.map do |span|
            {
              span_id: span.span_id,
              name: span.name,
              kind: span.kind,
              duration_ms: span.duration_ms,
              start_time: span.start_time&.iso8601(3),
              cumulative_time: critical_path[0..critical_path.index(span)].sum { |s| s.duration_ms || 0 }
            }
          end,
          total_critical_time: critical_path.sum { |s| s.duration_ms || 0 },
          critical_path_percentage: if critical_path.any?
                                      (critical_path.sum do |s|
                                        s.duration_ms || 0
                                      end.to_f / @trace.duration_ms * 100).round(2)
                                    else
                                      0
                                    end,
          bottleneck_spans: identify_bottleneck_spans(critical_path)
        }
      end

      def calculate_performance_stats(spans)
        return {} if spans.empty?

        durations = spans.filter_map(&:duration_ms)

        stats = {
          total_spans: spans.count,
          completed_spans: spans.count { |s| s.status == "ok" },
          error_spans: spans.count { |s| s.status == "error" },
          avg_duration_ms: durations.empty? ? 0 : (durations.sum.to_f / durations.size).round(2),
          median_duration_ms: durations.empty? ? 0 : calculate_median(durations),
          p95_duration_ms: durations.empty? ? 0 : calculate_percentile(durations, 95),
          p99_duration_ms: durations.empty? ? 0 : calculate_percentile(durations, 99),
          max_duration_ms: durations.max || 0,
          min_duration_ms: durations.min || 0
        }

        # Breakdown by span kind
        stats[:by_kind] = spans.group_by(&:kind).transform_values do |kind_spans|
          kind_durations = kind_spans.filter_map(&:duration_ms)
          {
            count: kind_spans.size,
            avg_duration_ms: kind_durations.empty? ? 0 : (kind_durations.sum.to_f / kind_durations.size).round(2),
            total_duration_ms: kind_durations.sum,
            error_count: kind_spans.count { |s| s.status == "error" }
          }
        end

        # Concurrency analysis
        stats[:concurrency] = analyze_span_concurrency(spans)

        stats
      end

      def calculate_span_depth(span, spans)
        depth = 0
        current_parent = span.parent_span_id

        while current_parent
          depth += 1
          parent_span = spans.find { |s| s.span_id == current_parent }
          break unless parent_span

          current_parent = parent_span.parent_span_id

          # Prevent infinite loops
          break if depth > 50
        end

        depth
      end

      def determine_task_type(span)
        case span.kind
        when "agent", "trace"
          "project"
        when "llm"
          "task"
        when "tool"
          "milestone"
        else
          "task"
        end
      end

      def determine_task_color(span)
        case span.status
        when "ok"
          case span.kind
          when "agent", "trace" then "#28a745"
          when "llm" then "#007bff"
          when "tool" then "#17a2b8"
          else "#6c757d"
          end
        when "error"
          "#dc3545"
        when "running", "in_progress"
          "#ffc107"
        else
          "#6c757d"
        end
      end

      def sanitize_attributes(attributes)
        return {} unless attributes.is_a?(Hash)

        # Limit and sanitize attributes for frontend display
        sanitized = {}
        attributes.each do |key, value|
          next if sanitized.size >= 20 # Limit number of attributes

          sanitized_key = key.to_s.gsub(/[^\w\.]/, "_")[0..50] # Sanitize key

          case value
          when String
            sanitized[sanitized_key] = value.length > 200 ? "#{value[0..197]}..." : value
          when Numeric, TrueClass, FalseClass, NilClass
            sanitized[sanitized_key] = value
          when Hash
            sanitized[sanitized_key] = if value.keys.length > 5
                                         "Hash with #{value.keys.length} keys"
                                       else
                                         value.transform_values do |v|
                                           v.to_s.length > 100 ? "#{v.to_s[0..97]}..." : v.to_s
                                         end
                                       end
          when Array
            sanitized[sanitized_key] = if value.length > 10
                                         "Array with #{value.length} items"
                                       else
                                         value.map { |v| v.to_s.length > 50 ? "#{v.to_s[0..47]}..." : v.to_s }
                                       end
          else
            sanitized[sanitized_key] = value.to_s[0..100]
          end
        end

        sanitized
      end

      def extract_error_details(span)
        return nil unless span.status == "error"

        attributes = span.span_attributes || {}

        {
          error_type: attributes["error.type"] || "Unknown",
          error_message: attributes["error.message"] || "No message available",
          error_stack: attributes["error.stack_trace"]&.split("\n")&.first(5) || [],
          error_code: attributes["error.code"]
        }
      end

      def trace_overview(trace)
        {
          trace_id: trace.trace_id,
          workflow_name: trace.workflow_name,
          status: trace.status,
          duration_ms: trace.duration_ms,
          started_at: trace.started_at&.iso8601(3),
          ended_at: trace.ended_at&.iso8601(3),
          span_count: trace.spans.count,
          metadata: trace.metadata
        }
      end

      def analyze_spans(spans)
        {
          total_spans: spans.count,
          by_status: spans.group_by(&:status).transform_values(&:count),
          by_kind: spans.group_by(&:kind).transform_values(&:count),
          duration_stats: calculate_span_duration_stats(spans),
          slowest_spans: find_slowest_spans(spans, 5),
          error_spans: find_error_spans(spans)
        }
      end

      def identify_bottlenecks(spans)
        bottlenecks = []

        # Find spans that take more than 20% of total trace time
        total_duration = @trace.duration_ms || 0
        return bottlenecks if total_duration.zero?

        spans.each do |span|
          span_duration = span.duration_ms || 0
          percentage = (span_duration.to_f / total_duration) * 100

          next unless percentage > 20

          bottlenecks << {
            span_id: span.span_id,
            name: span.name,
            kind: span.kind,
            duration_ms: span_duration,
            percentage: percentage.round(2),
            impact: percentage > 50 ? "critical" : "major"
          }
        end

        # Sort by impact
        bottlenecks.sort_by { |b| -b[:percentage] }
      end

      def generate_recommendations(spans)
        recommendations = []

        # Check for excessive LLM calls
        llm_spans = spans.select { |s| s.kind == "llm" }
        if llm_spans.count > 10
          recommendations << {
            type: "optimization",
            priority: "medium",
            title: "Consider batching LLM calls",
            description: "This trace has #{llm_spans.count} LLM calls. Consider batching similar requests."
          }
        end

        # Check for long-running operations
        slow_spans = spans.select { |s| (s.duration_ms || 0) > 5000 }
        if slow_spans.any?
          recommendations << {
            type: "performance",
            priority: "high",
            title: "Optimize slow operations",
            description: "#{slow_spans.count} spans took longer than 5 seconds."
          }
        end

        # Check error rate
        error_rate = (spans.count { |s| s.status == "error" }.to_f / spans.count) * 100
        if error_rate > 10
          recommendations << {
            type: "reliability",
            priority: "high",
            title: "High error rate detected",
            description: "#{error_rate.round(1)}% of spans failed. Review error handling."
          }
        end

        recommendations
      end

      def analyze_concurrency(spans)
        return {} if spans.empty?

        # Group spans by time windows to analyze concurrency
        time_windows = {}

        spans.each do |span|
          next unless span.start_time

          start_window = (span.start_time.to_f / 1.0).floor # 1-second windows
          end_time = span.end_time || span.start_time
          end_window = (end_time.to_f / 1.0).floor

          (start_window..end_window).each do |window|
            time_windows[window] ||= []
            time_windows[window] << span
          end
        end

        max_concurrency = time_windows.values.map(&:count).max || 0
        avg_concurrency = time_windows.values.map(&:count).sum.to_f / time_windows.count if time_windows.any?

        {
          max_concurrent_spans: max_concurrency,
          avg_concurrent_spans: avg_concurrency&.round(2) || 0,
          total_time_windows: time_windows.count,
          concurrency_distribution: time_windows.values.map(&:count).tally
        }
      end

      def analyze_span_concurrency(spans)
        analyze_concurrency(spans)
      end

      def calculate_median(values)
        sorted = values.sort
        len = sorted.length
        len.even? ? (sorted[(len / 2) - 1] + sorted[len / 2]) / 2.0 : sorted[len / 2]
      end

      def calculate_percentile(values, percentile)
        sorted = values.sort
        index = (percentile / 100.0 * (sorted.length - 1)).round
        sorted[index]
      end

      def find_longest_path(span, span_map, visited = Set.new)
        return [span] if visited.include?(span.span_id)

        visited.add(span.span_id)

        children = span_map.values.select { |s| s.parent_span_id == span.span_id }

        if children.empty?
          [span]
        else
          longest_child_path = children.map do |child|
            find_longest_path(child, span_map, visited.dup)
          end
          .max_by { |path| path.sum { |s| s.duration_ms || 0 } }

          [span] + longest_child_path
        end
      end

      def identify_bottleneck_spans(critical_path)
        return [] if critical_path.empty?

        total_time = critical_path.sum { |s| s.duration_ms || 0 }

        critical_path.select do |span|
          span_time = span.duration_ms || 0
          (span_time.to_f / total_time) > 0.3 # More than 30% of critical path time
        end
        .map do |span|
          {
            span_id: span.span_id,
            name: span.name,
            duration_ms: span.duration_ms,
            percentage_of_critical_path: ((span.duration_ms.to_f / total_time) * 100).round(2)
          }
        end
      end

      def compare_trace_metrics(trace_data)
        return {} if trace_data.size < 2

        base_trace = trace_data.first
        comparison_trace = trace_data.last

        {
          duration_diff: {
            base: base_trace[:duration_ms],
            comparison: comparison_trace[:duration_ms],
            difference_ms: comparison_trace[:duration_ms] - base_trace[:duration_ms],
            percentage_change: (((comparison_trace[:duration_ms].to_f / base_trace[:duration_ms]) - 1) * 100).round(2)
          },
          span_count_diff: {
            base: base_trace[:span_count],
            comparison: comparison_trace[:span_count],
            difference: comparison_trace[:span_count] - base_trace[:span_count]
          }
        }
      end

      def calculate_span_duration_stats(spans)
        durations = spans.filter_map(&:duration_ms)
        return {} if durations.empty?

        {
          min: durations.min,
          max: durations.max,
          avg: (durations.sum.to_f / durations.size).round(2),
          median: calculate_median(durations),
          p90: calculate_percentile(durations, 90),
          p95: calculate_percentile(durations, 95)
        }
      end

      def find_slowest_spans(spans, limit = 5)
        spans.select(&:duration_ms)
             .sort_by { |s| -s.duration_ms }
             .first(limit)
             .map do |span|
               {
                 span_id: span.span_id,
                 name: span.name,
                 kind: span.kind,
                 duration_ms: span.duration_ms
               }
             end
      end

      def find_error_spans(spans)
        spans.select { |s| s.status == "error" }
             .map do |span|
               {
                 span_id: span.span_id,
                 name: span.name,
                 kind: span.kind,
                 error_details: extract_error_details(span)
               }
             end
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
