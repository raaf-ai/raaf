# frozen_string_literal: true

module RAAF
  module Eval
    module UI
      ##
      # Phlex component for editing prompts with Monaco Editor
      #
      # Provides a split-pane editor showing original (baseline) prompt
      # on the left and editable new prompt on the right, with syntax
      # highlighting, validation, and token count estimation.
      #
      # @example Render in a view
      #   render RAAF::Eval::UI::PromptEditor.new(
      #     original: baseline_prompt,
      #     current: modified_prompt
      #   )
      #
      class PromptEditor < Phlex::HTML
        def initialize(original:, current: nil, language: "markdown", readonly: false)
          @original = original
          @current = current || original
          @language = language
          @readonly = readonly
        end

        def view_template
          div(class: "prompt-editor") do
            render_header
            render_editors
            render_footer
          end
        end

        private

        def render_header
          div(class: "flex justify-between items-center mb-4") do
            h2(class: "text-xl font-semibold text-gray-900") { "Prompt Editor" }
            div(class: "flex gap-2") do
              button(
                class: "px-3 py-1 text-sm border border-gray-300 rounded hover:bg-gray-50",
                data_action: "click->monaco-editor#toggleDiff"
              ) do
                "Show Diff"
              end
              button(
                class: "px-3 py-1 text-sm border border-gray-300 rounded hover:bg-gray-50",
                data_action: "click->monaco-editor#reset"
              ) do
                "Reset"
              end
            end
          end
        end

        def render_editors
          div(class: "grid grid-cols-1 md:grid-cols-2 gap-4") do
            render_editor_pane("Original Prompt", @original, true)
            render_editor_pane("Modified Prompt", @current, @readonly)
          end
        end

        def render_editor_pane(title, content, readonly)
          div(class: "bg-white rounded-lg shadow-sm overflow-hidden") do
            div(class: "px-4 py-2 bg-gray-50 border-b border-gray-200") do
              h3(class: "text-sm font-medium text-gray-700") { title }
            end
            div(
              class: "editor-container h-96",
              data_controller: "monaco-editor",
              data_monaco_editor_language_value: @language,
              data_monaco_editor_readonly_value: readonly,
              data_monaco_editor_original_content_value: @original
            ) do
              # Monaco editor will be mounted here via Stimulus controller
              div(id: "monaco-editor-#{readonly ? 'original' : 'modified'}", class: "h-full")

              # Hidden textarea to store content for form submission
              textarea(
                name: readonly ? "original_prompt" : "modified_prompt",
                class: "hidden",
                data_monaco_editor_target: "content"
              ) { content }
            end
          end
        end

        def render_footer
          div(class: "mt-4 grid grid-cols-1 md:grid-cols-3 gap-4") do
            render_stat_card("Characters", character_count, "text-blue-600")
            render_stat_card("Estimated Tokens", estimated_tokens, "text-green-600")
            render_validation_indicator
          end
        end

        def render_stat_card(label, value, color_class)
          div(class: "bg-white rounded-lg shadow-sm p-4") do
            div(class: "text-sm text-gray-500") { label }
            div(class: "text-2xl font-semibold #{color_class}") { value }
          end
        end

        def render_validation_indicator
          div(class: "bg-white rounded-lg shadow-sm p-4") do
            div(class: "text-sm text-gray-500") { "Validation" }
            div(
              class: "flex items-center gap-2",
              data_monaco_editor_target: "validation"
            ) do
              span(class: "inline-block w-3 h-3 bg-green-500 rounded-full")
              span(class: "text-sm text-gray-700") { "Valid" }
            end
          end
        end

        def character_count
          @current&.length || 0
        end

        def estimated_tokens
          # Rough estimation: ~4 characters per token
          (character_count / 4.0).ceil
        end
      end
    end
  end
end
