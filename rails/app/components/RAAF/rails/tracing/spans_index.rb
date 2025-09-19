# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      class SpansIndex < BaseComponent
        def initialize(spans:, params: {}, page: 1, total_pages: 1, per_page: 20, total_count: 0)
          @spans = spans
          @params = params
          @page = page
          @total_pages = total_pages
          @per_page = per_page
          @total_count = total_count
        end

        def view_template
          div(class: "p-6") do
            render_header
            render_filters
            render_spans_table
          end
        end

        private

        def render_header
          div(class: "sm:flex sm:items-center sm:justify-between mb-6") do
            div(class: "min-w-0 flex-1") do
              h1(class: "text-2xl font-bold leading-7 text-gray-900 sm:text-3xl sm:truncate") { "Spans" }
              p(class: "mt-1 text-sm text-gray-500") { "Detailed view of all execution spans" }
            end

            div(class: "mt-4 flex sm:mt-0 sm:ml-4") do
              render_preline_button(
                text: "Export JSON",
                href: "/raaf/tracing/spans.json",
                variant: "secondary",
                icon: "bi-download"
              )
            end
          end
        end

        def render_filters
          div(class: "bg-white p-6 rounded-lg shadow mb-6") do
            form_with(url: "/raaf/tracing/spans", method: :get, local: true, class: "grid grid-cols-1 gap-4 sm:grid-cols-6") do |form|
              div(class: "sm:col-span-2") do
                label(class: "block text-sm font-medium text-gray-700 mb-1") { "Search" }
                form.text_field(
                  :search,
                  placeholder: "Search spans...",
                  value: @params[:search],
                  class: "block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                )
              end

              div(class: "sm:col-span-1") do
                label(class: "block text-sm font-medium text-gray-700 mb-1") { "Kind" }
                form.select(
                  :kind,
                  [
                    ["All Kinds", ""],
                    ["Agent", "agent"],
                    ["Tool", "tool"],
                    ["Response", "response"],
                    ["Span", "span"]
                  ],
                  { selected: @params[:kind] },
                  { class: "block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm" }
                )
              end

              div(class: "sm:col-span-1") do
                label(class: "block text-sm font-medium text-gray-700 mb-1") { "Status" }
                form.select(
                  :status,
                  [
                    ["All Statuses", ""],
                    ["Completed", "completed"],
                    ["Failed", "failed"],
                    ["Error", "error"]
                  ],
                  { selected: @params[:status] },
                  { class: "block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm" }
                )
              end

              div(class: "sm:col-span-1") do
                label(class: "block text-sm font-medium text-gray-700 mb-1") { "Start Time" }
                form.datetime_local_field(
                  :start_time,
                  value: @params[:start_time],
                  class: "block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                )
              end

              div(class: "sm:col-span-1") do
                label(class: "block text-sm font-medium text-gray-700 mb-1") { "End Time" }
                form.datetime_local_field(
                  :end_time,
                  value: @params[:end_time],
                  class: "block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                )

                div(class: "mt-4") do
                  form.submit("Filter", class: "w-full inline-flex justify-center items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700")
                end
              end
            end
          end
        end

        def render_spans_table
          if @spans.any?
            render_preline_table do
              table(class: "min-w-full divide-y divide-gray-200") do
                render_table_header
                render_table_body
              end
            end
            render_pagination if @total_pages > 1
          else
            render_empty_state
          end
        end

        def render_table_header
          thead(class: "bg-gray-50") do
            tr do
              th(scope: "col", class: "px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider") do
                "Span Name"
              end
              th(scope: "col", class: "px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider") do
                "Kind"
              end
              th(scope: "col", class: "px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider") do
                "Status"
              end
              th(scope: "col", class: "px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider") do
                "Duration"
              end
              th(scope: "col", class: "px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider") do
                "Start Time"
              end
              th(scope: "col", class: "px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider") do
                "Trace"
              end
              th(scope: "col", class: "relative px-6 py-3") do
                span(class: "sr-only") { "Actions" }
              end
            end
          end
        end

        def render_table_body
          tbody(class: "bg-white divide-y divide-gray-200") do
            @spans.each do |span|
              render_span_row(span)
            end
          end
        end

        def render_span_row(span)
          tr(class: "hover:bg-gray-50") do
            td(class: "px-6 py-4 whitespace-nowrap") do
              div(class: "text-sm font-medium text-gray-900") { span.name }
              div(class: "text-sm text-gray-500 font-mono") { span.span_id }
            end

            td(class: "px-6 py-4 whitespace-nowrap") do
              render_kind_badge(span.kind)
            end

            td(class: "px-6 py-4 whitespace-nowrap") do
              render_status_badge(span.status)
            end

            td(class: "px-6 py-4 whitespace-nowrap text-sm text-gray-900") do
              format_duration(span.duration_ms)
            end

            td(class: "px-6 py-4 whitespace-nowrap text-sm text-gray-500") do
              span.start_time&.strftime("%Y-%m-%d %H:%M:%S.%3N")
            end

            td(class: "px-6 py-4 whitespace-nowrap text-sm") do
              if span.trace
                link_to(
                  span.trace.workflow_name || span.trace_id,
                  "/raaf/tracing/traces/#{span.trace_id}",
                  class: "text-blue-600 hover:text-blue-500"
                )
              else
                span(class: "text-gray-500") { span.trace_id }
              end
            end

            td(class: "px-6 py-4 whitespace-nowrap text-right text-sm font-medium") do
              link_to(
                "View",
                "/raaf/tracing/spans/#{span.span_id}",
                class: "text-blue-600 hover:text-blue-900"
              )
            end
          end
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
                plain " spans"
              end
            end

            div(class: "flex-1 flex justify-between sm:justify-end") do
              if @page > 1
                link_to(
                  "Previous",
                  "/raaf/tracing/spans?#{@params.merge(page: @page - 1).to_query}",
                  class: "relative inline-flex items-center px-4 py-2 border border-gray-300 text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50"
                )
              end

              if @page < @total_pages
                link_to(
                  "Next",
                  "/raaf/tracing/spans?#{@params.merge(page: @page + 1).to_query}",
                  class: "ml-3 relative inline-flex items-center px-4 py-2 border border-gray-300 text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50"
                )
              end
            end
          end
        end

        def render_empty_state
          div(class: "text-center py-12") do
            i(class: "bi bi-layers text-6xl text-gray-400 mb-4")
            h3(class: "text-lg font-medium text-gray-900 mb-2") { "No spans found" }
            p(class: "text-gray-500 mb-6") { "No spans match your current filters." }
            render_preline_button(
              text: "Clear Filters",
              href: "/raaf/tracing/spans",
              variant: "secondary"
            )
          end
        end
      end
    end
  end
end