# frozen_string_literal: true

module RubyAIAgentsFactory
  module Tracing
    # Controller for search functionality across traces and spans
    class SearchController < ApplicationController
      # GET /search
      # Unified search across traces and spans
      def index
        @query = params[:q]&.strip
        @results = perform_search if @query.present?

        respond_to do |format|
          format.html
          format.json { render json: serialize_search_results(@results) }
        end
      end

      # GET /search/traces
      # Search specifically in traces
      def traces
        @query = params[:q]&.strip
        @traces = search_traces if @query.present?

        respond_to do |format|
          format.html { render :index }
          format.json { render json: serialize_trace_results(@traces) }
        end
      end

      # GET /search/spans
      # Search specifically in spans
      def spans
        @query = params[:q]&.strip
        @spans = search_spans if @query.present?

        respond_to do |format|
          format.html { render :index }
          format.json { render json: serialize_span_results(@spans) }
        end
      end

      private

      def perform_search
        return {} unless @query.present?

        {
          traces: search_traces.limit(10),
          spans: search_spans.limit(20),
          total_traces: search_traces.count,
          total_spans: search_spans.count
        }
      end

      def search_traces
        return TraceRecord.none unless @query.present?

        query = TraceRecord.includes(:spans)

        # Search in trace fields
        search_conditions = []
        search_params = []

        # Trace ID search
        if @query.match?(/\Atrace_[a-f0-9]{32}\z/i)
          search_conditions << "trace_id ILIKE ?"
          search_params << @query
        end

        # Workflow name search
        search_conditions << "workflow_name ILIKE ?"
        search_params << "%#{@query}%"

        # Group ID search
        search_conditions << "group_id ILIKE ?"
        search_params << "%#{@query}%"

        # Metadata search (for PostgreSQL with JSON support)
        if connection_supports_json?
          search_conditions << "metadata::text ILIKE ?"
          search_params << "%#{@query}%"
        end

        query.where(search_conditions.join(" OR "), *search_params)
             .order(started_at: :desc)
      end

      def search_spans
        return SpanRecord.none unless @query.present?

        query = SpanRecord.includes(:trace)

        search_conditions = []
        search_params = []

        # Span ID search
        if @query.match?(/\Aspan_[a-f0-9]{24}\z/i)
          search_conditions << "span_id ILIKE ?"
          search_params << @query
        end

        # Trace ID search
        if @query.match?(/\Atrace_[a-f0-9]{32}\z/i)
          search_conditions << "trace_id ILIKE ?"
          search_params << @query
        end

        # Name search
        search_conditions << "name ILIKE ?"
        search_params << "%#{@query}%"

        # Kind search
        if valid_span_kind?(@query)
          search_conditions << "kind = ?"
          search_params << @query.downcase
        end

        # Status search
        if valid_span_status?(@query)
          search_conditions << "status = ?"
          search_params << @query.downcase
        end

        # Attributes search (for PostgreSQL with JSON support)
        if connection_supports_json?
          search_conditions << "attributes::text ILIKE ?"
          search_params << "%#{@query}%"
        end

        # Events search (for PostgreSQL with JSON support)
        if connection_supports_json?
          search_conditions << "events::text ILIKE ?"
          search_params << "%#{@query}%"
        end

        query.where(search_conditions.join(" OR "), *search_params)
             .order(start_time: :desc)
      end

      def connection_supports_json?
        ActiveRecord::Base.connection.adapter_name.downcase.include?("postgresql")
      end

      def valid_span_kind?(kind)
        %w[agent llm tool handoff guardrail mcp_list_tools response
           speech_group speech transcription custom internal trace].include?(kind.downcase)
      end

      def valid_span_status?(status)
        %w[ok error cancelled].include?(status.downcase)
      end

      def serialize_search_results(results)
        return {} unless results

        {
          query: @query,
          traces: {
            results: results[:traces].map do |trace|
              {
                trace_id: trace.trace_id,
                workflow_name: trace.workflow_name,
                status: trace.status,
                started_at: trace.started_at,
                duration_ms: trace.duration_ms,
                span_count: trace.spans.count
              }
            end,
            total: results[:total_traces]
          },
          spans: {
            results: results[:spans].map do |span|
              {
                span_id: span.span_id,
                trace_id: span.trace_id,
                name: span.name,
                kind: span.kind,
                status: span.status,
                start_time: span.start_time,
                duration_ms: span.duration_ms,
                workflow_name: span.trace&.workflow_name
              }
            end,
            total: results[:total_spans]
          }
        }
      end

      def serialize_trace_results(traces)
        return {} unless traces

        {
          query: @query,
          traces: traces.map do |trace|
            {
              trace_id: trace.trace_id,
              workflow_name: trace.workflow_name,
              group_id: trace.group_id,
              metadata: trace.metadata,
              status: trace.status,
              started_at: trace.started_at,
              ended_at: trace.ended_at,
              duration_ms: trace.duration_ms,
              span_count: trace.spans.count
            }
          end,
          total: traces.count
        }
      end

      def serialize_span_results(spans)
        return {} unless spans

        {
          query: @query,
          spans: spans.map do |span|
            {
              span_id: span.span_id,
              trace_id: span.trace_id,
              parent_id: span.parent_id,
              name: span.name,
              kind: span.kind,
              status: span.status,
              start_time: span.start_time,
              end_time: span.end_time,
              duration_ms: span.duration_ms,
              workflow_name: span.trace&.workflow_name
            }
          end,
          total: spans.count
        }
      end
    end
  end
end
