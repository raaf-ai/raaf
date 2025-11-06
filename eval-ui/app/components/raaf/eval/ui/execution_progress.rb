# frozen_string_literal: true

module RAAF
  module Eval
    module UI
      ##
      # Phlex component for displaying evaluation execution progress
      #
      # Shows real-time progress updates via Turbo Streams including:
      # - Progress bar with percentage
      # - Current status message
      # - Estimated time remaining
      # - Cancel button
      # - Error display
      #
      # @example Render in a view
      #   render RAAF::Eval::UI::ExecutionProgress.new(session: @session)
      #
      class ExecutionProgress < Phlex::HTML
        def initialize(session:)
          @session = session
        end

        def view_template
          div(
            id: "evaluation_progress",
            class: "execution-progress bg-white rounded-lg shadow-sm p-6",
            data_controller: "evaluation-progress",
            data_evaluation_progress_url_value: status_path,
            data_evaluation_progress_interval_value: 1000
          ) do
            render_header
            render_progress_bar
            render_status_message
            render_actions
            render_error if @session.failed?
          end
        end

        private

        def render_header
          div(class: "flex justify-between items-center mb-4") do
            h2(class: "text-xl font-semibold text-gray-900") { "Evaluation Progress" }
            div(class: "text-sm text-gray-500") do
              "Session: #{@session.name}"
            end
          end
        end

        def render_progress_bar
          div(class: "mb-6") do
            div(class: "flex justify-between items-center mb-2") do
              span(class: "text-sm font-medium text-gray-700") { "Progress" }
              span(class: "text-sm font-medium text-gray-700") { "#{@session.progress_percentage}%" }
            end
            div(class: "w-full bg-gray-200 rounded-full h-4 overflow-hidden") do
              div(
                class: progress_bar_class,
                style: "width: #{@session.progress_percentage}%",
                role: "progressbar",
                aria_valuenow: @session.progress_percentage,
                aria_valuemin: 0,
                aria_valuemax: 100
              )
            end
          end
        end

        def render_status_message
          div(class: "mb-4") do
            div(class: "text-sm text-gray-600") do
              span(class: "font-medium") { "Status: " }
              span(class: status_text_class) { status_text }
            end
            if @session.running?
              div(class: "text-xs text-gray-500 mt-1") do
                render_estimated_time
              end
            end
          end
        end

        def render_estimated_time
          # Simple estimation based on progress
          if @session.progress_percentage > 0 && @session.progress_percentage < 100
            elapsed = Time.current - @session.created_at
            estimated_total = elapsed / (@session.progress_percentage / 100.0)
            remaining = estimated_total - elapsed
            minutes = (remaining / 60).floor
            seconds = (remaining % 60).floor

            "Estimated time remaining: #{minutes}m #{seconds}s"
          else
            "Calculating..."
          end
        end

        def render_actions
          div(class: "flex justify-end gap-2") do
            if @session.running?
              button(
                type: "button",
                class: "px-4 py-2 text-sm text-red-600 border border-red-300 rounded-lg hover:bg-red-50",
                data_action: "click->evaluation-progress#cancel"
              ) do
                "Cancel Evaluation"
              end
            elsif @session.completed?
              a(
                href: results_path,
                class: "px-4 py-2 text-sm text-white bg-blue-600 rounded-lg hover:bg-blue-700"
              ) do
                "View Results"
              end
            elsif @session.failed?
              button(
                type: "button",
                class: "px-4 py-2 text-sm text-white bg-blue-600 rounded-lg hover:bg-blue-700",
                data_action: "click->evaluation-progress#retry"
              ) do
                "Retry Evaluation"
              end
            end
          end
        end

        def render_error
          div(class: "mt-4 p-4 bg-red-50 border border-red-200 rounded-lg") do
            div(class: "flex items-start") do
              div(class: "flex-shrink-0") do
                # Error icon
                svg(class: "h-5 w-5 text-red-400", fill: "currentColor", viewBox: "0 0 20 20") do
                  path(
                    fill_rule: "evenodd",
                    d: "M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z"
                  )
                end
              end
              div(class: "ml-3") do
                h3(class: "text-sm font-medium text-red-800") { "Evaluation Failed" }
                div(class: "mt-2 text-sm text-red-700") do
                  p { @session.error_message }
                end
              end
            end
          end
        end

        def progress_bar_class
          base = "h-full transition-all duration-300 ease-in-out"
          if @session.completed?
            "#{base} bg-green-600"
          elsif @session.failed?
            "#{base} bg-red-600"
          else
            "#{base} bg-blue-600"
          end
        end

        def status_text
          case @session.status
          when "pending"
            "Waiting to start..."
          when "running"
            "Running evaluation..."
          when "completed"
            "Evaluation completed successfully"
          when "failed"
            "Evaluation failed"
          when "cancelled"
            "Evaluation cancelled"
          else
            @session.status.humanize
          end
        end

        def status_text_class
          case @session.status
          when "completed"
            "text-green-600 font-semibold"
          when "failed"
            "text-red-600 font-semibold"
          when "running"
            "text-blue-600 font-semibold"
          else
            "text-gray-600"
          end
        end

        def status_path
          "/eval/evaluations/#{@session.id}/status"
        end

        def results_path
          "/eval/evaluations/#{@session.id}/results"
        end
      end
    end
  end
end
