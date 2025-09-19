# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      class ErrorsDashboard < BaseComponent
        def initialize(error_analysis: {}, error_trends: [], recent_errors: [], params: {})
          @error_analysis = error_analysis
          @error_trends = error_trends
          @recent_errors = recent_errors
          @params = params
        end

        def view_template
          div(class: "p-6") do
            render_header
            render_time_filter
            render_error_overview
            render_error_trends
            render_recent_errors
            render_error_breakdown
          end
        end

        private

        def render_header
          div(class: "sm:flex sm:items-center sm:justify-between mb-6") do
            div(class: "min-w-0 flex-1") do
              h1(class: "text-2xl font-bold leading-7 text-gray-900 sm:text-3xl sm:truncate") { "Error Dashboard" }
              p(class: "mt-1 text-sm text-gray-500") { "Monitor and analyze error patterns across agent executions" }
            end

            div(class: "mt-4 flex sm:mt-0 sm:ml-4") do
              render_preline_button(
                text: "Export Error Report",
                href: "/raaf/tracing/dashboard/errors.json",
                variant: "secondary",
                icon: "bi-download"
              )
            end
          end
        end

        def render_time_filter
          div(class: "bg-white p-6 rounded-lg shadow mb-6") do
            form_with(url: "/raaf/tracing/dashboard/errors", method: :get, local: true, class: "grid grid-cols-1 gap-4 sm:grid-cols-4") do |form|
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
                label(class: "block text-sm font-medium text-gray-700 mb-1") { "Error Severity" }
                form.select(
                  :severity,
                  [
                    ["All Severities", ""],
                    ["Critical", "critical"],
                    ["High", "high"],
                    ["Medium", "medium"],
                    ["Low", "low"]
                  ],
                  { selected: @params[:severity] },
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

        def render_error_overview
          div(class: "grid grid-cols-1 gap-5 sm:grid-cols-4 mb-6") do
            render_metric_card(
              title: "Total Errors",
              value: @error_analysis[:total_errors] || 0,
              color: "red",
              icon: "bi-exclamation-triangle"
            )

            render_metric_card(
              title: "Error Rate",
              value: "#{(@error_analysis[:error_rate] || 0).round(1)}%",
              color: "orange",
              icon: "bi-percent"
            )

            render_metric_card(
              title: "Unique Errors",
              value: @error_analysis[:unique_error_types] || 0,
              color: "purple",
              icon: "bi-collection"
            )

            render_metric_card(
              title: "Critical Errors",
              value: @error_analysis[:critical_errors] || 0,
              color: "red",
              icon: "bi-exclamation-circle"
            )
          end
        end

        def render_error_trends
          div(class: "bg-white rounded-lg shadow mb-6") do
            div(class: "px-6 py-4 border-b border-gray-200") do
              h3(class: "text-lg font-medium text-gray-900") { "Error Trends" }
            end

            div(class: "p-6") do
              if @error_trends.any?
                div(id: "error-trends-chart", class: "h-64") do
                  render_simple_error_chart
                end
              else
                div(class: "text-center py-8 text-gray-500") do
                  i(class: "bi bi-graph-down text-4xl mb-2")
                  p { "No error trend data available" }
                end
              end
            end
          end
        end

        def render_simple_error_chart
          # Simple HTML-based chart for error trends
          max_errors = @error_trends.map { |t| t[:error_spans] || 0 }.max || 1

          div(class: "space-y-2") do
            @error_trends.each do |trend|
              error_count = trend[:error_spans] || 0
              total_count = trend[:total_spans] || 1
              error_rate = (error_count.to_f / total_count * 100).round(1)
              bar_width = max_errors > 0 ? (error_count.to_f / max_errors * 100).round(1) : 0

              div(class: "flex items-center space-x-4") do
                div(class: "w-24 text-xs text-gray-600") do
                  Time.at(trend[:timestamp]).strftime("%H:%M")
                end

                div(class: "flex-1 relative") do
                  div(class: "h-6 bg-gray-100 rounded") do
                    div(
                      class: "h-full bg-red-500 rounded",
                      style: "width: #{bar_width}%"
                    )
                  end
                end

                div(class: "w-20 text-xs text-gray-600 text-right") do
                  "#{error_count} (#{error_rate}%)"
                end
              end
            end
          end
        end

        def render_recent_errors
          div(class: "bg-white rounded-lg shadow mb-6") do
            div(class: "px-6 py-4 border-b border-gray-200") do
              div(class: "flex items-center justify-between") do
                h3(class: "text-lg font-medium text-gray-900") { "Recent Errors" }
                if @recent_errors.size >= 50
                  span(class: "text-sm text-gray-500") { "Showing 50 most recent" }
                end
              end
            end

            if @recent_errors.any?
              div(class: "divide-y divide-gray-200") do
                @recent_errors.each do |error_span|
                  render_error_row(error_span)
                end
              end

              if @recent_errors.size >= 50
                div(class: "px-6 py-4 bg-gray-50 text-center") do
                  link_to(
                    "View all error spans",
                    "/raaf/tracing/spans?status=error",
                    class: "text-blue-600 hover:text-blue-500 font-medium"
                  )
                end
              end
            else
              div(class: "p-6 text-center text-gray-500") do
                i(class: "bi bi-check-circle text-4xl text-green-500 mb-2")
                p { "No errors found in the selected time range" }
                p(class: "text-sm") { "All systems are operating normally" }
              end
            end
          end
        end

        def render_error_row(error_span)
          error_details = error_span.error_details || {}

          div(class: "px-6 py-4 hover:bg-gray-50") do
            div(class: "flex items-start justify-between") do
              div(class: "flex-1 min-w-0") do
                div(class: "flex items-center space-x-3") do
                  render_kind_badge(error_span.kind)

                  div do
                    div(class: "text-sm font-medium text-gray-900") do
                      link_to(
                        error_span.name,
                        "/raaf/tracing/spans/#{error_span.span_id}",
                        class: "text-blue-600 hover:text-blue-500"
                      )
                    end
                    div(class: "text-sm text-gray-500 font-mono") { error_span.span_id }
                  end
                end

                div(class: "mt-2") do
                  if error_details.any?
                    div(class: "text-sm text-red-600") do
                      strong { error_details["error_type"] || "Unknown Error" }
                    end
                    if error_details["error_message"]
                      div(class: "text-sm text-gray-600 mt-1") do
                        truncate(error_details["error_message"], length: 100)
                      end
                    end
                  else
                    div(class: "text-sm text-red-600") { "Error details not available" }
                  end
                end

                div(class: "mt-2 flex items-center text-sm text-gray-500 space-x-4") do
                  span { "Duration: #{format_duration(error_span.duration_ms)}" }
                  span { "Time: #{error_span.start_time&.strftime('%Y-%m-%d %H:%M:%S')}" }
                  if error_span.trace
                    span do
                      plain "Workflow: "
                      link_to(
                        error_span.trace.workflow_name || "Unknown",
                        "/raaf/tracing/traces/#{error_span.trace_id}",
                        class: "text-blue-600 hover:text-blue-500"
                      )
                    end
                  end
                end
              end

              div(class: "flex-shrink-0") do
                severity = determine_error_severity(error_details)
                render_severity_badge(severity)
              end
            end
          end
        end

        def render_error_breakdown
          if @error_analysis[:errors_by_kind]
            div(class: "bg-white rounded-lg shadow") do
              div(class: "px-6 py-4 border-b border-gray-200") do
                h3(class: "text-lg font-medium text-gray-900") { "Errors by Type" }
              end

              div(class: "p-6") do
                div(class: "space-y-4") do
                  @error_analysis[:errors_by_kind].each do |kind, count|
                    render_error_kind_row(kind, count)
                  end
                end
              end
            end
          end
        end

        def render_error_kind_row(kind, count)
          percentage = if @error_analysis[:total_errors] && @error_analysis[:total_errors] > 0
                         (count.to_f / @error_analysis[:total_errors] * 100).round(1)
                       else
                         0
                       end

          div(class: "flex items-center justify-between p-3 bg-gray-50 rounded-lg") do
            div(class: "flex items-center space-x-3") do
              render_kind_badge(kind)
              span(class: "text-sm font-medium text-gray-900") { kind.to_s.capitalize }
            end

            div(class: "flex items-center space-x-4") do
              div(class: "flex-1 bg-gray-200 rounded-full h-2 w-24") do
                div(
                  class: "bg-red-500 h-2 rounded-full",
                  style: "width: #{percentage}%"
                )
              end

              span(class: "text-sm font-medium text-gray-900") { count.to_s }
              span(class: "text-sm text-gray-500") { "(#{percentage}%)" }
            end
          end
        end

        def render_severity_badge(severity)
          badge_class = case severity
                       when "critical" then "bg-red-100 text-red-800"
                       when "high" then "bg-orange-100 text-orange-800"
                       when "medium" then "bg-yellow-100 text-yellow-800"
                       when "low" then "bg-blue-100 text-blue-800"
                       else "bg-gray-100 text-gray-800"
                       end

          span(class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium #{badge_class}") do
            severity.to_s.capitalize
          end
        end

        def determine_error_severity(error_details)
          return "low" unless error_details.is_a?(Hash)

          error_type = error_details["error_type"]&.downcase || ""
          error_message = error_details["error_message"]&.downcase || ""

          # Critical errors
          return "critical" if error_type.include?("critical") || error_message.include?("critical")
          return "critical" if error_type.include?("fatal") || error_message.include?("fatal")
          return "critical" if error_type.include?("system") && error_message.include?("failure")

          # High severity errors
          return "high" if error_type.include?("timeout") || error_message.include?("timeout")
          return "high" if error_type.include?("connection") || error_message.include?("connection")
          return "high" if error_type.include?("authentication") || error_message.include?("authentication")

          # Medium severity errors
          return "medium" if error_type.include?("validation") || error_message.include?("validation")
          return "medium" if error_type.include?("parsing") || error_message.include?("parsing")

          # Default to low
          "low"
        end
      end
    end
  end
end