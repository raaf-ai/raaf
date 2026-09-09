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

        # No form screen exists in any canvas, so this follows the library the
        # designed screens are built from: cards for the sections, `Field` for
        # every label and hint, and the shared input classes. The field names,
        # Stimulus targets and actions are untouched — only the presentation
        # moved.
        def view_template
          div(class: "raaf-page") do
            render_form
          end
        end

        private

        def render_form
          if @evaluators.empty?
            render_no_evaluators_message
          else
            render_errors if @policy.errors.any?

            form_with(model: @policy, url: form_url, class: "raaf-page") do |f|
              render_basic_fields(f)
              render_check_selection(f)
              render_limits_fields(f)
              render_advanced_fields(f)
              render_actions(f)
            end
          end
        end

        def render_errors
          render(Molecules::Alert.new(:error, title: error_title)) do
            ul(class: "raaf-alert-list") do
              @policy.errors.full_messages.each { |message| li { message } }
            end
          end
        end

        def error_title
          "#{pluralize(@policy.errors.count, 'problem')} stopped this policy being saved"
        end

        def render_no_evaluators_message
          render(Organisms::Card.new(title: "No evaluators available")) do
            render Atoms::Text.new(
              "A policy needs at least one evaluator. Register evaluators before creating one.",
              tone: :secondary
            )

            render(Molecules::Panel.new(title: "To register evaluators", icon: "list-ol", pad: true)) do
              ol(class: "raaf-steps") do
                li { "Create evaluator classes that include RAAF::Eval::DSL::Evaluator" }
                li { "Register them with RAAF::Eval::DSL::EvaluatorRegistry" }
                li { "Or ensure the built-in evaluators are loaded in your application" }
              end
            end

            div(class: "raaf-form-actions") do
              render Atoms::Button.new(label: "Back to policies", href: continuous_policies_path,
                                       variant: :secondary, icon: "arrow-left")
            end
          end
        end

        def render_basic_fields(form)
          render(Organisms::Card.new(title: "Basics")) do
            render(Molecules::Field.new(label: "Policy name", for_id: "policy_name")) do
              form.text_field(:name, class: "raaf-input raaf-input--glass", required: true,
                                     placeholder: "e.g. Production quality check")
            end

            render(Molecules::Field.new(label: "Description", for_id: "policy_description",
                                        optional: true,
                                        hint: "What this policy watches, in one line.")) do
              form.text_area(:description, class: "raaf-input raaf-input--glass raaf-textarea", rows: 3,
                                           placeholder: "Describe what this policy monitors…")
            end

            div(class: "raaf-cluster") do
              form.check_box(:active, class: "raaf-checkbox")
              label(for: "policy_active", class: "raaf-check-label") { "Active — evaluations will run" }
            end
          end
        end

        def render_limits_fields(form)
          render(Organisms::Card.new(title: "Limits and retention")) do
            div(class: "raaf-field-grid") do
              render(Molecules::Field.new(label: "Max daily evaluations", optional: true,
                                          for_id: "policy_max_daily_evaluations",
                                          hint: "Blank for unlimited.")) do
                form.number_field(:max_daily_evaluations, class: "raaf-input raaf-input--glass", min: 0,
                                                          placeholder: "1000")
              end

              render(Molecules::Field.new(label: "Result retention (days)",
                                          for_id: "policy_retention_days",
                                          hint: "How long results are kept.")) do
                form.number_field(:retention_days, class: "raaf-input raaf-input--glass", min: 1,
                                                   value: @policy.retention_days || 30)
              end
            end
          end
        end

        def render_check_selection(form)
          render(Organisms::Card.new(title: "Checks",
                                     subtitle: "Which checks run, and how often",
                                     data: { controller: "policy-agent" })) do
            agent_scope

            # Group checks by agent
            checks_by_agent = build_checks_by_agent

            if checks_by_agent.empty?
              render Molecules::EmptyState.new(icon: "sliders", title: "No checks available",
                                               text: "Evaluators must declare evaluated fields.")
            else
              div(class: "raaf-stack") do
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

        # A policy matches spans by one agent name, so only one agent's checks
        # can be chosen. Rather than let the wrong pairing be made and refused
        # on save, the picker shows one agent at a time — and switching agent
        # clears what the previous one had ticked, because a half-kept
        # selection is what produced "AgentA, AgentB" policies that matched
        # nothing.
        def agent_scope
          agents = build_checks_by_agent.keys

          render(Molecules::Field.new(
                   label: "Agent", for_id: "policy-agent-scope",
                   hint: "The agent this policy watches. Its checks are the ones below."
                 )) do
            select(id: "policy-agent-scope",
                   class: "raaf-input raaf-input--glass raaf-select",
                   data: { policy_agent_target: "select", action: "change->policy-agent#select" }) do
              agents.each do |agent|
                option(value: agent, selected: agent == selected_agent) { agent }
              end
            end
          end
        end

        # The agent whose checks are shown.
        #
        # Found from the checks the policy already has ticked, not from
        # `agent_name`: the registry groups checks by class path
        # (`Ai::Agents::Dmu::Classification`) while a policy stores the RAAF
        # agent name (`StakeholderClassificationAgent`), so comparing the two
        # never matches and every policy would open on the wrong agent.
        def selected_agent
          @selected_agent ||= agent_with_selection || matching_agent_name || first_agent
        end

        def agent_with_selection
          build_checks_by_agent.find do |_agent, checks|
            checks.any? { |check| check_selected?(check[:evaluator_name], check[:check_name]) }
          end&.first
        end

        def matching_agent_name
          @policy.agent_name if build_checks_by_agent.key?(@policy.agent_name)
        end

        def first_agent
          build_checks_by_agent.keys.first
        end

        def render_agent_checks_group(form, agent_name, checks)
          hidden = agent_name == selected_agent ? "" : "hidden"

          div(class: "raaf-checkgroup #{hidden}",
              data: { policy_agent_target: "group", agent: agent_name }) do
            div(class: "raaf-checkgroup-head") do
              render Atoms::Icon.new("robot", size: :sm, tone: :muted)
              span(class: "raaf-checkgroup-agent") { agent_name }
              render Atoms::Mono.new("#{checks.size} checks", tone: :muted)
            end

            div do
              checks.each do |check|
                render_check_row(form, agent_name, check)
              end
            end
          end
        end

        def render_check_row(form, agent_name, check)
          check_id = "#{check[:evaluator_name]}_#{check[:check_name]}"
          is_selected = check_selected?(check[:evaluator_name], check[:check_name])

          div(class: "raaf-checkrow #{'is-selected' if is_selected}",
              data: { controller: "evaluator-toggle" }) do
            div(class: "raaf-checkrow-main") do
              div(class: "raaf-cluster") do
                checkbox_tag(
                  "evaluation_policy[check_configs][#{check_id}][enabled]",
                  "1",
                  is_selected,
                  class: "raaf-checkbox",
                  id: "check_#{check_id}",
                  data: { action: "change->evaluator-toggle#toggle", evaluator_toggle_target: "checkbox" }
                )
              end

              # Check name with specific evaluator type and description
              div(class: "raaf-checkrow-body") do
                label(for: "check_#{check_id}", class: "raaf-check-label") do
                  # Use display_name if available, otherwise field_name / specific_evaluator
                  if check[:display_name].present?
                    span(class: "raaf-checkrow-name") { check[:display_name] }
                  else
                    span(class: "raaf-checkrow-name") { check[:field_name] || check[:check_name] }
                    # Show specific evaluator type if available
                    if check[:specific_evaluator].present?
                      span(class: "raaf-checkrow-sep") { "/" }
                      span(class: "raaf-checkrow-evaluator") { format_specific_evaluator(check[:specific_evaluator]) }
                    end
                  end
                end
                # Show description if available
                p(class: "raaf-checkrow-desc") { check[:description] } if check[:description].present?
              end

              # Type badge (category: llm_judge, statistical, rule_based)
              div(class: "raaf-cluster") do
                render(Atoms::Badge.for_check_type(check[:evaluator_type], size: :sm) ||
                       Atoms::Badge.new("Unknown", size: :sm))
                render Atoms::KindBadge.new("llm") if check[:uses_llm]
              end
            end

            # Configuration row (below the main row) - trigger mode, sample every_n, and trials for statistical
            div(class: "raaf-checkrow-config #{'hidden' unless is_selected}",
                data: { evaluator_toggle_target: "config" }) do
              div(class: "raaf-cluster") do
                # Hidden sampling mode (always every_n)
                input(
                  type: "hidden",
                  name: "evaluation_policy[check_configs][#{check_id}][sampling_mode]",
                  value: "every_n"
                )

                # Trigger mode selector
                trigger_mode = get_check_trigger_mode(check[:evaluator_name], check[:check_name])
                div(class: "flex items-center gap-2") do
                  span(class: "raaf-checkrow-hint") { "Trigger" }
                  select(
                    name: "evaluation_policy[check_configs][#{check_id}][trigger_mode]",
                    id: "check_#{check_id}_trigger_mode",
                    class: "raaf-input raaf-input--glass raaf-select raaf-input--sm",
                    title: "Automatic: runs when spans are created. Manual: only runs via UI button.",
                    data: { evaluator_toggle_target: "triggerMode",
                            action: "change->evaluator-toggle#triggerModeChanged" }
                  ) do
                    option(value: "automatic", selected: trigger_mode == "automatic") { "Automatic" }
                    option(value: "manual", selected: trigger_mode == "manual") { "Manual" }
                  end
                end

                # Sample every N (hidden when trigger mode is manual)
                sampling_hidden = trigger_mode == "manual" ? "hidden" : ""
                div(class: "flex items-center gap-2 #{sampling_hidden}",
                    data: { evaluator_toggle_target: "samplingConfig" }) do
                  span(class: "raaf-checkrow-hint") { "Evaluate every" }
                  input(
                    type: "number",
                    name: "evaluation_policy[check_configs][#{check_id}][sample_every_n]",
                    id: "check_#{check_id}_sample_every_n",
                    value: get_check_sample_every_n(check[:evaluator_name], check[:check_name]),
                    min: 1,
                    step: 1,
                    class: "raaf-input raaf-input--glass raaf-input--sm raaf-input--narrow"
                  )
                  span(class: "raaf-checkrow-hint") { "spans" }
                end

                # Consistency mode and trials (only for statistical evaluators)
                if check[:evaluator_type].to_s == "statistical"
                  consistency_mode = get_check_consistency_mode(check[:evaluator_name], check[:check_name])
                  trials = get_check_trials(check[:evaluator_name], check[:check_name])

                  # Consistency mode selector
                  div(class: "flex items-center gap-2") do
                    span(class: "raaf-checkrow-hint") { "Mode" }
                    select(
                      name: "evaluation_policy[check_configs][#{check_id}][consistency_mode]",
                      id: "check_#{check_id}_consistency_mode",
                      class: "raaf-input raaf-input--glass raaf-select raaf-input--sm",
                      title: "Historical: use past spans (cheap). Re-run: execute agent multiple times (accurate, higher cost)"
                    ) do
                      option(value: "historical", selected: consistency_mode == "historical") { "Historical" }
                      option(value: "rerun", selected: consistency_mode == "rerun") { "Re-run" }
                    end
                  end

                  # Trials
                  div(class: "flex items-center gap-2") do
                    span(class: "raaf-checkrow-hint") { "Runs" }
                    input(
                      type: "number",
                      name: "evaluation_policy[check_configs][#{check_id}][trials]",
                      id: "check_#{check_id}_trials",
                      value: trials,
                      min: 2,
                      max: 10,
                      step: 1,
                      class: "raaf-input raaf-input--glass raaf-input--sm raaf-input--narrow",
                      title: "Number of runs to compare for consistency check"
                    )
                  end
                end
              end
            end

            # Hidden fields
            input(type: "hidden", name: "evaluation_policy[check_configs][#{check_id}][evaluator_name]",
                  value: check[:evaluator_name])
            input(type: "hidden", name: "evaluation_policy[check_configs][#{check_id}][check_name]",
                  value: check[:check_name])
            input(type: "hidden", name: "evaluation_policy[check_configs][#{check_id}][agent_name]", value: agent_name)
            if check[:specific_evaluator].present?
              input(type: "hidden", name: "evaluation_policy[check_configs][#{check_id}][specific_evaluator]",
                    value: check[:specific_evaluator])
            end
          end
        end

        # Does this policy already have this check?
        #
        # The picker names a check `field:specific_evaluator`
        # (`confidence_scores:consistency`) because one field can be graded
        # several ways. A policy stores only the field, with the chosen
        # evaluator recorded alongside in `check_specific_evaluators`.
        #
        # These were compared directly, so nothing ever matched: opening any
        # policy showed every box unticked, and saving it dropped every check
        # it had. All five lookups shared the flaw, which is why they now share
        # one finder.
        def check_selected?(evaluator_name, check_name)
          !stored_check(evaluator_name, check_name).nil?
        end

        # @return [Array(Hash, String), nil] the policy's evaluator entry and
        #   the key its per-check settings are stored under
        def stored_check(evaluator_name, check_name)
          field, specific = check_name.to_s.split(":", 2)

          Array(@policy.evaluators).each do |entry|
            next unless value(entry, :name).to_s == evaluator_name.to_s

            checks = Array(value(entry, :checks)).map(&:to_s)
            key = [check_name.to_s, field].find { |candidate| checks.include?(candidate) }
            next unless key

            recorded = value(entry, :check_specific_evaluators).to_h[field]
            next if specific.present? && recorded.present? && recorded.to_s != specific.to_s

            return [entry, key]
          end

          nil
        end

        def value(entry, key)
          entry[key] || entry[key.to_s]
        end

        # Per-check setting, falling back to the evaluator's own, then a
        # default — the shape every one of these settings has.
        def check_setting(evaluator_name, check_name, map_key, fallback_key, default)
          entry, key = stored_check(evaluator_name, check_name)
          return default unless entry

          per_check = value(entry, map_key).to_h
          per_check[key] || per_check[key.to_sym] ||
            value(entry, fallback_key) ||
            entry.dig(:config, fallback_key) || entry.dig("config", fallback_key.to_s) ||
            default
        end

        def get_check_trials(evaluator_name, check_name)
          check_setting(evaluator_name, check_name, :check_trials, :trials, 3)
        end

        def get_check_sample_every_n(evaluator_name, check_name)
          check_setting(evaluator_name, check_name, :check_sample_every_n, :sample_every_n, 10)
        end

        def get_check_consistency_mode(evaluator_name, check_name)
          check_setting(evaluator_name, check_name, :check_consistency_modes,
                        :consistency_mode, "historical")
        end

        def get_check_trigger_mode(evaluator_name, check_name)
          check_setting(evaluator_name, check_name, :check_trigger_modes,
                        :trigger_mode, "automatic")
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
          return unless evaluator[:uses_llm]

          span(class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-purple-100 text-purple-800") do
            "Uses LLM"
          end
        end

        # One wording for a scoring method across the console — see
        # Atoms::Badge::CHECK_TYPE_LABELS.
        def format_evaluator_type(type)
          Atoms::Badge.check_type_label(type) || "Unknown"
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
          render(Organisms::Card.new(title: "Advanced", subtitle: "Optional")) do
            div(class: "raaf-field-grid") do
              render(Molecules::Field.new(label: "Max concurrent evaluations",
                                          for_id: "policy_max_concurrent_evaluations",
                                          hint: "Parallel evaluations. Default 5.")) do
                form.number_field(:max_concurrent_evaluations, class: "raaf-input raaf-input--glass", min: 1, max: 50,
                                                               value: @policy.max_concurrent_evaluations || 5)
              end

              render(Molecules::Field.new(label: "Max retries", for_id: "policy_max_retries",
                                          hint: "Retries for a failed evaluation. Default 3.")) do
                form.number_field(:max_retries, class: "raaf-input raaf-input--glass", min: 0, max: 10,
                                                value: @policy.max_retries || 3)
              end

              render(Molecules::Field.new(label: "Queue priority", for_id: "policy_priority",
                                          hint: "Higher runs first. 0–100, default 50.")) do
                form.number_field(:priority, class: "raaf-input raaf-input--glass", min: 0, max: 100,
                                             value: @policy.priority || 50)
              end

              render(Molecules::Field.new(label: "Queue name", for_id: "policy_queue_name",
                                          optional: true,
                                          hint: "Leave blank for the default queue.")) do
                form.text_field(:queue_name, class: "raaf-input raaf-input--glass", placeholder: "default")
              end
            end
          end
        end

        def render_actions(form)
          div(class: "raaf-form-actions raaf-split") do
            div(class: "raaf-cluster") do
              form.submit(@policy.persisted? ? "Save policy" : "Create policy", class: "raaf-button")
              render Atoms::Button.new(label: "Cancel", href: continuous_policies_path,
                                       variant: :secondary)
            end

            # link_to rather than button_to: button_to emits its own <form>,
            # and a form nested inside this one does not submit.
            if @policy.persisted?
              link_to(
                continuous_policy_path(@policy),
                class: "raaf-button raaf-button--danger",
                data: { turbo_method: :delete,
                        turbo_confirm: "Delete this policy and everything it has recorded?" }
              ) { "Delete policy" }
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
