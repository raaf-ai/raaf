# frozen_string_literal: true

module RAAF
  module Rails
    module Continuous
      class QueueShow < Phlex::HTML
        include Phlex::Rails::Helpers::LinkTo
        include Phlex::Rails::Helpers::ButtonTo
        include Phlex::Rails::Helpers::TimeAgoInWords

        def initialize(queue_item:, results: [])
          @queue_item = queue_item
          @results = results
        end

        def view_template
          div(class: "container-fluid") do
            render_header
            div(class: "row") do
              div(class: "col-md-8") do
                render_queue_details
                render_error_section if @queue_item.error_message.present?
                render_results_section
              end
              div(class: "col-md-4") do
                render_status_sidebar
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
                plain "Queue Item "
                render_status_badge(@queue_item.status)
              end
              p(class: "text-muted") do
                plain "Created "
                plain time_ago_in_words(@queue_item.created_at)
                plain " ago"
              end
            end

            div(class: "btn-toolbar mb-2 mb-md-0") do
              div(class: "btn-group me-2") do
                if @queue_item.status == "failed"
                  button_to("Retry",
                    retry_continuous_queue_item_path(@queue_item),
                    method: :patch,
                    class: "btn btn-sm btn-success")
                end

                if %w[pending running].include?(@queue_item.status)
                  button_to("Cancel",
                    cancel_continuous_queue_item_path(@queue_item),
                    method: :patch,
                    class: "btn btn-sm btn-warning",
                    data: { confirm: "Cancel this evaluation?" })
                end
              end
            end
          end
        end

        def render_queue_details
          div(class: "card mb-4") do
            div(class: "card-header") do
              h5(class: "card-title mb-0") { "Queue Item Details" }
            end
            div(class: "card-body") do
              dl(class: "row mb-0") do
                render_detail_row("Span ID", render_span_link(@queue_item.span_id))
                render_detail_row("Policy", render_policy_link(@queue_item.policy))
                render_detail_row("Status", render_status_badge(@queue_item.status))
                render_detail_row("Priority", @queue_item.priority.to_s)
                render_detail_row("Attempts", @queue_item.attempts.to_s)
                render_detail_row("Created", format_timestamp(@queue_item.created_at))
                render_detail_row("Started", format_timestamp(@queue_item.started_at))
                render_detail_row("Completed", format_timestamp(@queue_item.completed_at))

                if @queue_item.completed_at && @queue_item.started_at
                  duration = (@queue_item.completed_at - @queue_item.started_at).round(2)
                  render_detail_row("Duration", "#{duration}s")
                end
              end
            end
          end
        end

        def render_error_section
          div(class: "card mb-4 border-danger") do
            div(class: "card-header bg-danger text-white") do
              h5(class: "card-title mb-0") do
                i(class: "bi bi-exclamation-triangle me-2")
                plain "Error Details"
              end
            end
            div(class: "card-body") do
              if @queue_item.error_message.present?
                div(class: "alert alert-danger mb-3") do
                  strong { "Error Message:" }
                  br
                  pre(class: "mb-0 mt-2", style: "white-space: pre-wrap;") do
                    @queue_item.error_message
                  end
                end
              end

              if @queue_item.error_backtrace.present?
                details do
                  summary(class: "btn btn-sm btn-outline-danger mb-2") { "Show Backtrace" }
                  pre(class: "bg-light p-3 mt-2", style: "max-height: 300px; overflow-y: auto;") do
                    @queue_item.error_backtrace
                  end
                end
              end
            end
          end
        end

        def render_results_section
          div(class: "card mb-4") do
            div(class: "card-header d-flex justify-content-between align-items-center") do
              h5(class: "card-title mb-0") { "Evaluation Results" }
              if @results.any?
                span(class: "badge bg-primary") { @results.count.to_s }
              end
            end
            div(class: "card-body") do
              if @results.any?
                div(class: "list-group list-group-flush") do
                  @results.each do |result|
                    render_result_item(result)
                  end
                end
              else
                p(class: "text-muted mb-0") { "No results available yet" }
              end
            end
          end
        end

        def render_status_sidebar
          div(class: "card mb-4") do
            div(class: "card-header") do
              h5(class: "card-title mb-0") { "Status" }
            end
            div(class: "card-body") do
              render_status_timeline
            end
          end
        end

        def render_status_timeline
          div(class: "timeline") do
            render_timeline_item("Created", @queue_item.created_at, true)
            render_timeline_item("Started", @queue_item.started_at, @queue_item.started_at.present?)
            render_timeline_item("Completed", @queue_item.completed_at, @queue_item.completed_at.present?)
          end
        end

        def render_timeline_item(label, timestamp, completed)
          div(class: "d-flex mb-3") do
            div(class: "me-3") do
              if completed
                i(class: "bi bi-check-circle text-success fs-4")
              else
                i(class: "bi bi-circle text-muted")
              end
            end
            div do
              strong { label }
              br
              if timestamp
                small(class: "text-muted") { format_timestamp(timestamp) }
              else
                small(class: "text-muted") { "Not yet" }
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
              link_to("/raaf/tracing/spans/#{@queue_item.span_id}",
                class: "list-group-item list-group-item-action") do
                i(class: "bi bi-eye me-2")
                plain "View Span"
              end

              if @queue_item.policy
                link_to(continuous_policy_path(@queue_item.policy),
                  class: "list-group-item list-group-item-action") do
                  i(class: "bi bi-shield-check me-2")
                  plain "View Policy"
                end
              end

              if @results.any?
                @results.each do |result|
                  link_to(continuous_result_path(result),
                    class: "list-group-item list-group-item-action") do
                    i(class: "bi bi-graph-up me-2")
                    plain "View #{result.evaluator_name} Result"
                  end
                end
              end

              hr(class: "my-0")

              if @queue_item.status == "failed"
                button_to("Retry Evaluation",
                  retry_continuous_queue_item_path(@queue_item),
                  method: :patch,
                  class: "list-group-item list-group-item-action text-success")
              end

              if %w[pending running].include?(@queue_item.status)
                button_to("Cancel Evaluation",
                  cancel_continuous_queue_item_path(@queue_item),
                  method: :patch,
                  class: "list-group-item list-group-item-action text-warning",
                  data: { confirm: "Cancel this evaluation?" })
              end
            end
          end
        end

        def render_result_item(result)
          div(class: "list-group-item") do
            div(class: "d-flex justify-content-between align-items-start") do
              div do
                strong { result.evaluator_name }
                br
                render_result_status_badge(result)
                if result.score
                  span(class: "ms-2") { "Score: #{result.score.round(2)}" }
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

        def render_span_link(span_id)
          link_to(span_id, "/raaf/tracing/spans/#{span_id}", class: "font-monospace text-decoration-none")
        end

        def render_policy_link(policy)
          if policy
            link_to(policy.name, continuous_policy_path(policy), class: "text-decoration-none")
          else
            span(class: "text-muted") { "Unknown policy" }
          end
        end

        def format_timestamp(time)
          return "N/A" unless time
          time.strftime("%Y-%m-%d %H:%M:%S")
        end
      end
    end
  end
end
