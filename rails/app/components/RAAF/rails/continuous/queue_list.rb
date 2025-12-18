# frozen_string_literal: true

module RAAF
  module Rails
    module Continuous
      class QueueList < RAAF::Rails::Tracing::BaseComponent

        def initialize(queue_items:, page: 1, per_page: 50, filters: {})
          @queue_items = queue_items
          @page = page
          @per_page = per_page
          @filters = filters
        end

        def view_template
          div(class: "p-6") do
            render_header
            render_filters
            render_queue_table
            render_pagination if @queue_items.respond_to?(:total_pages)
          end
        end

        private

        def render_header
          div(class: "sm:flex sm:items-center sm:justify-between mb-6 pb-4 border-b border-gray-200") do
            div do
              h1(class: "text-2xl font-bold text-gray-900") { "Evaluation Queue" }
              p(class: "mt-1 text-sm text-gray-500") { "Monitor pending and running evaluation jobs" }
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
            div(class: "px-4 py-5 sm:p-6") do
              form(method: "get", class: "grid grid-cols-1 gap-4 sm:grid-cols-4") do
                div do
                  label(for: "status-filter", class: "block text-sm font-medium text-gray-700 mb-1") { "Status" }
                  select(
                    name: "status",
                    id: "status-filter",
                    class: "block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                  ) do
                    option(value: "", selected: @filters[:status].blank?) { "All statuses" }
                    option(value: "pending", selected: @filters[:status] == "pending") { "Pending" }
                    option(value: "running", selected: @filters[:status] == "running") { "Running" }
                    option(value: "completed", selected: @filters[:status] == "completed") { "Completed" }
                    option(value: "failed", selected: @filters[:status] == "failed") { "Failed" }
                  end
                end

                div do
                  label(for: "policy-filter", class: "block text-sm font-medium text-gray-700 mb-1") { "Policy" }
                  select(
                    name: "policy_id",
                    id: "policy-filter",
                    class: "block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                  ) do
                    option(value: "", selected: @filters[:policy_id].blank?) { "All policies" }
                    # Would populate with actual policies
                  end
                end

                div do
                  label(for: "date-filter", class: "block text-sm font-medium text-gray-700 mb-1") { "Date From" }
                  input(
                    type: "date",
                    name: "date_from",
                    id: "date-filter",
                    class: "block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm",
                    value: @filters[:date_from]
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

        def render_queue_table
          div(class: "bg-white shadow rounded-lg overflow-hidden") do
            if @queue_items.any?
              div(class: "overflow-x-auto") do
                table(class: "min-w-full divide-y divide-gray-200") do
                  thead(class: "bg-gray-50") do
                    tr do
                      th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider") { "Span ID" }
                      th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider") { "Policy" }
                      th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider") { "Status" }
                      th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider") { "Attempts" }
                      th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider") { "Queued" }
                      th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider") { "Started" }
                      th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider") { "Completed" }
                      th(class: "px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider") { "Actions" }
                    end
                  end
                  tbody(class: "bg-white divide-y divide-gray-200") do
                    @queue_items.each do |item|
                      render_queue_row(item)
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
            i(class: "bi bi-inbox text-5xl text-gray-400")
            h3(class: "mt-4 text-lg font-medium text-gray-900") { "No queue items found" }
            p(class: "mt-1 text-sm text-gray-500") { "No evaluation jobs match the current filters." }
          end
        end

        def render_queue_row(item)
          tr(class: "hover:bg-gray-50") do
            td(class: "px-4 py-4 text-sm") do
              link_to(
                truncate_id(item.span_id),
                "/raaf/tracing/spans/#{item.span_id}",
                class: "font-mono text-blue-600 hover:text-blue-500"
              )
            end

            td(class: "px-4 py-4 text-sm") do
              if item.policy
                link_to(
                  item.policy.name,
                  continuous_policy_path(item.policy),
                  class: "text-blue-600 hover:text-blue-500"
                )
              else
                span(class: "text-gray-400") { "Unknown" }
              end
            end

            td(class: "px-4 py-4 text-sm") do
              render_status_badge(item.status)
            end

            td(class: "px-4 py-4 text-sm") do
              if item.attempts > 1
                render_badge(item.attempts.to_s, "yellow")
              else
                span(class: "text-gray-500") { item.attempts.to_s }
              end
            end

            td(class: "px-4 py-4 text-sm text-gray-500") do
              plain "#{time_ago_in_words(item.created_at)} ago"
            end

            td(class: "px-4 py-4 text-sm text-gray-500") do
              if item.started_at
                plain "#{time_ago_in_words(item.started_at)} ago"
              else
                span(class: "text-gray-400") { "-" }
              end
            end

            td(class: "px-4 py-4 text-sm text-gray-500") do
              if item.completed_at
                plain "#{time_ago_in_words(item.completed_at)} ago"
              else
                span(class: "text-gray-400") { "-" }
              end
            end

            td(class: "px-4 py-4 text-sm text-right") do
              render_row_actions(item)
            end
          end
        end

        def render_row_actions(item)
          div(class: "flex items-center justify-end gap-2") do
            link_to(
              "View",
              continuous_queue_item_path(item),
              class: "text-blue-600 hover:text-blue-800 text-sm font-medium"
            )

            if item.status == "failed"
              button_to(
                "Retry",
                retry_continuous_queue_item_path(item),
                method: :patch,
                class: "text-green-600 hover:text-green-800 text-sm font-medium"
              )
            end

            if %w[pending running].include?(item.status)
              button_to(
                "Cancel",
                cancel_continuous_queue_item_path(item),
                method: :patch,
                class: "text-yellow-600 hover:text-yellow-800 text-sm font-medium",
                data: { confirm: "Cancel this evaluation?" }
              )
            end
          end
        end

        def render_status_badge(status)
          badge_config = case status.to_s
                        when "pending"
                          { color: "yellow", icon: "bi-clock", text: "Pending" }
                        when "running"
                          { color: "blue", icon: "bi-play-circle", text: "Running" }
                        when "completed"
                          { color: "green", icon: "bi-check-circle", text: "Completed" }
                        when "failed"
                          { color: "red", icon: "bi-x-circle", text: "Failed" }
                        else
                          { color: "gray", icon: "bi-question-circle", text: status }
                        end

          color_classes = case badge_config[:color]
                         when "yellow" then "bg-yellow-100 text-yellow-800"
                         when "blue" then "bg-blue-100 text-blue-800"
                         when "green" then "bg-green-100 text-green-800"
                         when "red" then "bg-red-100 text-red-800"
                         else "bg-gray-100 text-gray-800"
                         end

          span(class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium #{color_classes}") do
            i(class: "#{badge_config[:icon]} mr-1")
            plain badge_config[:text]
          end
        end

        def render_badge(text, color)
          color_classes = case color
                         when "yellow" then "bg-yellow-100 text-yellow-800"
                         when "green" then "bg-green-100 text-green-800"
                         when "red" then "bg-red-100 text-red-800"
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
                "Showing #{(@page - 1) * @per_page + 1}-#{[@page * @per_page, @queue_items.total_count].min} of #{@queue_items.total_count}"
              end
            end
            div do
              # Pagination links would go here
            end
          end
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
