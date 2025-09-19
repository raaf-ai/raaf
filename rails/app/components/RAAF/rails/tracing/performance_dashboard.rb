# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      class PerformanceDashboard < BaseComponent
        def initialize(performance_by_kind: {}, slowest_spans: [], performance_over_time: [], params: {})
          @performance_by_kind = performance_by_kind
          @slowest_spans = slowest_spans
          @performance_over_time = performance_over_time
          @params = params
        end

        def view_template
          div(class: "p-6") do
            render_header
            render_time_filter
            render_performance_overview
            render_performance_by_kind
            render_slowest_operations
            render_performance_trends
          end
        end

        private

        def render_header
          div(class: "sm:flex sm:items-center sm:justify-between mb-6") do
            div(class: "min-w-0 flex-1") do
              h1(class: "text-2xl font-bold leading-7 text-gray-900 sm:text-3xl sm:truncate") { "Performance Dashboard" }
              p(class: "mt-1 text-sm text-gray-500") { "Monitor agent execution performance and identify bottlenecks" }
            end

            div(class: "mt-4 flex sm:mt-0 sm:ml-4") do
              render_preline_button(
                text: "Export Performance Report",
                href: "/raaf/tracing/dashboard/performance.json",
                variant: "secondary",
                icon: "bi-download"
              )
            end
          end
        end

        def render_time_filter
          div(class: "bg-white p-6 rounded-lg shadow mb-6") do
            form_with(url: "/raaf/tracing/dashboard/performance", method: :get, local: true, class: "grid grid-cols-1 gap-4 sm:grid-cols-4") do |form|
              div do
                label(class: "block text-sm font-medium text-gray-700 mb-1") { "Start Time" }
                form.datetime_local_field(
                  :start_time,
                  value: @params[:start_time] || 24.hours.ago.strftime("%Y-%m-%dT%H:%M"),
                  class: "block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                )
              end

              div do
                label(class: "block text-sm font-medium text-gray-700 mb-1") { "End Time" }
                form.datetime_local_field(
                  :end_time,
                  value: @params[:end_time] || Time.current.strftime("%Y-%m-%dT%H:%M"),
                  class: "block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                )
              end

              div do
                label(class: "block text-sm font-medium text-gray-700 mb-1") { "Span Kind" }
                form.select(
                  :kind,
                  [
                    ["All Kinds", ""],
                    ["Agent", "agent"],
                    ["LLM", "llm"],
                    ["Tool", "tool"],
                    ["Handoff", "handoff"]
                  ],
                  { selected: @params[:kind] },
                  { class: "block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm" }
                )
              end

              div(class: "flex items-end") do
                form.submit(
                  "Apply Filters",
                  class: "w-full inline-flex justify-center items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700"
                )
              end
            end
          end
        end

        def render_performance_overview
          div(class: "grid grid-cols-1 gap-5 sm:grid-cols-4 mb-6") do
            total_spans = @performance_by_kind.values.sum { |stats| stats[:total_spans] || 0 }
            avg_duration = if total_spans > 0
                             @performance_by_kind.values.sum { |stats| (stats[:avg_duration] || 0) * (stats[:total_spans] || 0) } / total_spans
                           else
                             0
                           end

            render_metric_card(
              title: "Total Spans",
              value: total_spans,
              color: "blue",
              icon: "bi-diagram-3"
            )

            render_metric_card(
              title: "Avg Duration",
              value: format_duration(avg_duration),
              color: "green",
              icon: "bi-stopwatch"
            )

            render_metric_card(
              title: "P95 Duration",
              value: format_duration(@performance_by_kind.values.map { |stats| stats[:p95_duration] || 0 }.max || 0),
              color: "yellow",
              icon: "bi-speedometer2"
            )

            render_metric_card(
              title: "Error Rate",
              value: "#{calculate_error_rate.round(1)}%",
              color: "red",
              icon: "bi-exclamation-triangle"
            )
          end
        end

        def render_performance_by_kind
          div(class: "bg-white rounded-lg shadow mb-6") do
            div(class: "px-6 py-4 border-b border-gray-200") do
              h3(class: "text-lg font-medium text-gray-900") { "Performance by Span Kind" }
            end

            div(class: "p-6") do
              if @performance_by_kind.any?
                div(class: "space-y-4") do
                  @performance_by_kind.each do |kind, stats|
                    render_kind_performance_row(kind, stats)
                  end
                end
              else
                div(class: "text-center py-8 text-gray-500") do
                  i(class: "bi bi-bar-chart text-4xl mb-2")
                  p { "No performance data available for the selected time range" }
                end
              end
            end
          end
        end

        def render_kind_performance_row(kind, stats)
          div(class: "flex items-center justify-between p-4 bg-gray-50 rounded-lg") do
            div(class: "flex items-center space-x-4") do
              render_kind_badge(kind)
              div do
                h4(class: "text-sm font-medium text-gray-900") { kind.to_s.capitalize }
                p(class: "text-sm text-gray-500") { "#{stats[:total_spans]} spans" }
              end
            end

            div(class: "grid grid-cols-4 gap-6 text-sm") do
              div(class: "text-center") do
                p(class: "font-medium text-gray-900") { format_duration(stats[:avg_duration]) }
                p(class: "text-gray-500") { "Avg Duration" }
              end

              div(class: "text-center") do
                p(class: "font-medium text-gray-900") { format_duration(stats[:median_duration]) }
                p(class: "text-gray-500") { "Median" }
              end

              div(class: "text-center") do
                p(class: "font-medium text-gray-900") { format_duration(stats[:p95_duration]) }
                p(class: "text-gray-500") { "P95" }
              end

              div(class: "text-center") do
                error_rate = stats[:total_spans] > 0 ? ((stats[:error_spans] || 0).to_f / stats[:total_spans] * 100) : 0
                p(class: "font-medium #{'text-red-600' if error_rate > 5} #{'text-gray-900' if error_rate <= 5}") do
                  "#{error_rate.round(1)}%"
                end
                p(class: "text-gray-500") { "Error Rate" }
              end
            end
          end
        end

        def render_slowest_operations
          div(class: "bg-white rounded-lg shadow mb-6") do
            div(class: "px-6 py-4 border-b border-gray-200") do
              h3(class: "text-lg font-medium text-gray-900") { "Slowest Operations" }
            end

            if @slowest_spans.any?
              div(class: "divide-y divide-gray-200") do
                @slowest_spans.each do |span|
                  render_slow_span_row(span)
                end
              end
            else
              div(class: "p-6 text-center text-gray-500") do
                i(class: "bi bi-hourglass-split text-4xl mb-2")
                p { "No slow operations detected" }
              end
            end
          end
        end

        def render_slow_span_row(span)
          div(class: "px-6 py-4 hover:bg-gray-50") do
            div(class: "flex items-center justify-between") do
              div(class: "flex-1 min-w-0") do
                div(class: "flex items-center space-x-3") do
                  render_kind_badge(span.kind)

                  div do
                    div(class: "text-sm font-medium text-gray-900") do
                      link_to(
                        span.name,
                        "/raaf/tracing/spans/#{span.span_id}",
                        class: "text-blue-600 hover:text-blue-500"
                      )
                    end
                    div(class: "text-sm text-gray-500 font-mono") { span.span_id }
                  end
                end
              end

              div(class: "flex items-center space-x-4 text-sm") do
                span(class: "font-medium text-gray-900") { format_duration(span.duration_ms) }
                span(class: "text-gray-500") { span.start_time&.strftime("%H:%M:%S") }

                if span.trace
                  link_to(
                    "View Trace",
                    "/raaf/tracing/traces/#{span.trace_id}",
                    class: "text-blue-600 hover:text-blue-500"
                  )
                end
              end
            end
          end
        end

        def render_performance_trends
          div(class: "bg-white rounded-lg shadow") do
            div(class: "px-6 py-4 border-b border-gray-200") do
              h3(class: "text-lg font-medium text-gray-900") { "Performance Trends" }
            end

            div(class: "p-6") do
              if @performance_over_time.any?
                div(id: "performance-chart", class: "h-64") do
                  # Chart will be rendered by JavaScript
                  div(class: "flex items-center justify-center h-full text-gray-500") do
                    i(class: "bi bi-graph-up text-4xl mb-2")
                    p { "Loading performance trends..." }
                  end
                end
              else
                div(class: "text-center py-8 text-gray-500") do
                  i(class: "bi bi-graph-up text-4xl mb-2")
                  p { "No trend data available" }
                end
              end
            end
          end
        end

        def calculate_error_rate
          return 0 if @performance_by_kind.empty?

          total_spans = @performance_by_kind.values.sum { |stats| stats[:total_spans] || 0 }
          error_spans = @performance_by_kind.values.sum { |stats| stats[:error_spans] || 0 }

          return 0 if total_spans.zero?

          (error_spans.to_f / total_spans) * 100
        end
      end
    end
  end
end