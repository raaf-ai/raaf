# frozen_string_literal: true

module RAAF
  module Rails
    module Continuous
      # Reusable component for displaying recent evaluation results
      # Can be used on policy show page and span detail page
      class RecentResultsPanel < RAAF::Rails::Tracing::BaseComponent
        def initialize(results:, title: "Recent Results", view_all_path: nil, limit: 5, show_evaluator: true, embedded: false)
          @results = results
          @title = title
          @view_all_path = view_all_path
          @limit = limit
          @show_evaluator = show_evaluator
          @embedded = embedded
          @evaluator_checks_cache = {}
          load_evaluator_checks
        end

        def view_template
          if @results.empty?
            return nil if @embedded  # Don't show anything in embedded mode when empty
            return render_empty_state
          end

          if @embedded
            # Embedded mode: no container, just title and list
            render_embedded_content
          else
            # Standalone mode: full container with shadow
            div(class: "bg-white shadow rounded-lg overflow-hidden") do
              render_header
              render_results_list
            end
          end
        end

        def render_embedded_content
          div do
            h4(class: "text-sm font-medium text-gray-700 mb-3") { @title }
            div(class: "space-y-2") do
              @results.first(@limit).each do |result|
                render_embedded_result_item(result)
              end
            end
          end
        end

        def render_embedded_result_item(result)
          # Extract check details
          field_name = result.details&.dig("field_name") || result.details&.dig(:field_name) ||
                       result.metadata&.dig("field_name") || result.metadata&.dig(:field_name)
          specific_evaluators = result.metadata&.dig("specific_evaluators") || result.metadata&.dig(:specific_evaluators) || []

          check_details = find_check_display_info(result, field_name, specific_evaluators)
          display_name = check_details[:display_name] || field_name&.to_s&.humanize || "Evaluation"

          a(
            href: helpers.continuous_result_path(result),
            class: "flex items-center justify-between p-2 rounded hover:bg-gray-50 transition-colors"
          ) do
            div(class: "flex items-center gap-2") do
              render_result_status_badge(result)
              span(class: "text-sm font-medium text-gray-700") { display_name }
            end
            span(class: "text-xs text-gray-400") { helpers.time_ago_in_words(result.created_at) + " ago" }
          end
        end

        private

        def render_header
          div(class: "px-4 py-5 sm:px-6 border-b border-gray-200 flex justify-between items-center") do
            h3(class: "text-lg font-medium text-gray-900") { @title }
            if @view_all_path
              link_to(
                "View All",
                @view_all_path,
                class: "text-sm text-blue-600 hover:text-blue-500"
              )
            end
          end
        end

        def render_results_list
          div(class: "px-4 py-5 sm:p-6") do
            div(class: "divide-y divide-gray-200") do
              @results.first(@limit).each do |result|
                render_result_item(result)
              end
            end
          end
        end

        def render_result_item(result)
          # Extract check details from metadata or details
          field_name = result.details&.dig("field_name") || result.details&.dig(:field_name) ||
                       result.metadata&.dig("field_name") || result.metadata&.dig(:field_name)
          specific_evaluators = result.metadata&.dig("specific_evaluators") || result.metadata&.dig(:specific_evaluators) || []

          # Try to find fancy name and description
          check_details = find_check_display_info(result, field_name, specific_evaluators)
          display_name = check_details[:display_name] || field_name&.to_s&.humanize || "Evaluation"
          description = check_details[:description]

          div(class: "py-4 first:pt-0 last:pb-0") do
            div(class: "flex justify-between items-start") do
              div(class: "flex-1") do
                # Check name with status badge and score
                div(class: "flex items-center gap-2") do
                  span(class: "font-medium text-gray-900") { display_name }
                  render_result_status_badge(result)
                  if result.score
                    span(class: "text-sm text-gray-600") { "Score: #{format_score(result.score)}" }
                  end
                end

                # Description if available
                if description.present?
                  p(class: "mt-1 text-xs text-gray-500") { description }
                end

                # Evaluator name and time
                span(class: "text-xs text-gray-400") do
                  if @show_evaluator && result.evaluator_name.present?
                    plain result.evaluator_name
                    plain " • "
                  end
                  plain time_ago_in_words(result.created_at)
                  plain " ago"
                end
              end

              link_to(
                "View",
                continuous_result_path(result),
                class: "text-sm text-blue-600 hover:text-blue-500"
              )
            end
          end
        end

        def render_empty_state
          div(class: "bg-white shadow rounded-lg overflow-hidden") do
            div(class: "px-4 py-5 sm:px-6 border-b border-gray-200") do
              h3(class: "text-lg font-medium text-gray-900") { @title }
            end
            div(class: "px-4 py-5 sm:p-6") do
              p(class: "text-gray-500") { "No results yet" }
            end
          end
        end

        def render_result_status_badge(result)
          # Determine status based on score or status field
          badge_config = determine_badge_config(result)
          render_badge(badge_config[:text], badge_config[:color])
        end

        def determine_badge_config(result)
          # First check status field
          case result.status
          when "good"
            { color: "green", text: "Good" }
          when "average"
            { color: "yellow", text: "Average" }
          when "bad"
            { color: "red", text: "Bad" }
          when "error"
            { color: "orange", text: "Error" }
          when "passed"
            { color: "green", text: "Good" }
          when "failed"
            { color: "red", text: "Bad" }
          else
            # Fallback to score-based
            if result.score
              score = result.score.to_f
              if score >= 0.8
                { color: "green", text: "Good" }
              elsif score >= 0.5
                { color: "yellow", text: "Average" }
              else
                { color: "red", text: "Bad" }
              end
            else
              { color: "gray", text: result.status || "Unknown" }
            end
          end
        end

        def render_badge(text, color)
          color_classes = case color
                         when "green" then "bg-green-100 text-green-800"
                         when "yellow" then "bg-yellow-100 text-yellow-800"
                         when "red" then "bg-red-100 text-red-800"
                         when "orange" then "bg-orange-100 text-orange-800"
                         else "bg-gray-100 text-gray-800"
                         end

          span(class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium #{color_classes}") do
            text
          end
        end

        def format_score(score)
          return "N/A" unless score
          "#{(score.to_f * 100).round(1)}%"
        end

        def find_check_display_info(result, field_name, specific_evaluators)
          return {} unless field_name.present?

          evaluator_type = specific_evaluators.first if specific_evaluators.present?
          check_details = find_check_details(result.evaluator_name, field_name, evaluator_type)

          {
            display_name: check_details&.dig(:display_name),
            description: check_details&.dig(:description)
          }
        end

        # Load evaluator metadata and checks
        def load_evaluator_checks
          return unless defined?(RAAF::Eval::Continuous::EvaluatorDiscovery)

          @results.each do |result|
            next unless result.evaluator_name
            next if @evaluator_checks_cache.key?(result.evaluator_name.to_s)

            begin
              evaluator_class = RAAF::Eval::Continuous::EvaluatorDiscovery.build(
                { "name" => result.evaluator_name }
              )

              if evaluator_class.respond_to?(:evaluated_checks)
                @evaluator_checks_cache[result.evaluator_name.to_s] = evaluator_class.evaluated_checks
              end
            rescue StandardError
              # Skip if evaluator cannot be loaded
            end
          end
        end

        def find_check_details(evaluator_name, field_name, evaluator_type = nil)
          return nil unless evaluator_name

          checks = @evaluator_checks_cache[evaluator_name.to_s]
          return nil unless checks

          checks.find do |check|
            field_match = check[:field_name].to_s == field_name.to_s
            if evaluator_type
              field_match && check[:evaluator_type].to_s == evaluator_type.to_s
            else
              field_match
            end
          end
        end
      end
    end
  end
end
