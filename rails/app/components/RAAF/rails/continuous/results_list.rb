# frozen_string_literal: true

module RAAF
  module Rails
    module Continuous
      class ResultsList < RAAF::Rails::Tracing::BaseComponent

        def initialize(results:, page: 1, per_page: 50, filters: {})
          @results = results
          @page = page
          @per_page = per_page
          @filters = filters
        end

        def view_template
          div(class: "p-6") do
            render_header
            render_filters
            render_results_table
            render_pagination if @results.respond_to?(:total_pages)
          end
        end

        private

        def render_header
          div(class: "sm:flex sm:items-center sm:justify-between mb-6 pb-4 border-b border-gray-200") do
            div do
              h1(class: "text-2xl font-bold text-gray-900") { "Evaluation Results" }
              p(class: "mt-1 text-sm text-gray-500") { "View and analyze continuous evaluation results" }
            end

            div(class: "mt-4 sm:mt-0 flex gap-2") do
              render_preline_button(
                text: "Refresh",
                href: "javascript:window.location.reload();",
                variant: "secondary",
                icon: "bi-arrow-clockwise"
              )
              render_preline_button(
                text: "Analytics",
                href: continuous_analytics_path,
                variant: "primary"
              )
            end
          end
        end

        def render_filters
          div(class: "bg-white shadow rounded-lg overflow-hidden mb-6") do
            div(class: "px-4 py-5 sm:p-6") do
              form(method: "get", class: "grid grid-cols-1 gap-4 sm:grid-cols-6") do
                div do
                  label(for: "agent-filter", class: "block text-sm font-medium text-gray-700 mb-1") { "Agent" }
                  select(
                    name: "agent_name",
                    id: "agent-filter",
                    class: "block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                  ) do
                    option(value: "", selected: @filters[:agent_name].blank?) { "All agents" }
                  end
                end

                div do
                  label(for: "status-filter", class: "block text-sm font-medium text-gray-700 mb-1") { "Status" }
                  select(
                    name: "status",
                    id: "status-filter",
                    class: "block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                  ) do
                    option(value: "", selected: @filters[:status].blank?) { "All statuses" }
                    option(value: "good", selected: @filters[:status] == "good") { "Good" }
                    option(value: "average", selected: @filters[:status] == "average") { "Average" }
                    option(value: "bad", selected: @filters[:status] == "bad") { "Bad" }
                    option(value: "error", selected: @filters[:status] == "error") { "Error" }
                  end
                end

                div do
                  label(for: "evaluator-filter", class: "block text-sm font-medium text-gray-700 mb-1") { "Evaluator" }
                  select(
                    name: "evaluator_name",
                    id: "evaluator-filter",
                    class: "block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                  ) do
                    option(value: "", selected: @filters[:evaluator_name].blank?) { "All evaluators" }
                  end
                end

                div do
                  label(for: "date-from-filter", class: "block text-sm font-medium text-gray-700 mb-1") { "From Date" }
                  input(
                    type: "date",
                    name: "date_from",
                    id: "date-from-filter",
                    class: "block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm",
                    value: @filters[:date_from]
                  )
                end

                div do
                  label(for: "date-to-filter", class: "block text-sm font-medium text-gray-700 mb-1") { "To Date" }
                  input(
                    type: "date",
                    name: "date_to",
                    id: "date-to-filter",
                    class: "block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm",
                    value: @filters[:date_to]
                  )
                end

                div(class: "flex items-end") do
                  button(
                    type: "submit",
                    class: "w-full inline-flex justify-center items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700"
                  ) { "Apply Filters" }
                end
              end
            end
          end
        end

        def render_results_table
          div(class: "bg-white shadow rounded-lg overflow-hidden") do
            if @results.any?
              div(class: "overflow-x-auto") do
                table(class: "min-w-full divide-y divide-gray-200") do
                  thead(class: "bg-gray-50") do
                    tr do
                      th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider") { "Agent" }
                      th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider") { "Evaluator" }
                      th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider") { "Field" }
                      th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider") { "Status" }
                      th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider") { "Score" }
                      th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider") { "Span ID" }
                      th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider") { "Created" }
                      th(class: "px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider") { "Actions" }
                    end
                  end
                  tbody(class: "bg-white divide-y divide-gray-200") do
                    @results.each do |result|
                      render_result_row(result)
                    end
                  end
                end
              end
            else
              render_empty_state
            end
          end
        end

        def render_empty_state
          div(class: "flex flex-col items-center justify-center py-12") do
            i(class: "bi bi-graph-up text-5xl text-gray-400")
            h3(class: "mt-4 text-lg font-medium text-gray-900") { "No results found" }
            p(class: "mt-1 text-sm text-gray-500") { "No evaluation results match the current filters." }
          end
        end

        def render_result_row(result)
          tr(class: "hover:bg-gray-50") do
            td(class: "px-4 py-4 text-sm") do
              render_badge(result.agent_name || "Unknown", "cyan")
            end

            td(class: "px-4 py-4 text-sm") do
              div do
                span(class: "font-medium text-gray-900") { result.evaluator_name }
                p(class: "text-xs text-gray-500") { result.evaluator_type }
              end
            end

            td(class: "px-4 py-4 text-sm") do
              field_name = result.metadata&.dig("field_name") || result.metadata&.dig(:field_name)
              if field_name.present?
                span(class: "font-medium text-gray-700") { field_name }
              else
                span(class: "text-gray-400") { "—" }
              end
            end

            td(class: "px-4 py-4 text-sm") do
              render_status_badge(result.status)
            end

            td(class: "px-4 py-4 text-sm") do
              if result.score
                render_score_badge(result.score)
              else
                span(class: "text-gray-400") { "N/A" }
              end
            end

            td(class: "px-4 py-4 text-sm") do
              link_to(
                truncate_id(result.span_id),
                "/raaf/tracing/spans/#{result.span_id}",
                class: "font-mono text-blue-600 hover:text-blue-500"
              )
            end

            td(class: "px-4 py-4 text-sm text-gray-500") do
              plain "#{time_ago_in_words(result.created_at)} ago"
            end

            td(class: "px-4 py-4 text-sm text-right") do
              link_to(
                "View Details",
                continuous_result_path(result),
                class: "text-blue-600 hover:text-blue-800 text-sm font-medium"
              )
            end
          end
        end

        def render_status_badge(status)
          badge_config = case status.to_s
                        when "good"
                          { color: "green", icon: "bi-check-circle", text: "Good" }
                        when "average"
                          { color: "yellow", icon: "bi-dash-circle", text: "Average" }
                        when "bad"
                          { color: "red", icon: "bi-x-circle", text: "Bad" }
                        when "error"
                          { color: "orange", icon: "bi-exclamation-triangle", text: "Error" }
                        else
                          { color: "gray", icon: "bi-question-circle", text: status }
                        end

          color_classes = case badge_config[:color]
                         when "green" then "bg-green-100 text-green-800"
                         when "yellow" then "bg-yellow-100 text-yellow-800"
                         when "red" then "bg-red-100 text-red-800"
                         when "orange" then "bg-orange-100 text-orange-800"
                         else "bg-gray-100 text-gray-800"
                         end

          span(class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium #{color_classes}") do
            i(class: "#{badge_config[:icon]} mr-1")
            plain badge_config[:text]
          end
        end

        def render_score_badge(score)
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
                         when "cyan" then "bg-cyan-100 text-cyan-800"
                         else "bg-gray-100 text-gray-800"
                         end

          span(class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium #{color_classes}") do
            text
          end
        end

        def render_pagination
          div(class: "flex items-center justify-between px-4 py-3 border-t border-gray-200") do
            div do
              span(class: "text-sm text-gray-500") do
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
