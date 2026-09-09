# frozen_string_literal: true

module RAAF
  module Rails
    module Eval
      ##
      # A new version of a prompt.
      #
      # The prompt screen's "New Version" control had nothing behind it and
      # linked back to the screen it was on. This is what it links to.
      #
      # The draft opens seeded from the version in force, because a new
      # version is nearly always an edit of the one running rather than a
      # blank page, and a diff against an empty predecessor tells nobody
      # anything.
      #
      class PromptVersionForm < RAAF::Rails::Tracing::BaseComponent
        # @param seed [PromptVersion, nil] the version to copy into the draft
        def initialize(prompt:, seed: nil)
          @prompt = prompt
          @seed = seed
        end

        def view_template
          div(class: "raaf-page") do
            header
            form(action: versions_path, method: "post", class: "raaf-page") do
              input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
              content_card
              actions
            end
          end
        end

        private

        def header
          render Organisms::RecordHead.new(
            parent: { label: @prompt.name, href: eval_prompt_path(@prompt) },
            title: "New version",
            mono: false,
            description: seeded_description,
            meta: @prompt.agent_name.presence && "agent #{@prompt.agent_name}"
          )
        end

        def seeded_description
          return "This prompt has no versions yet, so the draft starts empty." unless @seed

          "Seeded from v#{@seed.version_number}. Saving creates a new draft; " \
            "publishing it is a separate step."
        end

        def content_card
          render(Organisms::Card.new(title: "Version")) do
            render(Molecules::Field.new(label: "Prompt content", for_id: "version_content")) do
              textarea(name: "version[content]", id: "version_content", rows: 18,
                       class: "raaf-input raaf-input--glass raaf-textarea raaf-mono",
                       required: true) { @seed&.content }
            end

            div(class: "raaf-field-grid") do
              render(Molecules::Field.new(label: "Model", for_id: "version_model", optional: true,
                                          hint: "The model this wording was written for.")) do
                input(type: "text", name: "version[model]", id: "version_model",
                      value: @seed&.model, class: "raaf-input raaf-input--glass",
                      placeholder: "e.g. gpt-4o")
              end

              render(Molecules::Field.new(label: "What changed", for_id: "version_commit_message",
                                          optional: true,
                                          hint: "Read on the version history and beside the diff.")) do
                input(type: "text", name: "version[commit_message]", id: "version_commit_message",
                      class: "raaf-input raaf-input--glass",
                      placeholder: "e.g. Ask for the source before the verdict")
              end
            end
          end
        end

        def actions
          div(class: "raaf-cluster") do
            render Atoms::Button.new(label: "Create version", icon: "plus-lg", type: "submit")
            render Atoms::Button.new(label: "Cancel", variant: :secondary,
                                     href: eval_prompt_path(@prompt))
          end
        end

        def versions_path
          "#{eval_prompt_path(@prompt)}/versions"
        end
      end
    end
  end
end
