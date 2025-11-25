# frozen_string_literal: true

module RAAF
  module Rails
    module Continuous
      class ResultsList < Phlex::HTML
        include Phlex::Rails::Helpers::LinkTo
        include Phlex::Rails::Helpers::TimeAgoInWords

        def initialize(results:, page: 1, per_page: 50, filters: {})
          @results = results
          @page = page
          @per_page = per_page
          @filters = filters
        end

        def view_template
          div(class: "container-fluid") do
            render_header
            render_filters
            render_results_table
            render_pagination if @results.respond_to?(:total_pages)
          end
        end

        private

        def render_header
          div(class: "d-flex justify-content-between flex-wrap flex-md-nowrap align-items-center pt-3 pb-2 mb-3 border-bottom") do
            div do
              h1(class: "h2") { "Evaluation Results" }
              p(class: "text-muted") { "View and analyze continuous evaluation results" }
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

                link_to("Analytics", continuous_analytics_path, class: "btn btn-sm btn-outline-primary")
              end
            end
          end
        end

        def render_filters
          div(class: "card mb-4") do
            div(class: "card-body") do
              form(method: "get", class: "row g-3") do
                div(class: "col-md-2") do
                  label(for: "agent-filter", class: "form-label") { "Agent" }
                  select(name: "agent_name", id: "agent-filter", class: "form-select") do
                    option(value: "", selected: @filters[:agent_name].blank?) { "All agents" }
                    # Would populate with actual agent names
                  end
                end

                div(class: "col-md-2") do
                  label(for: "status-filter", class: "form-label") { "Status" }
                  select(name: "status", id: "status-filter", class: "form-select") do
                    option(value: "", selected: @filters[:status].blank?) { "All statuses" }
                    option(value: "passed", selected: @filters[:status] == "passed") { "Passed" }
                    option(value: "failed", selected: @filters[:status] == "failed") { "Failed" }
                    option(value: "error", selected: @filters[:status] == "error") { "Error" }
                  end
                end

                div(class: "col-md-2") do
                  label(for: "evaluator-filter", class: "form-label") { "Evaluator" }
                  select(name: "evaluator_name", id: "evaluator-filter", class: "form-select") do
                    option(value: "", selected: @filters[:evaluator_name].blank?) { "All evaluators" }
                    # Would populate with actual evaluator names
                  end
                end

                div(class: "col-md-2") do
                  label(for: "date-from-filter", class: "form-label") { "From Date" }
                  input(
                    type: "date",
                    name: "date_from",
                    id: "date-from-filter",
                    class: "form-control",
                    value: @filters[:date_from]
                  )
                end

                div(class: "col-md-2") do
                  label(for: "date-to-filter", class: "form-label") { "To Date" }
                  input(
                    type: "date",
                    name: "date_to",
                    id: "date-to-filter",
                    class: "form-control",
                    value: @filters[:date_to]
                  )
                end

                div(class: "col-md-2 d-flex align-items-end") do
                  button(type: "submit", class: "btn btn-primary w-100") { "Apply Filters" }
                end
              end
            end
          end
        end

        def render_results_table
          div(class: "card") do
            div(class: "card-body") do
              if @results.any?
                div(class: "table-responsive") do
                  table(class: "table table-sm table-hover") do
                    thead do
                      tr do
                        th { "Agent" }
                        th { "Evaluator" }
                        th { "Status" }
                        th { "Score" }
                        th { "Span ID" }
                        th { "Created" }
                        th(class: "text-end") { "Actions" }
                      end
                    end
                    tbody do
                      @results.each do |result|
                        render_result_row(result)
                      end
                    end
                  end
                end
              else
                div(class: "text-center py-5") do
                  i(class: "bi bi-graph-up display-4 text-muted")
                  h3(class: "mt-3") { "No results found" }
                  p(class: "text-muted") { "No evaluation results match the current filters." }
                end
              end
            end
          end
        end

        def render_result_row(result)
          tr do
            td do
              span(class: "badge bg-info") { result.agent_name || "Unknown" }
            end

            td do
              div do
                strong { result.evaluator_name }
                br
                small(class: "text-muted") { result.evaluator_type }
              end
            end

            td do
              render_status_badge(result.status)
            end

            td do
              if result.score
                render_score_badge(result.score)
              else
                span(class: "text-muted") { "N/A" }
              end
            end

            td do
              link_to(
                truncate_id(result.span_id),
                "/raaf/tracing/spans/#{result.span_id}",
                class: "font-monospace text-decoration-none"
              )
            end

            td do
              small do
                plain time_ago_in_words(result.created_at)
                plain " ago"
              end
            end

            td(class: "text-end") do
              link_to("View Details", continuous_result_path(result), class: "btn btn-sm btn-outline-primary")
            end
          end
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

        def render_score_badge(score)
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

        def render_pagination
          div(class: "d-flex justify-content-between align-items-center mt-3") do
            div do
              small(class: "text-muted") do
                "Showing #{(@page - 1) * @per_page + 1}-#{[@page * @per_page, @results.total_count].min} of #{@results.total_count}"
              end
            end
            div do
              # Pagination links would go here
            end
          end
        end

        def format_score(score)
          return "N/A" unless score
          score.is_a?(Numeric) ? score.round(2).to_s : score.to_s
        end

        def truncate_id(id)
          return id unless id.is_a?(String)
          return id if id.length <= 12
          "#{id[0..5]}...#{id[-6..-1]}"
        end
      end
    end
  end
end
