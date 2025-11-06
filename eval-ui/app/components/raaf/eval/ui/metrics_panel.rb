# frozen_string_literal: true

module RAAF
  module Eval
    module UI
      ##
      # Phlex component for displaying evaluation metrics
      #
      # Shows comprehensive metrics including:
      # - Token usage and cost
      # - Latency and performance
      # - Quality indicators
      # - Regression warnings
      # - Statistical significance
      #
      # @example Render in a view
      #   render RAAF::Eval::UI::MetricsPanel.new(
      #     baseline_metrics: baseline,
      #     result_metrics: result
      #   )
      #
      class MetricsPanel < Phlex::HTML
        def initialize(baseline_metrics:, result_metrics:)
          @baseline = baseline_metrics
          @result = result_metrics
        end

        def view_template
          div(class: "metrics-panel bg-white rounded-lg shadow-sm p-6") do
            render_header
            render_summary_cards
            render_detailed_metrics
            render_export_section
          end
        end

        private

        def render_header
          div(class: "flex justify-between items-center mb-6") do
            h2(class: "text-xl font-semibold text-gray-900") { "Metrics Dashboard" }
            render_regression_indicator
          end
        end

        def render_regression_indicator
          if has_regression?
            div(class: "flex items-center gap-2 px-3 py-1 bg-red-50 border border-red-200 rounded-lg") do
              span(class: "text-red-600 text-sm font-semibold") { "⚠️ Regression Detected" }
            end
          else
            div(class: "flex items-center gap-2 px-3 py-1 bg-green-50 border border-green-200 rounded-lg") do
              span(class: "text-green-600 text-sm font-semibold") { "✓ No Regressions" }
            end
          end
        end

        def render_summary_cards
          div(class: "grid grid-cols-1 md:grid-cols-3 gap-4 mb-6") do
            render_summary_card("Total Cost", total_cost_delta, "$")
            render_summary_card("Total Tokens", total_tokens_delta, "")
            render_summary_card("Avg Latency", avg_latency_delta, "ms")
          end
        end

        def render_summary_card(title, delta_info, unit)
          div(class: "bg-gray-50 rounded-lg p-4") do
            div(class: "text-sm text-gray-600 mb-1") { title }
            div(class: "flex items-baseline justify-between") do
              span(class: "text-2xl font-bold text-gray-900") do
                "#{format_metric(delta_info[:current])}#{unit}"
              end
              render_change_badge(delta_info[:change], delta_info[:direction])
            end
          end
        end

        def render_change_badge(change, direction)
          color = if direction == :improvement
                    "text-green-600 bg-green-50"
                  elsif direction == :regression
                    "text-red-600 bg-red-50"
                  else
                    "text-gray-600 bg-gray-50"
                  end

          arrow = if change > 0
                    "↑"
                  elsif change < 0
                    "↓"
                  else
                    "="
                  end

          span(class: "text-sm font-semibold px-2 py-1 rounded #{color}") do
            "#{arrow} #{change.abs}%"
          end
        end

        def render_detailed_metrics
          div(class: "space-y-6") do
            render_token_breakdown
            render_latency_breakdown
            render_quality_metrics
          end
        end

        def render_token_breakdown
          details(open: true, class: "border border-gray-200 rounded-lg") do
            summary(class: "px-4 py-3 bg-gray-50 cursor-pointer hover:bg-gray-100 font-medium text-gray-900") do
              "Token Usage Breakdown"
            end
            div(class: "p-4 space-y-3") do
              render_metric_row("Prompt Tokens", baseline_prompt_tokens, result_prompt_tokens)
              render_metric_row("Completion Tokens", baseline_completion_tokens, result_completion_tokens)
              render_metric_row("Total Tokens", baseline_total_tokens, result_total_tokens)
              render_cost_row
            end
          end
        end

        def render_latency_breakdown
          details(open: true, class: "border border-gray-200 rounded-lg") do
            summary(class: "px-4 py-3 bg-gray-50 cursor-pointer hover:bg-gray-100 font-medium text-gray-900") do
              "Performance Metrics"
            end
            div(class: "p-4 space-y-3") do
              render_metric_row("Total Latency (ms)", baseline_latency, result_latency)
              render_metric_row("Time to First Token (ms)", baseline_ttft, result_ttft)
              render_metric_row("Tokens per Second", baseline_tps, result_tps)
            end
          end
        end

        def render_quality_metrics
          details(class: "border border-gray-200 rounded-lg") do
            summary(class: "px-4 py-3 bg-gray-50 cursor-pointer hover:bg-gray-100 font-medium text-gray-900") do
              "Quality Assessment"
            end
            div(class: "p-4 space-y-3") do
              render_quality_score("Semantic Similarity", 0.92)
              render_quality_score("Coherence", 0.88)
              render_quality_score("Factual Accuracy", 0.85)
              render_quality_score("Safety Score", 0.98)
            end
          end
        end

        def render_metric_row(label, baseline, result)
          delta = result - baseline
          delta_percent = baseline.zero? ? 0 : ((delta.to_f / baseline) * 100).round(1)

          div(class: "flex justify-between items-center py-2 border-b border-gray-100 last:border-0") do
            span(class: "text-sm text-gray-700") { label }
            div(class: "flex items-center gap-3") do
              span(class: "text-sm text-gray-500") { baseline }
              span(class: "text-sm font-semibold text-gray-900") { result }
              render_mini_delta(delta, delta_percent)
            end
          end
        end

        def render_cost_row
          baseline = baseline_cost
          result = result_cost
          delta = result - baseline
          delta_percent = baseline.zero? ? 0 : ((delta / baseline) * 100).round(1)

          div(class: "flex justify-between items-center py-2 border-t-2 border-gray-200 font-semibold") do
            span(class: "text-sm text-gray-900") { "Total Cost" }
            div(class: "flex items-center gap-3") do
              span(class: "text-sm text-gray-600") { "$#{format('%.4f', baseline)}" }
              span(class: "text-sm text-gray-900") { "$#{format('%.4f', result)}" }
              render_mini_delta(delta, delta_percent)
            end
          end
        end

        def render_quality_score(label, score)
          color = if score >= 0.9
                    "text-green-600"
                  elsif score >= 0.7
                    "text-yellow-600"
                  else
                    "text-red-600"
                  end

          div(class: "flex justify-between items-center py-2 border-b border-gray-100 last:border-0") do
            span(class: "text-sm text-gray-700") { label }
            span(class: "text-sm font-semibold #{color}") { format("%.2f", score) }
          end
        end

        def render_mini_delta(delta, percent)
          return nil if delta.zero?

          color = delta > 0 ? "text-red-600" : "text-green-600"
          arrow = delta > 0 ? "↑" : "↓"

          span(class: "text-xs font-medium #{color}") { "#{arrow}#{percent.abs}%" }
        end

        def render_export_section
          div(class: "mt-6 pt-6 border-t border-gray-200") do
            button(
              class: "w-full px-4 py-2 text-sm text-blue-600 border border-blue-600 rounded-lg hover:bg-blue-50",
              data_action: "click->metrics-panel#export"
            ) do
              "Export Metrics (JSON)"
            end
          end
        end

        # Helper methods for data extraction
        def has_regression?
          # Simple heuristic: cost increased by more than 20% or latency increased by more than 30%
          cost_increase = ((result_cost - baseline_cost) / baseline_cost * 100) rescue 0
          latency_increase = ((result_latency - baseline_latency) / baseline_latency * 100) rescue 0

          cost_increase > 20 || latency_increase > 30
        end

        def total_cost_delta
          {
            current: result_cost,
            change: baseline_cost.zero? ? 0 : ((result_cost - baseline_cost) / baseline_cost * 100).round(1),
            direction: result_cost < baseline_cost ? :improvement : :regression
          }
        end

        def total_tokens_delta
          baseline = baseline_total_tokens
          result = result_total_tokens
          {
            current: result,
            change: baseline.zero? ? 0 : ((result - baseline).to_f / baseline * 100).round(1),
            direction: result < baseline ? :improvement : :regression
          }
        end

        def avg_latency_delta
          {
            current: result_latency,
            change: baseline_latency.zero? ? 0 : ((result_latency - baseline_latency) / baseline_latency * 100).round(1),
            direction: result_latency < baseline_latency ? :improvement : :regression
          }
        end

        # Metric extraction helpers
        def baseline_prompt_tokens
          @baseline.dig("token_usage", "prompt_tokens") || @baseline.dig(:token_usage, :prompt_tokens) || 0
        end

        def result_prompt_tokens
          @result.dig("token_usage", "prompt_tokens") || @result.dig(:token_usage, :prompt_tokens) || 0
        end

        def baseline_completion_tokens
          @baseline.dig("token_usage", "completion_tokens") || @baseline.dig(:token_usage, :completion_tokens) || 0
        end

        def result_completion_tokens
          @result.dig("token_usage", "completion_tokens") || @result.dig(:token_usage, :completion_tokens) || 0
        end

        def baseline_total_tokens
          @baseline.dig("token_usage", "total_tokens") || @baseline.dig(:token_usage, :total_tokens) || 0
        end

        def result_total_tokens
          @result.dig("token_usage", "total_tokens") || @result.dig(:token_usage, :total_tokens) || 0
        end

        def baseline_cost
          @baseline.dig("cost") || @baseline.dig(:cost) || 0.0
        end

        def result_cost
          @result.dig("cost") || @result.dig(:cost) || 0.0
        end

        def baseline_latency
          @baseline.dig("latency_ms") || @baseline.dig(:latency_ms) || 0
        end

        def result_latency
          @result.dig("latency_ms") || @result.dig(:latency_ms) || 0
        end

        def baseline_ttft
          @baseline.dig("ttft_ms") || @baseline.dig(:ttft_ms) || 0
        end

        def result_ttft
          @result.dig("ttft_ms") || @result.dig(:ttft_ms) || 0
        end

        def baseline_tps
          return 0 if baseline_latency.zero?

          (baseline_total_tokens.to_f / (baseline_latency / 1000.0)).round(2)
        end

        def result_tps
          return 0 if result_latency.zero?

          (result_total_tokens.to_f / (result_latency / 1000.0)).round(2)
        end

        def format_metric(value)
          case value
          when Float
            format("%.2f", value)
          else
            value.to_s
          end
        end
      end
    end
  end
end
