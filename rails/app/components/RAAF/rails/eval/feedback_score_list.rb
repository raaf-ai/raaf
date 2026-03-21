# frozen_string_literal: true

module RAAF
  module Rails
    module Eval
      class FeedbackScoreList < RAAF::Rails::Tracing::BaseComponent
        def initialize(scores:)
          @scores = scores
        end

        def view_template
          div(class: "p-6") do
            render_header
            render_scores_table
          end
        end

        private

        def render_header
          div(class: "sm:flex sm:items-center sm:justify-between mb-6 pb-4 border-b border-gray-200") do
            div do
              h1(class: "text-2xl font-bold text-gray-900") { "Feedback Scores" }
              p(class: "mt-1 text-sm text-gray-500") { "Human and automated annotations on traces and spans" }
            end
            div(class: "mt-4 sm:mt-0") do
              render_preline_button(text: "Statistics", href: eval_feedback_scores_path + "/statistics", variant: "secondary", icon: "bi-graph-up")
            end
          end
        end

        def render_scores_table
          div(class: "bg-white shadow rounded-lg overflow-hidden") do
            if @scores.any?
              table(class: "min-w-full divide-y divide-gray-200") do
                thead(class: "bg-gray-50") do
                  tr do
                    th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase") { "Name" }
                    th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase") { "Value" }
                    th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase") { "Target" }
                    th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase") { "Source" }
                    th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase") { "Scored By" }
                    th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase") { "Created" }
                  end
                end
                tbody(class: "bg-white divide-y divide-gray-200") do
                  @scores.each { |score| render_score_row(score) }
                end
              end
            else
              render_empty_state
            end
          end
        end

        def render_score_row(score)
          tr(class: "hover:bg-gray-50") do
            td(class: "px-4 py-3 font-medium text-sm text-gray-900") { score.name }
            td(class: "px-4 py-3 text-sm") do
              if score.numerical?
                color = score.value >= 0.7 ? "text-green-600" : score.value >= 0.4 ? "text-yellow-600" : "text-red-600"
                span(class: "font-mono font-medium #{color}") { score.value.round(3).to_s }
              else
                span(class: "px-2 py-0.5 rounded-full text-xs font-medium bg-purple-100 text-purple-800") { score.category_value }
              end
            end
            td(class: "px-4 py-3 text-sm text-gray-600") do
              if score.span_level?
                span(class: "font-mono text-xs") { "Span: #{score.span_id&.truncate(20)}" }
              else
                span(class: "font-mono text-xs") { "Trace: #{score.trace_id&.truncate(20)}" }
              end
            end
            td(class: "px-4 py-3 text-sm") do
              badge_class = %w[ui sdk].include?(score.source) ? "bg-blue-100 text-blue-800" : "bg-gray-100 text-gray-800"
              span(class: "px-2 py-0.5 rounded-full text-xs font-medium #{badge_class}") { score.source }
            end
            td(class: "px-4 py-3 text-sm text-gray-500") { score.scored_by || "-" }
            td(class: "px-4 py-3 text-sm text-gray-500") { score.created_at&.strftime("%Y-%m-%d %H:%M") }
          end
        end

        def render_empty_state
          div(class: "flex flex-col items-center justify-center py-12") do
            i(class: "bi bi-star text-5xl text-gray-400")
            h3(class: "mt-4 text-lg font-medium text-gray-900") { "No feedback scores yet" }
            p(class: "mt-1 text-sm text-gray-500") { "Score traces and spans to track agent quality." }
          end
        end
      end
    end
  end
end
