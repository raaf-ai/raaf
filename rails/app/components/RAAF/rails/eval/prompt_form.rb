# frozen_string_literal: true

module RAAF
  module Rails
    module Eval
      ##
      # A prompt's own record — its name, the agent it belongs to, and on
      # creation an optional first version.
      #
      # No form screen exists in any canvas, so this follows the library the
      # designed screens are built from: cards for the sections, `Field` for
      # every label and hint, and the shared input classes. It used to render
      # `bg-white` and `text-gray-900` into the dark shell.
      #
      class PromptForm < RAAF::Rails::Tracing::BaseComponent
        def initialize(prompt:)
          @prompt = prompt
        end

        def view_template
          div(class: "raaf-page") do
            header
            errors if @prompt.errors.any?

            form_with(model: @prompt, url: form_url, method: form_method, class: "raaf-page") do |f|
              basics(f)
              initial_version if @prompt.new_record?
              actions(f)
            end
          end
        end

        private

        def header
          render Organisms::RecordHead.new(
            parent: { label: "Prompts", href: eval_prompts_path },
            title: @prompt.new_record? ? "New prompt" : "Edit #{@prompt.name}",
            description: "A prompt is a named piece of wording with a version history. " \
                         "Agents run whichever version is published."
          )
        end

        def errors
          render(Molecules::Alert.new(:error, title: error_title)) do
            ul(class: "raaf-alert-list") do
              @prompt.errors.full_messages.each { |message| li { message } }
            end
          end
        end

        def error_title
          "#{pluralize(@prompt.errors.count, 'problem')} stopped this prompt being saved"
        end

        def basics(form)
          render(Organisms::Card.new(title: "Basics")) do
            render(Molecules::Field.new(label: "Name", for_id: "prompt_name")) do
              form.text_field(:name, class: "raaf-input raaf-input--glass", required: true,
                                     placeholder: "e.g. customer_support_prompt")
            end

            render(Molecules::Field.new(label: "Agent", for_id: "prompt_agent_name", optional: true,
                                        hint: "The agent that runs this wording.")) do
              form.text_field(:agent_name, class: "raaf-input raaf-input--glass",
                                           placeholder: "e.g. CustomerSupportAgent")
            end

            render(Molecules::Field.new(label: "Description", for_id: "prompt_description",
                                        optional: true,
                                        hint: "What this prompt is for, in one line.")) do
              form.text_area(:description, class: "raaf-input raaf-input--glass raaf-textarea", rows: 2)
            end
          end
        end

        # Only on creation: a prompt with no version has nothing to run, and
        # offering the first one here saves a second form immediately after.
        def initial_version
          render(Organisms::Card.new(title: "First version",
                                     subtitle: "Optional — a prompt can be created empty " \
                                               "and given its wording later")) do
            render(Molecules::Field.new(label: "Prompt content", for_id: "prompt_initial_content",
                                        optional: true)) do
              textarea(name: "prompt[initial_content]", id: "prompt_initial_content", rows: 10,
                       class: "raaf-input raaf-input--glass raaf-textarea raaf-mono",
                       placeholder: "You are a helpful assistant…")
            end

            render(Molecules::Field.new(label: "Model", for_id: "prompt_initial_model",
                                        optional: true)) do
              input(type: "text", name: "prompt[initial_model]", id: "prompt_initial_model",
                    class: "raaf-input raaf-input--glass", placeholder: "e.g. gpt-4o")
            end
          end
        end

        def actions(form)
          div(class: "raaf-cluster") do
            form.submit(@prompt.new_record? ? "Create prompt" : "Save prompt",
                        class: "raaf-button")
            render Atoms::Button.new(label: "Cancel", variant: :secondary, href: cancel_path)
          end
        end

        def cancel_path
          @prompt.new_record? ? eval_prompts_path : eval_prompt_path(@prompt)
        end

        def form_url
          @prompt.new_record? ? eval_prompts_path : eval_prompt_path(@prompt)
        end

        def form_method
          @prompt.new_record? ? :post : :patch
        end
      end
    end
  end
end
