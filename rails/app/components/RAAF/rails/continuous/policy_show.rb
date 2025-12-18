# frozen_string_literal: true

module RAAF
  module Rails
    module Continuous
      class PolicyShow < RAAF::Rails::Tracing::BaseComponent

        def initialize(policy:, today_stats: {}, recent_results: [])
          @policy = policy
          @today_stats = today_stats
          @recent_results = recent_results
          @evaluator_checks_cache = {}
          load_evaluator_checks
        end

        def view_template
          div(class: "p-6") do
            render_header
            div(class: "grid grid-cols-1 lg:grid-cols-3 gap-6") do
              div(class: "lg:col-span-2 space-y-6") do
                render_policy_details
                render_evaluators_section
                render_recent_results
              end
              div(class: "space-y-6") do
                render_stats_sidebar
                render_actions_sidebar
              end
            end
          end
        end

        private

        def render_header
          div(class: "sm:flex sm:items-center sm:justify-between mb-6 pb-4 border-b border-gray-200") do
            div do
              div(class: "flex items-center gap-3") do
                h1(class: "text-2xl font-bold text-gray-900") { @policy.name }
                render_status_badge(@policy)
              end
              if @policy.description.present?
                p(class: "mt-1 text-sm text-gray-500") { @policy.description }
              end
            end

            div(class: "mt-4 sm:mt-0 flex gap-2") do
              render_preline_button(
                text: "Edit",
                href: edit_continuous_policy_path(@policy),
                variant: "secondary",
                icon: "bi-pencil"
              )
              if @policy.active?
                button_to(
                  deactivate_continuous_policy_path(@policy),
                  method: :patch,
                  class: "inline-flex items-center gap-x-2 text-sm font-semibold rounded-lg border border-yellow-600 bg-yellow-600 text-white hover:bg-yellow-700 px-3 py-2"
                ) do
                  i(class: "bi bi-pause-circle")
                  plain "Deactivate"
                end
              else
                button_to(
                  activate_continuous_policy_path(@policy),
                  method: :patch,
                  class: "inline-flex items-center gap-x-2 text-sm font-semibold rounded-lg border border-green-600 bg-green-600 text-white hover:bg-green-700 px-3 py-2"
                ) do
                  i(class: "bi bi-play-circle")
                  plain "Activate"
                end
              end
            end
          end
        end

        def render_policy_details
          div(class: "bg-white shadow rounded-lg overflow-hidden") do
            div(class: "px-4 py-5 sm:px-6 border-b border-gray-200") do
              h3(class: "text-lg font-medium text-gray-900") { "Policy Configuration" }
            end
            div(class: "px-4 py-5 sm:p-6") do
              dl(class: "grid grid-cols-1 gap-x-4 gap-y-4 sm:grid-cols-2") do
                render_detail_row("Agent", @policy.agent_name.presence || "All agents")
                render_detail_row("Environment", @policy.environment.presence || "All environments")
                render_detail_row("Model Pattern", @policy.model_pattern.presence || "All models")
                render_detail_row("Sampling Mode", format_sampling_mode)
                render_detail_row("Daily Limit", @policy.max_daily_evaluations&.to_s || "Unlimited")
                render_detail_row("Retention", "#{@policy.retention_days} days")
                render_detail_row("Priority", @policy.priority.to_s)
                render_detail_row("Queue", @policy.queue_name.presence || "default")
              end
            end
          end
        end

        def render_evaluators_section
          div(class: "bg-white shadow rounded-lg overflow-hidden") do
            div(class: "px-4 py-5 sm:px-6 border-b border-gray-200") do
              h3(class: "text-lg font-medium text-gray-900") { "Configured Evaluators" }
            end
            div(class: "px-4 py-5 sm:p-6") do
              if @policy.evaluators.any?
                div(class: "divide-y divide-gray-200") do
                  @policy.evaluators.each do |evaluator|
                    render_evaluator_item(evaluator)
                  end
                end
              else
                p(class: "text-gray-500") { "No evaluators configured" }
              end
            end
          end
        end

        def render_evaluator_item(evaluator)
          # Evaluator is a hash with string keys
          name = evaluator["name"] || evaluator[:name]
          type = evaluator["type"] || evaluator[:type]
          checks = evaluator["checks"] || evaluator[:checks] || []
          check_sample_rates = evaluator["check_sample_rates"] || evaluator[:check_sample_rates] || {}
          agent_name = evaluator["agent_name"] || evaluator[:agent_name]

          # Get fancy names
          display_name = evaluator_display_name(name)
          description = evaluator_description(name)

          div(class: "py-4 first:pt-0 last:pb-0") do
            # Header: Agent name with check count (like edit page)
            div(class: "flex items-center gap-2 mb-4") do
              span(class: "font-semibold text-gray-900") { agent_name || display_name }
              span(class: "text-gray-500") { "(#{checks.size} checks)" }
            end

            # Show checks with their sample rates and fancy names
            if checks.any?
              div(class: "space-y-3") do
                checks.each do |check|
                  sample_rate = check_sample_rates[check.to_s] || check_sample_rates[check.to_sym] || 100
                  check_name = check_display_name(check, name)
                  check_desc = check_description(check, name)

                  div(class: "flex items-start justify-between py-2") do
                    # Check details
                    div(class: "flex-1 min-w-0") do
                      span(class: "font-medium text-gray-900") { check_name }
                      if check_desc.present?
                        p(class: "text-sm text-gray-500 mt-0.5") { check_desc }
                      end
                    end

                    # Sample rate badge
                    span(class: "flex-shrink-0 text-sm text-gray-500") { "#{sample_rate}%" }
                  end
                end
              end
            end
          end
        end

        def format_evaluator_type(type)
          case type.to_s
          when "llm_judge" then "LLM Judge"
          when "rule_based" then "Rule-based"
          when "statistical" then "Statistical"
          else type.to_s.split("_").map(&:capitalize).join(" ")
          end
        end

        def render_stats_sidebar
          div(class: "bg-white shadow rounded-lg overflow-hidden") do
            div(class: "px-4 py-5 sm:px-6 border-b border-gray-200") do
              h3(class: "text-lg font-medium text-gray-900") { "Today's Statistics" }
            end
            div(class: "px-4 py-5 sm:p-6 space-y-4") do
              render_stat_item("Evaluations", @today_stats[:total] || 0)
              render_stat_item("Good", @today_stats[:good] || 0, "green")
              render_stat_item("Average", @today_stats[:average] || 0, "yellow")
              render_stat_item("Bad", @today_stats[:bad] || 0, "red")
              render_stat_item("Error", @today_stats[:error] || 0, "orange") if (@today_stats[:error] || 0) > 0
              render_stat_item("Avg Score", format_score(@today_stats[:avg_score]))

              if @policy.max_daily_evaluations
                div(class: "pt-4 border-t border-gray-200") do
                  span(class: "text-sm text-gray-500") { "Daily Usage" }
                  div(class: "mt-2") do
                    percentage = (@today_stats[:total].to_f / @policy.max_daily_evaluations * 100).round
                    progress_color = if percentage >= 90
                                       "bg-red-600"
                                     elsif percentage >= 70
                                       "bg-yellow-500"
                                     else
                                       "bg-green-600"
                                     end
                    div(class: "w-full bg-gray-200 rounded-full h-4") do
                      div(
                        class: "#{progress_color} h-4 rounded-full transition-all duration-300",
                        style: "width: #{[percentage, 100].min}%"
                      ) do
                        span(class: "px-2 text-xs text-white font-medium") { "#{percentage}%" }
                      end
                    end
                  end
                end
              end
            end
          end
        end

        def render_actions_sidebar
          div(class: "bg-white shadow rounded-lg overflow-hidden") do
            div(class: "px-4 py-5 sm:px-6 border-b border-gray-200") do
              h3(class: "text-lg font-medium text-gray-900") { "Actions" }
            end
            div(class: "divide-y divide-gray-200") do
              link_to(
                continuous_queue_items_path(policy_id: @policy.id),
                class: "flex items-center px-4 py-3 hover:bg-gray-50 text-gray-700"
              ) do
                i(class: "bi bi-list-task mr-3 text-gray-400")
                plain "View Queue Items"
              end

              link_to(
                continuous_results_path(policy_id: @policy.id),
                class: "flex items-center px-4 py-3 hover:bg-gray-50 text-gray-700"
              ) do
                i(class: "bi bi-graph-up mr-3 text-gray-400")
                plain "View Results"
              end

              link_to(
                continuous_analytics_path,
                class: "flex items-center px-4 py-3 hover:bg-gray-50 text-gray-700"
              ) do
                i(class: "bi bi-bar-chart mr-3 text-gray-400")
                plain "Analytics Dashboard"
              end

              link_to(
                edit_continuous_policy_path(@policy),
                class: "flex items-center px-4 py-3 hover:bg-gray-50 text-blue-600"
              ) do
                i(class: "bi bi-pencil mr-3")
                plain "Edit Policy"
              end

              button_to(
                duplicate_continuous_policy_path(@policy),
                method: :post,
                class: "flex items-center w-full px-4 py-3 hover:bg-gray-50 text-cyan-600"
              ) do
                i(class: "bi bi-copy mr-3")
                plain "Duplicate Policy"
              end

              button_to(
                continuous_policy_path(@policy),
                method: :delete,
                class: "flex items-center w-full px-4 py-3 hover:bg-gray-50 text-red-600",
                data: { confirm: "Are you sure? This will delete all associated data." }
              ) do
                i(class: "bi bi-trash mr-3")
                plain "Delete Policy"
              end
            end
          end
        end

        def render_recent_results
          render RecentResultsPanel.new(
            results: @recent_results,
            title: "Recent Results",
            view_all_path: continuous_results_path(policy_id: @policy.id),
            limit: 5,
            show_evaluator: true
          )
        end

        def render_detail_row(label, value)
          div do
            dt(class: "text-sm font-medium text-gray-500") { label }
            dd(class: "mt-1 text-sm text-gray-900") { value }
          end
        end

        def render_stat_item(label, value, color = nil)
          div(class: "flex justify-between items-center") do
            span(class: "text-sm text-gray-500") { label }
            value_class = case color
                         when "green" then "text-green-600"
                         when "yellow" then "text-yellow-600"
                         when "orange" then "text-orange-600"
                         when "red" then "text-red-600"
                         else "text-gray-900"
                         end
            span(class: "text-lg font-semibold #{value_class}") { value }
          end
        end

        def render_status_badge(policy)
          if policy.active?
            span(class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800") do
              "Active"
            end
          else
            span(class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-800") do
              "Inactive"
            end
          end
        end

        def render_badge(text, color)
          color_classes = case color
                         when "blue" then "bg-blue-100 text-blue-800"
                         when "green" then "bg-green-100 text-green-800"
                         when "red" then "bg-red-100 text-red-800"
                         when "yellow" then "bg-yellow-100 text-yellow-800"
                         when "gray" then "bg-gray-100 text-gray-800"
                         when "info" then "bg-cyan-100 text-cyan-800"
                         when "success" then "bg-green-100 text-green-800"
                         when "warning" then "bg-yellow-100 text-yellow-800"
                         else "bg-gray-100 text-gray-800"
                         end

          span(class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium #{color_classes}") do
            text
          end
        end

        def format_sampling_mode
          case @policy.sampling_mode
          when "every_n"
            "Every #{@policy.sample_every_n}th span"
          when "all"
            "All spans"
          else
            @policy.sampling_mode
          end
        end

        def format_score(score)
          return "N/A" unless score
          score.is_a?(Numeric) ? score.round(2).to_s : score.to_s
        end

        def evaluator_type_color(type)
          case type.to_s
          when "rule", "rule_based" then "green"
          when "statistical" then "info"
          when "llm_judge" then "yellow"
          else "gray"
          end
        end

        # Load evaluator metadata and checks from all configured evaluators
        # @return [void]
        def load_evaluator_checks
          @evaluator_metadata_cache = {}

          @policy.evaluators.each do |evaluator|
            name = evaluator["name"] || evaluator[:name]
            next unless name

            begin
              evaluator_class = RAAF::Eval::Continuous::EvaluatorDiscovery.build(evaluator)

              # Store evaluator metadata (display_name, description)
              @evaluator_metadata_cache[name.to_s] = {
                display_name: evaluator_class.respond_to?(:display_name) ? evaluator_class.display_name : nil,
                description: evaluator_class.respond_to?(:description) ? evaluator_class.description : nil
              }

              # Store check details
              if evaluator_class.respond_to?(:evaluated_checks)
                checks = evaluator_class.evaluated_checks
                @evaluator_checks_cache[name.to_s] = checks
              end
            rescue StandardError
              # Skip if evaluator cannot be loaded
            end
          end
        end

        # Get display name for an evaluator
        # @param name [String] The evaluator name
        # @return [String] The display name or humanized name as fallback
        def evaluator_display_name(name)
          metadata = @evaluator_metadata_cache&.dig(name.to_s)
          metadata&.dig(:display_name).presence || name.to_s.humanize.titleize
        end

        # Get description for an evaluator
        # @param name [String] The evaluator name
        # @return [String, nil] The description
        def evaluator_description(name)
          metadata = @evaluator_metadata_cache&.dig(name.to_s)
          metadata&.dig(:description)
        end

        # Find check details by field name and evaluator type
        # @param evaluator_name [String] The evaluator name (e.g., "eval_prospect_scoring")
        # @param field_name [String] The field name (e.g., "individual_scores")
        # @param evaluator_type [String] The evaluator type (e.g., "consistency")
        # @return [Hash, nil] Check details with :display_name and :description
        def find_check_details(evaluator_name, field_name, evaluator_type = nil)
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

        # Get display name for a check, falling back to humanized field name
        # @param check [String] The check in "field:evaluator" format
        # @param evaluator_name [String] The evaluator name
        # @return [String] The display name
        def check_display_name(check, evaluator_name)
          field_name, evaluator_type = check.to_s.split(":", 2)
          details = find_check_details(evaluator_name, field_name, evaluator_type)

          if details && details[:display_name].present?
            details[:display_name]
          else
            # Fallback to humanized name
            field_name.to_s.humanize
          end
        end

        # Get description for a check
        # @param check [String] The check in "field:evaluator" format
        # @param evaluator_name [String] The evaluator name
        # @return [String, nil] The description
        def check_description(check, evaluator_name)
          field_name, evaluator_type = check.to_s.split(":", 2)
          details = find_check_details(evaluator_name, field_name, evaluator_type)
          details&.dig(:description)
        end
      end
    end
  end
end
