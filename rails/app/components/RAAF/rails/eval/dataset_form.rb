# frozen_string_literal: true

module RAAF
  module Rails
    module Eval
      ##
      # A dataset's own record.
      #
      # Follows the library the designed screens are built from — cards for
      # the sections, `Field` for every label and hint — rather than rendering
      # `bg-white` and `text-gray-900` into the dark shell.
      #
      class DatasetForm < RAAF::Rails::Tracing::BaseComponent
        def initialize(dataset:)
          @dataset = dataset
        end

        def view_template
          div(class: "raaf-page") do
            header
            errors if @dataset.errors.any?

            form_with(model: @dataset, url: form_url, method: form_method, class: "raaf-page") do |f|
              basics(f)
              actions(f)
            end
          end
        end

        private

        def header
          render Organisms::RecordHead.new(
            parent: { label: "Datasets", href: eval_datasets_path },
            title: @dataset.new_record? ? "New dataset" : "Edit #{@dataset.name}",
            description: "A dataset is the set of cases an experiment runs against. " \
                         "Items are added afterwards, by hand or imported from a span."
          )
        end

        def errors
          render(Molecules::Alert.new(:error, title: error_title)) do
            ul(class: "raaf-alert-list") do
              @dataset.errors.full_messages.each { |message| li { message } }
            end
          end
        end

        def error_title
          "#{pluralize(@dataset.errors.count, 'problem')} stopped this dataset being saved"
        end

        def basics(form)
          render(Organisms::Card.new(title: "Basics")) do
            render(Molecules::Field.new(label: "Name", for_id: "dataset_name")) do
              form.text_field(:name, class: "raaf-input raaf-input--glass", required: true,
                                     placeholder: "e.g. Support replies, September")
            end

            render(Molecules::Field.new(label: "Description", for_id: "dataset_description",
                                        optional: true,
                                        hint: "What these cases have in common.")) do
              form.text_area(:description, class: "raaf-input raaf-input--glass raaf-textarea", rows: 3)
            end
          end
        end

        def actions(form)
          div(class: "raaf-cluster") do
            form.submit(@dataset.new_record? ? "Create dataset" : "Save dataset",
                        class: "raaf-button")
            render Atoms::Button.new(label: "Cancel", variant: :secondary, href: cancel_path)
          end
        end

        def cancel_path
          @dataset.new_record? ? eval_datasets_path : eval_dataset_path(@dataset)
        end

        def form_url
          @dataset.new_record? ? eval_datasets_path : eval_dataset_path(@dataset)
        end

        def form_method
          @dataset.new_record? ? :post : :patch
        end
      end
    end
  end
end
