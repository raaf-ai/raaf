# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      module Replay
        # Component for listing all replays for a span
        #
        # Displays a table of replay attempts with status, configuration changes,
        # and links to view results.
        class IndexComponent < BaseComponent
          def initialize(span:, replays:)
            @span = span
            @replays = replays
          end

          def view_template
            div(class: "space-y-6") do
              render_header
              render_replays_table
            end
          end

          private

          def render_header
            div(class: "flex items-center justify-between") do
              div do
                # Breadcrumb
                nav(class: "flex text-sm text-gray-500 mb-2") do
                  a(href: tracing_spans_path, class: "hover:text-gray-700") { "Spans" }
                  span(class: "mx-2") { "/" }
                  a(href: tracing_span_path(@span.span_id), class: "hover:text-gray-700") do
                    @span.display_name
                  end
                  span(class: "mx-2") { "/" }
                  span(class: "text-gray-900") { "Replays" }
                end

                h1(class: "text-2xl font-bold text-gray-900") { "Replay History" }
                p(class: "mt-1 text-sm text-gray-500") do
                  "#{@replays.count} replay attempts for this span"
                end
              end

              # New replay button
              a(
                href: new_tracing_span_replay_path(@span.span_id),
                class: "inline-flex items-center px-4 py-2 border border-transparent rounded-lg text-sm font-medium text-white bg-blue-600 hover:bg-blue-700"
              ) do
                i(class: "bi bi-plus-lg mr-2")
                plain "New Replay"
              end
            end
          end

          def render_replays_table
            if @replays.any?
              div(class: "bg-white rounded-xl border border-gray-200 shadow-sm overflow-hidden") do
                table(class: "min-w-full divide-y divide-gray-200") do
                  thead(class: "bg-gray-50") do
                    tr do
                      th(scope: "col", class: "px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider") { "ID" }
                      th(scope: "col", class: "px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider") { "Status" }
                      th(scope: "col", class: "px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider") { "Changes" }
                      th(scope: "col", class: "px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider") { "Created" }
                      th(scope: "col", class: "px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider") { "Duration" }
                      th(scope: "col", class: "relative px-6 py-3") do
                        span(class: "sr-only") { "Actions" }
                      end
                    end
                  end

                  tbody(class: "bg-white divide-y divide-gray-200") do
                    @replays.each do |replay|
                      render_replay_row(replay)
                    end
                  end
                end
              end
            else
              render_empty_state
            end
          end

          def render_replay_row(replay)
            tr(class: "hover:bg-gray-50") do
              # ID
              td(class: "px-6 py-4 whitespace-nowrap") do
                span(class: "text-sm font-medium text-gray-900") { "##{replay.id}" }
                if replay.notes.present?
                  p(class: "text-xs text-gray-500 truncate max-w-xs") { replay.notes }
                end
              end

              # Status
              td(class: "px-6 py-4 whitespace-nowrap") do
                render_status_badge(replay.status)
              end

              # Changes summary
              td(class: "px-6 py-4") do
                render_changes_summary(replay)
              end

              # Created at
              td(class: "px-6 py-4 whitespace-nowrap text-sm text-gray-500") do
                replay.created_at.strftime("%Y-%m-%d %H:%M")
              end

              # Duration comparison
              td(class: "px-6 py-4 whitespace-nowrap") do
                if replay.completed? && replay.replayed_span
                  render_duration_comparison(replay)
                else
                  span(class: "text-sm text-gray-400") { "-" }
                end
              end

              # Actions
              td(class: "px-6 py-4 whitespace-nowrap text-right text-sm font-medium") do
                a(
                  href: tracing_span_replay_path(@span.span_id, replay.id),
                  class: "text-blue-600 hover:text-blue-900"
                ) { "View" }
              end
            end
          end

          def render_status_badge(status)
            badge_class = case status
                         when "pending" then "bg-yellow-100 text-yellow-800"
                         when "running" then "bg-blue-100 text-blue-800"
                         when "completed" then "bg-green-100 text-green-800"
                         when "failed" then "bg-red-100 text-red-800"
                         else "bg-gray-100 text-gray-800"
                         end

            icon = case status
                  when "pending" then "bi-hourglass-split"
                  when "running" then "bi-arrow-repeat"
                  when "completed" then "bi-check-circle"
                  when "failed" then "bi-x-circle"
                  else "bi-question-circle"
                  end

            span(class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium #{badge_class}") do
              i(class: "bi #{icon} mr-1")
              plain status.capitalize
            end
          end

          def render_changes_summary(replay)
            changes = []

            if replay.configuration_changes.present?
              replay.configuration_changes.each_key do |key|
                changes << key.to_s.titleize
              end
            end

            if replay.system_prompt.present?
              changes << "System Prompt"
            end

            if replay.user_messages.present? && replay.user_messages.any?
              changes << "User Messages"
            end

            if changes.any?
              div(class: "flex flex-wrap gap-1") do
                changes.first(3).each do |change|
                  span(class: "inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-gray-100 text-gray-700") do
                    change
                  end
                end
                if changes.length > 3
                  span(class: "text-xs text-gray-500") { "+#{changes.length - 3} more" }
                end
              end
            else
              span(class: "text-sm text-gray-400 italic") { "No changes" }
            end
          end

          def render_duration_comparison(replay)
            original_duration = @span.duration_ms
            replayed_duration = replay.replayed_span&.duration_ms

            return span(class: "text-sm text-gray-400") { "-" } unless original_duration && replayed_duration

            delta = replay.duration_comparison

            div(class: "text-sm") do
              span(class: "text-gray-900") { format_duration(replayed_duration) }
              if delta && delta != 0
                delta_class = delta > 0 ? "text-red-600" : "text-green-600"
                delta_sign = delta > 0 ? "+" : ""
                span(class: "ml-1 #{delta_class}") { "(#{delta_sign}#{delta.round(1)}%)" }
              end
            end
          end

          def render_empty_state
            div(class: "bg-white rounded-xl border border-gray-200 shadow-sm p-12 text-center") do
              div(class: "mx-auto w-12 h-12 bg-gray-100 rounded-full flex items-center justify-center mb-4") do
                i(class: "bi bi-arrow-repeat text-gray-400 text-xl")
              end
              h3(class: "text-sm font-medium text-gray-900") { "No replays yet" }
              p(class: "mt-1 text-sm text-gray-500") do
                "Create a replay to test different configurations and prompts."
              end
              div(class: "mt-6") do
                a(
                  href: new_tracing_span_replay_path(@span.span_id),
                  class: "inline-flex items-center px-4 py-2 border border-transparent rounded-lg text-sm font-medium text-white bg-blue-600 hover:bg-blue-700"
                ) do
                  i(class: "bi bi-plus-lg mr-2")
                  plain "Create First Replay"
                end
              end
            end
          end
        end
      end
    end
  end
end
