# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      class TimelineShow < BaseComponent
        def initialize(timeline_data: nil, gantt_data: nil, performance_stats: nil, trace: nil, spans: [])
          @timeline_data = timeline_data
          @gantt_data = gantt_data
          @performance_stats = performance_stats
          @trace = trace
          @spans = spans
        end

        def view_template
          div(class: "p-6") do
            render_header
            render_trace_selector
            render_timeline_view if @timeline_data
            render_performance_summary if @performance_stats
          end

          # JavaScript is handled by Stimulus timeline controller
          # Data attributes are already set up in render_timeline_chart
        end

        private

        def render_header
          div(class: "sm:flex sm:items-center sm:justify-between mb-6") do
            div(class: "min-w-0 flex-1") do
              h1(class: "text-2xl font-bold leading-7 text-gray-900 sm:text-3xl sm:truncate") { "Timeline Visualization" }
              p(class: "mt-1 text-sm text-gray-500") { "Detailed timeline view of trace execution" }
            end

            div(class: "mt-4 flex sm:mt-0 sm:ml-4 space-x-3") do
              render_preline_button(
                text: "Export Timeline Data",
                href: "/raaf/tracing/timeline.json",
                variant: "secondary",
                icon: "bi-download"
              )

              render_preline_button(
                text: "Switch to Gantt View",
                variant: "secondary",
                icon: "bi-diagram-3",
                id: "toggle-gantt-view"
              )
            end
          end
        end

        def render_trace_selector
          div(class: "bg-white p-6 rounded-lg shadow mb-6") do
            h3(class: "text-lg font-medium text-gray-900 mb-4") { "Select Trace for Timeline" }

            form_with(url: "/raaf/tracing/timeline", method: :get, local: true, class: "space-y-4") do |form|
              div(class: "flex space-x-4") do
                div(class: "flex-1") do
                  label(class: "block text-sm font-medium text-gray-700 mb-2") { "Trace ID" }
                  form.text_field(
                    :trace_id,
                    placeholder: "Enter trace ID (e.g., trace_abc123...)",
                    value: @trace&.trace_id,
                    class: "block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500"
                  )
                end

                div(class: "flex-shrink-0 flex items-end") do
                  form.submit(
                    "Load Timeline",
                    class: "inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700"
                  )
                end
              end

              div(class: "text-sm text-gray-500") do
                plain "Or browse "
                link_to("recent traces", "/raaf/tracing/traces", class: "text-blue-600 hover:text-blue-500")
                plain " to find a trace ID"
              end
            end
          end
        end

        def render_timeline_view
          div(class: "space-y-6") do
            render_timeline_header
            render_timeline_chart
            render_span_details
          end
        end

        def render_timeline_header
          div(class: "bg-white p-6 rounded-lg shadow") do
            div(class: "flex items-center justify-between") do
              div do
                h3(class: "text-lg font-medium text-gray-900") do
                  @timeline_data[:workflow_name] || "Timeline"
                end
                p(class: "text-sm text-gray-500 font-mono") { @timeline_data[:trace_id] }
              end

              div(class: "flex items-center space-x-6 text-sm") do
                span(class: "text-gray-500") do
                  plain "Duration: "
                  span(class: "font-medium") { format_duration(@timeline_data[:total_duration_ms]) }
                end
                span(class: "text-gray-500") do
                  plain "Spans: "
                  span(class: "font-medium") { @timeline_data[:span_count].to_s }
                end
                span(class: "text-gray-500") do
                  plain "Started: "
                  span(class: "font-medium") { Time.parse(@timeline_data[:trace_start]).strftime("%Y-%m-%d %H:%M:%S") }
                end
              end
            end
          end
        end

        def render_timeline_chart
          div(class: "bg-white rounded-lg shadow") do
            div(class: "px-6 py-4 border-b border-gray-200") do
              div(class: "flex items-center justify-between") do
                h4(class: "text-lg font-medium text-gray-900") { "Execution Timeline" }

                # View switcher controls
                div(class: "view-switcher flex space-x-2") do
                  button(
                    id: "timeline-view",
                    type: "button",
                    class: "btn btn-sm btn-secondary active"
                  ) { "Timeline" }
                  button(
                    id: "gantt-view",
                    type: "button",
                    class: "btn btn-sm btn-secondary"
                  ) { "Gantt" }
                  button(
                    id: "critical-path-view",
                    type: "button",
                    class: "btn btn-sm btn-secondary"
                  ) { "Critical Path" }
                end

                # Zoom controls
                div(class: "zoom-controls flex space-x-1") do
                  button(id: "zoom-in", type: "button", class: "btn btn-sm btn-outline") { "+" }
                  button(id: "zoom-out", type: "button", class: "btn btn-sm btn-outline") { "-" }
                  button(id: "zoom-fit", type: "button", class: "btn btn-sm btn-outline") { "Fit" }
                end
              end

              # Configuration options
              div(class: "mt-3 flex space-x-4 text-sm") do
                label(class: "flex items-center space-x-1") do
                  input(type: "checkbox", id: "show-attributes", checked: true)
                  span { "Show Attributes" }
                end
                label(class: "flex items-center space-x-1") do
                  input(type: "checkbox", id: "group-by-kind", checked: true)
                  span { "Group by Kind" }
                end
                label(class: "flex items-center space-x-1") do
                  input(type: "checkbox", id: "highlight-errors", checked: true)
                  span { "Highlight Errors" }
                end
              end
            end

            # Timeline visualization container with Stimulus controller
            div(
              id: "timeline-chart",
              class: "p-6",
              data: {
                controller: "timeline",
                timeline_timeline_data_value: @timeline_data.to_json,
                timeline_gantt_data_value: @gantt_data&.to_json || {}.to_json,
                timeline_trace_id_value: @trace&.trace_id || "",
                timeline_config_value: timeline_config.to_json
              }
            ) do
              # Timeline visualization views
              div(id: "timeline-visualization", style: "display: block;") do
                div(data: { timeline_target: "timelineCanvas" }, class: "timeline-canvas") do
                  div(class: "text-center py-12 text-gray-500") do
                    i(class: "bi bi-clock-history text-4xl mb-4")
                    p { "Loading timeline visualization..." }
                  end
                end
              end

              div(id: "gantt-visualization", style: "display: none;") do
                div(data: { timeline_target: "ganttChart" }, class: "gantt-chart") do
                  div(class: "text-center py-12 text-gray-500") do
                    i(class: "bi bi-diagram-3 text-4xl mb-4")
                    p { "Loading gantt chart..." }
                  end
                end
              end

              div(id: "critical-path-visualization", style: "display: none;") do
                div(data: { timeline_target: "criticalPathCanvas" }, class: "critical-path-canvas") do
                  div(class: "text-center py-12 text-gray-500") do
                    i(class: "bi bi-diagram-2 text-4xl mb-4")
                    p { "Loading critical path analysis..." }
                  end
                end
              end
            end
          end

          # Span details panel
          div(
            id: "span-details-panel",
            style: "display: none;",
            class: "fixed right-0 top-0 h-full w-96 bg-white shadow-lg z-50 overflow-y-auto",
            data: { timeline_target: "spanDetailsPanel" }
          ) do
            div(class: "p-4 border-b border-gray-200 flex items-center justify-between") do
              h3(class: "text-lg font-medium text-gray-900") { "Span Details" }
              button(
                id: "close-details",
                type: "button",
                class: "text-gray-400 hover:text-gray-600"
              ) { "×" }
            end
            div(
              id: "span-details-content",
              class: "p-4",
              data: { timeline_target: "spanDetailsContent" }
            ) do
              # Content will be populated by the controller
            end
          end
        end

        def render_span_details
          div(class: "bg-white rounded-lg shadow") do
            div(class: "px-6 py-4 border-b border-gray-200") do
              h4(class: "text-lg font-medium text-gray-900") { "Span Details" }
            end

            div(class: "divide-y divide-gray-200") do
              @timeline_data[:items].each do |span_item|
                render_span_detail(span_item)
              end
            end
          end
        end

        def render_span_detail(span_item)
          div(class: "px-6 py-4 hover:bg-gray-50") do
            div(class: "flex items-center justify-between") do
              div(class: "flex-1 min-w-0") do
                div(class: "flex items-center space-x-3") do
                  render_kind_badge(span_item[:kind])
                  render_status_badge(span_item[:status])

                  div do
                    div(class: "text-sm font-medium text-gray-900") do
                      link_to(
                        span_item[:name],
                        "/raaf/tracing/spans/#{span_item[:id]}",
                        class: "text-blue-600 hover:text-blue-500"
                      )
                    end
                    div(class: "text-sm text-gray-500 font-mono") { span_item[:id] }
                  end
                end

                div(class: "mt-2 flex items-center text-sm text-gray-500 space-x-4") do
                  span do
                    plain "Duration: #{format_duration(span_item[:duration_ms])}"
                  end
                  span do
                    plain "Start: +#{span_item[:start_offset_ms]}ms"
                  end
                  span do
                    plain "Depth: #{span_item[:depth]}"
                  end
                  if span_item[:error_details]
                    span(class: "text-red-600") do
                      plain "Error: #{span_item[:error_details][:error_type]}"
                    end
                  end
                end
              end

              div(class: "flex-shrink-0") do
                div(class: "text-right text-sm text-gray-500") do
                  div { "#{span_item[:percentage_start].round(1)}% → #{(span_item[:percentage_start] + span_item[:percentage_width]).round(1)}%" }
                  div { "#{span_item[:percentage_width].round(1)}% of total" }
                end
              end
            end
          end
        end

        def render_performance_summary
          div(class: "bg-white rounded-lg shadow") do
            div(class: "px-6 py-4 border-b border-gray-200") do
              h4(class: "text-lg font-medium text-gray-900") { "Performance Summary" }
            end

            div(class: "p-6") do
              div(class: "grid grid-cols-1 gap-5 sm:grid-cols-4") do
                render_metric_card(
                  title: "Total Spans",
                  value: @performance_stats[:total_spans],
                  color: "blue",
                  icon: "bi-diagram-3"
                )

                render_metric_card(
                  title: "Completed",
                  value: @performance_stats[:completed_spans],
                  color: "green",
                  icon: "bi-check-circle"
                )

                render_metric_card(
                  title: "Errors",
                  value: @performance_stats[:error_spans],
                  color: "red",
                  icon: "bi-x-circle"
                )

                render_metric_card(
                  title: "Avg Duration",
                  value: format_duration(@performance_stats[:avg_duration_ms]),
                  color: "yellow",
                  icon: "bi-stopwatch"
                )
              end

              if @performance_stats[:by_kind]
                div(class: "mt-6") do
                  h5(class: "text-sm font-medium text-gray-900 mb-3") { "Performance by Span Kind" }
                  div(class: "space-y-3") do
                    @performance_stats[:by_kind].each do |kind, stats|
                      render_kind_performance(kind, stats)
                    end
                  end
                end
              end
            end
          end
        end

        def render_kind_performance(kind, stats)
          div(class: "flex items-center justify-between p-3 bg-gray-50 rounded-lg") do
            div(class: "flex items-center space-x-3") do
              render_kind_badge(kind)
              span(class: "text-sm font-medium text-gray-900") { kind.capitalize }
            end

            div(class: "flex items-center space-x-6 text-sm text-gray-500") do
              span { "#{stats[:count]} spans" }
              span { "Avg: #{format_duration(stats[:avg_duration_ms])}" }
              span { "Total: #{format_duration(stats[:total_duration_ms])}" }
              if stats[:error_count] > 0
                span(class: "text-red-600") { "#{stats[:error_count]} errors" }
              end
            end
          end
        end

        # Configuration for timeline visualization
        def timeline_config
          {
            height: 600,
            margin: { top: 20, right: 20, bottom: 40, left: 150 },
            zoomLevel: 1.0,
            showAttributes: true,
            groupByKind: true,
            highlightErrors: true,
            currentView: "timeline"
          }
        end
      end
    end
  end
end