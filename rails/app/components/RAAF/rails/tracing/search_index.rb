# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      class SearchIndex < BaseComponent
        def initialize(query: nil, results: nil, params: {})
          @query = query
          @results = results
          @params = params
        end

        def view_template
          div(class: "p-6") do
            render_header
            render_search_form
            render_search_results if @results
          end
        end

        private

        def render_header
          div(class: "sm:flex sm:items-center sm:justify-between mb-6") do
            div(class: "min-w-0 flex-1") do
              h1(class: "text-2xl font-bold leading-7 text-gray-900 sm:text-3xl sm:truncate") { "Search" }
              p(class: "mt-1 text-sm text-gray-500") { "Search across traces, spans, and execution data" }
            end
          end
        end

        def render_search_form
          div(class: "bg-white p-6 rounded-lg shadow mb-6") do
            form_with(url: "/raaf/tracing/search", method: :get, local: true, class: "space-y-4") do |form|
              div(class: "flex space-x-4") do
                div(class: "flex-1") do
                  label(class: "block text-sm font-medium text-gray-700 mb-2") { "Search Query" }
                  form.text_field(
                    :q,
                    placeholder: "Search traces, spans, IDs, workflow names...",
                    value: @query,
                    class: "block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 text-lg py-3"
                  )

                  div(class: "mt-2 text-sm text-gray-500") do
                    plain "Search tips: Use trace IDs (trace_...), span IDs (span_...), workflow names, or any text content"
                  end
                end

                div(class: "flex-shrink-0 flex items-end") do
                  form.submit(
                    "Search",
                    class: "inline-flex items-center px-6 py-3 border border-transparent text-base font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
                  )
                end
              end
            end
          end
        end

        def render_search_results
          if @query.present?
            div(class: "space-y-6") do
              render_results_summary

              if @results[:traces].any?
                render_trace_results
              end

              if @results[:spans].any?
                render_span_results
              end

              if @results[:traces].empty? && @results[:spans].empty?
                render_no_results
              end
            end
          end
        end

        def render_results_summary
          div(class: "bg-blue-50 border border-blue-200 rounded-lg p-4") do
            div(class: "flex") do
              div(class: "flex-shrink-0") do
                i(class: "bi bi-info-circle text-blue-400")
              end
              div(class: "ml-3") do
                h3(class: "text-sm font-medium text-blue-800") do
                  "Search Results for \"#{@query}\""
                end
                div(class: "mt-2 text-sm text-blue-700") do
                  plain "Found "
                  span(class: "font-semibold") { @results[:total_traces].to_s }
                  plain " traces and "
                  span(class: "font-semibold") { @results[:total_spans].to_s }
                  plain " spans"
                end
              end
            end
          end
        end

        def render_trace_results
          traces = @results[:traces]

          div(class: "bg-white rounded-lg shadow") do
            div(class: "px-6 py-4 border-b border-gray-200") do
              div(class: "flex items-center justify-between") do
                h3(class: "text-lg font-medium text-gray-900") do
                  "Traces ("
                  span(class: "text-blue-600") { @results[:total_traces].to_s }
                  plain ")"
                end

                if traces.total_pages > 1
                  span(class: "text-sm text-gray-500") do
                    "Page #{traces.current_page} of #{traces.total_pages}"
                  end
                end
              end
            end

            div(class: "divide-y divide-gray-200") do
              traces.each do |trace|
                render_trace_result(trace)
              end
            end

            render_traces_pagination if traces.total_pages > 1
          end
        end

        def render_traces_pagination
          traces = @results[:traces]

          div(class: "px-6 py-4 bg-gray-50 border-t border-gray-200") do
            div(class: "flex items-center justify-between") do
              div(class: "text-sm text-gray-700") do
                plain "Showing "
                span(class: "font-medium") { ((traces.current_page - 1) * traces.limit_value + 1).to_s }
                plain " to "
                span(class: "font-medium") { [traces.current_page * traces.limit_value, traces.total_count].min.to_s }
                plain " of "
                span(class: "font-medium") { traces.total_count.to_s }
                plain " traces"
              end

              div(class: "flex space-x-2") do
                unless traces.first_page?
                  link_to(
                    "Previous",
                    "/raaf/tracing/search?q=#{@query}&traces_page=#{traces.prev_page}&spans_page=#{@params[:spans_page]}",
                    class: "px-3 py-1 border border-gray-300 rounded-md text-sm font-medium text-gray-700 bg-white hover:bg-gray-50"
                  )
                end

                unless traces.last_page?
                  link_to(
                    "Next",
                    "/raaf/tracing/search?q=#{@query}&traces_page=#{traces.next_page}&spans_page=#{@params[:spans_page]}",
                    class: "px-3 py-1 border border-gray-300 rounded-md text-sm font-medium text-gray-700 bg-white hover:bg-gray-50"
                  )
                end
              end
            end
          end
        end

        def render_trace_result(trace)
          div(class: "px-6 py-4 hover:bg-gray-50") do
            div(class: "flex items-center justify-between") do
              div(class: "flex-1 min-w-0") do
                div(class: "flex items-center space-x-3") do
                  render_status_badge(trace.status)

                  div do
                    div(class: "text-sm font-medium text-gray-900") do
                      link_to(
                        trace.workflow_name || "Unnamed Workflow",
                        "/raaf/tracing/traces/#{trace.trace_id}",
                        class: "text-blue-600 hover:text-blue-500"
                      )
                    end
                    div(class: "text-sm text-gray-500 font-mono") { trace.trace_id }
                  end
                end

                div(class: "mt-2 flex items-center text-sm text-gray-500 space-x-4") do
                  span do
                    plain "Duration: #{format_duration(trace.duration_ms)}"
                  end
                  span do
                    plain "Spans: #{trace.spans.count}"
                  end
                  span do
                    plain "Started: #{trace.started_at&.strftime('%Y-%m-%d %H:%M:%S')}"
                  end
                end
              end
            end
          end
        end

        def render_span_results
          spans = @results[:spans]

          div(class: "bg-white rounded-lg shadow") do
            div(class: "px-6 py-4 border-b border-gray-200") do
              div(class: "flex items-center justify-between") do
                h3(class: "text-lg font-medium text-gray-900") do
                  "Spans ("
                  span(class: "text-blue-600") { @results[:total_spans].to_s }
                  plain ")"
                end

                if spans.total_pages > 1
                  span(class: "text-sm text-gray-500") do
                    "Page #{spans.current_page} of #{spans.total_pages}"
                  end
                end
              end
            end

            div(class: "divide-y divide-gray-200") do
              spans.each do |span|
                render_span_result(span)
              end
            end

            render_spans_pagination if spans.total_pages > 1
          end
        end

        def render_spans_pagination
          spans = @results[:spans]

          div(class: "px-6 py-4 bg-gray-50 border-t border-gray-200") do
            div(class: "flex items-center justify-between") do
              div(class: "text-sm text-gray-700") do
                plain "Showing "
                span(class: "font-medium") { ((spans.current_page - 1) * spans.limit_value + 1).to_s }
                plain " to "
                span(class: "font-medium") { [spans.current_page * spans.limit_value, spans.total_count].min.to_s }
                plain " of "
                span(class: "font-medium") { spans.total_count.to_s }
                plain " spans"
              end

              div(class: "flex space-x-2") do
                unless spans.first_page?
                  link_to(
                    "Previous",
                    "/raaf/tracing/search?q=#{@query}&traces_page=#{@params[:traces_page]}&spans_page=#{spans.prev_page}",
                    class: "px-3 py-1 border border-gray-300 rounded-md text-sm font-medium text-gray-700 bg-white hover:bg-gray-50"
                  )
                end

                unless spans.last_page?
                  link_to(
                    "Next",
                    "/raaf/tracing/search?q=#{@query}&traces_page=#{@params[:traces_page]}&spans_page=#{spans.next_page}",
                    class: "px-3 py-1 border border-gray-300 rounded-md text-sm font-medium text-gray-700 bg-white hover:bg-gray-50"
                  )
                end
              end
            end
          end
        end

        def render_span_result(span_record)
          div(class: "px-6 py-4 hover:bg-gray-50") do
            div(class: "flex items-center justify-between") do
              div(class: "flex-1 min-w-0") do
                div(class: "flex items-center space-x-3") do
                  render_kind_badge(span_record.kind)
                  render_status_badge(span_record.status)

                  div do
                    div(class: "text-sm font-medium text-gray-900") do
                      link_to(
                        span_record.name,
                        "/raaf/tracing/spans/#{span_record.span_id}",
                        class: "text-blue-600 hover:text-blue-500"
                      )
                    end
                    div(class: "text-sm text-gray-500 font-mono") { span_record.span_id }
                  end
                end

                div(class: "mt-2 flex items-center text-sm text-gray-500 space-x-4") do
                  span do
                    plain "Duration: #{format_duration(span_record.duration_ms)}"
                  end
                  if span_record.trace&.workflow_name
                    span do
                      plain "Workflow: "
                      link_to(
                        span_record.trace.workflow_name,
                        "/raaf/tracing/traces/#{span_record.trace_id}",
                        class: "text-blue-600 hover:text-blue-500"
                      )
                    end
                  end
                  span do
                    plain "Started: #{span_record.start_time&.strftime('%Y-%m-%d %H:%M:%S')}"
                  end
                end
              end
            end
          end
        end

        def render_no_results
          div(class: "text-center py-12") do
            i(class: "bi bi-search text-6xl text-gray-400 mb-4")
            h3(class: "text-lg font-medium text-gray-900 mb-2") { "No results found" }
            p(class: "text-gray-500 mb-6") do
              "No traces or spans match your search for \"#{@query}\""
            end

            div(class: "text-sm text-gray-500 space-y-2") do
              p { "Try:" }
              ul(class: "list-disc list-inside space-y-1") do
                li { "Checking your spelling" }
                li { "Using different keywords" }
                li { "Searching for trace or span IDs" }
                li { "Using broader terms" }
              end
            end
          end
        end
      end
    end
  end
end