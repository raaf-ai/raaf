# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      class TracesTable < BaseComponent
        def initialize(traces:, page: 1, total_pages: 1, per_page: 20, total_count: 0, params: {})
          @traces = traces
          @page = page
          @total_pages = total_pages
          @per_page = per_page
          @total_count = total_count
          @params = params
        end

        def view_template
          div(class: "bg-white shadow rounded-lg overflow-hidden") do
            if @traces.any?
              render_table
              render_pagination if @total_pages > 1
            else
              render_empty_state
            end
          end
        end

        private

        def render_table
          render_preline_table do
            table(class: "min-w-full divide-y divide-gray-200") do
              render_table_header
              render_table_body
            end
          end
        end

        def render_table_header
          thead(class: "bg-gray-50") do
            tr do
              th(scope: "col", class: "px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider") do
                "Workflow"
              end
              th(scope: "col", class: "px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider") do
                "Status"
              end
              th(scope: "col", class: "px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider") do
                "Started"
              end
              th(scope: "col", class: "px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider") do
                "Duration"
              end
              th(scope: "col", class: "px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider") do
                "Spans"
              end
              th(scope: "col", class: "relative px-6 py-3") do
                span(class: "sr-only") { "Actions" }
              end
            end
          end
        end

        def render_table_body
          tbody(class: "bg-white divide-y divide-gray-200") do
            @traces.each do |trace|
              render_trace_row(trace)
              render_spans_row(trace) if trace.spans.any?
            end
          end
        end

        def render_trace_row(trace)
          tr(class: "hover:bg-gray-50 trace-row", data: { trace_id: trace.trace_id }) do
            td(class: "px-6 py-4 whitespace-nowrap") do
              div(class: "flex items-center") do
                if trace.spans.any?
                  button(
                    class: "mr-3 p-1 text-gray-400 hover:text-gray-600 toggle-spans",
                    data: { bs_toggle: "collapse", bs_target: "#spans-#{trace.trace_id.gsub('_', '-')}" }
                  ) do
                    i(class: "bi bi-chevron-right transform transition-transform")
                  end
                else
                  div(class: "w-6")
                end

                div do
                  link_to("/raaf/tracing/traces/#{trace.trace_id}", class: "font-medium text-blue-600 hover:text-blue-500") do
                    trace.workflow_name || "Unnamed Workflow"
                  end
                  div(class: "text-sm text-gray-500 font-mono") { trace.trace_id }
                end
              end
            end

            td(class: "px-6 py-4 whitespace-nowrap") do
              # Show skip reasons for any trace that has skipped spans (even if trace is completed)
              skip_reason = if trace.respond_to?(:skip_reasons_summary)
                              begin
                                trace.skip_reasons_summary
                              rescue StandardError => e
                                Rails.logger.warn "Failed to get skip_reasons_summary for trace #{trace.trace_id}: #{e.message}"
                                nil
                              end
                            end
              render_status_badge(trace.status, skip_reason: skip_reason)
            end

            td(class: "px-6 py-4 whitespace-nowrap") do
              div(class: "text-sm text-gray-900") do
                trace.started_at&.strftime("%Y-%m-%d %H:%M:%S")
              end
              div(class: "text-sm text-gray-500") do
                "#{time_ago_in_words(trace.started_at)} ago" if trace.started_at
              end
            end

            td(class: "px-6 py-4 whitespace-nowrap") do
              div(class: "text-sm text-gray-900") { format_duration(trace.duration_ms) }
              if trace.duration_ms
                div(class: "w-full bg-gray-200 rounded-full h-1 mt-1") do
                  div(
                    class: "bg-blue-600 h-1 rounded-full",
                    style: "width: #{[trace.duration_ms / 10000 * 100, 100].min}%"
                  )
                end
              end
            end

            td(class: "px-6 py-4 whitespace-nowrap") do
              div(class: "flex space-x-2") do
                span(class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-800") do
                  trace.spans.count.to_s
                end

                tool_count = trace.spans.where(kind: 'tool').count
                if tool_count > 0
                  span(
                    class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-purple-100 text-purple-800",
                    title: "Tool calls"
                  ) do
                    i(class: "bi bi-tools mr-1")
                    plain tool_count.to_s
                  end
                end

                error_count = trace.spans.where(status: 'error').count
                if error_count > 0
                  span(class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-red-100 text-red-800") do
                    "#{error_count} errors"
                  end
                end
              end
            end

            td(class: "px-6 py-4 whitespace-nowrap text-right text-sm font-medium") do
              div(class: "flex space-x-2 justify-end") do
                link_to(
                  "/raaf/tracing/traces/#{trace.trace_id}",
                  class: "text-blue-600 hover:text-blue-900"
                ) do
                  i(class: "bi bi-eye")
                end

                link_to(
                  "/raaf/tracing/traces/#{trace.trace_id}/analytics",
                  class: "text-green-600 hover:text-green-900"
                ) do
                  i(class: "bi bi-graph-up")
                end
              end
            end
          end
        end

        def render_spans_row(trace)
          tr(class: "collapse-row") do
            td(colspan: "6", class: "p-0") do
              div(class: "collapse", id: "spans-#{trace.trace_id.gsub('_', '-')}") do
                div(class: "bg-gray-50 p-4") do
                  h6(class: "text-sm font-medium text-gray-900 mb-3") do
                    "Spans for #{trace.workflow_name}"
                  end

                  div(class: "overflow-hidden shadow ring-1 ring-black ring-opacity-5 rounded-md") do
                    table(class: "min-w-full divide-y divide-gray-300") do
                      thead(class: "bg-gray-50") do
                        tr do
                          th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase") { "Name" }
                          th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase") { "Kind" }
                          th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase") { "Status" }
                          th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase") { "Duration" }
                          th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase") { "Start Time" }
                        end
                      end

                      tbody(class: "divide-y divide-gray-200 bg-white") do
                        render_spans_hierarchy(trace)
                      end
                    end
                  end

                  if trace.spans.count > 10
                    div(class: "mt-3 text-center") do
                      link_to(
                        "View all #{trace.spans.count} spans →",
                        "/raaf/tracing/traces/#{trace.trace_id}",
                        class: "text-blue-600 hover:text-blue-500 text-sm"
                      )
                    end
                  end
                end
              end
            end
          end
        end

        def render_spans_hierarchy(trace)
          spans = trace.spans.includes(:parent_span).order(:start_time).limit(10)
          root_spans = spans.select { |s| s.parent_id.nil? }
          child_spans = spans.select { |s| s.parent_id.present? }.group_by(&:parent_id)

          shown_count = 0

          render_span_rows = lambda do |span, level = 0|
            return if shown_count >= 10
            shown_count += 1

            tr do
              td(class: "px-4 py-3 text-sm") do
                div(style: "padding-left: #{level * 20}px;") do
                  display_name = span.respond_to?(:display_name) ? span.display_name : span.name
                  link_to(display_name, "/raaf/tracing/spans/#{span.span_id}", class: "text-blue-600 hover:text-blue-500")
                  if level > 0
                    small(class: "text-gray-400 ml-2") { "↳" }
                  end
                end
              end
              td(class: "px-4 py-3 text-sm") { render_kind_badge(span.kind) }
              td(class: "px-4 py-3 text-sm") do
                skip_reason = if %w[cancelled skipped].include?(span.status) && span.respond_to?(:skip_reason)
                                begin
                                  span.skip_reason
                                rescue StandardError => e
                                  Rails.logger.warn "Failed to get skip_reason for span #{span.span_id}: #{e.message}"
                                  "Error retrieving skip reason"
                                end
                              end
                render_status_badge(span.status, skip_reason: skip_reason)
              end
              td(class: "px-4 py-3 text-sm text-gray-900") { format_duration(span.duration_ms) }
              td(class: "px-4 py-3 text-sm text-gray-500") { span.start_time&.strftime("%H:%M:%S.%3N") }
            end

            # Render children
            if child_spans[span.span_id] && shown_count < 10
              child_spans[span.span_id].each do |child|
                render_span_rows.call(child, level + 1)
              end
            end
          end

          root_spans.each { |span| render_span_rows.call(span) }
        end

        def render_pagination
          nav(class: "bg-white px-4 py-3 flex items-center justify-between border-t border-gray-200 sm:px-6") do
            div(class: "hidden sm:block") do
              p(class: "text-sm text-gray-700") do
                plain "Showing "
                span(class: "font-medium") { ((@page - 1) * @per_page + 1).to_s }
                plain " to "
                span(class: "font-medium") { [@page * @per_page, @total_count].min.to_s }
                plain " of "
                span(class: "font-medium") { @total_count.to_s }
                plain " traces"
              end
            end

            div(class: "flex-1 flex justify-between sm:justify-end") do
              if @page > 1
                link_to(
                  "Previous",
                  "/raaf/tracing/traces?#{@params.merge(page: @page - 1).to_query}",
                  class: "relative inline-flex items-center px-4 py-2 border border-gray-300 text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50"
                )
              end

              if @page < @total_pages
                link_to(
                  "Next",
                  "/raaf/tracing/traces?#{@params.merge(page: @page + 1).to_query}",
                  class: "ml-3 relative inline-flex items-center px-4 py-2 border border-gray-300 text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50"
                )
              end
            end
          end
        end

        def render_empty_state
          div(class: "text-center py-12") do
            i(class: "bi bi-diagram-3 text-6xl text-gray-400 mb-4")
            h3(class: "text-lg font-medium text-gray-900 mb-2") { "No traces found" }
            p(class: "text-gray-500 mb-6") { "No traces match your current filters. Try adjusting your search criteria." }
            render_preline_button(
              text: "Clear Filters",
              href: "/raaf/tracing/traces",
              variant: "secondary"
            )
          end
        end
      end
    end
  end
end