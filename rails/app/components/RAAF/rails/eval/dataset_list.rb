# frozen_string_literal: true

module RAAF
  module Rails
    module Eval
      class DatasetList < RAAF::Rails::Tracing::BaseComponent
        def initialize(datasets:)
          @datasets = datasets
        end

        def view_template
          div(class: "p-6") do
            render_header
            render_datasets_table
          end
        end

        private

        def render_header
          div(class: "sm:flex sm:items-center sm:justify-between mb-6 pb-4 border-b border-gray-200") do
            div do
              h1(class: "text-2xl font-bold text-gray-900") { "Datasets" }
              p(class: "mt-1 text-sm text-gray-500") { "Manage evaluation datasets for systematic agent testing" }
            end
            div(class: "mt-4 sm:mt-0") do
              render_preline_button(text: "New Dataset", href: eval_datasets_path + "/new", variant: "primary", icon: "bi-plus-lg")
            end
          end
        end

        def render_datasets_table
          div(class: "bg-white shadow rounded-lg overflow-hidden") do
            if @datasets.any?
              div(class: "overflow-x-auto") do
                table(class: "min-w-full divide-y divide-gray-200") do
                  thead(class: "bg-gray-50") do
                    tr do
                      th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase") { "Name" }
                      th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase") { "Version" }
                      th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase") { "Items" }
                      th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase") { "Status" }
                      th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase") { "Created" }
                      th(class: "px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase") { "Actions" }
                    end
                  end
                  tbody(class: "bg-white divide-y divide-gray-200") do
                    @datasets.each { |dataset| render_dataset_row(dataset) }
                  end
                end
              end
            else
              render_empty_state
            end
          end
        end

        def render_dataset_row(dataset)
          tr(class: "hover:bg-gray-50") do
            td(class: "px-4 py-3") do
              a(href: eval_dataset_path(dataset), class: "text-blue-600 hover:text-blue-800 font-medium") { dataset.name }
              if dataset.description.present?
                p(class: "text-xs text-gray-500 mt-1") { dataset.description.truncate(60) }
              end
            end
            td(class: "px-4 py-3 text-sm text-gray-600") { "v#{dataset.version}" }
            td(class: "px-4 py-3 text-sm text-gray-600") { dataset.items_count.to_s }
            td(class: "px-4 py-3") do
              badge_class = dataset.status == "active" ? "bg-green-100 text-green-800" : "bg-gray-100 text-gray-800"
              span(class: "px-2 py-1 rounded-full text-xs font-medium #{badge_class}") { dataset.status }
            end
            td(class: "px-4 py-3 text-sm text-gray-500") { dataset.created_at&.strftime("%Y-%m-%d") }
            td(class: "px-4 py-3 text-right") do
              render_preline_button(text: "View", href: eval_dataset_path(dataset), variant: "secondary", size: "xs")
            end
          end
        end

        def render_empty_state
          div(class: "flex flex-col items-center justify-center py-12") do
            i(class: "bi bi-database text-5xl text-gray-400")
            h3(class: "mt-4 text-lg font-medium text-gray-900") { "No datasets yet" }
            p(class: "mt-1 text-sm text-gray-500") { "Create your first dataset to start systematic agent evaluation." }
            div(class: "mt-4") do
              render_preline_button(text: "Create Dataset", href: eval_datasets_path + "/new", variant: "primary")
            end
          end
        end
      end
    end
  end
end
