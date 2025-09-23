# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      class TracesIndex < BaseComponent
        def initialize(traces:, stats: nil, params: {}, total_pages: 1, page: 1, per_page: 20, total_count: 0)
          @traces = traces
          @stats = stats
          @params = params
          @total_pages = total_pages
          @page = page
          @per_page = per_page
          @total_count = total_count
        end

        def view_template
          div(
            id: "tracing-dashboard",
            class: "p-6",
            data: {
              controller: "dashboard",
              "dashboard-channel-name-value": "RubyAIAgentsFactory::Tracing::TracesChannel",
              "dashboard-polling-interval-value": "5000",
              "dashboard-auto-refresh-value": "true"
            }
          ) do
            render_header
            render_connection_status
            render_filters
            render_stats if @stats
            render_traces_table
            render_last_updated
          end
        end

        private

        def render_header
          div(class: "sm:flex sm:items-center sm:justify-between mb-6") do
            div(class: "min-w-0 flex-1") do
              h1(class: "text-2xl font-bold leading-7 text-gray-900 sm:text-3xl sm:truncate") { "Traces" }
              p(class: "mt-1 text-sm text-gray-500") { "Monitor and analyze your agent execution traces" }
            end

            div(class: "mt-4 flex sm:mt-0 sm:ml-4") do
              div(class: "flex space-x-3") do
                render_preline_button(
                  text: "Refresh",
                  variant: "secondary",
                  icon: "bi-arrow-clockwise",
                  id: "refresh-dashboard",
                  data: { "dashboard-target": "refreshButton" }
                )

                render_preline_button(
                  text: "Export JSON",
                  href: "/raaf/tracing/traces.json",
                  variant: "secondary",
                  icon: "bi-download"
                )
              end

              div(class: "flex items-center ml-4") do
                input(
                  type: "checkbox",
                  id: "auto-refresh-toggle",
                  checked: true,
                  class: "w-4 h-4 text-blue-600 bg-gray-100 border-gray-300 rounded focus:ring-blue-500",
                  data: { "dashboard-target": "autoRefreshToggle" }
                )
                label(for: "auto-refresh-toggle", class: "ml-2 text-sm font-medium text-gray-900") do
                  "Auto-refresh"
                end
              end
            end
          end
        end

        def render_connection_status
          div(
            id: "connection-status",
            class: "hidden mb-4 p-4 bg-blue-50 border border-blue-200 rounded-lg",
            role: "alert",
            data: { "dashboard-target": "connectionStatus" }
          ) do
            div(class: "flex") do
              div(class: "flex-shrink-0") do
                i(class: "bi bi-info-circle text-blue-400")
              end
              div(class: "ml-3") do
                span(class: "status-text text-sm text-blue-800") { "Connecting..." }
              end
            end
          end
        end

        def render_filters
          div(class: "bg-white p-6 rounded-lg shadow mb-6") do
            form_with(url: "/raaf/tracing/traces", method: :get, local: true, class: "grid grid-cols-1 gap-4 sm:grid-cols-6") do |form|
              div(class: "sm:col-span-2") do
                label(class: "block text-sm font-medium text-gray-700 mb-1") { "Search" }
                form.text_field(
                  :search,
                  placeholder: "Search traces...",
                  value: @params[:search],
                  class: "block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                )
              end

              div(class: "sm:col-span-1") do
                label(class: "block text-sm font-medium text-gray-700 mb-1") { "Workflow" }
                form.select(
                  :workflow,
                  [["All Workflows", ""]] + workflow_options,
                  { selected: @params[:workflow] },
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
                    ["Running", "running"],
                    ["Pending", "pending"]
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
                  form.submit("Filter", class: "w-full inline-flex justify-center items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500")
                end
              end
            end
          end
        end

        def render_stats
          return unless @stats

          div(class: "grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-4 mb-8") do
            render_metric_card(
              title: "Total",
              value: @stats[:total],
              color: "blue",
              icon: "bi-diagram-3"
            )

            render_metric_card(
              title: "Completed",
              value: @stats[:completed],
              color: "green",
              icon: "bi-check-circle"
            )

            render_metric_card(
              title: "Failed",
              value: @stats[:failed],
              color: "red",
              icon: "bi-x-circle"
            )

            render_metric_card(
              title: "Running",
              value: @stats[:running],
              color: "yellow",
              icon: "bi-play-circle"
            )
          end
        end

        def render_traces_table
          div(
            id: "traces-table-container",
            data: { "dashboard-target": "tracesContainer" }
          ) do
            render TracesTable.new(
              traces: @traces,
              page: @page,
              total_pages: @total_pages,
              per_page: @per_page,
              total_count: @total_count,
              params: @params
            )
          end
        end

        def render_last_updated
          div(class: "mt-6 text-right text-sm text-gray-500") do
            plain "Last updated: "
            span(
              id: "last-updated",
              data: { "dashboard-target": "lastUpdated" }
            ) { Time.current.strftime("%Y-%m-%d %H:%M:%S") }
          end
        end

        def workflow_options
          # This would normally come from the controller/service
          # For now, returning empty array, but in real implementation:
          # RubyAIAgentsFactory::Tracing::TraceRecord.distinct.pluck(:workflow_name).compact.map { |w| [w, w] }
          []
        end

      end
    end
  end
end