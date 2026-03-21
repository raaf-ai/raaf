# frozen_string_literal: true

module RAAF
  module Rails
    module Eval
      class PromptDiff < RAAF::Rails::Tracing::BaseComponent
        def initialize(prompt:, diff:)
          @prompt = prompt
          @diff = diff
        end

        def view_template
          div(class: "p-6") do
            h1(class: "text-2xl font-bold text-gray-900 mb-6") { "Prompt Diff: #{@prompt.name}" }
            if @diff
              render_diff_view
            else
              div(class: "bg-yellow-50 border border-yellow-200 rounded-lg p-4 text-sm text-yellow-700") do
                "Could not compute diff. Ensure both versions exist."
              end
            end
          end
        end

        private

        def render_diff_view
          div(class: "grid grid-cols-2 gap-4") do
            div(class: "bg-white shadow rounded-lg p-4") do
              h3(class: "text-sm font-medium text-gray-500 mb-2") { "Version #{@diff[:from][:version]}" }
              span(class: "text-xs text-gray-400") { "Model: #{@diff[:from][:model] || 'N/A'}" }
              pre(class: "mt-2 bg-red-50 rounded p-3 text-sm text-gray-800 whitespace-pre-wrap overflow-x-auto") { @diff[:from][:content] }
            end
            div(class: "bg-white shadow rounded-lg p-4") do
              h3(class: "text-sm font-medium text-gray-500 mb-2") { "Version #{@diff[:to][:version]}" }
              span(class: "text-xs text-gray-400") { "Model: #{@diff[:to][:model] || 'N/A'}" }
              pre(class: "mt-2 bg-green-50 rounded p-3 text-sm text-gray-800 whitespace-pre-wrap overflow-x-auto") { @diff[:to][:content] }
            end
          end

          div(class: "mt-4 flex gap-4") do
            div(class: "flex items-center gap-2") do
              dot_class = @diff[:content_changed] ? "bg-yellow-400" : "bg-green-400"
              div(class: "w-2 h-2 rounded-full #{dot_class}")
              span(class: "text-sm text-gray-600") { "Content #{@diff[:content_changed] ? 'changed' : 'unchanged'}" }
            end
            div(class: "flex items-center gap-2") do
              dot_class = @diff[:model_changed] ? "bg-yellow-400" : "bg-green-400"
              div(class: "w-2 h-2 rounded-full #{dot_class}")
              span(class: "text-sm text-gray-600") { "Model #{@diff[:model_changed] ? 'changed' : 'unchanged'}" }
            end
          end
        end
      end
    end
  end
end
