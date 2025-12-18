# frozen_string_literal: true

module RAAF
  module Rails
    module Continuous
      class AnalyticsDashboard < RAAF::Rails::Tracing::BaseComponent

        def initialize(stats: {}, filters: {}, agents: [], environments: [])
          @stats = stats
          @filters = filters
          @agents = agents
          @environments = environments
        end

        def view_template
          div(class: "p-6") do
            render_header
            render_filters
            render_overview_stats
            render_charts_section
            render_model_comparison
          end
        end

        private

        def render_header
          div(class: "sm:flex sm:items-center sm:justify-between mb-6 pb-4 border-b border-gray-200") do
            div do
              h1(class: "text-2xl font-bold text-gray-900") { "Continuous Evaluation Analytics" }
              p(class: "mt-1 text-sm text-gray-500") { "Analyze evaluation trends and agent performance" }
            end

            div(class: "mt-4 sm:mt-0 flex gap-2") do
              render_preline_button(
                text: "Refresh",
                href: "javascript:window.location.reload();",
                variant: "secondary",
                icon: "bi-arrow-clockwise"
              )
            end
          end
        end

        def render_filters
          div(class: "bg-white shadow rounded-lg overflow-hidden mb-6") do
            div(class: "px-4 py-5 sm:px-6 border-b border-gray-200") do
              h3(class: "text-lg font-medium text-gray-900") { "Filters" }
            end
            div(class: "px-4 py-5 sm:p-6") do
              form(method: "get", class: "grid grid-cols-1 gap-4 sm:grid-cols-5") do
                div do
                  label(for: "agent-filter", class: "block text-sm font-medium text-gray-700 mb-1") { "Agent" }
                  select(
                    name: "agent_name",
                    id: "agent-filter",
                    class: "block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                  ) do
                    option(value: "", selected: @filters[:agent_name].blank?) { "All agents" }
                    @agents.each do |agent|
                      option(value: agent, selected: @filters[:agent_name] == agent) { agent }
                    end
                  end
                end

                div do
                  label(for: "environment-filter", class: "block text-sm font-medium text-gray-700 mb-1") { "Environment" }
                  select(
                    name: "environment",
                    id: "environment-filter",
                    class: "block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                  ) do
                    option(value: "", selected: @filters[:environment].blank?) { "All environments" }
                    @environments.each do |env|
                      option(value: env, selected: @filters[:environment] == env) { env }
                    end
                  end
                end

                div do
                  label(for: "date-from", class: "block text-sm font-medium text-gray-700 mb-1") { "From Date" }
                  input(
                    type: "date",
                    name: "date_from",
                    id: "date-from",
                    class: "block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm",
                    value: @filters[:date_from]
                  )
                end

                div do
                  label(for: "date-to", class: "block text-sm font-medium text-gray-700 mb-1") { "To Date" }
                  input(
                    type: "date",
                    name: "date_to",
                    id: "date-to",
                    class: "block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm",
                    value: @filters[:date_to]
                  )
                end

                div(class: "flex items-end") do
                  button(
                    type: "submit",
                    class: "w-full inline-flex justify-center items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700"
                  ) { "Apply" }
                end
              end
            end
          end
        end

        def render_overview_stats
          div(class: "grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-4 mb-6") do
            render_stat_card("Total Evaluations", @stats[:total_evaluations] || 0, "bi-graph-up", "blue")
            render_stat_card(
              "Good Rate",
              format_percentage(@stats[:good_rate] || @stats[:pass_rate] || 0),
              "bi-check-circle",
              "green"
            )
            render_stat_card(
              "Avg Score",
              format_score(@stats[:avg_score] || 0),
              "bi-star",
              "cyan"
            )
            render_stat_card(
              "Total Cost",
              format_cost(@stats[:total_cost] || 0),
              "bi-currency-dollar",
              "yellow"
            )
          end
        end

        def render_stat_card(label, value, icon, color)
          border_color = case color
                        when "blue" then "border-blue-500"
                        when "green" then "border-green-500"
                        when "cyan" then "border-cyan-500"
                        when "yellow" then "border-yellow-500"
                        else "border-gray-300"
                        end

          text_color = case color
                      when "blue" then "text-blue-600"
                      when "green" then "text-green-600"
                      when "cyan" then "text-cyan-600"
                      when "yellow" then "text-yellow-600"
                      else "text-gray-600"
                      end

          icon_bg = case color
                   when "blue" then "text-blue-200"
                   when "green" then "text-green-200"
                   when "cyan" then "text-cyan-200"
                   when "yellow" then "text-yellow-200"
                   else "text-gray-200"
                   end

          div(class: "bg-white shadow rounded-lg overflow-hidden border-l-4 #{border_color}") do
            div(class: "px-4 py-5 sm:p-6") do
              div(class: "flex justify-between items-center") do
                div do
                  div(class: "text-2xl font-bold #{text_color}") { value }
                  p(class: "text-sm text-gray-500") { label }
                end
                i(class: "bi #{icon} text-4xl #{icon_bg}")
              end
            end
          end
        end

        def render_charts_section
          div(class: "grid grid-cols-1 gap-6 lg:grid-cols-2 mb-6") do
            render_quality_rate_chart
            render_score_distribution_chart
          end
        end

        def render_quality_rate_chart
          div(class: "bg-white shadow rounded-lg overflow-hidden") do
            div(class: "px-4 py-5 sm:px-6 border-b border-gray-200") do
              h3(class: "text-lg font-medium text-gray-900") { "Quality Rate Over Time" }
            end
            div(class: "px-4 py-5 sm:p-6") do
              div(
                id: "quality-rate-chart",
                class: "h-72 bg-gradient-to-br from-gray-50 to-gray-100 rounded-lg",
                data: {
                  controller: "d3-chart",
                  chart_type: "line",
                  chart_data: chart_data_json(:quality_rate)
                }
              ) do
                div(class: "flex items-center justify-center h-full") do
                  div(class: "text-center text-gray-500") do
                    i(class: "bi bi-graph-up text-5xl text-gray-300")
                    p(class: "mt-2") { "Quality rate trend visualization" }
                    span(class: "text-xs") { "Chart will be rendered with D3.js" }
                  end
                end
              end
            end
          end
        end

        def render_score_distribution_chart
          div(class: "bg-white shadow rounded-lg overflow-hidden") do
            div(class: "px-4 py-5 sm:px-6 border-b border-gray-200") do
              h3(class: "text-lg font-medium text-gray-900") { "Score Distribution" }
            end
            div(class: "px-4 py-5 sm:p-6") do
              div(
                id: "score-distribution-chart",
                class: "h-72 bg-gradient-to-br from-indigo-100 to-purple-100 rounded-lg",
                data: {
                  controller: "d3-chart",
                  chart_type: "histogram",
                  chart_data: chart_data_json(:score_distribution)
                }
              ) do
                div(class: "flex items-center justify-center h-full") do
                  div(class: "text-center text-gray-600") do
                    i(class: "bi bi-bar-chart text-5xl text-indigo-300")
                    p(class: "mt-2") { "Score distribution visualization" }
                    span(class: "text-xs") { "Chart will be rendered with D3.js" }
                  end
                end
              end
            end
          end
        end

        def render_model_comparison
          div(class: "bg-white shadow rounded-lg overflow-hidden") do
            div(class: "px-4 py-5 sm:px-6 border-b border-gray-200") do
              h3(class: "text-lg font-medium text-gray-900") { "Model Comparison" }
            end
            div(class: "px-4 py-5 sm:p-6") do
              if @stats[:model_comparison]&.any?
                div(class: "overflow-x-auto") do
                  table(class: "min-w-full divide-y divide-gray-200") do
                    thead(class: "bg-gray-50") do
                      tr do
                        th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider") { "Model" }
                        th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider") { "Evaluations" }
                        th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider") { "Good Rate" }
                        th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider") { "Avg Score" }
                        th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider") { "Avg Cost" }
                        th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider") { "Avg Duration" }
                      end
                    end
                    tbody(class: "bg-white divide-y divide-gray-200") do
                      @stats[:model_comparison].each do |model_stat|
                        render_model_row(model_stat)
                      end
                    end
                  end
                end
              else
                render_empty_state
              end
            end
          end
        end

        def render_empty_state
          div(class: "flex flex-col items-center justify-center py-12") do
            i(class: "bi bi-cpu text-5xl text-gray-400")
            h3(class: "mt-4 text-lg font-medium text-gray-900") { "No model data available" }
            p(class: "mt-1 text-sm text-gray-500") { "Model comparison will appear once evaluations are run" }
          end
        end

        def render_model_row(model_stat)
          tr(class: "hover:bg-gray-50") do
            td(class: "px-4 py-4 text-sm") do
              span(class: "font-medium text-gray-900") { model_stat[:model_name] }
            end

            td(class: "px-4 py-4 text-sm text-gray-500") do
              model_stat[:count].to_s
            end

            td(class: "px-4 py-4 text-sm") do
              percentage = model_stat[:good_rate] || model_stat[:pass_rate] || 0
              color = if percentage >= 80
                        "green"
                      elsif percentage >= 60
                        "yellow"
                      else
                        "red"
                      end
              render_badge("#{percentage}%", color)
            end

            td(class: "px-4 py-4 text-sm") do
              render_score_badge(model_stat[:avg_score])
            end

            td(class: "px-4 py-4 text-sm text-gray-500") do
              format_cost(model_stat[:avg_cost])
            end

            td(class: "px-4 py-4 text-sm text-gray-500") do
              format_duration(model_stat[:avg_duration_ms])
            end
          end
        end

        def render_score_badge(score)
          return span(class: "text-gray-400") { "N/A" } unless score

          numeric_score = score.to_f
          color = if numeric_score >= 0.8
                    "green"
                  elsif numeric_score >= 0.6
                    "yellow"
                  else
                    "red"
                  end

          render_badge(format_score(score), color)
        end

        def render_badge(text, color)
          color_classes = case color
                         when "blue" then "bg-blue-100 text-blue-800"
                         when "green" then "bg-green-100 text-green-800"
                         when "red" then "bg-red-100 text-red-800"
                         when "yellow" then "bg-yellow-100 text-yellow-800"
                         else "bg-gray-100 text-gray-800"
                         end

          span(class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium #{color_classes}") do
            text
          end
        end

        def format_percentage(value)
          return "0%" unless value
          "#{value.round(1)}%"
        end

        def format_score(score)
          return "N/A" unless score
          score.is_a?(Numeric) ? score.round(2).to_s : score.to_s
        end

        def format_cost(cost)
          return "$0.00" unless cost
          "$#{sprintf('%.4f', cost)}"
        end

        def format_duration(ms)
          return "N/A" unless ms
          if ms < 1000
            "#{ms.round}ms"
          else
            "#{(ms / 1000.0).round(2)}s"
          end
        end

        def chart_data_json(chart_type)
          {
            chart_type: chart_type,
            data: []
          }.to_json
        end
      end
    end
  end
end
