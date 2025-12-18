# frozen_string_literal: true

module RAAF
  module Rails
    module Continuous
      class ResultShow < RAAF::Rails::Tracing::BaseComponent

        def initialize(result:)
          @result = result
          load_evaluator_metadata
        end

        def view_template
          div(class: "p-6") do
            render_header
            div(class: "grid grid-cols-1 lg:grid-cols-3 gap-6") do
              div(class: "lg:col-span-2 space-y-6") do
                render_score_section
                render_formatted_result_section
                render_reasoning_section if @result.reasoning.present?
                render_metrics_section if @result.metrics.present?
                render_metadata_section
              end
              div(class: "space-y-6") do
                render_summary_sidebar
                render_links_sidebar
              end
            end
          end
        end

        private

        # Load evaluator metadata for fancy names
        def load_evaluator_metadata
          @evaluator_display_name = nil
          @evaluator_description = nil
          @evaluator_checks = []

          return unless @result.evaluator_name.present?

          begin
            evaluator_class = RAAF::Eval::Continuous::EvaluatorDiscovery.build(
              { "name" => @result.evaluator_name }
            )

            if evaluator_class.respond_to?(:display_name)
              @evaluator_display_name = evaluator_class.display_name
            end

            if evaluator_class.respond_to?(:description)
              @evaluator_description = evaluator_class.description
            end

            if evaluator_class.respond_to?(:evaluated_checks)
              @evaluator_checks = evaluator_class.evaluated_checks
            end
          rescue StandardError
            # If evaluator lookup fails, we'll fall back to raw names
          end
        end

        # Get fancy display name for the evaluator
        def evaluator_fancy_name
          @evaluator_display_name.presence || @result.evaluator_name.to_s.humanize.titleize
        end

        # Get fancy display name for a check/field
        def check_fancy_name(field_name)
          return field_name.to_s.humanize unless @evaluator_checks.any?

          # field_name format: "original_field_path:evaluator_type" e.g., "individual_scores:consistency"
          field_part, evaluator_type = field_name.to_s.split(":", 2)

          # Find matching check
          check = @evaluator_checks.find do |c|
            check_field = c[:field_name].to_s
            check_type = c[:evaluator_type].to_s

            # Match on field name and evaluator type
            check_field == field_part && check_type == evaluator_type
          end

          check&.dig(:display_name).presence || field_name.to_s.humanize
        end

        # Get description for a check/field
        def check_description(field_name)
          return nil unless @evaluator_checks.any?

          field_part, evaluator_type = field_name.to_s.split(":", 2)

          check = @evaluator_checks.find do |c|
            check_field = c[:field_name].to_s
            check_type = c[:evaluator_type].to_s
            check_field == field_part && check_type == evaluator_type
          end

          check&.dig(:description)
        end

        def render_header
          field_name = @result.metadata&.dig("field_name") || @result.metadata&.dig(:field_name)
          field_display_name = field_name.present? ? check_fancy_name(field_name) : nil
          field_desc = field_name.present? ? check_description(field_name) : nil

          div(class: "sm:flex sm:items-center sm:justify-between mb-6 pb-4 border-b border-gray-200") do
            div do
              div(class: "flex items-center gap-3") do
                h1(class: "text-2xl font-bold text-gray-900") do
                  plain evaluator_fancy_name
                  if field_display_name.present?
                    span(class: "text-gray-400 mx-2") { "/" }
                    span(class: "text-blue-600") { field_display_name }
                  end
                end
                render_status_badge(@result.status)
              end
              # Show check description if available, otherwise evaluator description
              description = field_desc.presence || @evaluator_description
              if description.present?
                p(class: "mt-1 text-sm text-gray-500") { description }
              else
                p(class: "mt-1 text-sm text-gray-500") do
                  plain "Evaluation result from "
                  plain time_ago_in_words(@result.created_at)
                  plain " ago"
                end
              end
            end
          end
        end

        def render_score_section
          div(class: "bg-white shadow rounded-lg overflow-hidden") do
            div(class: "px-4 py-5 sm:px-6 border-b border-gray-200") do
              h3(class: "text-lg font-medium text-gray-900") { "Score" }
            end
            div(class: "px-4 py-5 sm:p-6 text-center") do
              if @result.score
                render_score_visualization(@result.score)
              else
                p(class: "text-gray-500") { "No score available" }
              end
            end
          end
        end

        def render_score_visualization(score)
          numeric_score = score.to_f
          percentage = (numeric_score * 100).round

          div(class: "mb-6") do
            div(class: "text-6xl font-bold text-gray-900") do
              plain percentage.to_s
              span(class: "text-2xl text-gray-500") { "%" }
            end
          end

          div(class: "mb-4") do
            progress_color = if numeric_score >= 0.8
                              "bg-green-600"
                            elsif numeric_score >= 0.6
                              "bg-yellow-500"
                            else
                              "bg-red-600"
                            end

            div(class: "w-full bg-gray-200 rounded-full h-6") do
              div(
                class: "#{progress_color} h-6 rounded-full transition-all duration-300 flex items-center justify-center",
                style: "width: #{percentage}%"
              ) do
                if percentage >= 20
                  span(class: "text-xs text-white font-medium") { "#{percentage}%" }
                end
              end
            end
          end

          div do
            badge_config = if numeric_score >= 0.8
                            { color: "green", text: "Good" }
                          elsif numeric_score >= 0.5
                            { color: "yellow", text: "Average" }
                          else
                            { color: "red", text: "Bad" }
                          end

            color_classes = case badge_config[:color]
                           when "green" then "bg-green-100 text-green-800"
                           when "yellow" then "bg-yellow-100 text-yellow-800"
                           when "red" then "bg-red-100 text-red-800"
                           else "bg-gray-100 text-gray-800"
                           end

            span(class: "inline-flex items-center px-4 py-2 rounded-full text-lg font-medium #{color_classes}") do
              badge_config[:text]
            end
          end
        end

        def render_formatted_result_section
          # Get formatted markdown from details
          markdown = @result.details&.dig("formatted_markdown") ||
                     @result.details&.dig(:formatted_markdown)
          return if markdown.blank?

          div(class: "bg-white shadow rounded-lg overflow-hidden") do
            div(class: "px-4 py-5 sm:px-6 border-b border-gray-200") do
              h3(class: "text-lg font-medium text-gray-900") { "Evaluation Details" }
            end
            div(class: "px-4 py-5 sm:p-6") do
              # Render markdown as HTML with prose styling for proper formatting
              div(class: "prose prose-sm max-w-none") do
                raw RAAF::Rails::Tracing::MarkdownRenderer.markdown_to_html(markdown)
              end
            end
          end
        end

        def render_reasoning_section
          div(class: "bg-white shadow rounded-lg overflow-hidden") do
            div(class: "px-4 py-5 sm:px-6 border-b border-gray-200") do
              h3(class: "text-lg font-medium text-gray-900") { "Reasoning" }
            end
            div(class: "px-4 py-5 sm:p-6") do
              div(class: "bg-gray-50 p-4 rounded-md") do
                p(class: "text-sm text-gray-700 whitespace-pre-wrap") { @result.reasoning }
              end
            end
          end
        end

        def render_metrics_section
          div(class: "bg-white shadow rounded-lg overflow-hidden") do
            div(class: "px-4 py-5 sm:px-6 border-b border-gray-200") do
              h3(class: "text-lg font-medium text-gray-900") { "Metrics" }
            end
            div(class: "px-4 py-5 sm:p-6") do
              if @result.metrics.is_a?(Hash)
                # Check if this has evaluation-specific data (current_value, baseline_value, etc.)
                if has_evaluation_details?(@result.metrics)
                  render_rich_evaluation_metrics(@result.metrics)
                else
                  dl(class: "grid grid-cols-1 gap-x-4 gap-y-4 sm:grid-cols-2") do
                    @result.metrics.each do |key, value|
                      div do
                        dt(class: "text-sm font-medium text-gray-500") { format_key(key) }
                        dd(class: "mt-1 text-sm text-gray-900") { format_value(value) }
                      end
                    end
                  end
                end
              else
                pre(class: "bg-gray-50 p-4 rounded-md text-sm text-gray-700 overflow-x-auto") do
                  JSON.pretty_generate(@result.metrics)
                end
              end
            end
          end
        end

        # Check if metrics contain evaluation-specific details
        def has_evaluation_details?(metrics)
          evaluation_keys = %w[current_value baseline_value max_drop threshold_good threshold_average
                               current_tokens baseline_tokens current_latency baseline_latency drop tolerance]
          metrics.keys.any? { |k| evaluation_keys.include?(k.to_s) }
        end

        # Render rich evaluation metrics with visual indicators
        def render_rich_evaluation_metrics(metrics)
          div(class: "space-y-4") do
            # Value comparison section (if we have current and baseline values)
            render_value_comparison(metrics)

            # Threshold visualization
            render_threshold_visualization(metrics)

            # Additional metrics that don't fit above
            render_additional_metrics(metrics)
          end
        end

        def render_value_comparison(metrics)
          current_value = metrics["current_value"] || metrics[:current_value]
          baseline_value = metrics["baseline_value"] || metrics[:baseline_value]
          drop = metrics["drop"] || metrics[:drop]
          max_drop = metrics["max_drop"] || metrics[:max_drop]

          return unless current_value || baseline_value

          div(class: "bg-gray-50 rounded-lg p-4") do
            h4(class: "text-sm font-medium text-gray-900 mb-3") { "Value Comparison" }
            div(class: "grid grid-cols-1 sm:grid-cols-3 gap-4") do
              # Current value
              if current_value
                render_value_card("Current Value", current_value, "text-blue-600", "bi-bullseye")
              end

              # Baseline value
              if baseline_value
                render_value_card("Baseline Value", baseline_value, "text-gray-600", "bi-flag")
              end

              # Drop/Change
              if drop || max_drop
                drop_value = max_drop || drop
                drop_color = drop_value.to_f > 0 ? "text-red-600" : "text-green-600"
                drop_icon = drop_value.to_f > 0 ? "bi-arrow-down" : "bi-arrow-up"
                render_value_card("Change", format_numeric(drop_value), drop_color, drop_icon)
              end
            end
          end
        end

        def render_value_card(label, value, color_class, icon_class)
          div(class: "bg-white rounded-md p-3 border border-gray-200") do
            div(class: "flex items-center gap-2") do
              i(class: "#{icon_class} #{color_class} text-lg")
              span(class: "text-xs text-gray-500") { label }
            end
            div(class: "mt-1 text-lg font-semibold #{color_class}") do
              if value.is_a?(Array)
                plain "[#{value.map { |v| format_numeric(v) }.join(', ')}]"
              else
                plain format_numeric(value)
              end
            end
          end
        end

        def render_threshold_visualization(metrics)
          threshold_good = metrics["threshold_good"] || metrics[:threshold_good]
          threshold_average = metrics["threshold_average"] || metrics[:threshold_average]
          tolerance = metrics["tolerance"] || metrics[:tolerance]

          return unless threshold_good || threshold_average || tolerance

          div(class: "bg-gray-50 rounded-lg p-4 mt-4") do
            h4(class: "text-sm font-medium text-gray-900 mb-3") { "Evaluation Thresholds" }

            # Visual threshold bar
            if threshold_good && threshold_average
              render_threshold_bar(threshold_good.to_f, threshold_average.to_f)
            end

            # Threshold values
            div(class: "grid grid-cols-1 sm:grid-cols-3 gap-4 mt-3") do
              if threshold_good
                div(class: "flex items-center gap-2") do
                  span(class: "inline-block w-3 h-3 rounded-full bg-green-500")
                  span(class: "text-sm text-gray-600") { "Good: ≥ #{format_numeric(threshold_good)}" }
                end
              end

              if threshold_average
                div(class: "flex items-center gap-2") do
                  span(class: "inline-block w-3 h-3 rounded-full bg-yellow-500")
                  span(class: "text-sm text-gray-600") { "Average: ≥ #{format_numeric(threshold_average)}" }
                end
              end

              if tolerance
                div(class: "flex items-center gap-2") do
                  span(class: "inline-block w-3 h-3 rounded-full bg-blue-500")
                  span(class: "text-sm text-gray-600") { "Tolerance: #{format_numeric(tolerance)}" }
                end
              end
            end
          end
        end

        def render_threshold_bar(good_threshold, average_threshold)
          score = @result.score&.to_f || 0.0
          score_percent = (score * 100).clamp(0, 100)
          good_percent = (good_threshold * 100).clamp(0, 100)
          avg_percent = (average_threshold * 100).clamp(0, 100)

          div(class: "relative h-6 bg-gradient-to-r from-red-200 via-yellow-200 to-green-200 rounded-full overflow-hidden") do
            # Threshold markers
            div(class: "absolute top-0 bottom-0 w-0.5 bg-yellow-600", style: "left: #{avg_percent}%")
            div(class: "absolute top-0 bottom-0 w-0.5 bg-green-600", style: "left: #{good_percent}%")

            # Score marker
            div(class: "absolute top-0 bottom-0 w-1 bg-blue-600 rounded", style: "left: calc(#{score_percent}% - 2px)") do
              div(class: "absolute -top-5 left-1/2 transform -translate-x-1/2 text-xs font-medium text-blue-600") do
                plain "#{score_percent.round}%"
              end
            end
          end
        end

        def render_additional_metrics(metrics)
          # Filter out keys we've already displayed
          displayed_keys = %w[current_value baseline_value drop max_drop threshold_good threshold_average tolerance]
          remaining = metrics.reject { |k, _| displayed_keys.include?(k.to_s) }

          return if remaining.empty?

          div(class: "bg-gray-50 rounded-lg p-4 mt-4") do
            h4(class: "text-sm font-medium text-gray-900 mb-3") { "Additional Details" }
            dl(class: "grid grid-cols-1 gap-x-4 gap-y-2 sm:grid-cols-2") do
              remaining.each do |key, value|
                next if value.nil?

                div(class: "flex justify-between py-1") do
                  dt(class: "text-sm text-gray-500") { format_key(key) }
                  dd(class: "text-sm font-medium text-gray-900") { format_value(value) }
                end
              end
            end
          end
        end

        def format_numeric(value)
          return "N/A" if value.nil?
          return value.to_s unless value.is_a?(Numeric)

          if value.is_a?(Float)
            if value.abs < 0.01 && value != 0
              sprintf("%.4f", value)
            elsif value.abs >= 1000
              number_with_delimiter(value.round)
            else
              value.round(2).to_s
            end
          else
            number_with_delimiter(value)
          end
        end

        def number_with_delimiter(number)
          number.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
        end

        def render_metadata_section
          div(class: "bg-white shadow rounded-lg overflow-hidden") do
            div(class: "px-4 py-5 sm:px-6 border-b border-gray-200") do
              h3(class: "text-lg font-medium text-gray-900") { "Metadata" }
            end
            div(class: "px-4 py-5 sm:p-6") do
              dl(class: "grid grid-cols-1 gap-x-4 gap-y-4 sm:grid-cols-2") do
                render_detail_row("Result ID", @result.id)
                render_detail_row("Agent Name", @result.agent_name)
                render_detail_row("Evaluator", evaluator_fancy_name)
                render_detail_row("Evaluator Type", format_evaluator_type(@result.evaluator_type))
                render_detail_row("Status", render_status_badge(@result.status))
                render_detail_row("Created", format_timestamp(@result.created_at))
                render_detail_row("Duration", format_duration(@result.evaluation_duration_ms)) if @result.evaluation_duration_ms

                if @result.metrics&.dig("tokens").present?
                  render_detail_row("Tokens Used", @result.metrics["tokens"].to_s)
                end

                if @result.metrics&.dig("cost").present?
                  render_detail_row("Cost", "$#{sprintf('%.4f', @result.metrics["cost"])}")
                end
              end
            end
          end
        end

        def render_summary_sidebar
          field_name = @result.metadata&.dig("field_name") || @result.metadata&.dig(:field_name)
          field_display_name = field_name.present? ? check_fancy_name(field_name) : nil
          specific_evaluators = @result.metadata&.dig("specific_evaluators") || @result.metadata&.dig(:specific_evaluators) || []

          div(class: "bg-white shadow rounded-lg overflow-hidden") do
            div(class: "px-4 py-5 sm:px-6 border-b border-gray-200") do
              h3(class: "text-lg font-medium text-gray-900") { "Summary" }
            end
            div(class: "divide-y divide-gray-200") do
              render_summary_item("Status", render_status_badge(@result.status))
              render_summary_item("Score", format_score(@result.score))
              render_summary_item("Check", field_display_name) if field_display_name.present?
              render_summary_item("Agent", @result.agent_name || "Unknown")
              render_summary_item("Evaluator", evaluator_fancy_name)
              render_summary_item("Type", format_evaluator_type(@result.evaluator_type))
              if specific_evaluators.any?
                render_summary_item("Checks", render_evaluator_badges(specific_evaluators))
              end
            end
          end
        end

        def render_evaluator_badges(evaluators)
          div(class: "flex flex-wrap gap-1") do
            evaluators.each do |evaluator|
              span(class: "inline-flex items-center px-2 py-0.5 rounded text-xs font-medium #{evaluator_badge_color(evaluator)}") do
                evaluator.to_s.gsub('_', ' ')
              end
            end
          end
        end

        def evaluator_badge_color(evaluator)
          case evaluator.to_s
          when /llm_judge|semantic/ then "bg-purple-100 text-purple-800"
          when /consistency/ then "bg-blue-100 text-blue-800"
          when /regression|no_regression/ then "bg-orange-100 text-orange-800"
          when /bias/ then "bg-red-100 text-red-800"
          when /token|latency|performance/ then "bg-cyan-100 text-cyan-800"
          else "bg-gray-100 text-gray-800"
          end
        end

        def format_evaluator_type(type)
          case type.to_s
          when "llm_judge" then "LLM Judge"
          when "rule_based" then "Rule-based"
          when "statistical" then "Statistical"
          when "custom" then "Custom"
          else type.to_s.split("_").map(&:capitalize).join(" ")
          end
        end

        def render_links_sidebar
          div(class: "bg-white shadow rounded-lg overflow-hidden") do
            div(class: "px-4 py-5 sm:px-6 border-b border-gray-200") do
              h3(class: "text-lg font-medium text-gray-900") { "Related" }
            end
            div(class: "divide-y divide-gray-200") do
              link_to(
                "/raaf/tracing/spans/#{@result.span_id}",
                class: "flex items-center px-4 py-3 hover:bg-gray-50 text-gray-700"
              ) do
                i(class: "bi bi-eye mr-3 text-gray-400")
                plain "View Span"
              end

              if @result.evaluation_queue_item
                link_to(
                  continuous_queue_item_path(@result.evaluation_queue_item),
                  class: "flex items-center px-4 py-3 hover:bg-gray-50 text-gray-700"
                ) do
                  i(class: "bi bi-list-task mr-3 text-gray-400")
                  plain "View Queue Item"
                end
              end

              if @result.evaluation_policy
                link_to(
                  continuous_policy_path(@result.evaluation_policy),
                  class: "flex items-center px-4 py-3 hover:bg-gray-50 text-gray-700"
                ) do
                  i(class: "bi bi-shield-check mr-3 text-gray-400")
                  plain "View Policy"
                end
              end

              link_to(
                continuous_results_path(agent_name: @result.agent_name),
                class: "flex items-center px-4 py-3 hover:bg-gray-50 text-gray-700"
              ) do
                i(class: "bi bi-filter mr-3 text-gray-400")
                plain "More from this Agent"
              end

              link_to(
                continuous_results_path(evaluator_name: @result.evaluator_name),
                class: "flex items-center px-4 py-3 hover:bg-gray-50 text-gray-700"
              ) do
                i(class: "bi bi-filter mr-3 text-gray-400")
                plain "More from this Evaluator"
              end
            end
          end
        end

        def render_summary_item(label, value)
          div(class: "flex justify-between items-center px-4 py-3") do
            span(class: "text-sm text-gray-500") { label }
            span(class: "text-sm text-gray-900") { value }
          end
        end

        def render_detail_row(label, value)
          div do
            dt(class: "text-sm font-medium text-gray-500") { label }
            dd(class: "mt-1 text-sm text-gray-900") { value }
          end
        end

        def render_status_badge(status)
          badge_config = case status.to_s
                        when "good"
                          { color: "green", icon: "bi-check-circle", text: "Good" }
                        when "average"
                          { color: "yellow", icon: "bi-dash-circle", text: "Average" }
                        when "bad"
                          { color: "red", icon: "bi-x-circle", text: "Bad" }
                        when "error"
                          { color: "orange", icon: "bi-exclamation-triangle", text: "Error" }
                        else
                          { color: "gray", icon: "bi-question-circle", text: status }
                        end

          color_classes = case badge_config[:color]
                         when "green" then "bg-green-100 text-green-800"
                         when "yellow" then "bg-yellow-100 text-yellow-800"
                         when "red" then "bg-red-100 text-red-800"
                         when "orange" then "bg-orange-100 text-orange-800"
                         else "bg-gray-100 text-gray-800"
                         end

          span(class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium #{color_classes}") do
            i(class: "#{badge_config[:icon]} mr-1")
            plain badge_config[:text]
          end
        end

        def format_score(score)
          return "N/A" unless score
          score.is_a?(Numeric) ? score.round(2).to_s : score.to_s
        end

        def format_timestamp(time)
          return "N/A" unless time
          time.strftime("%Y-%m-%d %H:%M:%S")
        end

        def format_duration(ms)
          return "N/A" unless ms
          if ms < 1000
            "#{ms.round}ms"
          else
            "#{(ms / 1000.0).round(2)}s"
          end
        end

        def format_key(key)
          key.to_s.split('_').map(&:capitalize).join(' ')
        end

        def format_value(value)
          case value
          when Numeric
            value.is_a?(Float) ? value.round(3).to_s : value.to_s
          when TrueClass, FalseClass
            value ? "Yes" : "No"
          when Hash
            pre(class: "text-xs bg-gray-50 p-2 rounded") { JSON.pretty_generate(value) }
          when Array
            value.join(", ")
          else
            value.to_s
          end
        end
      end
    end
  end
end
