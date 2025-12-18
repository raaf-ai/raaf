# frozen_string_literal: true

module RAAF
  module Rails
    module Continuous
      class QueueShow < RAAF::Rails::Tracing::BaseComponent

        def initialize(queue_item:, results: [])
          @queue_item = queue_item
          @results = results
        end

        def view_template
          div(class: "p-6") do
            render_header
            div(class: "grid grid-cols-1 lg:grid-cols-3 gap-6") do
              div(class: "lg:col-span-2 space-y-6") do
                render_queue_details
                render_error_section if @queue_item.error_message.present?
                render_results_section
              end
              div(class: "space-y-6") do
                render_status_sidebar
                render_actions_sidebar
              end
            end
          end
        end

        private

        def render_header
          div(class: "sm:flex sm:items-center sm:justify-between mb-6 pb-4 border-b border-gray-200") do
            div do
              div(class: "flex items-center gap-3") do
                h1(class: "text-2xl font-bold text-gray-900") { "Queue Item" }
                render_status_badge(@queue_item.status)
              end
              p(class: "mt-1 text-sm text-gray-500") do
                plain "Created "
                plain time_ago_in_words(@queue_item.created_at)
                plain " ago"
              end
            end

            div(class: "mt-4 sm:mt-0 flex gap-2") do
              if @queue_item.status == "failed"
                button_to(
                  "Retry",
                  retry_continuous_queue_item_path(@queue_item),
                  method: :patch,
                  class: "inline-flex items-center gap-x-2 text-sm font-semibold rounded-lg border border-green-600 bg-green-600 text-white hover:bg-green-700 px-3 py-2"
                )
              end

              if %w[pending running].include?(@queue_item.status)
                button_to(
                  "Cancel",
                  cancel_continuous_queue_item_path(@queue_item),
                  method: :patch,
                  class: "inline-flex items-center gap-x-2 text-sm font-semibold rounded-lg border border-yellow-600 bg-yellow-600 text-white hover:bg-yellow-700 px-3 py-2",
                  data: { confirm: "Cancel this evaluation?" }
                )
              end
            end
          end
        end

        def render_queue_details
          div(class: "bg-white shadow rounded-lg overflow-hidden") do
            div(class: "px-4 py-5 sm:px-6 border-b border-gray-200") do
              h3(class: "text-lg font-medium text-gray-900") { "Queue Item Details" }
            end
            div(class: "px-4 py-5 sm:p-6") do
              dl(class: "grid grid-cols-1 gap-x-4 gap-y-4 sm:grid-cols-2") do
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
          div(class: "bg-white shadow rounded-lg overflow-hidden border border-red-200") do
            div(class: "px-4 py-5 sm:px-6 border-b border-red-200 bg-red-600") do
              h3(class: "text-lg font-medium text-white flex items-center") do
                i(class: "bi bi-exclamation-triangle mr-2")
                plain "Error Details"
              end
            end
            div(class: "px-4 py-5 sm:p-6") do
              if @queue_item.error_message.present?
                div(class: "bg-red-50 border border-red-200 rounded-md p-4 mb-4") do
                  span(class: "font-semibold text-red-800") { "Error Message:" }
                  pre(class: "mt-2 text-sm text-red-700 whitespace-pre-wrap") do
                    @queue_item.error_message
                  end
                end
              end

              if @queue_item.error_backtrace.present?
                details(class: "group") do
                  summary(class: "cursor-pointer inline-flex items-center px-3 py-1.5 border border-red-300 text-sm font-medium rounded-md text-red-700 bg-white hover:bg-red-50") do
                    "Show Backtrace"
                  end
                  pre(class: "mt-4 bg-gray-50 p-4 rounded-md text-xs text-gray-700 overflow-y-auto max-h-72") do
                    @queue_item.error_backtrace
                  end
                end
              end
            end
          end
        end

        def render_results_section
          div(class: "bg-white shadow rounded-lg overflow-hidden") do
            div(class: "px-4 py-5 sm:px-6 border-b border-gray-200 flex justify-between items-center") do
              h3(class: "text-lg font-medium text-gray-900") { "Evaluation Results" }
              if @results.any?
                span(class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-800") do
                  @results.count.to_s
                end
              end
            end
            div(class: "px-4 py-5 sm:p-6") do
              if @results.any?
                div(class: "divide-y divide-gray-200") do
                  @results.each do |result|
                    render_result_item(result)
                  end
                end
              else
                p(class: "text-gray-500") { "No results available yet" }
              end
            end
          end
        end

        def render_status_sidebar
          div(class: "bg-white shadow rounded-lg overflow-hidden") do
            div(class: "px-4 py-5 sm:px-6 border-b border-gray-200") do
              h3(class: "text-lg font-medium text-gray-900") { "Status" }
            end
            div(class: "px-4 py-5 sm:p-6") do
              render_status_timeline
            end
          end
        end

        def render_status_timeline
          div(class: "space-y-4") do
            render_timeline_item("Created", @queue_item.created_at, true)
            render_timeline_item("Started", @queue_item.started_at, @queue_item.started_at.present?)
            render_timeline_item("Completed", @queue_item.completed_at, @queue_item.completed_at.present?)
          end
        end

        def render_timeline_item(label, timestamp, completed)
          div(class: "flex items-start") do
            div(class: "mr-3 flex-shrink-0") do
              if completed
                i(class: "bi bi-check-circle text-green-500 text-xl")
              else
                i(class: "bi bi-circle text-gray-300 text-xl")
              end
            end
            div do
              span(class: "font-medium text-gray-900") { label }
              div(class: "text-sm text-gray-500") do
                if timestamp
                  plain format_timestamp(timestamp)
                else
                  plain "Not yet"
                end
              end
            end
          end
        end

        def render_actions_sidebar
          div(class: "bg-white shadow rounded-lg overflow-hidden") do
            div(class: "px-4 py-5 sm:px-6 border-b border-gray-200") do
              h3(class: "text-lg font-medium text-gray-900") { "Actions" }
            end
            div(class: "divide-y divide-gray-200") do
              link_to(
                "/raaf/tracing/spans/#{@queue_item.span_id}",
                class: "flex items-center px-4 py-3 hover:bg-gray-50 text-gray-700"
              ) do
                i(class: "bi bi-eye mr-3 text-gray-400")
                plain "View Span"
              end

              if @queue_item.policy
                link_to(
                  continuous_policy_path(@queue_item.policy),
                  class: "flex items-center px-4 py-3 hover:bg-gray-50 text-gray-700"
                ) do
                  i(class: "bi bi-shield-check mr-3 text-gray-400")
                  plain "View Policy"
                end
              end

              if @results.any?
                @results.each do |result|
                  link_to(
                    continuous_result_path(result),
                    class: "flex items-center px-4 py-3 hover:bg-gray-50 text-gray-700"
                  ) do
                    i(class: "bi bi-graph-up mr-3 text-gray-400")
                    plain "View #{result.evaluator_name} Result"
                  end
                end
              end

              if @queue_item.status == "failed"
                button_to(
                  "Retry Evaluation",
                  retry_continuous_queue_item_path(@queue_item),
                  method: :patch,
                  class: "flex items-center w-full px-4 py-3 hover:bg-gray-50 text-green-600"
                )
              end

              if %w[pending running].include?(@queue_item.status)
                button_to(
                  "Cancel Evaluation",
                  cancel_continuous_queue_item_path(@queue_item),
                  method: :patch,
                  class: "flex items-center w-full px-4 py-3 hover:bg-gray-50 text-yellow-600",
                  data: { confirm: "Cancel this evaluation?" }
                )
              end
            end
          end
        end

        def render_result_item(result)
          div(class: "py-4 first:pt-0 last:pb-0") do
            div(class: "flex justify-between items-start") do
              div do
                span(class: "font-medium text-gray-900") { result.evaluator_name }
                div(class: "mt-1 flex items-center gap-2") do
                  render_result_status_badge(result)
                  if result.score
                    span(class: "text-sm text-gray-600") { "Score: #{result.score.round(2)}" }
                  end
                end
              end
              link_to(
                "View",
                continuous_result_path(result),
                class: "text-sm text-blue-600 hover:text-blue-500"
              )
            end
          end
        end

        def render_detail_row(label, value)
          div do
            dt(class: "text-sm font-medium text-gray-500") { label }
            dd(class: "mt-1 text-sm text-gray-900") { value }
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

        def render_result_status_badge(result)
          badge_config = case result.status
                        when "passed"
                          { color: "green", text: "Passed" }
                        when "failed"
                          { color: "red", text: "Failed" }
                        when "error"
                          { color: "yellow", text: "Error" }
                        else
                          { color: "gray", text: result.status }
                        end

          color_classes = case badge_config[:color]
                         when "green" then "bg-green-100 text-green-800"
                         when "red" then "bg-red-100 text-red-800"
                         when "yellow" then "bg-yellow-100 text-yellow-800"
                         else "bg-gray-100 text-gray-800"
                         end

          span(class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium #{color_classes}") do
            badge_config[:text]
          end
        end

        def render_span_link(span_id)
          link_to(
            span_id,
            "/raaf/tracing/spans/#{span_id}",
            class: "font-mono text-blue-600 hover:text-blue-500"
          )
        end

        def render_policy_link(policy)
          if policy
            link_to(
              policy.name,
              continuous_policy_path(policy),
              class: "text-blue-600 hover:text-blue-500"
            )
          else
            span(class: "text-gray-400") { "Unknown policy" }
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
