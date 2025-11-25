# frozen_string_literal: true

module RAAF
  module Rails
    module Continuous
      class QueueList < Phlex::HTML
        include Phlex::Rails::Helpers::LinkTo
        include Phlex::Rails::Helpers::ButtonTo
        include Phlex::Rails::Helpers::TimeAgoInWords

        def initialize(queue_items:, page: 1, per_page: 50, filters: {})
          @queue_items = queue_items
          @page = page
          @per_page = per_page
          @filters = filters
        end

        def view_template
          div(class: "container-fluid") do
            render_header
            render_filters
            render_queue_table
            render_pagination if @queue_items.respond_to?(:total_pages)
          end
        end

        private

        def render_header
          div(class: "d-flex justify-content-between flex-wrap flex-md-nowrap align-items-center pt-3 pb-2 mb-3 border-bottom") do
            div do
              h1(class: "h2") { "Evaluation Queue" }
              p(class: "text-muted") { "Monitor pending and running evaluation jobs" }
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
            div(class: "card-body") do
              form(method: "get", class: "row g-3") do
                div(class: "col-md-3") do
                  label(for: "status-filter", class: "form-label") { "Status" }
                  select(name: "status", id: "status-filter", class: "form-select") do
                    option(value: "", selected: @filters[:status].blank?) { "All statuses" }
                    option(value: "pending", selected: @filters[:status] == "pending") { "Pending" }
                    option(value: "running", selected: @filters[:status] == "running") { "Running" }
                    option(value: "completed", selected: @filters[:status] == "completed") { "Completed" }
                    option(value: "failed", selected: @filters[:status] == "failed") { "Failed" }
                  end
                end

                div(class: "col-md-3") do
                  label(for: "policy-filter", class: "form-label") { "Policy" }
                  select(name: "policy_id", id: "policy-filter", class: "form-select") do
                    option(value: "", selected: @filters[:policy_id].blank?) { "All policies" }
                    # Would populate with actual policies
                  end
                end

                div(class: "col-md-3") do
                  label(for: "date-filter", class: "form-label") { "Date Range" }
                  input(
                    type: "date",
                    name: "date_from",
                    id: "date-filter",
                    class: "form-control",
                    value: @filters[:date_from]
                  )
                end

                div(class: "col-md-3 d-flex align-items-end") do
                  button(type: "submit", class: "btn btn-primary w-100") { "Apply Filters" }
                end
              end
            end
          end
        end

        def render_queue_table
          div(class: "card") do
            div(class: "card-body") do
              if @queue_items.any?
                div(class: "table-responsive") do
                  table(class: "table table-sm table-hover") do
                    thead do
                      tr do
                        th { "Span ID" }
                        th { "Policy" }
                        th { "Status" }
                        th { "Attempts" }
                        th { "Queued" }
                        th { "Started" }
                        th { "Completed" }
                        th(class: "text-end") { "Actions" }
                      end
                    end
                    tbody do
                      @queue_items.each do |item|
                        render_queue_row(item)
                      end
                    end
                  end
                end
              else
                div(class: "text-center py-5") do
                  i(class: "bi bi-inbox display-4 text-muted")
                  h3(class: "mt-3") { "No queue items found" }
                  p(class: "text-muted") { "No evaluation jobs match the current filters." }
                end
              end
            end
          end
        end

        def render_queue_row(item)
          tr do
            td do
              link_to(
                truncate_id(item.span_id),
                "/raaf/tracing/spans/#{item.span_id}",
                class: "font-monospace text-decoration-none"
              )
            end

            td do
              if item.policy
                link_to(
                  item.policy.name,
                  continuous_policy_path(item.policy),
                  class: "text-decoration-none"
                )
              else
                span(class: "text-muted") { "Unknown" }
              end
            end

            td do
              render_status_badge(item.status)
            end

            td do
              if item.attempts > 1
                span(class: "badge bg-warning") { item.attempts.to_s }
              else
                span(class: "text-muted") { item.attempts.to_s }
              end
            end

            td do
              small { time_ago_in_words(item.created_at) + " ago" }
            end

            td do
              if item.started_at
                small { time_ago_in_words(item.started_at) + " ago" }
              else
                span(class: "text-muted") { "-" }
              end
            end

            td do
              if item.completed_at
                small { time_ago_in_words(item.completed_at) + " ago" }
              else
                span(class: "text-muted") { "-" }
              end
            end

            td(class: "text-end") do
              div(class: "btn-group btn-group-sm") do
                link_to("View", continuous_queue_item_path(item), class: "btn btn-outline-primary")

                if item.status == "failed"
                  button_to("Retry",
                    retry_continuous_queue_item_path(item),
                    method: :patch,
                    class: "btn btn-outline-success")
                end

                if %w[pending running].include?(item.status)
                  button_to("Cancel",
                    cancel_continuous_queue_item_path(item),
                    method: :patch,
                    class: "btn btn-outline-warning",
                    data: { confirm: "Cancel this evaluation?" })
                end
              end
            end
          end
        end

        def render_status_badge(status)
          badge_config = case status.to_s
                        when "pending"
                          { class: "bg-warning text-dark", icon: "clock", text: "Pending" }
                        when "running"
                          { class: "bg-primary", icon: "play-circle", text: "Running" }
                        when "completed"
                          { class: "bg-success", icon: "check-circle", text: "Completed" }
                        when "failed"
                          { class: "bg-danger", icon: "x-circle", text: "Failed" }
                        else
                          { class: "bg-secondary", icon: "question-circle", text: status }
                        end

          span(class: "badge #{badge_config[:class]}") do
            i(class: "bi bi-#{badge_config[:icon]} me-1")
            plain badge_config[:text]
          end
        end

        def render_pagination
          div(class: "d-flex justify-content-between align-items-center mt-3") do
            div do
              small(class: "text-muted") do
                "Showing #{(@page - 1) * @per_page + 1}-#{[@page * @per_page, @queue_items.total_count].min} of #{@queue_items.total_count}"
              end
            end
            div do
              # Pagination links would go here using will_paginate or kaminari
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
