# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      # Controller for search functionality across traces and spans
      class SearchController < ApplicationController
        # GET /search
        # Unified search across traces and spans
        def index
          @query = params[:q]&.strip

          # The design prints the query's cost beside its hit count. Measured
          # around the search itself rather than the whole request, so the number
          # is about the query and not about rendering a page of results.
          if @query.present?
            started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            @results = perform_search
            @elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
          end

          respond_to do |format|
            format.html do
              search_component = RAAF::Rails::Tracing::SearchIndex.new(
                query: @query,
                results: @results,
                facets: @facets,
                elapsed_ms: @elapsed_ms,
                params: params.permit(:q, :kind, :status, :workflow, :traces_page, :spans_page)
              )

              render_in_layout search_component, title: "Search"
            end
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
          return {} if @query.blank?

          # Paginate traces (10 per page)
          traces_query = apply_trace_facets(search_traces)
          paginated_traces = traces_query.page(params[:traces_page]).per(10)

          # Facet counts are taken before the facet filters are applied, so
          # choosing "tool" still shows how many llm spans the query matched.
          spans_query = search_spans
          @facets = facet_counts(spans_query)
          spans_query = apply_facets(spans_query)

          # Paginate spans (20 per page)
          paginated_spans = spans_query.page(params[:spans_page]).per(20)

          {
            traces: paginated_traces,
            spans: paginated_spans,
            total_traces: paginated_traces.total_count,
            total_spans: paginated_spans.total_count
          }
        end

        # Counts over the whole match, so a facet describes the result set
        # rather than the page currently on screen. Kind, status and workflow are
        # the three axes the rest of the console already filters by, so a search
        # narrows the same way a listing does.
        #
        # All three come from one grouped query and are folded apart in Ruby.
        # The search predicate is an unindexed ILIKE over casted JSON, so every
        # pass over it costs about a second on this data — three separate facet
        # queries cost three seconds to answer what one can.
        def facet_counts(scope)
          rows = scope.reorder(nil)
                      .left_joins(:trace)
                      .group(:kind, :status, "raaf_tracing_traces.workflow_name")
                      .count

          { kind: tally(rows, 0), status: tally(rows, 1), workflow: tally(rows, 2) }
        rescue StandardError
          { kind: {}, status: {}, workflow: {} }
        end

        # Sums the grouped counts down to one of the three axes. Blank keys are
        # dropped: a span whose trace was pruned has no workflow to offer.
        def tally(rows, index)
          rows.each_with_object(Hash.new(0)) do |(key, count), totals|
            value = Array(key)[index]
            totals[value] += count if value.present?
          end
        end

        def apply_facets(scope)
          scope = scope.where(kind: params[:kind]) if params[:kind].present?
          scope = scope.where(status: params[:status]) if params[:status].present?
          if params[:workflow].present?
            scope = scope.left_joins(:trace).where(raaf_tracing_traces: { workflow_name: params[:workflow] })
          end
          scope
        end

        # The same facets, applied to the trace half of the result set. Without
        # this the traces ignored every filter, and since they are listed first
        # a query matching more than ten of them filled the page whatever you
        # picked — which reads as the facets doing nothing at all.
        #
        # Kind and status are span vocabularies: a trace has no kind, and its
        # statuses are completed/failed rather than the ok/error the facet
        # offers. Narrowing by either is a question about spans, so the traces
        # step aside. Workflow is the one axis both halves share.
        def apply_trace_facets(scope)
          return TraceRecord.none if params[:kind].present? || params[:status].present?

          scope = scope.where(workflow_name: params[:workflow]) if params[:workflow].present?
          scope
        end

        def search_traces
          return TraceRecord.none if @query.blank?

          query = TraceRecord.includes(:spans)

          # Search in trace fields
          search_conditions = []
          search_params = []

          # Trace ID search
          if @query.match?(/\Atrace_[a-f0-9]{32}\z/i)
            search_conditions << "raaf_tracing_traces.trace_id ILIKE ?"
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
          return SpanRecord.none if @query.blank?

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
            search_conditions << "raaf_tracing_spans.trace_id ILIKE ?"
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

          # Attributes search (for PostgreSQL with JSON support). The column is
          # `span_attributes`; `attributes` is Active Record's own method and
          # was never a column, so this clause used to raise on every query.
          if connection_supports_json?
            search_conditions << "span_attributes::text ILIKE ?"
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
end
