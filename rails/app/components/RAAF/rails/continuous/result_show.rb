# frozen_string_literal: true

module RAAF
  module Rails
    module Continuous
      class ResultShow < Phlex::HTML
        include Phlex::Rails::Helpers::LinkTo
        include Phlex::Rails::Helpers::TimeAgoInWords

        def initialize(result:)
          @result = result
        end

        def view_template
          div(class: "container-fluid") do
            render_header
            div(class: "row") do
              div(class: "col-md-8") do
                render_score_section
                render_reasoning_section if @result.reasoning.present?
                render_metrics_section if @result.metrics.present?
                render_metadata_section
              end
              div(class: "col-md-4") do
                render_summary_sidebar
                render_links_sidebar
              end
            end
          end
        end

        private

        def render_header
          div(class: "d-flex justify-content-between flex-wrap flex-md-nowrap align-items-center pt-3 pb-2 mb-3 border-bottom") do
            div do
              h1(class: "h2") do
                plain @result.evaluator_name
                plain " "
                render_status_badge(@result.status)
              end
              p(class: "text-muted") do
                plain "Evaluation result from "
                plain time_ago_in_words(@result.created_at)
                plain " ago"
              end
            end
          end
        end

        def render_score_section
          div(class: "card mb-4") do
            div(class: "card-header") do
              h5(class: "card-title mb-0") { "Score" }
            end
            div(class: "card-body text-center") do
              if @result.score
                render_score_visualization(@result.score)
              else
                p(class: "text-muted") { "No score available" }
              end
            end
          end
        end

        def render_score_visualization(score)
          numeric_score = score.to_f
          percentage = (numeric_score * 100).round

          div(class: "mb-3") do
            div(class: "display-1", style: "font-weight: 700;") do
              plain percentage.to_s
              span(class: "fs-3 text-muted") { "%" }
            end
          end

          div(class: "progress", style: "height: 30px;") do
            progress_class = if numeric_score >= 0.8
                              "bg-success"
                            elsif numeric_score >= 0.6
                              "bg-warning"
                            else
                              "bg-danger"
                            end

            div(
              class: "progress-bar #{progress_class}",
              role: "progressbar",
              style: "width: #{percentage}%;",
              aria_valuenow: percentage,
              aria_valuemin: "0",
              aria_valuemax: "100"
            ) do
              "#{percentage}%"
            end
          end

          div(class: "mt-3") do
            if numeric_score >= 0.8
              span(class: "badge bg-success fs-5") { "Excellent" }
            elsif numeric_score >= 0.6
              span(class: "badge bg-warning text-dark fs-5") { "Acceptable" }
            else
              span(class: "badge bg-danger fs-5") { "Needs Improvement" }
            end
          end
        end

        def render_reasoning_section
          div(class: "card mb-4") do
            div(class: "card-header") do
              h5(class: "card-title mb-0") { "Reasoning" }
            end
            div(class: "card-body") do
              div(class: "bg-light p-3 rounded") do
                p(class: "mb-0", style: "white-space: pre-wrap;") { @result.reasoning }
              end
            end
          end
        end

        def render_metrics_section
          div(class: "card mb-4") do
            div(class: "card-header") do
              h5(class: "card-title mb-0") { "Metrics" }
            end
            div(class: "card-body") do
              if @result.metrics.is_a?(Hash)
                dl(class: "row mb-0") do
                  @result.metrics.each do |key, value|
                    dt(class: "col-sm-4 text-muted") { format_key(key) }
                    dd(class: "col-sm-8") { format_value(value) }
                  end
                end
              else
                pre(class: "bg-light p-3 rounded mb-0") do
                  JSON.pretty_generate(@result.metrics)
                end
              end
            end
          end
        end

        def render_metadata_section
          div(class: "card mb-4") do
            div(class: "card-header") do
              h5(class: "card-title mb-0") { "Metadata" }
            end
            div(class: "card-body") do
              dl(class: "row mb-0") do
                render_detail_row("Result ID", @result.id)
                render_detail_row("Agent Name", @result.agent_name)
                render_detail_row("Evaluator Type", @result.evaluator_type)
                render_detail_row("Status", render_status_badge(@result.status))
                render_detail_row("Created", format_timestamp(@result.created_at))
                render_detail_row("Duration", format_duration(@result.execution_time_ms)) if @result.execution_time_ms

                if @result.token_usage.present?
                  render_detail_row("Tokens Used", @result.token_usage.to_s)
                end

                if @result.cost.present?
                  render_detail_row("Cost", "$#{format('%.4f', @result.cost)}")
                end
              end
            end
          end
        end

        def render_summary_sidebar
          div(class: "card mb-4") do
            div(class: "card-header") do
              h5(class: "card-title mb-0") { "Summary" }
            end
            div(class: "list-group list-group-flush") do
              render_summary_item("Status", render_status_badge(@result.status))
              render_summary_item("Score", format_score(@result.score))
              render_summary_item("Agent", @result.agent_name || "Unknown")
              render_summary_item("Evaluator", @result.evaluator_name)
              render_summary_item("Type", @result.evaluator_type)
            end
          end
        end

        def render_links_sidebar
          div(class: "card") do
            div(class: "card-header") do
              h5(class: "card-title mb-0") { "Related" }
            end
            div(class: "list-group list-group-flush") do
              link_to("/raaf/tracing/spans/#{@result.span_id}",
                class: "list-group-item list-group-item-action") do
                i(class: "bi bi-eye me-2")
                plain "View Span"
              end

              if @result.queue_item
                link_to(continuous_queue_item_path(@result.queue_item),
                  class: "list-group-item list-group-item-action") do
                  i(class: "bi bi-list-task me-2")
                  plain "View Queue Item"
                end
              end

              if @result.policy
                link_to(continuous_policy_path(@result.policy),
                  class: "list-group-item list-group-item-action") do
                  i(class: "bi bi-shield-check me-2")
                  plain "View Policy"
                end
              end

              hr(class: "my-0")

              link_to(
                continuous_results_path(agent_name: @result.agent_name),
                class: "list-group-item list-group-item-action"
              ) do
                i(class: "bi bi-filter me-2")
                plain "More from this Agent"
              end

              link_to(
                continuous_results_path(evaluator_name: @result.evaluator_name),
                class: "list-group-item list-group-item-action"
              ) do
                i(class: "bi bi-filter me-2")
                plain "More from this Evaluator"
              end
            end
          end
        end

        def render_summary_item(label, value)
          div(class: "list-group-item d-flex justify-content-between align-items-center") do
            span(class: "text-muted") { label }
            span { value }
          end
        end

        def render_detail_row(label, value)
          dt(class: "col-sm-4 text-muted") { label }
          dd(class: "col-sm-8") { value }
        end

        def render_status_badge(status)
          badge_config = case status.to_s
                        when "passed"
                          { class: "bg-success", icon: "check-circle", text: "Passed" }
                        when "failed"
                          { class: "bg-danger", icon: "x-circle", text: "Failed" }
                        when "error"
                          { class: "bg-warning text-dark", icon: "exclamation-triangle", text: "Error" }
                        else
                          { class: "bg-secondary", icon: "question-circle", text: status }
                        end

          span(class: "badge #{badge_config[:class]}") do
            i(class: "bi bi-#{badge_config[:icon]} me-1")
            plain badge_config[:text]
          end
        end

        def format_score(score)
          return "N/A" unless score
          score.is_a?(Numeric) ? score.round(2).to_s : score.to_s
        end

        def format_timestamp(time)
          return "N/A" unless time
          time.strftime("%Y-%m-%d %H:%M:%S")
        end

        def format_duration(ms)
          return "N/A" unless ms
          if ms < 1000
            "#{ms.round}ms"
          else
            "#{(ms / 1000.0).round(2)}s"
          end
        end

        def format_key(key)
          key.to_s.split('_').map(&:capitalize).join(' ')
        end

        def format_value(value)
          case value
          when Numeric
            value.is_a?(Float) ? value.round(3).to_s : value.to_s
          when TrueClass, FalseClass
            value ? "Yes" : "No"
          when Hash
            pre(class: "mb-0") { JSON.pretty_generate(value) }
          when Array
            value.join(", ")
          else
            value.to_s
          end
        end
      end
    end
  end
end
