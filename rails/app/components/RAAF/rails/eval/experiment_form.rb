# frozen_string_literal: true

module RAAF
  module Rails
    module Eval
      class ExperimentForm < RAAF::Rails::Tracing::BaseComponent
        def initialize(experiment:, datasets: [])
          @experiment = experiment
          @datasets = datasets
        end

        def view_template
          div(class: "p-6 max-w-2xl") do
            h1(class: "text-2xl font-bold text-gray-900 mb-6") { "New Experiment" }
            form_with(model: @experiment, url: eval_experiments_path, method: :post) do |f|
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
              f.label :dataset_id, "Dataset", class: "block text-sm font-medium text-gray-700"
              f.collection_select :dataset_id, @datasets, :id, :name, { prompt: "Select a dataset" },
                                 class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
            end
            div(class: "grid grid-cols-2 gap-4") do
              div do
                f.label :agent_name, class: "block text-sm font-medium text-gray-700"
                f.text_field :agent_name, class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm sm:text-sm"
              end
              div do
                f.label :model, class: "block text-sm font-medium text-gray-700"
                f.text_field :model, class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm sm:text-sm", placeholder: "e.g. gpt-4o"
              end
            end
            div do
              f.label :provider, class: "block text-sm font-medium text-gray-700"
              f.text_field :provider, class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm sm:text-sm", placeholder: "e.g. openai, anthropic"
            end
            div do
              f.label :description, class: "block text-sm font-medium text-gray-700"
              f.text_area :description, rows: 2, class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm sm:text-sm"
            end
            div(class: "flex gap-3 pt-4") do
              f.submit("Create Experiment", class: "px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 font-medium text-sm cursor-pointer")
              render_preline_button(text: "Cancel", href: eval_experiments_path, variant: "secondary")
            end
          end
        end
      end
    end
  end
end
