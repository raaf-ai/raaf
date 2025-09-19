# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      class CostsIndex < BaseComponent
        def initialize(cost_data:, params: {})
          @cost_data = cost_data
          @params = params
        end

        def view_template
          div(class: "p-6") do
            render_header
            render_time_filter
            render_cost_overview
            render_cost_breakdown
          end
        end

        private

        def render_header
          div(class: "sm:flex sm:items-center sm:justify-between mb-6") do
            div(class: "min-w-0 flex-1") do
              h1(class: "text-2xl font-bold leading-7 text-gray-900 sm:text-3xl sm:truncate") { "Cost Tracking" }
              p(class: "mt-1 text-sm text-gray-500") { "Monitor AI model usage costs and token consumption" }
            end

            div(class: "mt-4 flex sm:mt-0 sm:ml-4") do
              render_preline_button(
                text: "Export Report",
                href: "/raaf/tracing/costs.json",
                variant: "secondary",
                icon: "bi-download"
              )
            end
          end
        end

        def render_time_filter
          div(class: "bg-white p-6 rounded-lg shadow mb-6") do
            form_with(url: "/raaf/tracing/costs", method: :get, local: true, class: "grid grid-cols-1 gap-4 sm:grid-cols-4") do |form|
              div do
                label(class: "block text-sm font-medium text-gray-700 mb-1") { "Start Date" }
                form.date_field(
                  :start_date,
                  value: @params[:start_date] || 30.days.ago.to_date,
                  class: "block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                )
              end

              div do
                label(class: "block text-sm font-medium text-gray-700 mb-1") { "End Date" }
                form.date_field(
                  :end_date,
                  value: @params[:end_date] || Date.current,
                  class: "block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                )
              end

              div do
                label(class: "block text-sm font-medium text-gray-700 mb-1") { "Model" }
                form.select(
                  :model,
                  [
                    ["All Models", ""],
                    ["GPT-4", "gpt-4"],
                    ["GPT-4 Turbo", "gpt-4-turbo"],
                    ["GPT-3.5 Turbo", "gpt-3.5-turbo"],
                    ["Claude 3", "claude-3"]
                  ],
                  { selected: @params[:model] },
                  { class: "block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm" }
                )
              end

              div(class: "flex items-end space-x-3") do
                form.submit(
                  "Apply Filter",
                  class: "flex-1 inline-flex justify-center items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700"
                )
                link_to(
                  "Reset",
                  "/raaf/tracing/costs",
                  class: "flex-1 inline-flex justify-center items-center px-4 py-2 border border-gray-300 text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50"
                )
              end
            end
          end
        end

        def render_cost_overview
          div(class: "grid grid-cols-1 gap-5 sm:grid-cols-4 mb-8") do
            render_cost_metric_card(
              title: "Total Cost",
              value: format_currency(@cost_data[:total_cost] || 0),
              color: "blue",
              icon: "bi-currency-dollar"
            )

            render_cost_metric_card(
              title: "Total Tokens",
              value: format_number(@cost_data[:total_tokens] || 0),
              color: "green",
              icon: "bi-hash"
            )

            render_cost_metric_card(
              title: "Avg Cost per Trace",
              value: format_currency(@cost_data[:avg_cost_per_trace] || 0),
              color: "purple",
              icon: "bi-graph-up"
            )

            render_cost_metric_card(
              title: "Most Expensive Model",
              value: @cost_data[:most_expensive_model] || "N/A",
              color: "yellow",
              icon: "bi-cpu"
            )
          end
        end

        def render_cost_breakdown
          div(class: "grid grid-cols-1 gap-6 lg:grid-cols-2") do
            render_cost_by_model
            render_cost_by_workflow
          end
        end

        def render_cost_by_model
          div(class: "bg-white overflow-hidden shadow rounded-lg") do
            div(class: "px-4 py-5 sm:px-6 border-b border-gray-200") do
              h3(class: "text-lg leading-6 font-medium text-gray-900") { "Cost by Model" }
            end

            div(class: "px-4 py-5 sm:p-6") do
              if @cost_data[:by_model]&.any?
                div(class: "space-y-4") do
                  @cost_data[:by_model].each do |model_data|
                    render_cost_breakdown_item(
                      name: model_data[:model],
                      cost: model_data[:cost],
                      tokens: model_data[:tokens],
                      percentage: model_data[:percentage]
                    )
                  end
                end
              else
                p(class: "text-gray-500") { "No cost data available for the selected period." }
              end
            end
          end
        end

        def render_cost_by_workflow
          div(class: "bg-white overflow-hidden shadow rounded-lg") do
            div(class: "px-4 py-5 sm:px-6 border-b border-gray-200") do
              h3(class: "text-lg leading-6 font-medium text-gray-900") { "Cost by Workflow" }
            end

            div(class: "px-4 py-5 sm:p-6") do
              if @cost_data[:by_workflow]&.any?
                div(class: "space-y-4") do
                  @cost_data[:by_workflow].each do |workflow_data|
                    render_cost_breakdown_item(
                      name: workflow_data[:workflow],
                      cost: workflow_data[:cost],
                      tokens: workflow_data[:tokens],
                      percentage: workflow_data[:percentage]
                    )
                  end
                end
              else
                p(class: "text-gray-500") { "No workflow cost data available." }
              end
            end
          end
        end

        def render_cost_breakdown_item(name:, cost:, tokens:, percentage:)
          div(class: "border border-gray-200 rounded-lg p-4") do
            div(class: "flex justify-between items-start mb-2") do
              div(class: "font-medium text-gray-900") { name }
              div(class: "text-right") do
                div(class: "font-medium text-gray-900") { format_currency(cost) }
                div(class: "text-sm text-gray-500") { format_number(tokens) + " tokens" }
              end
            end

            div(class: "w-full bg-gray-200 rounded-full h-2") do
              div(
                class: "bg-blue-600 h-2 rounded-full",
                style: "width: #{[percentage || 0, 100].min}%"
              )
            end

            div(class: "mt-1 text-sm text-gray-500") do
              "#{percentage || 0}% of total cost"
            end
          end
        end

        def render_cost_metric_card(title:, value:, color:, icon:)
          div(class: "bg-white overflow-hidden shadow rounded-lg") do
            div(class: "p-5") do
              div(class: "flex items-center") do
                div(class: "flex-shrink-0") do
                  div(class: "w-8 h-8 bg-#{color}-500 rounded-md flex items-center justify-center") do
                    i(class: "bi #{icon} text-white")
                  end
                end
                div(class: "ml-5 w-0 flex-1") do
                  dt(class: "text-sm font-medium text-gray-500 truncate") { title }
                  dd do
                    div(class: "text-lg font-medium text-gray-900") { value }
                  end
                end
              end
            end
          end
        end

        def format_currency(amount)
          return "$0.00" unless amount
          "$#{'%.2f' % amount}"
        end

        def format_number(number)
          return "0" unless number
          number.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
        end
      end
    end
  end
end