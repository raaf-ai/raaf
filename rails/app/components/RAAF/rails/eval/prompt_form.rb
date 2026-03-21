# frozen_string_literal: true

module RAAF
  module Rails
    module Eval
      class PromptForm < RAAF::Rails::Tracing::BaseComponent
        def initialize(prompt:)
          @prompt = prompt
        end

        def view_template
          div(class: "p-6 max-w-2xl") do
            h1(class: "text-2xl font-bold text-gray-900 mb-6") { @prompt.new_record? ? "New Prompt" : "Edit Prompt" }
            form_with(model: @prompt, url: @prompt.new_record? ? eval_prompts_path : eval_prompt_path(@prompt), method: @prompt.new_record? ? :post : :patch) do |f|
              render_form_fields(f)
            end
          end
        end

        private

        def render_form_fields(f)
          div(class: "space-y-4") do
            div do
              f.label :name, class: "block text-sm font-medium text-gray-700"
              f.text_field :name, class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm", required: true, placeholder: "e.g. customer_support_prompt"
            end
            div do
              f.label :agent_name, class: "block text-sm font-medium text-gray-700"
              f.text_field :agent_name, class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm sm:text-sm", placeholder: "e.g. CustomerSupportAgent"
            end
            div do
              f.label :description, class: "block text-sm font-medium text-gray-700"
              f.text_area :description, rows: 2, class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm sm:text-sm"
            end

            if @prompt.new_record?
              div(class: "border-t border-gray-200 pt-4") do
                h3(class: "text-sm font-medium text-gray-700 mb-2") { "Initial Version (optional)" }
                div do
                  label(class: "block text-sm font-medium text-gray-700") { "Prompt Content" }
                  textarea(name: "prompt[initial_content]", rows: 6, class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm sm:text-sm font-mono", placeholder: "You are a helpful assistant...")
                end
                div do
                  label(class: "block text-sm font-medium text-gray-700") { "Target Model" }
                  input(type: "text", name: "prompt[initial_model]", class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm sm:text-sm", placeholder: "e.g. gpt-4o")
                end
              end
            end

            div(class: "flex gap-3 pt-4") do
              f.submit(@prompt.new_record? ? "Create Prompt" : "Update Prompt", class: "px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 font-medium text-sm cursor-pointer")
              render_preline_button(text: "Cancel", href: eval_prompts_path, variant: "secondary")
            end
          end
        end
      end
    end
  end
end
