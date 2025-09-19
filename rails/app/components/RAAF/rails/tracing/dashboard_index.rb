# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      class DashboardIndex < BaseComponent
        def initialize(overview_stats:, top_workflows:, recent_traces:, recent_errors: [], params: {})
          @overview_stats = overview_stats
          @top_workflows = top_workflows
          @recent_traces = recent_traces
          @recent_errors = recent_errors
          @params = params
        end

        def view_template
          div(class: "p-6") do
            render_header
            render_time_filter
            render_overview_metrics
            render_content_grid
            render_recent_errors if @recent_errors.any?
          end

          content_for :javascript do
            render_auto_refresh_script
          end
        end

        private

        def render_header
          div(class: "sm:flex sm:items-center sm:justify-between mb-6") do
            div(class: "min-w-0 flex-1") do
              h1(class: "text-2xl font-bold leading-7 text-gray-900 sm:text-3xl sm:truncate") { "Dashboard" }
              p(class: "mt-1 text-sm text-gray-500") { "Overview of your agent execution metrics" }
            end

            div(class: "mt-4 flex sm:mt-0 sm:ml-4") do
              render_preline_button(
                text: "Auto Refresh",
                variant: "secondary",
                icon: "bi-arrow-clockwise",
                onclick: "enableAutoRefresh(30000)"
              )
            end
          end
        end

        def render_time_filter
          div(class: "bg-white p-6 rounded-lg shadow mb-6") do
            form_with(url: dashboard_path, method: :get, local: true, class: "grid grid-cols-1 gap-4 sm:grid-cols-5") do |form|
              div(class: "sm:col-span-2") do
                label(class: "block text-sm font-medium text-gray-700 mb-1") { "Start Time" }
                form.datetime_local_field(
                  :start_time,
                  value: @params[:start_time] || 24.hours.ago.strftime("%Y-%m-%dT%H:%M"),
                  class: "block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                )
              end

              div(class: "sm:col-span-2") do
                label(class: "block text-sm font-medium text-gray-700 mb-1") { "End Time" }
                form.datetime_local_field(
                  :end_time,
                  value: @params[:end_time] || Time.current.strftime("%Y-%m-%dT%H:%M"),
                  class: "block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                )
              end

              div(class: "sm:col-span-1 flex space-x-3") do
                form.submit(
                  "Apply Filter",
                  class: "flex-1 inline-flex justify-center items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700"
                )
                link_to(
                  "Reset",
                  dashboard_path,
                  class: "flex-1 inline-flex justify-center items-center px-4 py-2 border border-gray-300 text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50"
                )
              end
            end
          end
        end

        def render_overview_metrics
          div(class: "grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-4 mb-8") do
            # First row metrics
            render_metric_card(
              title: "Total Traces",
              value: @overview_stats[:total_traces],
              color: "blue",
              icon: "bi-diagram-3"
            )

            render_metric_card(
              title: "Completed",
              value: @overview_stats[:completed_traces],
              color: "green",
              icon: "bi-check-circle"
            )

            render_metric_card(
              title: "Failed",
              value: @overview_stats[:failed_traces],
              color: "red",
              icon: "bi-x-circle"
            )

            render_metric_card(
              title: "Running",
              value: @overview_stats[:running_traces],
              color: "yellow",
              icon: "bi-play-circle"
            )
          end

          div(class: "grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-4 mb-8") do
            # Second row metrics
            render_metric_card(
              title: "Total Spans",
              value: @overview_stats[:total_spans],
              color: "indigo",
              icon: "bi-layers"
            )

            render_metric_card(
              title: "Error Spans",
              value: @overview_stats[:error_spans],
              color: "red",
              icon: "bi-exclamation-triangle"
            )

            render_metric_card(
              title: "Avg Duration",
              value: format_duration(@overview_stats[:avg_trace_duration] && @overview_stats[:avg_trace_duration] * 1000),
              color: "purple",
              icon: "bi-clock"
            )

            render_metric_card(
              title: "Success Rate",
              value: "#{@overview_stats[:success_rate]}%",
              color: "green",
              icon: "bi-graph-up"
            )
          end
        end

        def render_content_grid
          div(class: "grid grid-cols-1 gap-6 lg:grid-cols-2") do
            render_top_workflows
            render_recent_traces
          end
        end

        def render_top_workflows
          div(class: "bg-white overflow-hidden shadow rounded-lg") do
            div(class: "px-4 py-5 sm:px-6 flex justify-between items-center border-b border-gray-200") do
              h3(class: "text-lg leading-6 font-medium text-gray-900") { "Top Workflows" }
              link_to(
                "View All",
                tracing_traces_path,
                class: "text-sm text-blue-600 hover:text-blue-500"
              )
            end

            div(class: "px-4 py-5 sm:p-6") do
              if @top_workflows.any?
                div(class: "overflow-hidden shadow ring-1 ring-black ring-opacity-5 rounded-md") do
                  table(class: "min-w-full divide-y divide-gray-300") do
                    thead(class: "bg-gray-50") do
                      tr do
                        th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase") { "Workflow" }
                        th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase") { "Traces" }
                        th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase") { "Avg Duration" }
                        th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase") { "Success Rate" }
                      end
                    end

                    tbody(class: "divide-y divide-gray-200 bg-white") do
                      @top_workflows.each do |workflow|
                        tr do
                          td(class: "px-4 py-3 text-sm") do
                            link_to(
                              workflow[:workflow_name],
                              tracing_traces_path(workflow: workflow[:workflow_name]),
                              class: "text-blue-600 hover:text-blue-500"
                            )
                          end
                          td(class: "px-4 py-3 text-sm text-gray-900") { workflow[:trace_count] }
                          td(class: "px-4 py-3 text-sm text-gray-900") do
                            format_duration(workflow[:avg_duration] && workflow[:avg_duration] * 1000)
                          end
                          td(class: "px-4 py-3 text-sm") do
                            render_success_rate_badge(workflow[:success_rate])
                          end
                        end
                      end
                    end
                  end
                end
              else
                p(class: "text-gray-500") { "No workflows found in the selected time range." }
              end
            end
          end
        end

        def render_recent_traces
          div(class: "bg-white overflow-hidden shadow rounded-lg") do
            div(class: "px-4 py-5 sm:px-6 flex justify-between items-center border-b border-gray-200") do
              h3(class: "text-lg leading-6 font-medium text-gray-900") { "Recent Traces" }
              link_to(
                "View All",
                tracing_traces_path,
                class: "text-sm text-blue-600 hover:text-blue-500"
              )
            end

            div(class: "px-4 py-5 sm:p-6") do
              if @recent_traces.any?
                div(class: "space-y-3") do
                  @recent_traces.each do |trace|
                    div(class: "flex justify-between items-center p-3 bg-gray-50 rounded-lg") do
                      div(class: "min-w-0 flex-1") do
                        link_to(
                          trace.workflow_name,
                          tracing_trace_path(trace.trace_id),
                          class: "font-medium text-blue-600 hover:text-blue-500"
                        )
                        div(class: "mt-1 text-sm text-gray-500") do
                          plain "#{trace.started_at&.strftime('%H:%M:%S')} • "
                          plain pluralize(trace.spans.count, 'span')
                        end
                      end

                      div(class: "flex flex-col items-end") do
                        render_status_badge(trace.status)
                        div(class: "mt-1 text-sm text-gray-500") do
                          format_duration(trace.duration_ms)
                        end
                      end
                    end
                  end
                end
              else
                p(class: "text-gray-500") { "No recent traces found." }
              end
            end
          end
        end

        def render_recent_errors
          div(class: "mt-8") do
            div(class: "bg-white overflow-hidden shadow rounded-lg") do
              div(class: "px-4 py-5 sm:px-6 flex justify-between items-center border-b border-red-200") do
                h3(class: "text-lg leading-6 font-medium text-red-900 flex items-center") do
                  i(class: "bi bi-exclamation-triangle mr-2")
                  plain "Recent Errors"
                end
                link_to(
                  "View All",
                  dashboard_errors_path,
                  class: "text-sm text-red-600 hover:text-red-500"
                )
              end

              div(class: "px-4 py-5 sm:p-6") do
                div(class: "space-y-3") do
                  @recent_errors.each do |span|
                    div(class: "p-4 border border-red-200 rounded-lg bg-red-50") do
                      div(class: "flex justify-between items-start") do
                        div(class: "min-w-0 flex-1") do
                          div(class: "font-medium text-red-900") do
                            plain span.name
                            span(class: "ml-2") { render_kind_badge(span.kind) }
                          end

                          div(class: "mt-1 text-sm text-red-700") do
                            plain "Trace: "
                            link_to(
                              span.trace&.workflow_name || span.trace_id,
                              tracing_trace_path(span.trace_id),
                              class: "text-red-700 hover:text-red-800"
                            )
                          end

                          if span.error_details&.dig('exception_message')
                            div(class: "mt-2 text-sm text-red-600") do
                              truncate(span.error_details['exception_message'], length: 100)
                            end
                          end
                        end

                        div(class: "text-sm text-red-500") do
                          "#{time_ago_in_words(span.start_time)} ago"
                        end
                      end
                    end
                  end
                end
              end
            end
          end
        end

        def render_success_rate_badge(rate)
          if rate > 95
            badge_class = "bg-green-100 text-green-800"
          elsif rate > 80
            badge_class = "bg-yellow-100 text-yellow-800"
          else
            badge_class = "bg-red-100 text-red-800"
          end

          span(class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium #{badge_class}") do
            "#{rate}%"
          end
        end

        def render_auto_refresh_script
          script do
            plain <<~JAVASCRIPT
              // Auto-refresh every 30 seconds for dashboard
              function enableAutoRefresh(interval) {
                if (window.dashboardRefreshInterval) {
                  clearInterval(window.dashboardRefreshInterval);
                }

                window.dashboardRefreshInterval = setInterval(() => {
                  window.location.reload();
                }, interval);
              }

              // Set up event handlers for buttons with data-onclick
              document.addEventListener('DOMContentLoaded', function() {
                document.querySelectorAll('[data-onclick]').forEach(button => {
                  const clickCode = button.getAttribute('data-onclick');
                  button.addEventListener('click', function(e) {
                    e.preventDefault();
                    eval(clickCode);
                  });
                });
              });

              enableAutoRefresh(30000);
            JAVASCRIPT
          end
        end
      end
    end
  end
end