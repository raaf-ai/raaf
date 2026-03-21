# frozen_string_literal: true

module RAAF
  module Rails
    module Eval
      class ExperimentList < RAAF::Rails::Tracing::BaseComponent
        def initialize(experiments:)
          @experiments = experiments
        end

        def view_template
          div(class: "p-6") do
            render_header
            render_experiments_table
          end
        end

        private

        def render_header
          div(class: "sm:flex sm:items-center sm:justify-between mb-6 pb-4 border-b border-gray-200") do
            div do
              h1(class: "text-2xl font-bold text-gray-900") { "Experiments" }
              p(class: "mt-1 text-sm text-gray-500") { "Run and compare agent configurations against datasets" }
            end
            div(class: "mt-4 sm:mt-0") do
              render_preline_button(text: "New Experiment", href: eval_experiments_path + "/new", variant: "primary", icon: "bi-plus-lg")
            end
          end
        end

        def render_experiments_table
          div(class: "bg-white shadow rounded-lg overflow-hidden") do
            if @experiments.any?
              div(class: "overflow-x-auto") do
                table(class: "min-w-full divide-y divide-gray-200") do
                  thead(class: "bg-gray-50") do
                    tr do
                      th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase") { "Name" }
                      th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase") { "Agent" }
                      th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase") { "Model" }
                      th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase") { "Progress" }
                      th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase") { "Status" }
                      th(class: "px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase") { "Actions" }
                    end
                  end
                  tbody(class: "bg-white divide-y divide-gray-200") do
                    @experiments.each { |exp| render_experiment_row(exp) }
                  end
                end
              end
            else
              render_empty_state
            end
          end
        end

        def render_experiment_row(exp)
          tr(class: "hover:bg-gray-50") do
            td(class: "px-4 py-3") do
              a(href: eval_experiment_path(exp), class: "text-blue-600 hover:text-blue-800 font-medium") { exp.name }
            end
            td(class: "px-4 py-3 text-sm text-gray-600") { exp.agent_name || "-" }
            td(class: "px-4 py-3 text-sm text-gray-600") { exp.model || "-" }
            td(class: "px-4 py-3 text-sm") do
              if exp.total_items > 0
                div(class: "flex items-center gap-2") do
                  div(class: "w-24 bg-gray-200 rounded-full h-2") do
                    div(class: "bg-blue-600 h-2 rounded-full", style: "width: #{exp.progress_percentage}%")
                  end
                  span(class: "text-xs text-gray-500") { "#{exp.progress_percentage}%" }
                end
              else
                span(class: "text-xs text-gray-400") { "Not started" }
              end
            end
            td(class: "px-4 py-3") { render_status_badge(exp.status) }
            td(class: "px-4 py-3 text-right") do
              render_preline_button(text: "View", href: eval_experiment_path(exp), variant: "secondary", size: "xs")
            end
          end
        end

        def render_empty_state
          div(class: "flex flex-col items-center justify-center py-12") do
            i(class: "bi bi-flask text-5xl text-gray-400")
            h3(class: "mt-4 text-lg font-medium text-gray-900") { "No experiments yet" }
            p(class: "mt-1 text-sm text-gray-500") { "Create an experiment to compare agent configurations." }
            div(class: "mt-4") do
              render_preline_button(text: "Create Experiment", href: eval_experiments_path + "/new", variant: "primary")
            end
          end
        end
      end
    end
  end
end
