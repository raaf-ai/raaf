# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      module Replay
        ##
        # The replay form -- one recorded call, its settings and its prompt,
        # opened for editing so it can be run again.
        #
        # No canvas draws it, so the shape is the experiment editor's: the
        # editable sections in a column beside a sticky rail carrying what the
        # original call was and the button that starts the run. Every control
        # comes from the library rather than being styled here.
        #
        # **What the ids are for.** The form is not posted by the browser --
        # `replay-form#submit` collects the fields and sends them as JSON, so
        # the queued replay can be reported without a page load. That reader
        # finds the prompt by `#system_prompt`, the messages by
        # `#messages-container`, the note by `#notes`, and everything else by
        # Stimulus target. Those names are the contract between this file and
        # the controller in BaseLayout; renaming one here silently drops that
        # field from the replay.
        #
        class NewComponent < BaseComponent
          # The models offered per provider. Kept beside the same list in the
          # `replay-form` Stimulus controller, which rebuilds the dropdown when
          # the provider changes -- this one is what the page is first drawn
          # with.
          MODELS = {
            "openai" => [
              ["gpt-5", "GPT-5"],
              ["gpt-4.1", "GPT-4.1"],
              ["gpt-4.1-mini", "GPT-4.1 Mini"],
              ["gpt-4.1-nano", "GPT-4.1 Nano"],
              ["gpt-4o", "GPT-4o"],
              ["gpt-4o-mini", "GPT-4o Mini"],
              ["gpt-4-turbo", "GPT-4 Turbo"],
              ["o3-pro", "O3 Pro"],
              ["o3", "O3"],
              ["o4-mini", "O4 Mini"],
              ["o1-preview", "O1 Preview"],
              ["o1-mini", "O1 Mini"],
              ["o3-mini", "O3 Mini"]
            ],
            "anthropic" => [
              ["claude-sonnet-4-20250514", "Claude 4 Sonnet"],
              ["claude-3-5-sonnet-20241022", "Claude 3.5 Sonnet"],
              ["claude-3-opus-20240229", "Claude 3 Opus"],
              ["claude-3-5-haiku-20241022", "Claude 3.5 Haiku"]
            ],
            "google" => [
              ["gemini-3-pro-preview", "Gemini 3 Pro Preview"],
              ["gemini-3-flash-preview", "Gemini 3 Flash Preview"],
              ["gemini-2.5-pro", "Gemini 2.5 Pro"],
              ["gemini-2.5-flash", "Gemini 2.5 Flash"],
              ["gemini-2.5-flash-lite", "Gemini 2.5 Flash Lite"],
              ["gemini-2.0-flash", "Gemini 2.0 Flash"],
              ["gemini-2.0-flash-lite", "Gemini 2.0 Flash Lite"]
            ],
            "perplexity" => [
              ["sonar-pro", "Sonar Pro"],
              ["sonar", "Sonar"],
              ["sonar-reasoning-pro", "Sonar Reasoning Pro"],
              ["sonar-reasoning", "Sonar Reasoning"]
            ],
            "groq" => [
              ["llama-3.3-70b-versatile", "Llama 3.3 70B"],
              ["llama-3.1-70b-versatile", "Llama 3.1 70B"],
              ["llama-3.1-8b-instant", "Llama 3.1 8B"],
              ["mixtral-8x7b-32768", "Mixtral 8x7B"]
            ],
            "xai" => [
              ["grok-2-1212", "Grok 2"],
              ["grok-2-vision-1212", "Grok 2 Vision"],
              ["grok-beta", "Grok Beta"]
            ]
          }.freeze

          PROVIDERS = [
            ["openai", "OpenAI"],
            ["anthropic", "Anthropic"],
            ["google", "Google Gemini"],
            ["perplexity", "Perplexity"],
            ["groq", "Groq"],
            ["xai", "xAI (Grok)"]
          ].freeze

          # Model name to provider. Ordered, because `o1-` and `o3-` would
          # otherwise be caught by nothing and `grok` by the llama rule.
          PROVIDER_PATTERNS = [
            [/\Agpt-|\Ao\d-/, "openai"],
            [/\Aclaude/, "anthropic"],
            [/\Agemini/, "google"],
            [/\Asonar/, "perplexity"],
            [/\Agrok/, "xai"],
            [/\A(llama|mixtral|gemma)/, "groq"]
          ].freeze

          def initialize(span:, replay:)
            @span = span
            @replay = replay
            @settings = original_settings
            @messages = original_messages
          end

          def view_template
            div(class: "raaf-page") do
              errors if @replay.errors.any?

              form(action: tracing_span_replays_path(@span.span_id), method: "post",
                   data: { controller: "replay-form", turbo: "false",
                           replay_form_debug_value: ::Rails.env.development? }) do
                input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)

                div(class: "raaf-editor") do
                  div(class: "raaf-editor-main") do
                    model_card
                    sampling_card
                    prompt_card
                  end

                  aside(class: "raaf-editor-side") do
                    original_card
                    run_card
                  end
                end
              end

              # Where the create action's Turbo Stream lands, and where the
              # submit script writes while the request is in flight.
              div(id: "replay-status")
            end
          end

          private

          def errors
            render(Molecules::Alert.new(:error, title: error_title)) do
              ul(class: "raaf-alert-list") do
                @replay.errors.full_messages.each { |message| li { message } }
              end
            end
          end

          def error_title
            "#{pluralize(@replay.errors.count, 'problem')} stopped this replay starting"
          end

          # ── Model ─────────────────────────────────────────────────────────

          def model_card
            render(Organisms::Card.new(
                     title: "Model",
                     subtitle: "Where the same conversation is sent this time"
                   )) do
              div(class: "raaf-field-grid") do
                render(Molecules::Field.new(
                         label: "Provider", for_id: "provider",
                         hint: "Changing this reloads the models below."
                       )) do
                  select(id: "provider", name: "provider", class: select_class,
                         data: { replay_form_target: "provider",
                                 action: "change->replay-form#updateModelOptions" }) do
                    PROVIDERS.each do |value, label|
                      option(value: value, selected: value == detected_provider) { label }
                    end
                  end
                end

                render(Molecules::Field.new(
                         label: "Model", for_id: "model",
                         hint: model_hint
                       )) do
                  select(id: "model", name: "model", class: select_class,
                         data: { replay_form_target: "model" }) do
                    MODELS.fetch(detected_provider, []).each do |value, label|
                      option(value: value, selected: value == @settings[:model]) { label }
                    end
                  end
                end
              end
            end
          end

          def model_hint
            return "The original call recorded no model." if @settings[:model].blank?

            "The call ran on #{@settings[:model]}."
          end

          # ── Sampling ──────────────────────────────────────────────────────

          def sampling_card
            render(Organisms::Card.new(
                     title: "Sampling",
                     subtitle: "How the model is allowed to answer"
                   )) do
              slider("Temperature", name: "temperature", target: "temperature",
                                    value: @settings[:temperature] || 0.7, min: 0, max: 2, step: 0.1,
                                    hint: "Low is near-deterministic; high wanders. A single high-temperature " \
                                          "replay says little on its own.")

              render(Molecules::Field.new(
                       label: "Max tokens", for_id: "max_tokens",
                       hint: "The ceiling on the answer, not a target."
                     )) do
                input(type: "number", id: "max_tokens", name: "max_tokens",
                      value: @settings[:max_tokens] || 1024, min: 1, max: 128_000,
                      class: input_class(mono: true),
                      data: { replay_form_target: "maxTokens" })
              end

              slider("Top P", name: "top_p", target: "topP",
                              value: @settings[:top_p] || 1.0, min: 0, max: 1, step: 0.05,
                              hint: "Nucleus sampling. Leave at 1 when you are varying temperature.")

              slider("Frequency penalty", name: "frequency_penalty", target: "frequencyPenalty",
                                          value: @settings[:frequency_penalty] || 0, min: 0, max: 2, step: 0.1,
                                          hint: "Pushes down tokens the answer has already used.")

              slider("Presence penalty", name: "presence_penalty", target: "presencePenalty",
                                         value: @settings[:presence_penalty] || 0, min: 0, max: 2, step: 0.1,
                                         hint: "Pushes the answer towards subjects it has not raised yet.")
            end
          end

          # The value beside the label is what the slider reports, updated by
          # `replay-form#updateSliderValue` -- which finds it by id, so the id
          # is derived from the field name and not from the target.
          def slider(label, name:, target:, value:, min:, max:, step:, hint:)
            div(class: "raaf-field raaf-field--wide") do
              div(class: "raaf-slider-head") do
                render Atoms::Label.new(label, for_id: name)
                render Atoms::Mono.new(value.to_s, tone: :accent, id: "#{name}-value",
                                                   data: { replay_form_target: "#{target}Value" })
              end

              input(type: "range", id: name, name: name, class: "raaf-slider",
                    min: min, max: max, step: step, value: value,
                    data: { replay_form_target: target,
                            action: "input->replay-form#updateSliderValue" })

              p(class: "raaf-input-hint") { hint }
            end
          end

          # ── Prompt ────────────────────────────────────────────────────────

          def prompt_card
            render(Organisms::Card.new(
                     title: "Prompt",
                     subtitle: "What the model is asked, as it was recorded",
                     data: { controller: "prompt-editor" }
                   )) do |card|
              card.actions do
                render Atoms::Button.new(label: "Add message", icon: "plus-lg", size: :sm,
                                         variant: :secondary, type: "button",
                                         data: { action: "click->prompt-editor#addMessage" })
              end

              render(Molecules::Field.new(
                       label: "System prompt", for_id: "system_prompt", optional: true,
                       hint: "Blank keeps whatever the agent's instructions produce."
                     )) do
                textarea(id: "system_prompt", name: "system_prompt", rows: 8,
                         class: "#{input_class(mono: true)} raaf-textarea") { system_prompt.to_s }
              end

              messages_field
            end
          end

          def messages_field
            div(class: "raaf-field") do
              render Atoms::Label.new("Messages")

              div(id: "messages-container", class: "raaf-msgs",
                  data: { prompt_editor_target: "messages" }) do
                user_messages.each_with_index { |message, index| message_row(message, index) }
              end

              p(class: "raaf-input-hint#{' hidden' if user_messages.any?}",
                data: { prompt_editor_target: "empty" }) do
                "The original span recorded no user messages. Add one to give the model something " \
                  "to answer."
              end
            end
          end

          # The row's shape is duplicated in `prompt-editor#addMessage`, which
          # builds the same markup for a message added in the browser. Change
          # one and the other has to follow.
          def message_row(message, index)
            div(class: "raaf-msg", data: { message_index: index }) do
              div(class: "raaf-msg-head") do
                span(class: "raaf-msg-role") { message["role"].presence || "user" }

                button(type: "button", class: "raaf-msg-remove", "aria-label": "Remove message",
                       data: { action: "click->prompt-editor#removeMessage" }) do
                  i(class: "bi bi-x-lg")
                end
              end

              textarea(name: "user_messages[#{index}][content]", rows: 4,
                       class: "#{input_class(mono: true)} raaf-textarea") { message["content"].to_s }

              input(type: "hidden", name: "user_messages[#{index}][role]",
                    value: message["role"].presence || "user")
            end
          end

          # ── The rail ──────────────────────────────────────────────────────

          def original_card
            render(Organisms::Card.new(title: "The original call", flush: true)) do
              fact("Span", @span.display_name)
              fact("Model", @settings[:model].presence || "—")
              fact("Duration", format_duration(@span.duration_ms))
              fact("Status", @span.status.to_s)
              fact("Messages", user_messages.size.to_s)
            end
          end

          def fact(label, value)
            div(class: "raaf-editor-fact") do
              span(class: "raaf-editor-fact-label") { label }
              render Atoms::Mono.new(value)
            end
          end

          def run_card
            div(class: "raaf-editor-actions") do
              render(Molecules::Field.new(
                       label: "Note", for_id: "notes", optional: true,
                       hint: "What you are testing. It is how this attempt is told from the next."
                     )) do
                input(type: "text", id: "notes", name: "notes", class: input_class,
                      placeholder: "e.g. does Sonnet keep the JSON shape?")
              end

              button(type: "submit", class: "raaf-button",
                     data: { action: "click->replay-form#submit" }) do
                render Atoms::Icon.new("play-fill", size: :sm)
                plain "Run replay"
              end

              link_to("Back to the trace", trace_span_path(@span.span_id, @span.trace_id),
                      class: "raaf-editor-back")
            end
          end

          # ── What the span recorded ────────────────────────────────────────

          def original_settings
            attrs = @span.span_attributes || {}
            llm = attrs.dig("llm", "request") || {}

            {
              model: llm["model"] || attrs["llm.request.model"] || attrs["agent.model"] || attrs["model"],
              temperature: numeric(llm["temperature"] || attrs["agent.temperature"]),
              max_tokens: integer(llm["max_tokens"] || llm["max_output_tokens"] || attrs["agent.max_tokens"]),
              top_p: numeric(llm["top_p"] || attrs["agent.top_p"]),
              frequency_penalty: numeric(llm["frequency_penalty"] || attrs["agent.frequency_penalty"]),
              presence_penalty: numeric(llm["presence_penalty"] || attrs["agent.presence_penalty"])
            }.compact
          end

          # A span that recorded "N/A" for a setting it never sent would
          # otherwise put that string in a number field, which browsers drop
          # silently -- so anything that is not a number becomes nothing, and
          # the field falls back to its default.
          def numeric(value)
            return nil if value.nil?
            return value if value.is_a?(Numeric)

            Float(value)
          rescue ArgumentError, TypeError
            nil
          end

          def integer(value)
            return nil if value.nil?
            return value.to_i if value.is_a?(Numeric)

            Integer(value)
          rescue ArgumentError, TypeError
            nil
          end

          def original_messages
            attrs = @span.span_attributes || {}
            messages = attrs.dig("llm", "request", "messages") ||
                       attrs["llm.request.messages"] ||
                       attrs["agent.conversation_messages"] ||
                       []

            messages = parse_messages(messages) if messages.is_a?(String)

            Array(messages).select { |message| message.is_a?(Hash) }
          end

          def parse_messages(value)
            JSON.parse(value)
          rescue JSON::ParserError
            []
          end

          def system_prompt
            from_messages = @messages.find { |message| message["role"] == "system" }&.dig("content")
            return from_messages if from_messages.present?

            (@span.span_attributes || {})["agent.system_instructions"]
          end

          def user_messages
            @user_messages ||= @messages.reject { |message| message["role"] == "system" }
          end

          def detected_provider
            @detected_provider ||= begin
              model = @settings[:model].to_s
              PROVIDER_PATTERNS.find { |pattern, _| model.match?(pattern) }&.last || "openai"
            end
          end

          # ── Control classes ───────────────────────────────────────────────

          # The bare input classes are the light-theme ones; this console is
          # dark throughout, so every control carries the glass modifier.
          def input_class(mono: false)
            ["raaf-input", "raaf-input--glass", ("raaf-input--mono" if mono)].compact.join(" ")
          end

          def select_class
            "#{input_class(mono: true)} raaf-select"
          end
        end
      end
    end
  end
end
