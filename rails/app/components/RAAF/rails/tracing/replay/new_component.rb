# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      module Replay
        # Component for the new replay form page
        #
        # Displays a form to configure and execute a span replay with
        # editable prompts and model settings.
        class NewComponent < BaseComponent
          def initialize(span:, replay:)
            @span = span
            @replay = replay
            @original_settings = extract_original_settings
            @original_messages = extract_original_messages
          end

          def view_template
            div(class: "space-y-6", data: { controller: "replay-form" }) do
              # Header with breadcrumb
              render_header

              # Form wrapped with action URL
              form(
                action: tracing_span_replays_path(@span.span_id),
                method: :post,
                data: { turbo: "false" }
              ) do
                # Main form content
                div(class: "grid grid-cols-1 lg:grid-cols-2 gap-6") do
                  # Left column: Configuration
                  div(class: "space-y-6") do
                    render_configuration_form
                  end

                  # Right column: Prompts
                  div(class: "space-y-6") do
                    render_prompt_editor
                  end
                end

                # Submit section
                render_submit_section
              end
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
                  a(href: tracing_span_path(@span.span_id), class: "hover:text-gray-700") { @span.display_name }
                  span(class: "mx-2") { "/" }
                  span(class: "text-gray-900") { "New Replay" }
                end

                h1(class: "text-2xl font-bold text-gray-900") do
                  "Replay & Debug"
                end
                p(class: "mt-1 text-sm text-gray-500") do
                  "Modify configuration and prompts, then replay the LLM call to see how changes affect the output."
                end
              end

              # Original span info
              div(class: "text-right text-sm text-gray-500") do
                div { "Original Model: #{@original_settings[:model] || 'Unknown'}" }
                div { "Duration: #{format_duration(@span.duration_ms)}" }
              end
            end
          end

          def render_configuration_form
            div(class: "bg-white rounded-xl border border-gray-200 shadow-sm p-6") do
              h2(class: "text-lg font-semibold text-gray-900 mb-4") { "Model Configuration" }

              div(class: "space-y-4", id: "configuration-form") do
                # Model selection
                render_model_field

                # Temperature
                render_slider_field(
                  label: "Temperature",
                  name: "temperature",
                  value: @original_settings[:temperature] || 0.7,
                  min: 0,
                  max: 2,
                  step: 0.1,
                  description: "Controls randomness. Lower values are more focused, higher more creative."
                )

                # Max tokens
                render_number_field(
                  label: "Max Tokens",
                  name: "max_tokens",
                  value: @original_settings[:max_tokens] || 1024,
                  min: 1,
                  max: 128_000,
                  description: "Maximum number of tokens to generate."
                )

                # Top P
                render_slider_field(
                  label: "Top P",
                  name: "top_p",
                  value: @original_settings[:top_p] || 1.0,
                  min: 0,
                  max: 1,
                  step: 0.05,
                  description: "Nucleus sampling threshold."
                )

                # Frequency penalty
                render_slider_field(
                  label: "Frequency Penalty",
                  name: "frequency_penalty",
                  value: @original_settings[:frequency_penalty] || 0,
                  min: 0,
                  max: 2,
                  step: 0.1,
                  description: "Reduces repetition of frequent tokens."
                )

                # Presence penalty
                render_slider_field(
                  label: "Presence Penalty",
                  name: "presence_penalty",
                  value: @original_settings[:presence_penalty] || 0,
                  min: 0,
                  max: 2,
                  step: 0.1,
                  description: "Encourages discussing new topics."
                )
              end
            end
          end

          def render_model_field
            # Provider selection
            div(class: "space-y-2") do
              label(for: "provider", class: "block text-sm font-medium text-gray-700") { "Provider" }
              select(
                id: "provider",
                name: "provider",
                class: "block w-full rounded-lg border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm",
                data: {
                  replay_form_target: "provider",
                  action: "change->replay-form#updateModelOptions"
                }
              ) do
                detected_provider = detect_provider(@original_settings[:model])
                option(value: "openai", selected: detected_provider == "openai") { "OpenAI" }
                option(value: "anthropic", selected: detected_provider == "anthropic") { "Anthropic" }
                option(value: "google", selected: detected_provider == "google") { "Google Gemini" }
                option(value: "perplexity", selected: detected_provider == "perplexity") { "Perplexity" }
                option(value: "groq", selected: detected_provider == "groq") { "Groq" }
                option(value: "xai", selected: detected_provider == "xai") { "xAI (Grok)" }
              end
            end

            # Model selection (filtered by provider)
            div(class: "space-y-2 mt-4") do
              label(for: "model", class: "block text-sm font-medium text-gray-700") { "Model" }
              select(
                id: "model",
                name: "model",
                class: "block w-full rounded-lg border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm",
                data: { replay_form_target: "model" }
              ) do
                render_model_options
              end
            end
          end

          def render_model_options
            # Render initial models for the detected provider
            # JavaScript will dynamically update this when provider changes
            provider = detect_provider(@original_settings[:model])
            models = models_for_provider(provider)

            models.each do |model|
              option(
                value: model[:value],
                selected: @original_settings[:model] == model[:value]
              ) { model[:label] }
            end
          end

          def models_for_provider(provider)
            case provider
            when "openai"
              [
                # GPT-5 Series (Latest)
                { value: "gpt-5", label: "GPT-5" },
                # GPT-4.1 Series (April 2025)
                { value: "gpt-4.1", label: "GPT-4.1" },
                { value: "gpt-4.1-mini", label: "GPT-4.1 Mini" },
                { value: "gpt-4.1-nano", label: "GPT-4.1 Nano" },
                # GPT-4o Series
                { value: "gpt-4o", label: "GPT-4o" },
                { value: "gpt-4o-mini", label: "GPT-4o Mini" },
                { value: "gpt-4-turbo", label: "GPT-4 Turbo" },
                # O-Series Reasoning Models
                { value: "o3-pro", label: "O3 Pro" },
                { value: "o3", label: "O3" },
                { value: "o4-mini", label: "O4 Mini" },
                { value: "o1-preview", label: "O1 Preview" },
                { value: "o1-mini", label: "O1 Mini" },
                { value: "o3-mini", label: "O3 Mini" }
              ]
            when "anthropic"
              [
                { value: "claude-sonnet-4-20250514", label: "Claude 4 Sonnet" },
                { value: "claude-3-5-sonnet-20241022", label: "Claude 3.5 Sonnet" },
                { value: "claude-3-opus-20240229", label: "Claude 3 Opus" },
                { value: "claude-3-5-haiku-20241022", label: "Claude 3.5 Haiku" }
              ]
            when "google"
              [
                { value: "gemini-3-pro-preview", label: "Gemini 3 Pro Preview" },
                { value: "gemini-3-flash-preview", label: "Gemini 3 Flash Preview" },
                { value: "gemini-2.5-pro", label: "Gemini 2.5 Pro" },
                { value: "gemini-2.5-flash", label: "Gemini 2.5 Flash" },
                { value: "gemini-2.5-flash-lite", label: "Gemini 2.5 Flash Lite" },
                { value: "gemini-2.0-flash", label: "Gemini 2.0 Flash" },
                { value: "gemini-2.0-flash-lite", label: "Gemini 2.0 Flash Lite" }
              ]
            when "perplexity"
              [
                { value: "sonar-pro", label: "Sonar Pro" },
                { value: "sonar", label: "Sonar" },
                { value: "sonar-reasoning-pro", label: "Sonar Reasoning Pro" },
                { value: "sonar-reasoning", label: "Sonar Reasoning" }
              ]
            when "groq"
              [
                { value: "llama-3.3-70b-versatile", label: "Llama 3.3 70B" },
                { value: "llama-3.1-70b-versatile", label: "Llama 3.1 70B" },
                { value: "llama-3.1-8b-instant", label: "Llama 3.1 8B" },
                { value: "mixtral-8x7b-32768", label: "Mixtral 8x7B" }
              ]
            when "xai"
              [
                { value: "grok-2-1212", label: "Grok 2" },
                { value: "grok-2-vision-1212", label: "Grok 2 Vision" },
                { value: "grok-beta", label: "Grok Beta" }
              ]
            else
              [{ value: "gpt-4o", label: "GPT-4o" }]
            end
          end

          def detect_provider(model)
            return "openai" if model.nil?

            case model
            when /^(gpt-|o1-|o3-|o4-)/
              "openai"
            when /^claude/
              "anthropic"
            when /^gemini/
              "google"
            when /^sonar/
              "perplexity"
            when /^(llama|mixtral|gemma)/
              "groq"
            when /^grok/
              "xai"
            else
              "openai"
            end
          end

          def render_slider_field(label:, name:, value:, min:, max:, step:, description:)
            div(class: "space-y-2") do
              div(class: "flex items-center justify-between") do
                label(for: name, class: "block text-sm font-medium text-gray-700") { label }
                span(
                  class: "text-sm text-gray-500",
                  id: "#{name}-value",
                  data: { replay_form_target: "#{name}Value" }
                ) { value.to_s }
              end
              input(
                type: "range",
                id: name,
                name: name,
                value: value,
                min: min,
                max: max,
                step: step,
                class: "w-full h-2 bg-gray-200 rounded-lg appearance-none cursor-pointer accent-blue-600",
                data: {
                  replay_form_target: name,
                  action: "input->replay-form#updateSliderValue"
                }
              )
              p(class: "text-xs text-gray-500") { description }
            end
          end

          def render_number_field(label:, name:, value:, min:, max:, description:)
            div(class: "space-y-2") do
              label(for: name, class: "block text-sm font-medium text-gray-700") { label }
              input(
                type: "number",
                id: name,
                name: name,
                value: value,
                min: min,
                max: max,
                class: "block w-full rounded-lg border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm",
                data: { replay_form_target: name }
              )
              p(class: "text-xs text-gray-500") { description }
            end
          end

          def render_prompt_editor
            div(class: "bg-white rounded-xl border border-gray-200 shadow-sm p-6") do
              h2(class: "text-lg font-semibold text-gray-900 mb-4") { "Prompts" }

              div(class: "space-y-4", data: { controller: "prompt-editor" }) do
                # System prompt
                render_prompt_section(
                  label: "System Prompt",
                  name: "system_prompt",
                  content: extract_system_prompt,
                  rows: 8
                )

                # User messages
                render_messages_section
              end
            end
          end

          def render_prompt_section(label:, name:, content:, rows:)
            div(class: "space-y-2") do
              label(for: name, class: "block text-sm font-medium text-gray-700") { label }
              textarea(
                id: name,
                name: name,
                rows: rows,
                class: "block w-full rounded-lg border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm font-mono",
                data: { prompt_editor_target: name }
              ) { content || "" }
            end
          end

          def render_messages_section
            div(class: "space-y-4") do
              div(class: "flex items-center justify-between") do
                label(class: "block text-sm font-medium text-gray-700") { "User Messages" }
                button(
                  type: "button",
                  class: "text-sm text-blue-600 hover:text-blue-800",
                  data: { action: "click->prompt-editor#addMessage" }
                ) { "+ Add Message" }
              end

              div(id: "messages-container", class: "space-y-3", data: { prompt_editor_target: "messagesContainer" }) do
                user_messages = extract_user_messages
                if user_messages.any?
                  user_messages.each_with_index do |msg, index|
                    render_message_field(msg, index)
                  end
                else
                  p(class: "text-sm text-gray-500 italic") { "No user messages in original span" }
                end
              end
            end
          end

          def render_message_field(message, index)
            div(class: "border border-gray-200 rounded-lg p-3", data: { message_index: index }) do
              div(class: "flex items-center justify-between mb-2") do
                span(class: "text-xs font-medium text-gray-500 uppercase") { message["role"] || "user" }
                button(
                  type: "button",
                  class: "text-gray-400 hover:text-red-500",
                  data: { action: "click->prompt-editor#removeMessage" }
                ) do
                  i(class: "bi bi-x-lg")
                end
              end
              textarea(
                name: "user_messages[#{index}][content]",
                rows: 4,
                class: "block w-full rounded-lg border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm font-mono"
              ) { message["content"] || "" }
              input(type: "hidden", name: "user_messages[#{index}][role]", value: message["role"] || "user")
            end
          end

          def render_submit_section
            div(class: "bg-white rounded-xl border border-gray-200 shadow-sm p-6") do
              div(class: "flex items-center justify-between") do
                # Notes field
                div(class: "flex-1 mr-4") do
                  label(for: "notes", class: "block text-sm font-medium text-gray-700 mb-1") { "Notes (optional)" }
                  input(
                    type: "text",
                    id: "notes",
                    name: "notes",
                    placeholder: "Add notes about this replay experiment...",
                    class: "block w-full rounded-lg border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                  )
                end

                # Buttons
                div(class: "flex items-center gap-3") do
                  a(
                    href: tracing_span_path(@span.span_id),
                    class: "inline-flex items-center px-4 py-2 border border-gray-300 rounded-lg text-sm font-medium text-gray-700 bg-white hover:bg-gray-50"
                  ) { "Cancel" }

                  button(
                    type: "submit",
                    class: "inline-flex items-center px-4 py-2 border border-transparent rounded-lg text-sm font-medium text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500",
                    data: { action: "click->replay-form#submit" }
                  ) do
                    i(class: "bi bi-play-fill mr-2")
                    plain "Run Replay"
                  end
                end
              end
            end

            # Status container for Turbo Stream updates
            div(id: "replay-status")
          end

          def extract_original_settings
            attrs = @span.span_attributes || {}
            llm_config = attrs.dig("llm", "request") || {}

            {
              model: llm_config["model"] || attrs["model"] || attrs["agent.model"],
              temperature: safe_numeric(llm_config["temperature"] || attrs["agent.temperature"]),
              max_tokens: safe_integer(llm_config["max_tokens"] || llm_config["max_output_tokens"] || attrs["agent.max_tokens"]),
              top_p: safe_numeric(llm_config["top_p"] || attrs["agent.top_p"]),
              frequency_penalty: safe_numeric(llm_config["frequency_penalty"] || attrs["agent.frequency_penalty"]),
              presence_penalty: safe_numeric(llm_config["presence_penalty"] || attrs["agent.presence_penalty"])
            }.compact
          end

          # Convert value to numeric, return nil for non-numeric values like "N/A"
          def safe_numeric(value)
            return nil if value.nil?
            return value if value.is_a?(Numeric)
            return nil if value.to_s.strip.downcase == "n/a"

            Float(value)
          rescue ArgumentError, TypeError
            nil
          end

          # Convert value to integer, return nil for non-numeric values
          def safe_integer(value)
            return nil if value.nil?
            return value.to_i if value.is_a?(Numeric)
            return nil if value.to_s.strip.downcase == "n/a"

            Integer(value)
          rescue ArgumentError, TypeError
            nil
          end

          def extract_original_messages
            attrs = @span.span_attributes || {}
            llm_config = attrs.dig("llm", "request") || {}

            # Check various storage formats
            messages = llm_config["messages"] ||
                       attrs["llm.request.messages"] ||
                       attrs["agent.conversation_messages"] ||
                       []

            # Parse JSON if it's a string
            if messages.is_a?(String) && messages.present?
              begin
                messages = JSON.parse(messages)
              rescue JSON::ParserError
                messages = []
              end
            end

            messages
          end

          def extract_system_prompt
            # First check messages for system role
            system_from_messages = @original_messages.find { |m| m["role"] == "system" }&.dig("content")
            return system_from_messages if system_from_messages.present?

            # Fallback to direct system instructions attribute
            attrs = @span.span_attributes || {}
            attrs["agent.system_instructions"]
          end

          def extract_user_messages
            @original_messages.reject { |m| m["role"] == "system" }
          end
        end
      end
    end
  end
end
