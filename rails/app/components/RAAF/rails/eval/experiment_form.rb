# frozen_string_literal: true

module RAAF
  module Rails
    module Eval
      ##
      # A new experiment: what to run, over which cases, on which model.
      #
      # Follows the library the designed screens are built from — cards for
      # the sections, `Field` for every label and hint — rather than rendering
      # `bg-white` and `text-gray-900` into the dark shell.
      #
      class ExperimentForm < RAAF::Rails::Tracing::BaseComponent
        def initialize(experiment:, datasets: [])
          @experiment = experiment
          @datasets = datasets
        end

        def view_template
          div(class: "raaf-page") do
            header
            errors if @experiment.errors.any?

            if @datasets.blank?
              no_datasets
            else
              form_with(model: @experiment, url: eval_experiments_path, method: :post,
                        class: "raaf-page") do |f|
                basics(f)
                agent(f)
                actions(f)
              end
            end
          end
        end

        private

        def header
          render Organisms::RecordHead.new(
            parent: { label: "Experiments", href: eval_experiments_path },
            title: "New experiment",
            description: "An experiment runs one agent over every case in a dataset and " \
                         "scores what comes back. It is the most expensive thing the " \
                         "console starts, so the run reports its tokens and spend."
          )
        end

        def errors
          render(Molecules::Alert.new(:danger, title: error_title)) do
            ul(class: "raaf-alert-list") do
              @experiment.errors.full_messages.each { |message| li { message } }
            end
          end
        end

        def error_title
          "#{pluralize(@experiment.errors.count, 'problem')} stopped this experiment being saved"
        end

        # An experiment with no dataset has nothing to run over, so the form
        # says that rather than offering an empty select.
        def no_datasets
          render(Organisms::Card.new(title: "No datasets")) do
            render Atoms::Text.new(
              "An experiment runs over a dataset's cases. Create one first.",
              tone: :secondary
            )
            render Atoms::Button.new(label: "New dataset", icon: "plus-lg",
                                     href: new_eval_dataset_path)
          end
        end

        def basics(form)
          render(Organisms::Card.new(title: "Basics")) do
            render(Molecules::Field.new(label: "Name", for_id: "experiment_name")) do
              form.text_field(:name, class: "raaf-input raaf-input--glass", required: true,
                                     placeholder: "e.g. Support replies, stricter prompt")
            end

            render(Molecules::Field.new(label: "Dataset", for_id: "experiment_dataset_id",
                                        hint: "The cases this run is scored over.")) do
              form.collection_select(:dataset_id, @datasets, :id, :name,
                                     { prompt: "Select a dataset" },
                                     { class: "raaf-input raaf-input--glass raaf-select" })
            end

            render(Molecules::Field.new(label: "Description", for_id: "experiment_description",
                                        optional: true,
                                        hint: "What this run is testing, in one line.")) do
              form.text_area(:description, class: "raaf-input raaf-input--glass raaf-textarea", rows: 2)
            end
          end
        end

        def agent(form)
          render(Organisms::Card.new(title: "What to run")) do
            div(class: "raaf-field-grid") do
              render(Molecules::Field.new(label: "Agent", for_id: "experiment_agent_name")) do
                form.text_field(:agent_name, class: "raaf-input raaf-input--glass",
                                             placeholder: "e.g. SupportAgent")
              end

              render(Molecules::Field.new(label: "Model", for_id: "experiment_model",
                                          hint: "Also what the run's spend is priced against.")) do
                form.text_field(:model, class: "raaf-input raaf-input--glass",
                                        placeholder: "e.g. gpt-4o")
              end
            end

            render(Molecules::Field.new(label: "Provider", for_id: "experiment_provider",
                                        optional: true,
                                        hint: "Left blank, the model name decides.")) do
              form.text_field(:provider, class: "raaf-input raaf-input--glass",
                                         placeholder: "e.g. openai, anthropic")
            end
          end
        end

        def actions(form)
          div(class: "raaf-cluster") do
            form.submit("Create experiment", class: "raaf-button")
            render Atoms::Button.new(label: "Cancel", variant: :secondary,
                                     href: eval_experiments_path)
          end
        end
      end
    end
  end
end
