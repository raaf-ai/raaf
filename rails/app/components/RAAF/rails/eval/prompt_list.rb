# frozen_string_literal: true

module RAAF
  module Rails
    module Eval
      class PromptList < RAAF::Rails::Tracing::BaseComponent
        def initialize(prompts:)
          @prompts = prompts
        end

        def view_template
          div(class: "p-6") do
            render_header
            render_prompts_table
          end
        end

        private

        def render_header
          div(class: "sm:flex sm:items-center sm:justify-between mb-6 pb-4 border-b border-gray-200") do
            div do
              h1(class: "text-2xl font-bold text-gray-900") { "Prompts" }
              p(class: "mt-1 text-sm text-gray-500") { "Version-controlled prompts with history and rollback" }
            end
            div(class: "mt-4 sm:mt-0") do
              render_preline_button(text: "New Prompt", href: eval_prompts_path + "/new", variant: "primary", icon: "bi-plus-lg")
            end
          end
        end

        def render_prompts_table
          div(class: "bg-white shadow rounded-lg overflow-hidden") do
            if @prompts.any?
              div(class: "overflow-x-auto") do
                table(class: "min-w-full divide-y divide-gray-200") do
                  thead(class: "bg-gray-50") do
                    tr do
                      th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase") { "Name" }
                      th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase") { "Agent" }
                      th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase") { "Latest Version" }
                      th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase") { "Updated" }
                      th(class: "px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase") { "Actions" }
                    end
                  end
                  tbody(class: "bg-white divide-y divide-gray-200") do
                    @prompts.each { |prompt| render_prompt_row(prompt) }
                  end
                end
              end
            else
              render_empty_state
            end
          end
        end

        def render_prompt_row(prompt)
          tr(class: "hover:bg-gray-50") do
            td(class: "px-4 py-3") do
              a(href: eval_prompt_path(prompt), class: "text-blue-600 hover:text-blue-800 font-medium") { prompt.name }
              p(class: "text-xs text-gray-500 mt-1") { prompt.description.truncate(60) } if prompt.description.present?
            end
            td(class: "px-4 py-3 text-sm text-gray-600") { prompt.agent_name || "-" }
            td(class: "px-4 py-3 text-sm text-gray-600") { "v#{prompt.latest_version}" }
            td(class: "px-4 py-3 text-sm text-gray-500") { prompt.updated_at&.strftime("%Y-%m-%d") }
            td(class: "px-4 py-3 text-right") do
              render_preline_button(text: "View", href: eval_prompt_path(prompt), variant: "secondary", size: "xs")
            end
          end
        end

        def render_empty_state
          div(class: "flex flex-col items-center justify-center py-12") do
            i(class: "bi bi-file-text text-5xl text-gray-400")
            h3(class: "mt-4 text-lg font-medium text-gray-900") { "No prompts yet" }
            p(class: "mt-1 text-sm text-gray-500") { "Create versioned prompts to track changes over time." }
            div(class: "mt-4") do
              render_preline_button(text: "Create Prompt", href: eval_prompts_path + "/new", variant: "primary")
            end
          end
        end
      end
    end
  end
end
