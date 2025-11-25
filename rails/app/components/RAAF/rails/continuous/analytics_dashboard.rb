# frozen_string_literal: true

module RAAF
  module Rails
    module Continuous
      class AnalyticsDashboard < Phlex::HTML
        include Phlex::Rails::Helpers::LinkTo
        include Phlex::Rails::Helpers::FormWith

        def initialize(stats: {}, filters: {}, agents: [], environments: [])
          @stats = stats
          @filters = filters
          @agents = agents
          @environments = environments
        end

        def view_template
          div(class: "container-fluid") do
            render_header
            render_filters
            render_overview_stats
            render_charts_section
            render_model_comparison
          end
        end

        private

        def render_header
          div(class: "d-flex justify-content-between flex-wrap flex-md-nowrap align-items-center pt-3 pb-2 mb-3 border-bottom") do
            div do
              h1(class: "h2") { "Continuous Evaluation Analytics" }
              p(class: "text-muted") { "Analyze evaluation trends and agent performance" }
            end

            div(class: "btn-toolbar mb-2 mb-md-0") do
              div(class: "btn-group me-2") do
                a(
                  href: "javascript:window.location.reload();",
                  class: "btn btn-sm btn-outline-secondary"
                ) do
                  i(class: "bi bi-arrow-clockwise me-1")
                  plain "Refresh"
                end
              end
            end
          end
        end

        def render_filters
          div(class: "card mb-4") do
            div(class: "card-header") do
              h5(class: "card-title mb-0") { "Filters" }
            end
            div(class: "card-body") do
              form(method: "get", class: "row g-3") do
                div(class: "col-md-3") do
                  label(for: "agent-filter", class: "form-label") { "Agent" }
                  select(name: "agent_name", id: "agent-filter", class: "form-select") do
                    option(value: "", selected: @filters[:agent_name].blank?) { "All agents" }
                    @agents.each do |agent|
                      option(value: agent, selected: @filters[:agent_name] == agent) { agent }
                    end
                  end
                end

                div(class: "col-md-3") do
                  label(for: "environment-filter", class: "form-label") { "Environment" }
                  select(name: "environment", id: "environment-filter", class: "form-select") do
                    option(value: "", selected: @filters[:environment].blank?) { "All environments" }
                    @environments.each do |env|
                      option(value: env, selected: @filters[:environment] == env) { env }
                    end
                  end
                end

                div(class: "col-md-2") do
                  label(for: "date-from", class: "form-label") { "From Date" }
                  input(
                    type: "date",
                    name: "date_from",
                    id: "date-from",
                    class: "form-control",
                    value: @filters[:date_from]
                  )
                end

                div(class: "col-md-2") do
                  label(for: "date-to", class: "form-label") { "To Date" }
                  input(
                    type: "date",
                    name: "date_to",
                    id: "date-to",
                    class: "form-control",
                    value: @filters[:date_to]
                  )
                end

                div(class: "col-md-2 d-flex align-items-end") do
                  button(type: "submit", class: "btn btn-primary w-100") { "Apply" }
                end
              end
            end
          end
        end

        def render_overview_stats
          div(class: "row mb-4") do
            div(class: "col-md-3") do
              render_stat_card("Total Evaluations", @stats[:total_evaluations] || 0, "bi-graph-up", "primary")
            end

            div(class: "col-md-3") do
              render_stat_card(
                "Pass Rate",
                format_percentage(@stats[:pass_rate] || 0),
                "bi-check-circle",
                "success"
              )
            end

            div(class: "col-md-3") do
              render_stat_card(
                "Avg Score",
                format_score(@stats[:avg_score] || 0),
                "bi-star",
                "info"
              )
            end

            div(class: "col-md-3") do
              render_stat_card(
                "Total Cost",
                format_cost(@stats[:total_cost] || 0),
                "bi-currency-dollar",
                "warning"
              )
            end
          end
        end

        def render_stat_card(label, value, icon, color)
          div(class: "card border-#{color}") do
            div(class: "card-body") do
              div(class: "d-flex justify-content-between align-items-center") do
                div do
                  h3(class: "card-title text-#{color} mb-0") { value }
                  p(class: "text-muted mb-0") { label }
                end
                i(class: "bi #{icon} display-4 text-#{color} opacity-25")
              end
            end
          end
        end

        def render_charts_section
          div(class: "row mb-4") do
            div(class: "col-md-6") do
              render_pass_rate_chart
            end

            div(class: "col-md-6") do
              render_score_distribution_chart
            end
          end
        end

        def render_pass_rate_chart
          div(class: "card") do
            div(class: "card-header") do
              h5(class: "card-title mb-0") { "Pass Rate Over Time" }
            end
            div(class: "card-body") do
              # D3.js chart placeholder
              div(
                id: "pass-rate-chart",
                class: "chart-container",
                style: "height: 300px; background: linear-gradient(135deg, #f5f7fa 0%, #c3cfe2 100%);",
                data: {
                  controller: "d3-chart",
                  chart_type: "line",
                  chart_data: chart_data_json(:pass_rate)
                }
              ) do
                div(class: "d-flex align-items-center justify-content-center h-100") do
                  div(class: "text-center text-muted") do
                    i(class: "bi bi-graph-up display-4")
                    p(class: "mt-2") { "Pass rate trend visualization" }
                    small { "Chart will be rendered with D3.js" }
                  end
                end
              end
            end
          end
        end

        def render_score_distribution_chart
          div(class: "card") do
            div(class: "card-header") do
              h5(class: "card-title mb-0") { "Score Distribution" }
            end
            div(class: "card-body") do
              # D3.js chart placeholder
              div(
                id: "score-distribution-chart",
                class: "chart-container",
                style: "height: 300px; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);",
                data: {
                  controller: "d3-chart",
                  chart_type: "histogram",
                  chart_data: chart_data_json(:score_distribution)
                }
              ) do
                div(class: "d-flex align-items-center justify-content-center h-100") do
                  div(class: "text-center text-white") do
                    i(class: "bi bi-bar-chart display-4")
                    p(class: "mt-2") { "Score distribution visualization" }
                    small { "Chart will be rendered with D3.js" }
                  end
                end
              end
            end
          end
        end

        def render_model_comparison
          div(class: "card") do
            div(class: "card-header") do
              h5(class: "card-title mb-0") { "Model Comparison" }
            end
            div(class: "card-body") do
              if @stats[:model_comparison]&.any?
                div(class: "table-responsive") do
                  table(class: "table table-sm table-hover") do
                    thead do
                      tr do
                        th { "Model" }
                        th { "Evaluations" }
                        th { "Pass Rate" }
                        th { "Avg Score" }
                        th { "Avg Cost" }
                        th { "Avg Duration" }
                      end
                    end
                    tbody do
                      @stats[:model_comparison].each do |model_stat|
                        render_model_row(model_stat)
                      end
                    end
                  end
                end
              else
                div(class: "text-center py-5 text-muted") do
                  i(class: "bi bi-cpu display-4")
                  h5(class: "mt-3") { "No model data available" }
                  p { "Model comparison will appear once evaluations are run" }
                end
              end
            end
          end
        end

        def render_model_row(model_stat)
          tr do
            td do
              strong { model_stat[:model_name] }
            end

            td { model_stat[:count].to_s }

            td do
              percentage = model_stat[:pass_rate]
              badge_class = if percentage >= 80
                              "bg-success"
                            elsif percentage >= 60
                              "bg-warning text-dark"
                            else
                              "bg-danger"
                            end
              span(class: "badge #{badge_class}") { "#{percentage}%" }
            end

            td do
              render_score_badge(model_stat[:avg_score])
            end

            td { format_cost(model_stat[:avg_cost]) }

            td { format_duration(model_stat[:avg_duration_ms]) }
          end
        end

        def render_score_badge(score)
          return span(class: "text-muted") { "N/A" } unless score

          numeric_score = score.to_f
          badge_class = if numeric_score >= 0.8
                          "bg-success"
                        elsif numeric_score >= 0.6
                          "bg-warning text-dark"
                        else
                          "bg-danger"
                        end

          span(class: "badge #{badge_class}") { format_score(score) }
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
          "$#{format('%.4f', cost)}"
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
          # Placeholder for chart data
          # In real implementation, this would be populated from @stats
          {
            chart_type: chart_type,
            data: []
          }.to_json
        end
      end
    end
  end
end
