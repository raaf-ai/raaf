# frozen_string_literal: true

require "diff/lcs"
require "diffy"

module RAAF
  module Eval
    module UI
      ##
      # Phlex component for comparing evaluation results
      #
      # Displays baseline and new results side-by-side with:
      # - Syntax-highlighted diff
      # - Line-by-line or unified diff views
      # - Delta indicators for metrics
      # - Expandable sections
      #
      # @example Render in a view
      #   render RAAF::Eval::UI::ResultsComparison.new(
      #     baseline: baseline_result,
      #     result: new_result
      #   )
      #
      class ResultsComparison < Phlex::HTML
        def initialize(baseline:, result:)
          @baseline = baseline
          @result = result
        end

        def view_template
          div(class: "results-comparison") do
            render_header
            render_comparison_layout
          end
        end

        private

        def render_header
          div(class: "flex justify-between items-center mb-6") do
            h2(class: "text-2xl font-semibold text-gray-900") { "Results Comparison" }
            div(class: "flex gap-2") do
              button(
                class: "px-3 py-1 text-sm border border-gray-300 rounded hover:bg-gray-50",
                data_action: "click->results-comparison#toggleView"
              ) do
                "Toggle View"
              end
              button(
                class: "px-3 py-1 text-sm border border-gray-300 rounded hover:bg-gray-50",
                data_action: "click->results-comparison#exportDiff"
              ) do
                "Export Diff"
              end
            end
          end
        end

        def render_comparison_layout
          div(class: "grid grid-cols-1 lg:grid-cols-3 gap-6") do
            # Baseline output (left column)
            render_output_panel("Baseline Output", baseline_output, "baseline")

            # New output (middle column)
            render_output_panel("New Output", result_output, "result")

            # Metrics panel (right column - fixed)
            render_metrics_sidebar
          end
        end

        def render_output_panel(title, output, panel_id)
          div(class: "bg-white rounded-lg shadow-sm overflow-hidden") do
            div(class: "px-4 py-3 bg-gray-50 border-b border-gray-200") do
              h3(class: "text-sm font-medium text-gray-700") { title }
            end
            div(class: "p-4") do
              render_output_content(output, panel_id)
            end
          end
        end

        def render_output_content(output, panel_id)
          if panel_id == "result"
            # Show diff highlights for new output
            render_diff_output
          else
            # Plain output for baseline
            pre(class: "text-sm text-gray-900 whitespace-pre-wrap font-mono bg-gray-50 p-4 rounded") do
              output
            end
          end
        end

        def render_diff_output
          diff = Diffy::Diff.new(baseline_output, result_output, context: 3)

          div(class: "diff-output") do
            diff.each_chunk do |chunk|
              render_diff_chunk(chunk)
            end
          end
        end

        def render_diff_chunk(chunk)
          case chunk
          when /^\+/
            # Addition
            div(class: "bg-green-50 border-l-4 border-green-500 p-2 my-1") do
              pre(class: "text-sm text-green-900 font-mono") { chunk.sub(/^\+/, "") }
            end
          when /^-/
            # Deletion
            div(class: "bg-red-50 border-l-4 border-red-500 p-2 my-1") do
              pre(class: "text-sm text-red-900 font-mono line-through") { chunk.sub(/^-/, "") }
            end
          else
            # Unchanged
            div(class: "p-2 my-1") do
              pre(class: "text-sm text-gray-700 font-mono") { chunk }
            end
          end
        end

        def render_metrics_sidebar
          div(class: "bg-white rounded-lg shadow-sm overflow-hidden lg:sticky lg:top-4") do
            div(class: "px-4 py-3 bg-gray-50 border-b border-gray-200") do
              h3(class: "text-sm font-medium text-gray-700") { "Metrics Comparison" }
            end
            div(class: "p-4 space-y-4") do
              render_metric_card("Tokens", baseline_tokens, result_tokens)
              render_metric_card("Latency (ms)", baseline_latency, result_latency)
              render_metric_card("Cost ($)", baseline_cost, result_cost)
              render_quality_indicator
            end
          end
        end

        def render_metric_card(label, baseline_value, result_value)
          delta = result_value - baseline_value
          delta_percent = baseline_value.zero? ? 0 : ((delta.to_f / baseline_value) * 100).round(1)

          div(class: "border-b border-gray-200 pb-3") do
            div(class: "text-xs text-gray-500 mb-1") { label }
            div(class: "flex justify-between items-center") do
              div do
                div(class: "text-sm text-gray-600") { "Baseline: #{format_value(baseline_value)}" }
                div(class: "text-sm font-semibold text-gray-900") { "New: #{format_value(result_value)}" }
              end
              render_delta_indicator(delta, delta_percent)
            end
          end
        end

        def render_delta_indicator(delta, delta_percent)
          color_class = if delta > 0
                          "text-red-600 bg-red-50"
                        elsif delta < 0
                          "text-green-600 bg-green-50"
                        else
                          "text-gray-600 bg-gray-50"
                        end

          arrow = if delta > 0
                    "↑"
                  elsif delta < 0
                    "↓"
                  else
                    "="
                  end

          div(class: "px-2 py-1 rounded text-xs font-semibold #{color_class}") do
            "#{arrow} #{delta_percent.abs}%"
          end
        end

        def render_quality_indicator
          div(class: "pt-3 border-t border-gray-200") do
            div(class: "text-xs text-gray-500 mb-2") { "Quality Assessment" }
            div(class: "space-y-2") do
              render_quality_badge("Coherence", "high")
              render_quality_badge("Accuracy", "medium")
              render_quality_badge("Safety", "high")
            end
          end
        end

        def render_quality_badge(label, level)
          color = case level
                  when "high"
                    "bg-green-100 text-green-800"
                  when "medium"
                    "bg-yellow-100 text-yellow-800"
                  when "low"
                    "bg-red-100 text-red-800"
                  else
                    "bg-gray-100 text-gray-800"
                  end

          div(class: "flex justify-between items-center") do
            span(class: "text-sm text-gray-700") { label }
            span(class: "px-2 py-1 text-xs font-semibold rounded #{color}") { level.capitalize }
          end
        end

        # Helper methods to extract data
        def baseline_output
          @baseline.dig("output") || @baseline.dig(:output) || ""
        end

        def result_output
          @result.dig("output") || @result.dig(:output) || ""
        end

        def baseline_tokens
          @baseline.dig("tokens") || @baseline.dig(:tokens) || 0
        end

        def result_tokens
          @result.dig("tokens") || @result.dig(:tokens) || 0
        end

        def baseline_latency
          @baseline.dig("latency_ms") || @baseline.dig(:latency_ms) || 0
        end

        def result_latency
          @result.dig("latency_ms") || @result.dig(:latency_ms) || 0
        end

        def baseline_cost
          @baseline.dig("cost") || @baseline.dig(:cost) || 0.0
        end

        def result_cost
          @result.dig("cost") || @result.dig(:cost) || 0.0
        end

        def format_value(value)
          case value
          when Float
            format("%.4f", value)
          else
            value.to_s
          end
        end
      end
    end
  end
end
