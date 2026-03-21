# frozen_string_literal: true

module RAAF
  module Rails
    module Eval
      class DatasetForm < RAAF::Rails::Tracing::BaseComponent
        def initialize(dataset:)
          @dataset = dataset
        end

        def view_template
          div(class: "p-6 max-w-2xl") do
            h1(class: "text-2xl font-bold text-gray-900 mb-6") { @dataset.new_record? ? "New Dataset" : "Edit Dataset" }
            form_with(model: @dataset, url: @dataset.new_record? ? eval_datasets_path : eval_dataset_path(@dataset), method: @dataset.new_record? ? :post : :patch) do |f|
              render_form_fields(f)
            end
          end
        end

        private

        def render_form_fields(f)
          div(class: "space-y-4") do
            div do
              f.label :name, class: "block text-sm font-medium text-gray-700"
              f.text_field :name, class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm", required: true
            end
            div do
              f.label :description, class: "block text-sm font-medium text-gray-700"
              f.text_area :description, rows: 3, class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
            end
            div(class: "flex gap-3 pt-4") do
              f.submit(@dataset.new_record? ? "Create Dataset" : "Update Dataset", class: "px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 font-medium text-sm cursor-pointer")
              render_preline_button(text: "Cancel", href: eval_datasets_path, variant: "secondary")
            end
          end
        end
      end
    end
  end
end
