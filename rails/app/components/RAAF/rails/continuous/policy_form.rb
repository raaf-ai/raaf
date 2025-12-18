# frozen_string_literal: true

module RAAF
  module Rails
    module Continuous
      class PolicyForm < RAAF::Rails::Tracing::BaseComponent

        def initialize(policy:, evaluators: [], agents: [], environments: [])
          @policy = policy
          @evaluators = evaluators
          @agents = agents
          @environments = environments
        end

        def view_template
          div(class: "p-6") do
            render_header
            render_form
          end
        end

        private

        def render_header
          div(class: "sm:flex sm:items-center sm:justify-between mb-6 pb-4 border-b border-gray-200") do
            div do
              h1(class: "text-2xl font-bold text-gray-900") { @policy.persisted? ? "Edit Policy" : "New Policy" }
              p(class: "mt-1 text-sm text-gray-500") { "Configure continuous evaluation policy" }
            end
          end
        end

        def render_form
          if @evaluators.empty?
            render_no_evaluators_message
          else
            render_errors if @policy.errors.any?

            div(class: "bg-white shadow rounded-lg overflow-hidden") do
              div(class: "px-4 py-5 sm:p-6") do
                form_with(model: @policy, url: form_url, class: "space-y-8") do |f|
                  render_basic_fields(f)
                  render_check_selection(f)
                  render_limits_fields(f)
                  render_advanced_fields(f)
                  render_actions(f)
                end
              end
            end
          end
        end

        def render_errors
          div(class: "bg-red-50 border border-red-200 rounded-lg p-4 mb-6") do
            div(class: "flex items-start") do
              div(class: "flex-shrink-0") do
                i(class: "bi bi-exclamation-circle text-red-500 text-xl")
              end
              div(class: "ml-3") do
                h3(class: "text-sm font-medium text-red-800") do
                  "#{@policy.errors.count} error(s) prevented this policy from being saved:"
                end
                ul(class: "mt-2 text-sm text-red-700 list-disc list-inside space-y-1") do
                  @policy.errors.full_messages.each do |message|
                    li { message }
                  end
                end
              end
            end
          end
        end

        def render_no_evaluators_message
          div(class: "bg-white shadow rounded-lg overflow-hidden") do
            div(class: "px-4 py-12 sm:p-12") do
              div(class: "text-center") do
                div(class: "mx-auto flex items-center justify-center h-16 w-16 rounded-full bg-yellow-100 mb-4") do
                  i(class: "bi bi-exclamation-triangle text-yellow-600 text-2xl")
                end
                h3(class: "text-lg font-medium text-gray-900 mb-2") { "No Evaluators Available" }
                p(class: "text-sm text-gray-500 mb-6 max-w-md mx-auto") do
                  "Policies require at least one evaluator to function. Please register evaluators before creating a policy."
                end
                div(class: "bg-gray-50 rounded-lg p-4 text-left max-w-lg mx-auto mb-6") do
                  p(class: "text-sm font-medium text-gray-700 mb-2") { "To register evaluators:" }
                  ol(class: "text-sm text-gray-600 list-decimal list-inside space-y-1") do
                    li { "Create evaluator classes that include RAAF::Eval::DSL::Evaluator" }
                    li { "Register them with RAAF::Eval::DSL::EvaluatorRegistry" }
                    li { "Or ensure built-in evaluators are loaded in your application" }
                  end
                end
                link_to(
                  "Back to Policies",
                  continuous_policies_path,
                  class: "inline-flex items-center px-4 py-2 border border-gray-300 text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50"
                )
              end
            end
          end
        end

        def render_basic_fields(form)
          div(class: "space-y-6") do
            h3(class: "text-lg font-medium text-gray-900 border-b border-gray-200 pb-2") { "Basic Information" }

            div do
              label(for: "policy_name", class: "block text-sm font-medium text-gray-700") { "Policy Name *" }
              form.text_field(
                :name,
                class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm",
                required: true,
                placeholder: "e.g., Production Quality Check"
              )
            end

            div do
              label(for: "policy_description", class: "block text-sm font-medium text-gray-700") { "Description (optional)" }
              form.text_area(
                :description,
                class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm",
                rows: 3,
                placeholder: "Describe what this policy monitors..."
              )
            end

            div(class: "flex items-center") do
              form.check_box(:active, class: "h-4 w-4 rounded border-gray-300 text-blue-600 focus:ring-blue-500")
              label(for: "policy_active", class: "ml-2 block text-sm text-gray-700") { "Active (evaluations will run)" }
            end
          end
        end

        def render_limits_fields(form)
          div(class: "space-y-6 pt-6") do
            h3(class: "text-lg font-medium text-gray-900 border-b border-gray-200 pb-2") { "Limits & Retention" }

            div do
              label(for: "policy_max_daily_evaluations", class: "block text-sm font-medium text-gray-700") { "Max Daily Evaluations (optional)" }
              form.number_field(
                :max_daily_evaluations,
                class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm",
                min: 0,
                placeholder: "1000"
              )
              p(class: "mt-1 text-sm text-gray-500") { "Maximum evaluations per day. Leave blank for unlimited." }
            end

            div do
              label(for: "policy_retention_days", class: "block text-sm font-medium text-gray-700") { "Result Retention (days)" }
              form.number_field(
                :retention_days,
                class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm",
                min: 1,
                value: @policy.retention_days || 30
              )
              p(class: "mt-1 text-sm text-gray-500") { "How long to keep evaluation results (default: 30 days)" }
            end
          end
        end

        def render_check_selection(form)
          div(class: "space-y-6 pt-6") do
            div(class: "flex items-center justify-between border-b border-gray-200 pb-2") do
              h3(class: "text-lg font-medium text-gray-900") { "Select Checks *" }
              span(class: "text-sm text-gray-500") { "Choose which checks to run and their sample rates" }
            end

            # Group checks by agent
            checks_by_agent = build_checks_by_agent

            if checks_by_agent.empty?
              div(class: "py-8 text-center text-gray-500") do
                "No checks available. Evaluators must define evaluated fields."
              end
            else
              div(class: "space-y-6 mt-4") do
                checks_by_agent.each do |agent_name, checks|
                  render_agent_checks_group(form, agent_name, checks)
                end
              end
            end
          end
        end

        def build_checks_by_agent
          checks_by_agent = {}

          @evaluators.each do |evaluator|
            agent_name = evaluator[:agent_name] || "Unknown Agent"
            checks = evaluator[:checks] || []

            next if checks.empty?

            checks_by_agent[agent_name] ||= []
            checks.each do |check|
              # Handle both old format (symbol/string) and new format (hash with details)
              if check.is_a?(Hash)
                # New format with detailed check info
                field_name = check[:field_name] || check["field_name"]
                evaluator_type = check[:evaluator_type] || check["evaluator_type"]
                check_type = check[:check_type] || check["check_type"] || evaluator[:type]
                check_display_name = check[:display_name] || check["display_name"]
                check_description = check[:description] || check["description"]

                checks_by_agent[agent_name] << {
                  check_name: "#{field_name}:#{evaluator_type}",
                  field_name: field_name.to_s,
                  specific_evaluator: evaluator_type.to_s,
                  evaluator_name: evaluator[:name],
                  evaluator_type: check_type.to_s,
                  display_name: check_display_name,
                  description: check_description || evaluator[:description],
                  uses_llm: check_type.to_s == "llm_judge"
                }
              else
                # Old format (just field name as symbol/string)
                checks_by_agent[agent_name] << {
                  check_name: check.to_s,
                  field_name: check.to_s,
                  specific_evaluator: nil,
                  evaluator_name: evaluator[:name],
                  evaluator_type: evaluator[:type],
                  display_name: nil,
                  description: evaluator[:description],
                  uses_llm: evaluator[:uses_llm]
                }
              end
            end
          end

          checks_by_agent
        end

        def render_agent_checks_group(form, agent_name, checks)
          div(class: "border border-gray-200 rounded-lg overflow-hidden") do
            # Agent header
            div(class: "bg-gray-50 px-4 py-3 border-b border-gray-200") do
              div(class: "flex items-center gap-2") do
                i(class: "bi bi-robot text-gray-400")
                span(class: "font-medium text-gray-900") { agent_name }
                span(class: "text-sm text-gray-500") { "(#{checks.size} checks)" }
              end
            end

            # Checks list
            div(class: "divide-y divide-gray-100") do
              checks.each do |check|
                render_check_row(form, agent_name, check)
              end
            end
          end
        end

        def render_check_row(form, agent_name, check)
          check_id = "#{check[:evaluator_name]}_#{check[:check_name]}"
          is_selected = check_selected?(check[:evaluator_name], check[:check_name])

          div(class: "px-4 py-3 hover:bg-gray-50 #{is_selected ? 'bg-blue-50' : ''}",
              data: { controller: "evaluator-toggle" }) do
            # Main row with checkbox, name, and badges
            div(class: "flex items-center gap-4") do
              # Checkbox
              div(class: "flex items-center") do
                checkbox_tag(
                  "evaluation_policy[check_configs][#{check_id}][enabled]",
                  "1",
                  is_selected,
                  class: "h-4 w-4 rounded border-gray-300 text-blue-600 focus:ring-blue-500",
                  id: "check_#{check_id}",
                  data: { action: "change->evaluator-toggle#toggle", evaluator_toggle_target: "checkbox" }
                )
              end

              # Check name with specific evaluator type and description
              div(class: "flex-1") do
                label(for: "check_#{check_id}", class: "cursor-pointer") do
                  # Use display_name if available, otherwise field_name / specific_evaluator
                  if check[:display_name].present?
                    span(class: "font-medium text-gray-900") { check[:display_name] }
                  else
                    span(class: "font-medium text-gray-900") { check[:field_name] || check[:check_name] }
                    # Show specific evaluator type if available
                    if check[:specific_evaluator].present?
                      span(class: "text-gray-400 mx-1") { "/" }
                      span(class: "text-blue-600 font-medium") { format_specific_evaluator(check[:specific_evaluator]) }
                    end
                  end
                end
                # Show description if available
                if check[:description].present?
                  p(class: "text-xs text-gray-500 mt-0.5") { check[:description] }
                end
              end

              # Type badge (category: llm_judge, statistical, rule_based)
              div(class: "flex items-center gap-2") do
                span(class: "inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium #{evaluator_type_badge_class(check[:evaluator_type])}") do
                  format_evaluator_type(check[:evaluator_type])
                end
                if check[:uses_llm]
                  span(class: "inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-purple-100 text-purple-800") do
                    "LLM"
                  end
                end
              end
            end

            # Configuration row (below the main row) - trigger mode, sample every_n, and trials for statistical
            div(class: "mt-2 ml-8 pl-4 border-l-2 border-gray-200 #{is_selected ? '' : 'hidden'}",
                data: { evaluator_toggle_target: "config" }) do
              div(class: "flex items-center gap-4 py-2 flex-wrap") do
                # Hidden sampling mode (always every_n)
                input(
                  type: "hidden",
                  name: "evaluation_policy[check_configs][#{check_id}][sampling_mode]",
                  value: "every_n"
                )

                # Trigger mode selector
                trigger_mode = get_check_trigger_mode(check[:evaluator_name], check[:check_name])
                div(class: "flex items-center gap-2") do
                  span(class: "text-sm text-gray-600") { "Trigger:" }
                  select(
                    name: "evaluation_policy[check_configs][#{check_id}][trigger_mode]",
                    id: "check_#{check_id}_trigger_mode",
                    class: "block w-28 rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 text-sm",
                    title: "Automatic: runs when spans are created. Manual: only runs via UI button.",
                    data: { evaluator_toggle_target: "triggerMode", action: "change->evaluator-toggle#triggerModeChanged" }
                  ) do
                    option(value: "automatic", selected: trigger_mode == "automatic") { "Automatic" }
                    option(value: "manual", selected: trigger_mode == "manual") { "Manual" }
                  end
                end

                # Sample every N (hidden when trigger mode is manual)
                sampling_hidden = trigger_mode == "manual" ? "hidden" : ""
                div(class: "flex items-center gap-2 #{sampling_hidden}",
                    data: { evaluator_toggle_target: "samplingConfig" }) do
                  span(class: "text-sm text-gray-600") { "Evaluate every" }
                  input(
                    type: "number",
                    name: "evaluation_policy[check_configs][#{check_id}][sample_every_n]",
                    id: "check_#{check_id}_sample_every_n",
                    value: get_check_sample_every_n(check[:evaluator_name], check[:check_name]),
                    min: 1,
                    step: 1,
                    class: "block w-16 rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 text-sm"
                  )
                  span(class: "text-sm text-gray-500") { "spans" }
                end

                # Consistency mode and trials (only for statistical evaluators)
                if check[:evaluator_type].to_s == "statistical"
                  consistency_mode = get_check_consistency_mode(check[:evaluator_name], check[:check_name])
                  trials = get_check_trials(check[:evaluator_name], check[:check_name])

                  # Consistency mode selector
                  div(class: "flex items-center gap-2") do
                    span(class: "text-sm text-gray-500") { "Mode:" }
                    select(
                      name: "evaluation_policy[check_configs][#{check_id}][consistency_mode]",
                      id: "check_#{check_id}_consistency_mode",
                      class: "block w-28 rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 text-sm",
                      title: "Historical: use past spans (cheap). Re-run: execute agent multiple times (accurate, higher cost)"
                    ) do
                      option(value: "historical", selected: consistency_mode == "historical") { "Historical" }
                      option(value: "rerun", selected: consistency_mode == "rerun") { "Re-run" }
                    end
                  end

                  # Trials
                  div(class: "flex items-center gap-2") do
                    span(class: "text-sm text-gray-500") { "Runs:" }
                    input(
                      type: "number",
                      name: "evaluation_policy[check_configs][#{check_id}][trials]",
                      id: "check_#{check_id}_trials",
                      value: trials,
                      min: 2,
                      max: 10,
                      step: 1,
                      class: "block w-16 rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 text-sm",
                      title: "Number of runs to compare for consistency check"
                    )
                  end
                end
              end
            end

            # Hidden fields
            input(type: "hidden", name: "evaluation_policy[check_configs][#{check_id}][evaluator_name]", value: check[:evaluator_name])
            input(type: "hidden", name: "evaluation_policy[check_configs][#{check_id}][check_name]", value: check[:check_name])
            input(type: "hidden", name: "evaluation_policy[check_configs][#{check_id}][agent_name]", value: agent_name)
            input(type: "hidden", name: "evaluation_policy[check_configs][#{check_id}][specific_evaluator]", value: check[:specific_evaluator]) if check[:specific_evaluator].present?
          end
        end

        def check_selected?(evaluator_name, check_name)
          evaluators = @policy.evaluators || []
          evaluators.any? do |e|
            eval_name = e[:name] || e["name"]
            eval_checks = e[:checks] || e["checks"] || []
            eval_name.to_s == evaluator_name.to_s && eval_checks.map(&:to_s).include?(check_name.to_s)
          end
        end

        def get_check_trials(evaluator_name, check_name)
          evaluators = @policy.evaluators || []
          evaluator = evaluators.find do |e|
            eval_name = e[:name] || e["name"]
            eval_checks = e[:checks] || e["checks"] || []
            eval_name.to_s == evaluator_name.to_s && eval_checks.map(&:to_s).include?(check_name.to_s)
          end
          return 3 unless evaluator  # Default to 3 trials

          # Check for per-check trials first, then evaluator-level, then default
          check_trials = evaluator[:check_trials] || evaluator["check_trials"] || {}
          check_trials[check_name.to_s] || check_trials[check_name.to_sym] ||
            evaluator.dig(:config, :trials) || evaluator.dig("config", "trials") ||
            evaluator[:trials] || evaluator["trials"] || 3
        end

        def get_check_sample_every_n(evaluator_name, check_name)
          evaluators = @policy.evaluators || []
          evaluator = evaluators.find do |e|
            eval_name = e[:name] || e["name"]
            eval_checks = e[:checks] || e["checks"] || []
            eval_name.to_s == evaluator_name.to_s && eval_checks.map(&:to_s).include?(check_name.to_s)
          end
          return 10 unless evaluator  # Default to every 10

          # Check for per-check sample_every_n
          check_sample_every_n = evaluator[:check_sample_every_n] || evaluator["check_sample_every_n"] || {}
          check_sample_every_n[check_name.to_s] || check_sample_every_n[check_name.to_sym] ||
            evaluator[:sample_every_n] || evaluator["sample_every_n"] || 10
        end

        def get_check_consistency_mode(evaluator_name, check_name)
          evaluators = @policy.evaluators || []
          evaluator = evaluators.find do |e|
            eval_name = e[:name] || e["name"]
            eval_checks = e[:checks] || e["checks"] || []
            eval_name.to_s == evaluator_name.to_s && eval_checks.map(&:to_s).include?(check_name.to_s)
          end
          return "historical" unless evaluator  # Default to historical (cheaper)

          # Check for per-check consistency mode
          check_consistency_modes = evaluator[:check_consistency_modes] || evaluator["check_consistency_modes"] || {}
          check_consistency_modes[check_name.to_s] || check_consistency_modes[check_name.to_sym] ||
            evaluator[:consistency_mode] || evaluator["consistency_mode"] || "historical"
        end

        def get_check_trigger_mode(evaluator_name, check_name)
          evaluators = @policy.evaluators || []
          evaluator = evaluators.find do |e|
            eval_name = e[:name] || e["name"]
            eval_checks = e[:checks] || e["checks"] || []
            eval_name.to_s == evaluator_name.to_s && eval_checks.map(&:to_s).include?(check_name.to_s)
          end
          return "automatic" unless evaluator  # Default to automatic

          # Check for per-check trigger mode
          check_trigger_modes = evaluator[:check_trigger_modes] || evaluator["check_trigger_modes"] || {}
          check_trigger_modes[check_name.to_s] || check_trigger_modes[check_name.to_sym] ||
            evaluator[:trigger_mode] || evaluator["trigger_mode"] || "automatic"
        end

        def selected_evaluator_names
          @selected_evaluator_names ||= begin
            evaluators = @policy.evaluators || []
            evaluators.map { |e| (e[:name] || e["name"]).to_s }
          end
        end

        def format_evaluator_name(name)
          name.to_s.split("_").map(&:capitalize).join(" ")
        end

        def render_evaluator_badges(evaluator)
          span(class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium #{evaluator_type_badge_class(evaluator[:type])}") do
            format_evaluator_type(evaluator[:type])
          end
          if evaluator[:uses_llm]
            span(class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-purple-100 text-purple-800") do
              "Uses LLM"
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

        def format_specific_evaluator(evaluator)
          case evaluator.to_s
          when "consistency" then "Consistency"
          when "no_regression" then "No Regression"
          when "llm_judge" then "LLM Judge"
          when "semantic_similarity" then "Semantic Similarity"
          when "bias_detection" then "Bias Detection"
          when "token_efficiency" then "Token Efficiency"
          when "latency" then "Latency"
          when "variance" then "Variance"
          when "pii_detector" then "PII Detector"
          when "format_validator" then "Format Validator"
          else evaluator.to_s.split("_").map(&:capitalize).join(" ")
          end
        end

        def render_advanced_fields(form)
          div(class: "space-y-6 pt-6") do
            div(class: "flex items-center gap-2 border-b border-gray-200 pb-2") do
              h3(class: "text-lg font-medium text-gray-900") { "Advanced Settings" }
              span(class: "text-sm text-gray-500") { "(optional)" }
            end

            # Two-column grid for compact layout
            div(class: "grid grid-cols-1 md:grid-cols-2 gap-6") do
              div do
                label(for: "policy_max_concurrent_evaluations", class: "block text-sm font-medium text-gray-700") { "Max Concurrent Evaluations" }
                form.number_field(
                  :max_concurrent_evaluations,
                  class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm",
                  min: 1,
                  max: 50,
                  value: @policy.max_concurrent_evaluations || 5
                )
                p(class: "mt-1 text-sm text-gray-500") { "Maximum parallel evaluations (default: 5)" }
              end

              div do
                label(for: "policy_max_retries", class: "block text-sm font-medium text-gray-700") { "Max Retries" }
                form.number_field(
                  :max_retries,
                  class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm",
                  min: 0,
                  max: 10,
                  value: @policy.max_retries || 3
                )
                p(class: "mt-1 text-sm text-gray-500") { "Retry attempts for failed evaluations (default: 3)" }
              end

              div do
                label(for: "policy_priority", class: "block text-sm font-medium text-gray-700") { "Queue Priority" }
                form.number_field(
                  :priority,
                  class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm",
                  min: 0,
                  max: 100,
                  value: @policy.priority || 50
                )
                p(class: "mt-1 text-sm text-gray-500") { "Higher priority runs first (0-100, default: 50)" }
              end

              div do
                label(for: "policy_queue_name", class: "block text-sm font-medium text-gray-700") { "Queue Name" }
                form.text_field(
                  :queue_name,
                  class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm",
                  placeholder: "default"
                )
                p(class: "mt-1 text-sm text-gray-500") { "Solid Queue queue name (leave blank for default)" }
              end
            end
          end
        end

        def render_actions(form)
          div(class: "flex items-center justify-between pt-8 border-t border-gray-200") do
            div(class: "flex items-center gap-3") do
              form.submit(
                "Save Policy",
                class: "inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
              )
              link_to(
                "Cancel",
                continuous_policies_path,
                class: "inline-flex items-center px-4 py-2 border border-gray-300 text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50"
              )
            end

            if @policy.persisted?
              # Use link_to with turbo_method instead of button_to to avoid nested form issue
              # button_to creates its own <form>, which when nested inside form_with causes submission problems
              link_to(
                continuous_policy_path(@policy),
                class: "inline-flex items-center px-4 py-2 border border-red-300 text-sm font-medium rounded-md text-red-700 bg-white hover:bg-red-50",
                data: { turbo_method: :delete, turbo_confirm: "Are you sure? This will delete all associated data." }
              ) do
                i(class: "bi bi-trash mr-2")
                plain "Delete Policy"
              end
            end
          end
        end

        def form_url
          if @policy.persisted?
            continuous_policy_path(@policy)
          else
            continuous_policies_path
          end
        end

        def evaluator_type_badge_class(type)
          case type.to_s
          when "rule_based", "rule" then "bg-green-100 text-green-800"
          when "statistical" then "bg-cyan-100 text-cyan-800"
          when "llm_judge" then "bg-yellow-100 text-yellow-800"
          else "bg-gray-100 text-gray-800"
          end
        end

        # Helper method for checkbox (Phlex doesn't have this by default)
        def checkbox_tag(name, value, checked, options = {})
          input(
            type: "checkbox",
            name: name,
            value: value,
            checked: checked,
            **options
          )
        end
      end
    end
  end
end
