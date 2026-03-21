# frozen_string_literal: true

module RAAF
  module Rails
    module Eval
      class FeedbackScoreShow < RAAF::Rails::Tracing::BaseComponent
        def initialize(score:)
          @score = score
        end

        def view_template
          div(class: "p-6 max-w-2xl") do
            h1(class: "text-2xl font-bold text-gray-900 mb-4") { "Feedback Score: #{@score.name}" }
            render_details
          end
        end

        private

        def render_details
          div(class: "bg-white shadow rounded-lg p-6 space-y-3") do
            render_detail("Name", @score.name)
            render_detail("Value", @score.numerical? ? @score.value.to_s : @score.category_value)
            render_detail("Type", @score.numerical? ? "Numerical" : "Categorical")
            render_detail("Target", @score.span_level? ? "Span: #{@score.span_id}" : "Trace: #{@score.trace_id}")
            render_detail("Source", @score.source)
            render_detail("Scored By", @score.scored_by || "-")
            render_detail("Reason", @score.reason || "-")
            render_detail("Created", @score.created_at&.strftime("%Y-%m-%d %H:%M:%S"))
          end
        end

        def render_detail(label, value)
          div(class: "flex justify-between py-2 border-b border-gray-100") do
            span(class: "text-sm font-medium text-gray-500") { label }
            span(class: "text-sm text-gray-900") { value.to_s }
          end
        end
      end
    end
  end
end
