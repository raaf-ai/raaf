# frozen_string_literal: true

module RAAF
  module Rails
    module Continuous
      class PolicyShow < Phlex::HTML
        include Phlex::Rails::Helpers::LinkTo
        include Phlex::Rails::Helpers::ButtonTo
        include Phlex::Rails::Helpers::Pluralize
        include Phlex::Rails::Helpers::TimeAgoInWords

        def initialize(policy:, today_stats: {}, recent_results: [])
          @policy = policy
          @today_stats = today_stats
          @recent_results = recent_results
        end

        def view_template
          div(class: "container-fluid") do
            render_header
            div(class: "row") do
              div(class: "col-md-8") do
                render_policy_details
                render_evaluators_section
                render_recent_results
              end
              div(class: "col-md-4") do
                render_stats_sidebar
                render_actions_sidebar
              end
            end
          end
        end

        private

        def render_header
          div(class: "d-flex justify-content-between flex-wrap flex-md-nowrap align-items-center pt-3 pb-2 mb-3 border-bottom") do
            div do
              h1(class: "h2") do
                plain @policy.name
                plain " "
                render_status_badge(@policy)
              end
              if @policy.description.present?
                p(class: "text-muted") { @policy.description }
              end
            end

            div(class: "btn-toolbar mb-2 mb-md-0") do
              div(class: "btn-group me-2") do
                link_to("Edit", edit_continuous_policy_path(@policy), class: "btn btn-sm btn-outline-primary")
                if @policy.active?
                  button_to("Deactivate",
                    deactivate_continuous_policy_path(@policy),
                    method: :patch,
                    class: "btn btn-sm btn-outline-warning")
                else
                  button_to("Activate",
                    activate_continuous_policy_path(@policy),
                    method: :patch,
                    class: "btn btn-sm btn-outline-success")
                end
              end
            end
          end
        end

        def render_policy_details
          div(class: "card mb-4") do
            div(class: "card-header") do
              h5(class: "card-title mb-0") { "Policy Configuration" }
            end
            div(class: "card-body") do
              dl(class: "row mb-0") do
                render_detail_row("Agent", @policy.agent_name.presence || "All agents")
                render_detail_row("Environment", @policy.environment.presence || "All environments")
                render_detail_row("Model Pattern", @policy.model_pattern.presence || "All models")
                render_detail_row("Sampling Mode", format_sampling_mode)
                render_detail_row("Daily Limit", @policy.max_daily_evaluations&.to_s || "Unlimited")
                render_detail_row("Retention", "#{@policy.retention_days} days")
                render_detail_row("Priority", @policy.priority.to_s)
                render_detail_row("Queue", @policy.queue_name.presence || "default")
              end
            end
          end
        end

        def render_evaluators_section
          div(class: "card mb-4") do
            div(class: "card-header") do
              h5(class: "card-title mb-0") { "Configured Evaluators" }
            end
            div(class: "card-body") do
              if @policy.evaluators.any?
                div(class: "list-group list-group-flush") do
                  @policy.evaluators.each do |evaluator|
                    render_evaluator_item(evaluator)
                  end
                end
              else
                p(class: "text-muted mb-0") { "No evaluators configured" }
              end
            end
          end
        end

        def render_evaluator_item(evaluator)
          div(class: "list-group-item") do
            div(class: "d-flex justify-content-between align-items-start") do
              div do
                strong { evaluator.name }
                br
                small(class: "text-muted") { evaluator.description }
              end
              div do
                span(class: "badge bg-#{evaluator_type_color(evaluator.evaluator_type)}") do
                  evaluator.evaluator_type
                end
                if evaluator.uses_llm?
                  span(class: "badge bg-warning text-dark ms-1") { "LLM" }
                end
              end
            end
          end
        end

        def render_stats_sidebar
          div(class: "card mb-4") do
            div(class: "card-header") do
              h5(class: "card-title mb-0") { "Today's Statistics" }
            end
            div(class: "card-body") do
              render_stat_item("Evaluations", @today_stats[:total] || 0)
              render_stat_item("Passed", @today_stats[:passed] || 0, "text-success")
              render_stat_item("Failed", @today_stats[:failed] || 0, "text-danger")
              render_stat_item("Avg Score", format_score(@today_stats[:avg_score]))

              if @policy.max_daily_evaluations
                hr
                div(class: "mt-3") do
                  small(class: "text-muted") { "Daily Usage" }
                  div(class: "progress mt-2", style: "height: 20px;") do
                    percentage = (@today_stats[:total].to_f / @policy.max_daily_evaluations * 100).round
                    progress_class = if percentage >= 90
                                      "bg-danger"
                                    elsif percentage >= 70
                                      "bg-warning"
                                    else
                                      "bg-success"
                                    end
                    div(
                      class: "progress-bar #{progress_class}",
                      role: "progressbar",
                      style: "width: #{[percentage, 100].min}%",
                      aria_valuenow: percentage,
                      aria_valuemin: "0",
                      aria_valuemax: "100"
                    ) do
                      "#{percentage}%"
                    end
                  end
                end
              end
            end
          end
        end

        def render_actions_sidebar
          div(class: "card") do
            div(class: "card-header") do
              h5(class: "card-title mb-0") { "Actions" }
            end
            div(class: "list-group list-group-flush") do
              link_to(continuous_queue_items_path(policy_id: @policy.id),
                class: "list-group-item list-group-item-action") do
                i(class: "bi bi-list-task me-2")
                plain "View Queue Items"
              end

              link_to(continuous_results_path(policy_id: @policy.id),
                class: "list-group-item list-group-item-action") do
                i(class: "bi bi-graph-up me-2")
                plain "View Results"
              end

              link_to(continuous_analytics_path(policy_id: @policy.id),
                class: "list-group-item list-group-item-action") do
                i(class: "bi bi-bar-chart me-2")
                plain "Analytics Dashboard"
              end

              hr(class: "my-0")

              link_to(edit_continuous_policy_path(@policy),
                class: "list-group-item list-group-item-action text-primary") do
                i(class: "bi bi-pencil me-2")
                plain "Edit Policy"
              end

              button_to("Duplicate Policy",
                duplicate_continuous_policy_path(@policy),
                method: :post,
                class: "list-group-item list-group-item-action text-info")

              button_to("Delete Policy",
                continuous_policy_path(@policy),
                method: :delete,
                class: "list-group-item list-group-item-action text-danger",
                data: { confirm: "Are you sure? This will delete all associated data." })
            end
          end
        end

        def render_recent_results
          div(class: "card mb-4") do
            div(class: "card-header d-flex justify-content-between align-items-center") do
              h5(class: "card-title mb-0") { "Recent Results" }
              link_to("View All", continuous_results_path(policy_id: @policy.id), class: "btn btn-sm btn-outline-primary")
            end
            div(class: "card-body") do
              if @recent_results.any?
                div(class: "list-group list-group-flush") do
                  @recent_results.first(5).each do |result|
                    render_result_item(result)
                  end
                end
              else
                p(class: "text-muted mb-0") { "No results yet" }
              end
            end
          end
        end

        def render_result_item(result)
          div(class: "list-group-item") do
            div(class: "d-flex justify-content-between align-items-start") do
              div do
                small(class: "text-muted") do
                  plain result.evaluator_name
                  plain " • "
                  plain time_ago_in_words(result.created_at)
                  plain " ago"
                end
                br
                render_result_status_badge(result)
                if result.score
                  span(class: "ms-2") { "Score: #{format_score(result.score)}" }
                end
              end
              link_to("View", continuous_result_path(result), class: "btn btn-sm btn-outline-primary")
            end
          end
        end

        def render_detail_row(label, value)
          dt(class: "col-sm-4 text-muted") { label }
          dd(class: "col-sm-8") { value }
        end

        def render_stat_item(label, value, color_class = nil)
          div(class: "d-flex justify-content-between align-items-center mb-2") do
            span(class: "text-muted") { label }
            span(class: "h5 mb-0 #{color_class}") { value }
          end
        end

        def render_status_badge(policy)
          if policy.active?
            span(class: "badge bg-success") { "Active" }
          else
            span(class: "badge bg-secondary") { "Inactive" }
          end
        end

        def render_result_status_badge(result)
          case result.status
          when "passed"
            span(class: "badge bg-success") { "Passed" }
          when "failed"
            span(class: "badge bg-danger") { "Failed" }
          when "error"
            span(class: "badge bg-warning text-dark") { "Error" }
          else
            span(class: "badge bg-secondary") { result.status }
          end
        end

        def format_sampling_mode
          case @policy.sampling_mode
          when "percentage"
            "#{@policy.sample_rate}% of spans"
          when "every_n"
            "Every #{@policy.sample_every_n}th span"
          when "all"
            "All spans"
          else
            @policy.sampling_mode
          end
        end

        def format_score(score)
          return "N/A" unless score
          score.is_a?(Numeric) ? score.round(2).to_s : score.to_s
        end

        def evaluator_type_color(type)
          case type.to_s
          when "rule" then "success"
          when "statistical" then "info"
          when "llm_judge" then "warning"
          else "secondary"
          end
        end
      end
    end
  end
end
