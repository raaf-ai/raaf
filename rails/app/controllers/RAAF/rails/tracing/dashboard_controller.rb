# frozen_string_literal: true

require "raaf/cost_manager"

module RAAF
  module Rails
    module Tracing
    # Controller for analytics dashboards and overview pages
    class DashboardController < ApplicationController
      # GET /dashboard
      # Main dashboard with overview metrics
      def index
        @time_range = parse_time_range(params)

        # Overview statistics
        @overview_stats = calculate_overview_stats(@time_range)

        # Top workflows
        @top_workflows = RAAF::Rails::Tracing::TraceRecord.top_workflows(limit: 10, timeframe: @time_range)

        # Recent activity
        @recent_traces = RAAF::Rails::Tracing::TraceRecord.recent.limit(10).includes(:spans)
        @recent_errors = RAAF::Rails::Tracing::SpanRecord.errors.recent.limit(10).includes(:trace)

        # Performance trends (simplified for now)
        @performance_trends = calculate_performance_trends(@time_range)

        respond_to do |format|
          format.html do
            dashboard_component = RAAF::Rails::Tracing::DashboardIndex.new(
              overview_stats: @overview_stats,
              top_workflows: @top_workflows,
              recent_traces: @recent_traces,
              recent_errors: @recent_errors,
              params: params.permit(:start_time, :end_time)
            )

            layout = RAAF::Rails::Tracing::BaseLayout.new(title: "Dashboard") do
              render dashboard_component
            end

            render layout
          end
          format.json do
            render json: {
              overview: @overview_stats,
              workflows: @top_workflows,
              recent_traces: serialize_recent_traces(@recent_traces),
              recent_errors: serialize_recent_errors(@recent_errors),
              trends: @performance_trends
            }
          end
        end
      end

      # GET /dashboard/performance
      # Performance analytics dashboard
      def performance
        @time_range = parse_time_range(params)

        # Performance metrics by span kind
        @performance_by_kind = %w[agent llm tool handoff].to_h do |kind|
          metrics = RAAF::Rails::Tracing::SpanRecord.performance_metrics(kind: kind, timeframe: @time_range)
          [kind, metrics]
        end

        # Slowest operations
        @slowest_spans = RAAF::Rails::Tracing::SpanRecord.slow(1000).within_timeframe(@time_range.begin, @time_range.end)
                                   .includes(:trace)
                                   .order(duration_ms: :desc)
                                   .limit(20)

        # Performance trends over time
        @performance_over_time = calculate_performance_over_time(@time_range)

        respond_to do |format|
          format.html do
            performance_component = RAAF::Rails::Tracing::PerformanceDashboard.new(
              performance_by_kind: @performance_by_kind,
              slowest_spans: @slowest_spans,
              performance_over_time: @performance_over_time,
              params: params.permit(:start_time, :end_time, :kind)
            )

            layout = RAAF::Rails::Tracing::BaseLayout.new(title: "Performance Dashboard") do
              render performance_component
            end

            render layout
          end
          format.json do
            render json: {
              performance_by_kind: @performance_by_kind,
              slowest_spans: serialize_spans(@slowest_spans),
              performance_over_time: @performance_over_time
            }
          end
        end
      end

      # GET /dashboard/costs
      # Cost and usage analytics dashboard
      def costs
        @time_range = parse_time_range(params)

        # Initialize cost manager
        cost_manager = RAAF::Tracing::CostManager.new

        # Overall cost analysis
        @cost_analysis = RAAF::Rails::Tracing::SpanRecord.cost_analysis(timeframe: @time_range)

        # Calculate actual costs using CostManager
        traces = RAAF::Rails::Tracing::TraceRecord.within_timeframe(@time_range.begin, @time_range.end)
        total_cost = 0.0
        total_input_tokens = 0
        total_output_tokens = 0
        total_llm_calls = 0
        model_costs = {}

        traces.includes(:spans).find_each do |trace|
          trace_cost = cost_manager.calculate_trace_cost(trace)
          total_cost += trace_cost[:total_cost]

          # Aggregate costs by model
          trace_cost[:models_used]&.each do |model, data|
            model_costs[model] ||= { cost: 0.0, calls: 0, input_tokens: 0, output_tokens: 0 }
            model_costs[model][:cost] += data[:cost]
            model_costs[model][:calls] += data[:spans]
            model_costs[model][:input_tokens] += data[:input_tokens]
            model_costs[model][:output_tokens] += data[:output_tokens]

            # Aggregate totals
            total_input_tokens += data[:input_tokens]
            total_output_tokens += data[:output_tokens]
            total_llm_calls += data[:spans]
          end
        end

        @total_cost = total_cost
        @model_costs = model_costs

        # Override cost_analysis with actual calculated values if we have data
        if total_llm_calls.positive?
          @cost_analysis[:total_input_tokens] = total_input_tokens
          @cost_analysis[:total_output_tokens] = total_output_tokens
          @cost_analysis[:total_tokens] = total_input_tokens + total_output_tokens
          @cost_analysis[:total_llm_calls] = total_llm_calls
          @cost_analysis[:avg_tokens_per_call] =
            ((total_input_tokens + total_output_tokens).to_f / total_llm_calls).round(2)
        end

        # Cost breakdown by model (with token counts)
        @cost_by_model = calculate_cost_by_model(@time_range)

        # Usage trends over time
        @usage_over_time = calculate_usage_over_time(@time_range)

        # Top consuming workflows
        @top_consuming_workflows = calculate_top_consuming_workflows(@time_range)

        respond_to do |format|
          format.html do
            costs_component = RAAF::Rails::Tracing::CostsIndex.new(
              cost_data: {
                total_cost: @total_cost,
                total_tokens: @cost_analysis[:total_tokens] || 0,
                avg_cost_per_trace: @total_cost / (@cost_analysis[:total_llm_calls] || 1),
                most_expensive_model: @model_costs.max_by { |_, data| data[:cost] }&.first || "N/A",
                by_model: @model_costs.map do |model, data|
                  {
                    model: model,
                    cost: data[:cost],
                    tokens: data[:input_tokens] + data[:output_tokens],
                    percentage: @total_cost > 0 ? ((data[:cost] / @total_cost) * 100).round(2) : 0
                  }
                end.sort_by { |m| -m[:cost] },
                by_workflow: @top_consuming_workflows.map do |workflow, data|
                  {
                    workflow: workflow,
                    cost: data[:total_cost],
                    tokens: data[:total_tokens],
                    percentage: @total_cost > 0 ? ((data[:total_cost] / @total_cost) * 100).round(2) : 0
                  }
                end
              },
              params: params.permit(:start_date, :end_date, :model)
            )

            layout = RAAF::Rails::Tracing::BaseLayout.new(title: "Cost Dashboard") do
              render costs_component
            end

            render layout
          end
          format.json do
            render json: {
              cost_analysis: @cost_analysis,
              cost_by_model: @cost_by_model,
              usage_over_time: @usage_over_time,
              top_workflows: @top_consuming_workflows
            }
          end
        end
      end

      # GET /dashboard/errors
      # Error analysis dashboard
      def errors
        @time_range = parse_time_range(params)

        # Error analysis
        @error_analysis = RAAF::Rails::Tracing::SpanRecord.error_analysis(timeframe: @time_range)

        # Error trends over time
        @error_trends = calculate_error_trends(@time_range)

        # Recent errors with details
        @recent_errors = RAAF::Rails::Tracing::SpanRecord.errors.within_timeframe(@time_range.begin, @time_range.end)
                                   .includes(:trace)
                                   .recent
                                   .limit(50)

        respond_to do |format|
          format.html do
            errors_component = RAAF::Rails::Tracing::ErrorsDashboard.new(
              error_analysis: @error_analysis,
              error_trends: @error_trends,
              recent_errors: @recent_errors,
              params: params.permit(:start_time, :end_time, :severity)
            )

            layout = RAAF::Rails::Tracing::BaseLayout.new(title: "Error Dashboard") do
              render errors_component
            end

            render layout
          end
          format.json do
            render json: {
              error_analysis: @error_analysis,
              error_trends: @error_trends,
              recent_errors: serialize_error_spans(@recent_errors)
            }
          end
        end
      end

      private

      def calculate_overview_stats(time_range)
        traces = RAAF::Rails::Tracing::TraceRecord.within_timeframe(time_range.begin, time_range.end)
        spans = RAAF::Rails::Tracing::SpanRecord.within_timeframe(time_range.begin, time_range.end)

        {
          total_traces: traces.count,
          completed_traces: traces.completed.count,
          failed_traces: traces.failed.count,
          running_traces: traces.running.count,
          total_spans: spans.count,
          error_spans: spans.errors.count,
          avg_trace_duration: traces.where.not(ended_at: nil)
                                    .average("EXTRACT(EPOCH FROM (ended_at - started_at))")
                                    &.round(2),
          success_rate: if traces.any?
                          ((traces.completed.count.to_f / traces.count) * 100).round(2)
                        else
                          0
                        end,
          error_rate: if spans.any?
                        ((spans.errors.count.to_f / spans.count) * 100).round(2)
                      else
                        0
                      end
        }
      end

      def calculate_performance_trends(time_range)
        # Simplified trending - could be enhanced with more sophisticated time series analysis
        hours = ((time_range.end - time_range.begin) / 1.hour).ceil
        bucket_size = [hours / 24, 1].max # At least 1 hour buckets, up to 24 buckets

        buckets = []
        current_time = time_range.begin

        while current_time < time_range.end
          bucket_end = [current_time + bucket_size.hours, time_range.end].min

          traces_in_bucket = RAAF::Rails::Tracing::TraceRecord.within_timeframe(current_time, bucket_end)

          buckets << {
            timestamp: current_time,
            trace_count: traces_in_bucket.count,
            avg_duration: traces_in_bucket.where.not(ended_at: nil)
                                          .average("EXTRACT(EPOCH FROM (ended_at - started_at))")
                                          &.round(2),
            error_count: traces_in_bucket.failed.count
          }

          current_time = bucket_end
        end

        buckets
      end

      def calculate_performance_over_time(time_range)
        # Similar to performance_trends but focused on span performance
        hours = ((time_range.end - time_range.begin) / 1.hour).ceil
        bucket_size = [hours / 24, 1].max

        buckets = []
        current_time = time_range.begin

        while current_time < time_range.end
          bucket_end = [current_time + bucket_size.hours, time_range.end].min

          spans_in_bucket = RAAF::Rails::Tracing::SpanRecord.within_timeframe(current_time, bucket_end)

          buckets << {
            timestamp: current_time,
            span_count: spans_in_bucket.count,
            avg_duration: spans_in_bucket.average(:duration_ms)&.round(2),
            p95_duration: spans_in_bucket.percentile(:duration_ms, 0.95)&.round(2),
            error_count: spans_in_bucket.errors.count
          }

          current_time = bucket_end
        end

        buckets
      end

      def calculate_cost_by_model(time_range)
        llm_spans = RAAF::Rails::Tracing::SpanRecord.by_kind("llm").within_timeframe(time_range.begin, time_range.end)

        model_stats = {}

        llm_spans.find_each do |span|
          model = span.span_attributes.dig("llm", "request", "model")
          next unless model

          input_tokens = span.span_attributes.dig("llm", "usage", "input_tokens").to_i
          output_tokens = span.span_attributes.dig("llm", "usage", "output_tokens").to_i

          model_stats[model] ||= {
            call_count: 0,
            input_tokens: 0,
            output_tokens: 0,
            total_tokens: 0
          }

          model_stats[model][:call_count] += 1
          model_stats[model][:input_tokens] += input_tokens
          model_stats[model][:output_tokens] += output_tokens
          model_stats[model][:total_tokens] += input_tokens + output_tokens
        end

        model_stats
      end

      def calculate_usage_over_time(time_range)
        # Similar bucketing approach for token usage over time
        hours = ((time_range.end - time_range.begin) / 1.hour).ceil
        bucket_size = [hours / 24, 1].max

        buckets = []
        current_time = time_range.begin

        while current_time < time_range.end
          bucket_end = [current_time + bucket_size.hours, time_range.end].min

          llm_spans = RAAF::Rails::Tracing::SpanRecord.by_kind("llm").within_timeframe(current_time, bucket_end)

          total_input_tokens = 0
          total_output_tokens = 0

          llm_spans.find_each do |span|
            total_input_tokens += span.span_attributes.dig("llm", "usage", "input_tokens").to_i
            total_output_tokens += span.span_attributes.dig("llm", "usage", "output_tokens").to_i
          end

          buckets << {
            timestamp: current_time,
            llm_calls: llm_spans.count,
            input_tokens: total_input_tokens,
            output_tokens: total_output_tokens,
            total_tokens: total_input_tokens + total_output_tokens
          }

          current_time = bucket_end
        end

        buckets
      end

      def calculate_top_consuming_workflows(time_range)
        traces = RAAF::Rails::Tracing::TraceRecord.within_timeframe(time_range.begin, time_range.end)
        cost_manager = RAAF::Tracing::CostManager.new

        workflow_usage = {}

        traces.includes(:spans).find_each do |trace|
          llm_spans = trace.spans.select { |s| s.kind == "llm" }

          total_tokens = llm_spans.sum do |span|
            input_tokens = span.span_attributes.dig("llm", "usage", "input_tokens").to_i
            output_tokens = span.span_attributes.dig("llm", "usage", "output_tokens").to_i
            input_tokens + output_tokens
          end

          # Calculate cost for this trace
          trace_cost = cost_manager.calculate_trace_cost(trace)

          workflow_usage[trace.workflow_name] ||= {
            trace_count: 0,
            total_tokens: 0,
            llm_calls: 0,
            total_cost: 0.0
          }

          workflow_usage[trace.workflow_name][:trace_count] += 1
          workflow_usage[trace.workflow_name][:total_tokens] += total_tokens
          workflow_usage[trace.workflow_name][:llm_calls] += llm_spans.count
          workflow_usage[trace.workflow_name][:total_cost] += trace_cost[:total_cost]
        end

        # Sort by total tokens descending
        workflow_usage.sort_by { |_, stats| -stats[:total_tokens] }.first(10).to_h
      end

      def calculate_error_trends(time_range)
        hours = ((time_range.end - time_range.begin) / 1.hour).ceil
        bucket_size = [hours / 24, 1].max

        buckets = []
        current_time = time_range.begin

        while current_time < time_range.end
          bucket_end = [current_time + bucket_size.hours, time_range.end].min

          spans_in_bucket = RAAF::Rails::Tracing::SpanRecord.within_timeframe(current_time, bucket_end)
          error_spans = spans_in_bucket.errors

          buckets << {
            timestamp: current_time,
            total_spans: spans_in_bucket.count,
            error_spans: error_spans.count,
            error_rate: if spans_in_bucket.any?
                          ((error_spans.count.to_f / spans_in_bucket.count) * 100).round(2)
                        else
                          0
                        end
          }

          current_time = bucket_end
        end

        buckets
      end

      def serialize_recent_traces(traces)
        traces.map do |trace|
          {
            trace_id: trace.trace_id,
            workflow_name: trace.workflow_name,
            status: trace.status,
            started_at: trace.started_at,
            duration_ms: trace.duration_ms,
            span_count: trace.spans.count
          }
        end
      end

      def serialize_recent_errors(spans)
        spans.map do |span|
          {
            span_id: span.span_id,
            trace_id: span.trace_id,
            name: span.name,
            kind: span.kind,
            start_time: span.start_time,
            workflow_name: span.trace&.workflow_name,
            error_details: span.error_details
          }
        end
      end

      def serialize_error_spans(spans)
        spans.map do |span|
          {
            span_id: span.span_id,
            trace_id: span.trace_id,
            name: span.name,
            kind: span.kind,
            start_time: span.start_time,
            duration_ms: span.duration_ms,
            workflow_name: span.trace&.workflow_name,
            error_details: span.error_details
          }
        end
      end
    end
  end
      end
end
