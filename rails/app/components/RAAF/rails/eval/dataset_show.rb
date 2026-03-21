# frozen_string_literal: true

module RAAF
  module Rails
    module Eval
      class DatasetShow < RAAF::Rails::Tracing::BaseComponent
        def initialize(dataset:, items:, experiments:)
          @dataset = dataset
          @items = items
          @experiments = experiments
        end

        def view_template
          div(class: "p-6") do
            render_header
            render_metrics
            render_items_table
            render_experiments_section
          end
        end

        private

        def render_header
          div(class: "sm:flex sm:items-center sm:justify-between mb-6 pb-4 border-b border-gray-200") do
            div do
              h1(class: "text-2xl font-bold text-gray-900") { @dataset.name }
              p(class: "mt-1 text-sm text-gray-500") { @dataset.description } if @dataset.description.present?
              div(class: "mt-2 flex items-center gap-3") do
                span(class: "text-xs text-gray-500") { "Version #{@dataset.version}" }
                badge_class = @dataset.status == "active" ? "bg-green-100 text-green-800" : "bg-gray-100 text-gray-800"
                span(class: "px-2 py-0.5 rounded-full text-xs font-medium #{badge_class}") { @dataset.status }
              end
            end
            div(class: "mt-4 sm:mt-0 flex gap-2") do
              render_preline_button(text: "New Version", href: eval_dataset_path(@dataset) + "/new_version", variant: "secondary", icon: "bi-copy")
              render_preline_button(text: "Archive", href: eval_dataset_path(@dataset) + "/archive", variant: "danger", icon: "bi-archive")
            end
          end
        end

        def render_metrics
          div(class: "grid grid-cols-1 md:grid-cols-3 gap-4 mb-6") do
            render_metric_card(title: "Total Items", value: @dataset.items_count, color: "blue", icon: "bi-list-check")
            render_metric_card(title: "Experiments Run", value: @experiments.size, color: "purple", icon: "bi-flask")
            render_metric_card(title: "Version", value: "v#{@dataset.version}", color: "green", icon: "bi-tag")
          end
        end

        def render_items_table
          div(class: "mb-6") do
            h2(class: "text-lg font-semibold text-gray-900 mb-3") { "Dataset Items" }
            div(class: "bg-white shadow rounded-lg overflow-hidden") do
              if @items.any?
                table(class: "min-w-full divide-y divide-gray-200") do
                  thead(class: "bg-gray-50") do
                    tr do
                      th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase") { "ID" }
                      th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase") { "Input (preview)" }
                      th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase") { "Expected Output" }
                      th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase") { "Source" }
                    end
                  end
                  tbody(class: "bg-white divide-y divide-gray-200") do
                    @items.each { |item| render_item_row(item) }
                  end
                end
              else
                div(class: "p-8 text-center text-gray-500") { "No items in this dataset yet." }
              end
            end
          end
        end

        def render_item_row(item)
          tr(class: "hover:bg-gray-50") do
            td(class: "px-4 py-3 text-sm text-gray-600") { "##{item.id}" }
            td(class: "px-4 py-3 text-sm text-gray-800 font-mono") { item.input.to_json.truncate(80) }
            td(class: "px-4 py-3 text-sm text-gray-600 font-mono") { item.has_expected_output? ? item.expected_output.to_json.truncate(60) : "-" }
            td(class: "px-4 py-3 text-sm") do
              if item.from_production?
                span(class: "px-2 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-800") { "Span" }
              else
                span(class: "px-2 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-800") { "Manual" }
              end
            end
          end
        end

        def render_experiments_section
          h2(class: "text-lg font-semibold text-gray-900 mb-3") { "Recent Experiments" }
          div(class: "bg-white shadow rounded-lg overflow-hidden") do
            if @experiments.any?
              @experiments.each do |exp|
                div(class: "px-4 py-3 border-b border-gray-100 flex justify-between items-center hover:bg-gray-50") do
                  div do
                    a(href: eval_experiment_path(exp), class: "text-blue-600 hover:text-blue-800 font-medium") { exp.name }
                    span(class: "ml-2 text-xs text-gray-500") { exp.model }
                  end
                  render_status_badge(exp.status)
                end
              end
            else
              div(class: "p-8 text-center text-gray-500") { "No experiments run against this dataset yet." }
            end
          end
        end
      end
    end
  end
end
