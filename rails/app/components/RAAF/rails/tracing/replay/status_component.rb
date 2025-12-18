# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      module Replay
        # Component for displaying replay status during Turbo Stream updates
        #
        # Used to show real-time status updates as replays are processed.
        class StatusComponent < BaseComponent
          def initialize(replay:)
            @replay = replay
          end

          def view_template
            div(id: "replay-status", class: status_container_class) do
              case @replay.status
              when "pending"
                render_pending_status
              when "running"
                render_running_status
              when "completed"
                render_completed_status
              when "failed"
                render_failed_status
              end
            end
          end

          private

          def status_container_class
            base = "rounded-xl p-4 border"
            case @replay.status
            when "pending" then "#{base} bg-yellow-50 border-yellow-200"
            when "running" then "#{base} bg-blue-50 border-blue-200"
            when "completed" then "#{base} bg-green-50 border-green-200"
            when "failed" then "#{base} bg-red-50 border-red-200"
            else "#{base} bg-gray-50 border-gray-200"
            end
          end

          def render_pending_status
            div(class: "flex items-center") do
              div(class: "flex-shrink-0") do
                i(class: "bi bi-hourglass-split text-yellow-600 text-xl")
              end
              div(class: "ml-3") do
                h3(class: "text-sm font-medium text-yellow-800") { "Queued" }
                p(class: "mt-1 text-sm text-yellow-700") do
                  "Your replay is queued and will begin processing shortly..."
                end
              end
            end
          end

          def render_running_status
            div(class: "flex items-center") do
              div(class: "flex-shrink-0") do
                # Spinning icon
                div(class: "animate-spin") do
                  i(class: "bi bi-arrow-repeat text-blue-600 text-xl")
                end
              end
              div(class: "ml-3") do
                h3(class: "text-sm font-medium text-blue-800") { "Processing" }
                p(class: "mt-1 text-sm text-blue-700") do
                  "Executing replay with your configuration changes..."
                end
              end
              # Progress indicator
              div(class: "ml-auto") do
                div(class: "flex items-center text-sm text-blue-600") do
                  span(class: "animate-pulse") { "●" }
                  span(class: "ml-1") { "Running" }
                end
              end
            end
          end

          def render_completed_status
            div(class: "flex items-center justify-between") do
              div(class: "flex items-center") do
                div(class: "flex-shrink-0") do
                  i(class: "bi bi-check-circle text-green-600 text-xl")
                end
                div(class: "ml-3") do
                  h3(class: "text-sm font-medium text-green-800") { "Completed" }
                  p(class: "mt-1 text-sm text-green-700") do
                    "Replay completed successfully. View the results below."
                  end
                end
              end

              # View results link
              if @replay.replayed_span
                a(
                  href: tracing_span_replay_path(@replay.original_span_id, @replay.id),
                  class: "inline-flex items-center px-3 py-1.5 border border-green-300 rounded-lg text-sm font-medium text-green-700 bg-white hover:bg-green-50"
                ) do
                  plain "View Results"
                  i(class: "bi bi-arrow-right ml-1")
                end
              end
            end
          end

          def render_failed_status
            div(class: "flex items-start") do
              div(class: "flex-shrink-0") do
                i(class: "bi bi-exclamation-triangle text-red-600 text-xl")
              end
              div(class: "ml-3 flex-1") do
                h3(class: "text-sm font-medium text-red-800") { "Failed" }
                p(class: "mt-1 text-sm text-red-700") do
                  @replay.error_message || "An unknown error occurred during replay."
                end

                # Retry button
                div(class: "mt-3") do
                  a(
                    href: new_tracing_span_replay_path(@replay.original_span_id),
                    class: "inline-flex items-center px-3 py-1.5 border border-red-300 rounded-lg text-sm font-medium text-red-700 bg-white hover:bg-red-50"
                  ) do
                    i(class: "bi bi-arrow-repeat mr-1")
                    plain "Try Again"
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end
