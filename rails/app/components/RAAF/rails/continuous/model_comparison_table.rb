# frozen_string_literal: true

module RAAF
  module Rails
    module Continuous
      # Model Comparison Table Component
      # Displays performance comparison across different models
      class ModelComparisonTable < Phlex::HTML
        def initialize(url:, agent: nil, refresh_interval: 30000)
          @url = url
          @agent = agent
          @refresh_interval = refresh_interval
        end

        def view_template
          div(
            class: "model-comparison-container",
            data: {
              controller: "raaf--rails--continuous--model-comparison-table",
              raaf__rails__continuous__model_comparison_table_url_value: @url,
              raaf__rails__continuous__model_comparison_table_agent_value: @agent,
              raaf__rails__continuous__model_comparison_table_refresh_interval_value: @refresh_interval
            }
          ) do
            # Header with refresh button
            render_header

            # Loading state
            div(
              class: "hidden text-center py-8",
              data: { raaf__rails__continuous__model_comparison_table_target: "loading" }
            ) do
              span(class: "inline-block animate-spin mr-2") { "⏳" }
              span { "Loading model comparison..." }
            end

            # Error state
            div(
              class: "hidden text-red-500 text-center py-8",
              data: { raaf__rails__continuous__model_comparison_table_target: "error" }
            )

            # Table container
            div(
              class: "overflow-x-auto",
              data: { raaf__rails__continuous__model_comparison_table_target: "table" }
            )
          end
        end

        private

        def render_header
          div(class: "flex justify-between items-center mb-4") do
            h3(class: "text-lg font-semibold text-gray-900 dark:text-gray-100") do
              "Model Performance Comparison"
            end

            button(
              type: "button",
              class: "px-3 py-1 text-sm bg-blue-600 text-white rounded hover:bg-blue-700 transition-colors",
              data: { action: "click->raaf--rails--continuous--model-comparison-table#refresh" }
            ) do
              "Refresh"
            end
          end
        end
      end
    end
  end
end
