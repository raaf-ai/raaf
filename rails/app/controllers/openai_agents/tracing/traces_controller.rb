# frozen_string_literal: true

module RAAF
  module Tracing
    # Controller for managing and viewing traces
    #
    # Provides endpoints for:
    # - Listing traces with filtering and pagination
    # - Viewing individual trace details
    # - Analyzing trace performance
    # - Downloading trace data
    class TracesController < ApplicationController
      before_action :set_trace, only: %i[show spans analytics]

      # GET /traces
      # Lists all traces with filtering options
      def index
        @traces = TraceRecord.includes(:spans)

        # Apply filters
        @traces = filter_traces(@traces)

        # Get summary statistics
        @stats = calculate_summary_stats(@traces)

        # Paginate results
        @page = params[:page]&.to_i || 1
        @per_page = [params[:per_page]&.to_i || 25, 100].min
        @traces = paginate_records(@traces.recent, page: @page, per_page: @per_page)

        # Calculate pagination info
        @total_count = TraceRecord.count
        @total_pages = (@total_count.to_f / @per_page).ceil

        respond_to do |format|
          format.html do
            if request.xhr?
              # For AJAX requests, render just the traces table partial
              render partial: "traces_table", locals: { traces: @traces }, layout: false
            end
          end
          format.json { render json: serialize_traces(@traces) }
        end
      end

      # GET /traces/:id
      # Shows detailed view of a specific trace
      def show
        @spans = @trace.spans.includes(:children).order(:start_time)
        @performance_summary = @trace.performance_summary
        @cost_analysis = @trace.cost_analysis
        @span_hierarchy = @trace.span_hierarchy

        respond_to do |format|
          format.html
          format.json { render json: serialize_trace_detail(@trace) }
        end
      end

      # GET /traces/:id/spans
      # Lists all spans for a trace
      def spans
        @spans = @trace.spans.includes(:children).order(:start_time)

        respond_to do |format|
          format.html { render :show }
          format.json { render json: serialize_spans(@spans) }
        end
      end

      # GET /traces/:id/analytics
      # Shows analytics for a specific trace
      def analytics
        @performance_summary = @trace.performance_summary
        @cost_analysis = @trace.cost_analysis

        # Calculate timing breakdown
        @timing_breakdown = calculate_timing_breakdown(@trace)

        # Error analysis if any errors
        @error_analysis = calculate_error_analysis(@trace) if @trace.status == "failed"

        respond_to do |format|
          format.html
          format.json do
            render json: {
              performance: @performance_summary,
              costs: @cost_analysis,
              timing: @timing_breakdown,
              errors: @error_analysis
            }
          end
        end
      end

      private

      def set_trace
        @trace = TraceRecord.find_by!(trace_id: params[:id])
      rescue ActiveRecord::RecordNotFound
        redirect_to traces_path, alert: "Trace not found. It may have been deleted."
      end

      def filter_traces(traces)
        # Filter by workflow
        traces = traces.by_workflow(params[:workflow]) if params[:workflow].present?

        # Filter by status
        traces = traces.by_status(params[:status]) if params[:status].present?

        # Filter by time range
        if params[:start_time].present? || params[:end_time].present?
          time_range = parse_time_range(params)
          traces = traces.within_timeframe(time_range.begin, time_range.end)
        end

        # Filter by duration
        if params[:min_duration].present?
          min_duration = params[:min_duration].to_f
          traces = traces.where("EXTRACT(EPOCH FROM (ended_at - started_at)) >= ?", min_duration)
        end

        # Search by trace ID
        if params[:search].present?
          search_term = "%#{params[:search]}%"
          traces = traces.where(
            "trace_id ILIKE ? OR workflow_name ILIKE ?",
            search_term, search_term
          )
        end

        traces
      end

      def calculate_summary_stats(traces_relation)
        {
          total: traces_relation.count,
          completed: traces_relation.completed.count,
          failed: traces_relation.failed.count,
          running: traces_relation.running.count,
          avg_duration: traces_relation.where.not(ended_at: nil)
                                       .average("EXTRACT(EPOCH FROM (ended_at - started_at))")
                                       &.round(2)
        }
      end

      def calculate_timing_breakdown(trace)
        spans_by_kind = trace.spans.group_by(&:kind)

        breakdown = {}
        spans_by_kind.each do |kind, spans|
          total_duration = spans.sum(&:duration_ms) || 0
          breakdown[kind] = {
            count: spans.count,
            total_duration_ms: total_duration.round(2),
            avg_duration_ms: spans.any? ? (total_duration / spans.count).round(2) : 0,
            percentage: if trace.duration_ms && trace.duration_ms > 0
                          ((total_duration / trace.duration_ms) * 100).round(1)
                        else
                          0
                        end
          }
        end

        breakdown
      end

      def calculate_error_analysis(trace)
        error_spans = trace.spans.where(status: "error")

        {
          error_count: error_spans.count,
          error_rate: if trace.spans.any?
                        ((error_spans.count.to_f / trace.spans.count) * 100).round(2)
                      else
                        0
                      end,
          errors_by_kind: error_spans.group(:kind).count,
          error_details: error_spans.limit(10).map(&:error_summary)
        }
      end

      def serialize_traces(traces)
        {
          traces: traces.map do |trace|
            {
              trace_id: trace.trace_id,
              workflow_name: trace.workflow_name,
              status: trace.status,
              started_at: trace.started_at,
              ended_at: trace.ended_at,
              duration_ms: trace.duration_ms,
              span_count: trace.spans.count
            }
          end,
          pagination: {
            page: @page,
            per_page: @per_page,
            total_count: @total_count,
            total_pages: @total_pages
          },
          stats: @stats
        }
      end

      def serialize_trace_detail(trace)
        {
          trace: {
            trace_id: trace.trace_id,
            workflow_name: trace.workflow_name,
            group_id: trace.group_id,
            metadata: trace.metadata,
            status: trace.status,
            started_at: trace.started_at,
            ended_at: trace.ended_at,
            duration_ms: trace.duration_ms
          },
          spans: serialize_spans(trace.spans),
          performance: @performance_summary,
          costs: @cost_analysis,
          hierarchy: @span_hierarchy
        }
      end

      def serialize_spans(spans)
        spans.map do |span|
          {
            span_id: span.span_id,
            parent_id: span.parent_id,
            name: span.name,
            kind: span.kind,
            status: span.status,
            start_time: span.start_time,
            end_time: span.end_time,
            duration_ms: span.duration_ms,
            attributes: span.span_attributes,
            events: span.events
          }
        end
      end
    end
  end
end
