# frozen_string_literal: true

module RAAF
  module Eval
    module UI
      ##
      # Phlex component for editing AI model settings
      #
      # Provides form inputs for model selection, temperature, max tokens,
      # and other LLM parameters with real-time validation.
      #
      # @example Render in a view
      #   render RAAF::Eval::UI::SettingsForm.new(configuration: @config)
      #
      class SettingsForm < Phlex::HTML
        def initialize(configuration: {}, baseline: {})
          @configuration = configuration
          @baseline = baseline
        end

        def view_template
          div(class: "settings-form bg-white rounded-lg shadow-sm p-6", data_controller: "form-validation") do
            h2(class: "text-xl font-semibold text-gray-900 mb-4") { "AI Settings" }

            render_model_selection
            render_basic_parameters
            render_advanced_section
            render_actions
          end
        end

        private

        def render_model_selection
          div(class: "mb-6") do
            label(class: "block text-sm font-medium text-gray-700 mb-2") { "Model & Provider" }
            div(class: "grid grid-cols-2 gap-4") do
              render_provider_select
              render_model_select
            end
          end
        end

        def render_provider_select
          div do
            label(class: "block text-xs text-gray-500 mb-1") { "Provider" }
            select(
              name: "configuration[provider]",
              class: "w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500",
              data_action: "change->form-validation#validate"
            ) do
              option(value: "openai", selected: current_provider == "openai") { "OpenAI" }
              option(value: "anthropic", selected: current_provider == "anthropic") { "Anthropic" }
              option(value: "google", selected: current_provider == "google") { "Google" }
              option(value: "groq", selected: current_provider == "groq") { "Groq" }
            end
          end
        end

        def render_model_select
          div do
            label(class: "block text-xs text-gray-500 mb-1") { "Model" }
            select(
              name: "configuration[model]",
              class: "w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500",
              data_action: "change->form-validation#validate",
              required: true
            ) do
              render_model_options
            end
          end
        end

        def render_model_options
          option(value: "gpt-4o", selected: current_model == "gpt-4o") { "GPT-4o" }
          option(value: "gpt-4-turbo", selected: current_model == "gpt-4-turbo") { "GPT-4 Turbo" }
          option(value: "gpt-3.5-turbo", selected: current_model == "gpt-3.5-turbo") { "GPT-3.5 Turbo" }
          option(value: "claude-3-opus", selected: current_model == "claude-3-opus") { "Claude 3 Opus" }
          option(value: "claude-3-sonnet", selected: current_model == "claude-3-sonnet") { "Claude 3 Sonnet" }
          option(value: "gemini-pro", selected: current_model == "gemini-pro") { "Gemini Pro" }
        end

        def render_basic_parameters
          div(class: "space-y-4 mb-6") do
            render_slider_input(
              "Temperature",
              "temperature",
              current_temperature,
              0.0,
              2.0,
              0.1,
              "Controls randomness. Lower = more focused, higher = more creative"
            )
            render_number_input(
              "Max Tokens",
              "max_tokens",
              current_max_tokens,
              1,
              4096,
              "Maximum number of tokens to generate"
            )
            render_slider_input(
              "Top P",
              "top_p",
              current_top_p,
              0.0,
              1.0,
              0.01,
              "Nucleus sampling threshold"
            )
          end
        end

        def render_slider_input(label, name, value, min, max, step, description)
          div do
            div(class: "flex justify-between items-center mb-2") do
              label(class: "text-sm font-medium text-gray-700") { label }
              span(class: "text-sm text-gray-500") { value }
            end
            input(
              type: "range",
              name: "configuration[#{name}]",
              value: value,
              min: min,
              max: max,
              step: step,
              class: "w-full h-2 bg-gray-200 rounded-lg appearance-none cursor-pointer",
              data_action: "input->form-validation#validate"
            )
            p(class: "text-xs text-gray-500 mt-1") { description }
          end
        end

        def render_number_input(label, name, value, min, max, description)
          div do
            label(class: "block text-sm font-medium text-gray-700 mb-2") { label }
            input(
              type: "number",
              name: "configuration[#{name}]",
              value: value,
              min: min,
              max: max,
              class: "w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500",
              data_action: "input->form-validation#validate"
            )
            p(class: "text-xs text-gray-500 mt-1") { description }
          end
        end

        def render_advanced_section
          details(class: "mb-6") do
            summary(class: "cursor-pointer text-sm font-medium text-gray-700 hover:text-gray-900") do
              "Advanced Settings"
            end
            div(class: "mt-4 space-y-4 pl-4") do
              render_slider_input(
                "Frequency Penalty",
                "frequency_penalty",
                current_frequency_penalty,
                -2.0,
                2.0,
                0.1,
                "Reduces repetition of token sequences"
              )
              render_slider_input(
                "Presence Penalty",
                "presence_penalty",
                current_presence_penalty,
                -2.0,
                2.0,
                0.1,
                "Encourages discussing new topics"
              )
            end
          end
        end

        def render_actions
          div(class: "flex justify-between items-center pt-4 border-t border-gray-200") do
            button(
              type: "button",
              class: "px-4 py-2 text-sm text-gray-700 border border-gray-300 rounded-lg hover:bg-gray-50",
              data_action: "click->settings-form#resetToBaseline"
            ) do
              "Reset to Baseline"
            end
            div(class: "text-xs text-gray-500 italic") do
              "Changes will be applied when you run the evaluation"
            end
          end
        end

        # Helper methods to get current values
        def current_provider
          @configuration["provider"] || @configuration[:provider] || "openai"
        end

        def current_model
          @configuration["model"] || @configuration[:model] || "gpt-4o"
        end

        def current_temperature
          @configuration["temperature"] || @configuration[:temperature] || 0.7
        end

        def current_max_tokens
          @configuration["max_tokens"] || @configuration[:max_tokens] || 1000
        end

        def current_top_p
          @configuration["top_p"] || @configuration[:top_p] || 1.0
        end

        def current_frequency_penalty
          @configuration["frequency_penalty"] || @configuration[:frequency_penalty] || 0.0
        end

        def current_presence_penalty
          @configuration["presence_penalty"] || @configuration[:presence_penalty] || 0.0
        end
      end
    end
  end
end
