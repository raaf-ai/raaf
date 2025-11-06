# frozen_string_literal: true

module RAAF
  module Eval
    module UI
      # ConfigurationComparison component displays multiple evaluation configurations
      # in a tabbed interface with side-by-side comparison grid, difference highlighting,
      # and visual indicators for best/worst performers.
      class ConfigurationComparison < Phlex::HTML
        attr_reader :configurations, :baseline, :selected_indices, :metrics

        def initialize(configurations:, baseline: nil, selected_indices: nil, metrics: {})
          @configurations = configurations
          @baseline = baseline
          @selected_indices = selected_indices || (0...configurations.length).to_a
          @metrics = metrics
        end

        def template
          div(class: "configuration-comparison bg-white rounded-lg shadow-lg overflow-hidden") do
            # Header
            render_header

            # Tabbed interface
            render_tabs

            # Side-by-side comparison grid
            render_comparison_grid

            # Footer with actions
            render_footer
          end
        end

        private

        def render_header
          div(class: "bg-gray-50 border-b border-gray-200 px-6 py-4") do
            div(class: "flex items-center justify-between") do
              div do
                h3(class: "text-lg font-semibold text-gray-900") do
                  text "Configuration Comparison"
                end
                p(class: "mt-1 text-sm text-gray-600") do
                  text "Comparing #{selected_configurations.length} configuration(s)"
                end
              end

              # Configuration selector
              render_configuration_selector
            end
          end
        end

        def render_configuration_selector
          div(class: "flex items-center space-x-2") do
            label(for: "config-selector", class: "text-sm text-gray-700") do
              text "Select configs:"
            end

            select(
              id: "config-selector",
              multiple: true,
              class: "px-3 py-1 text-sm border border-gray-300 rounded",
              data: {
                action: "change->configuration-comparison#updateSelection"
              }
            ) do
              configurations.each_with_index do |config, idx|
                selected = selected_indices.include?(idx)
                option(value: idx, selected: selected) do
                  text config[:name] || "Configuration #{idx + 1}"
                end
              end
            end
          end
        end

        def render_tabs
          div(class: "border-b border-gray-200") do
            nav(class: "flex space-x-4 px-6", role: "tablist") do
              # Overview tab
              render_tab("overview", "Overview", active: true)

              # Model settings tab
              render_tab("model", "Model Settings")

              # Parameters tab
              render_tab("parameters", "Parameters")

              # Metrics tab
              render_tab("metrics", "Metrics") if metrics.any?
            end
          end
        end

        def render_tab(id, label, active: false)
          button(
            type: "button",
            role: "tab",
            class: tab_class(active),
            data: {
              action: "click->configuration-comparison#switchTab",
              tab_id: id
            }
          ) do
            text label
          end
        end

        def tab_class(active)
          base = "px-4 py-3 text-sm font-medium border-b-2 transition-colors"
          if active
            "#{base} border-blue-600 text-blue-600"
          else
            "#{base} border-transparent text-gray-600 hover:text-gray-900 hover:border-gray-300"
          end
        end

        def render_comparison_grid
          div(class: "p-6", data: { controller: "configuration-comparison" }) do
            # Overview panel (default)
            render_overview_panel

            # Model settings panel (hidden by default)
            render_model_settings_panel

            # Parameters panel (hidden by default)
            render_parameters_panel

            # Metrics panel (hidden by default)
            render_metrics_panel if metrics.any?
          end
        end

        def render_overview_panel
          div(
            class: "tab-panel",
            data: { tab_panel: "overview" }
          ) do
            div(class: "grid gap-4", style: grid_columns_style) do
              selected_configurations.each_with_index do |config, idx|
                render_configuration_card(config, idx)
              end
            end
          end
        end

        def render_configuration_card(config, idx)
          is_baseline = baseline && config[:id] == baseline[:id]
          is_best = idx == best_configuration_index
          is_worst = idx == worst_configuration_index

          div(class: configuration_card_class(is_baseline, is_best, is_worst)) do
            # Card header
            div(class: "px-4 py-3 border-b border-gray-200 bg-gray-50") do
              div(class: "flex items-center justify-between") do
                h4(class: "font-semibold text-sm text-gray-900") do
                  text config[:name] || "Configuration #{idx + 1}"
                end

                div(class: "flex items-center space-x-2") do
                  render_performance_badge(is_baseline, is_best, is_worst)
                end
              end
            end

            # Card body
            div(class: "p-4 space-y-3") do
              # Model info
              render_config_field("Model", config.dig(:settings, :model) || 'Not specified')

              # Provider info
              render_config_field("Provider", config.dig(:settings, :provider) || 'Not specified')

              # Temperature
              render_config_field("Temperature", format_value(config.dig(:settings, :temperature)))

              # Max tokens
              render_config_field("Max Tokens", config.dig(:settings, :max_tokens) || 'Not specified')

              # Differences indicator
              if baseline && config[:id] != baseline[:id]
                render_differences_indicator(config)
              end
            end
          end
        end

        def configuration_card_class(is_baseline, is_best, is_worst)
          base = "bg-white rounded-lg border-2 transition-all"

          if is_baseline
            "#{base} border-blue-500"
          elsif is_best
            "#{base} border-green-500"
          elsif is_worst
            "#{base} border-red-500"
          else
            "#{base} border-gray-200"
          end
        end

        def render_performance_badge(is_baseline, is_best, is_worst)
          if is_baseline
            span(class: "px-2 py-1 text-xs font-semibold bg-blue-100 text-blue-800 rounded") do
              text "Baseline"
            end
          elsif is_best
            span(class: "px-2 py-1 text-xs font-semibold bg-green-100 text-green-800 rounded") do
              text "Best"
            end
          elsif is_worst
            span(class: "px-2 py-1 text-xs font-semibold bg-red-100 text-red-800 rounded") do
              text "Worst"
            end
          end
        end

        def render_config_field(label, value)
          div(class: "flex justify-between items-start") do
            dt(class: "text-xs text-gray-600 font-medium") do
              text "#{label}:"
            end
            dd(class: "text-xs text-gray-900 font-mono") do
              text value.to_s
            end
          end
        end

        def render_differences_indicator(config)
          diff_count = count_differences(config, baseline)

          if diff_count > 0
            div(class: "mt-3 pt-3 border-t border-gray-200") do
              p(class: "text-xs text-orange-600 font-medium") do
                text "#{diff_count} difference(s) from baseline"
              end
            end
          end
        end

        def render_model_settings_panel
          div(
            class: "tab-panel hidden",
            data: { tab_panel: "model" }
          ) do
            # Detailed model settings comparison table
            table(class: "w-full border-collapse") do
              thead do
                tr(class: "bg-gray-50") do
                  th(class: "px-4 py-2 text-left text-xs font-semibold text-gray-700 border-b") do
                    text "Setting"
                  end

                  selected_configurations.each_with_index do |config, idx|
                    th(class: "px-4 py-2 text-left text-xs font-semibold text-gray-700 border-b") do
                      text config[:name] || "Config #{idx + 1}"
                    end
                  end
                end
              end

              tbody do
                render_setting_row("Model", :model)
                render_setting_row("Provider", :provider)
                render_setting_row("Temperature", :temperature)
                render_setting_row("Max Tokens", :max_tokens)
                render_setting_row("Top P", :top_p)
                render_setting_row("Frequency Penalty", :frequency_penalty)
                render_setting_row("Presence Penalty", :presence_penalty)
              end
            end
          end
        end

        def render_setting_row(label, key)
          tr(class: "hover:bg-gray-50") do
            td(class: "px-4 py-2 text-xs font-medium text-gray-700 border-b") do
              text label
            end

            baseline_value = baseline&.dig(:settings, key)

            selected_configurations.each do |config|
              value = config.dig(:settings, key)
              is_different = baseline_value && value != baseline_value

              td(class: "px-4 py-2 text-xs font-mono border-b #{is_different ? 'bg-yellow-50' : ''}") do
                text format_value(value)

                if is_different
                  span(class: "ml-2 text-orange-600") { text "•" }
                end
              end
            end
          end
        end

        def render_parameters_panel
          div(
            class: "tab-panel hidden",
            data: { tab_panel: "parameters" }
          ) do
            div(class: "space-y-4") do
              selected_configurations.each_with_index do |config, idx|
                render_parameter_section(config, idx)
              end
            end
          end
        end

        def render_parameter_section(config, idx)
          div(class: "bg-gray-50 rounded-lg p-4") do
            h4(class: "font-semibold text-sm text-gray-900 mb-3") do
              text config[:name] || "Configuration #{idx + 1}"
            end

            div(class: "grid grid-cols-2 gap-3") do
              config.dig(:settings)&.each do |key, value|
                render_parameter_item(key, value)
              end
            end
          end
        end

        def render_parameter_item(key, value)
          div do
            dt(class: "text-xs text-gray-600") do
              text key.to_s.split('_').map(&:capitalize).join(' ')
            end
            dd(class: "text-xs text-gray-900 font-mono mt-1") do
              text format_value(value)
            end
          end
        end

        def render_metrics_panel
          div(
            class: "tab-panel hidden",
            data: { tab_panel: "metrics" }
          ) do
            # Metrics comparison table
            table(class: "w-full border-collapse") do
              thead do
                tr(class: "bg-gray-50") do
                  th(class: "px-4 py-2 text-left text-xs font-semibold text-gray-700 border-b") do
                    text "Metric"
                  end

                  selected_configurations.each_with_index do |config, idx|
                    th(class: "px-4 py-2 text-center text-xs font-semibold text-gray-700 border-b") do
                      text config[:name] || "Config #{idx + 1}"
                    end
                  end
                end
              end

              tbody do
                metrics.each do |metric_key, metric_label|
                  render_metric_row(metric_key, metric_label)
                end
              end
            end
          end
        end

        def render_metric_row(metric_key, metric_label)
          tr(class: "hover:bg-gray-50") do
            td(class: "px-4 py-2 text-xs font-medium text-gray-700 border-b") do
              text metric_label
            end

            selected_configurations.each do |config|
              value = config.dig(:metrics, metric_key)

              td(class: "px-4 py-2 text-xs text-center border-b") do
                text format_metric_value(metric_key, value)
              end
            end
          end
        end

        def render_footer
          div(class: "bg-gray-50 border-t border-gray-200 px-6 py-4") do
            div(class: "flex items-center justify-between") do
              # Left side - info
              p(class: "text-xs text-gray-600") do
                text "Use the tabs above to compare different aspects"
              end

              # Right side - actions
              div(class: "flex items-center space-x-3") do
                button(
                  type: "button",
                  class: "px-3 py-2 text-sm border border-gray-300 rounded hover:bg-gray-50"
                ) do
                  text "Export Comparison"
                end

                button(
                  type: "button",
                  class: "px-3 py-2 text-sm bg-blue-600 text-white rounded hover:bg-blue-700"
                ) do
                  text "Save Comparison"
                end
              end
            end
          end
        end

        # Helper methods

        def selected_configurations
          @selected_configurations ||= selected_indices.map { |idx| configurations[idx] }.compact
        end

        def grid_columns_style
          cols = [selected_configurations.length, 4].min
          "grid-template-columns: repeat(#{cols}, minmax(0, 1fr));"
        end

        def best_configuration_index
          return nil unless metrics.any?

          # Simple heuristic: lowest cost and fastest
          selected_configurations.each_with_index.min_by do |config, _idx|
            cost = config.dig(:metrics, :cost) || Float::INFINITY
            latency = config.dig(:metrics, :latency_ms) || Float::INFINITY
            cost + (latency / 1000.0)
          end&.last
        end

        def worst_configuration_index
          return nil unless metrics.any?

          # Simple heuristic: highest cost and slowest
          selected_configurations.each_with_index.max_by do |config, _idx|
            cost = config.dig(:metrics, :cost) || 0
            latency = config.dig(:metrics, :latency_ms) || 0
            cost + (latency / 1000.0)
          end&.last
        end

        def count_differences(config, baseline_config)
          return 0 unless baseline_config

          diff_count = 0
          config_settings = config[:settings] || {}
          baseline_settings = baseline_config[:settings] || {}

          all_keys = (config_settings.keys + baseline_settings.keys).uniq
          all_keys.each do |key|
            diff_count += 1 if config_settings[key] != baseline_settings[key]
          end

          diff_count
        end

        def format_value(value)
          case value
          when Float
            format('%.3f', value)
          when NilClass
            'Not specified'
          else
            value.to_s
          end
        end

        def format_metric_value(metric_key, value)
          return 'N/A' if value.nil?

          case metric_key
          when :cost
            "$#{format('%.4f', value)}"
          when :latency_ms, :ttft_ms
            "#{value}ms"
          when :tokens, :token_count
            value.to_s
          else
            format_value(value)
          end
        end
      end
    end
  end
end
