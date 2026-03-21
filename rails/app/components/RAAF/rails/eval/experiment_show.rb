# frozen_string_literal: true

module RAAF
  module Rails
    module Eval
      class ExperimentShow < RAAF::Rails::Tracing::BaseComponent
        def initialize(experiment:, results:)
          @experiment = experiment
          @results = results
        end

        def view_template
          div(class: "p-6") do
            render_header
            render_metrics
            render_aggregate_scores
            render_results_table
          end
        end

        private

        def render_header
          div(class: "sm:flex sm:items-center sm:justify-between mb-6 pb-4 border-b border-gray-200") do
            div do
              h1(class: "text-2xl font-bold text-gray-900") { @experiment.name }
              div(class: "mt-2 flex items-center gap-4 text-sm text-gray-500") do
                span { "Agent: #{@experiment.agent_name}" } if @experiment.agent_name
                span { "Model: #{@experiment.model}" } if @experiment.model
                span { "Provider: #{@experiment.provider}" } if @experiment.provider
              end
            end
            div(class: "mt-4 sm:mt-0 flex gap-2") do
              if @experiment.status == "pending"
                render_preline_button(text: "Run", href: eval_experiment_path(@experiment) + "/run", variant: "success", icon: "bi-play-fill")
              end
              if @experiment.in_progress?
                render_preline_button(text: "Cancel", href: eval_experiment_path(@experiment) + "/cancel", variant: "danger", icon: "bi-stop-fill")
              end
              render_status_badge(@experiment.status)
            end
          end
        end

        def render_metrics
          div(class: "grid grid-cols-1 md:grid-cols-4 gap-4 mb-6") do
            render_metric_card(title: "Progress", value: "#{@experiment.progress_percentage}%", color: "blue", icon: "bi-bar-chart")
            render_metric_card(title: "Completed", value: @experiment.completed_items, color: "green", icon: "bi-check-circle")
            render_metric_card(title: "Failed", value: @experiment.failed_items, color: "red", icon: "bi-x-circle")
            duration_text = @experiment.duration ? format_duration(@experiment.duration * 1000) : "N/A"
            render_metric_card(title: "Duration", value: duration_text, color: "purple", icon: "bi-clock")
          end
        end

        def render_aggregate_scores
          agg = @experiment.aggregate_metrics
          return unless agg.is_a?(Hash) && agg["scores"].present?

          div(class: "mb-6") do
            h2(class: "text-lg font-semibold text-gray-900 mb-3") { "Aggregate Scores" }
            div(class: "grid grid-cols-2 md:grid-cols-4 gap-4") do
              agg["scores"].each do |name, stats|
                next unless stats.is_a?(Hash)
                render_metric_card(title: name.to_s.titleize, value: stats["avg"]&.round(3).to_s, color: "blue")
              end
            end
          end
        end

        def render_results_table
          h2(class: "text-lg font-semibold text-gray-900 mb-3") { "Results" }
          div(class: "bg-white shadow rounded-lg overflow-hidden") do
            if @results.any?
              table(class: "min-w-full divide-y divide-gray-200") do
                thead(class: "bg-gray-50") do
                  tr do
                    th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase") { "Item" }
                    th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase") { "Status" }
                    th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase") { "Score" }
                    th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase") { "Output (preview)" }
                  end
                end
                tbody(class: "bg-white divide-y divide-gray-200") do
                  @results.each { |result| render_result_row(result) }
                end
              end
            else
              div(class: "p-8 text-center text-gray-500") { "No results yet. Run the experiment to see results." }
            end
          end
        end

        def render_result_row(result)
          tr(class: "hover:bg-gray-50") do
            td(class: "px-4 py-3 text-sm text-gray-600") { "##{result.dataset_item_id}" }
            td(class: "px-4 py-3") { render_status_badge(result.status) }
            td(class: "px-4 py-3 text-sm font-medium") do
              score = result.overall_score
              if score
                color = score >= 0.7 ? "text-green-600" : score >= 0.4 ? "text-yellow-600" : "text-red-600"
                span(class: color) { score.round(3).to_s }
              else
                span(class: "text-gray-400") { "-" }
              end
            end
            td(class: "px-4 py-3 text-sm text-gray-600 font-mono") do
              result.output.is_a?(Hash) ? result.output.to_json.truncate(80) : result.output.to_s.truncate(80)
            end
          end
        end
      end
    end
  end
end
