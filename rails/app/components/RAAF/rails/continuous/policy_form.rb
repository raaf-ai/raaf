# frozen_string_literal: true

module RAAF
  module Rails
    module Continuous
      class PolicyForm < Phlex::HTML
        include Phlex::Rails::Helpers::FormWith
        include Phlex::Rails::Helpers::LinkTo

        def initialize(policy:, evaluators: [], agents: [], environments: [])
          @policy = policy
          @evaluators = evaluators
          @agents = agents
          @environments = environments
        end

        def view_template
          div(class: "container-fluid") do
            render_header
            render_form
          end
        end

        private

        def render_header
          div(class: "d-flex justify-content-between flex-wrap flex-md-nowrap align-items-center pt-3 pb-2 mb-3 border-bottom") do
            div do
              h1(class: "h2") { @policy.persisted? ? "Edit Policy" : "New Policy" }
              p(class: "text-muted") { "Configure continuous evaluation policy" }
            end
          end
        end

        def render_form
          div(class: "card") do
            div(class: "card-body") do
              form_with(model: @policy, url: form_url, class: "needs-validation") do |f|
                render_basic_fields(f)
                render_targeting_fields(f)
                render_sampling_fields(f)
                render_limits_fields(f)
                render_evaluator_selection(f)
                render_advanced_fields(f)
                render_actions(f)
              end
            end
          end
        end

        def render_basic_fields(form)
          div(class: "mb-4") do
            h5(class: "card-title") { "Basic Information" }

            div(class: "mb-3") do
              form.label(:name, "Policy Name", class: "form-label")
              form.text_field(:name, class: "form-control", required: true, placeholder: "e.g., Production Quality Check")
            end

            div(class: "mb-3") do
              form.label(:description, "Description (optional)", class: "form-label")
              form.text_area(:description, class: "form-control", rows: 3, placeholder: "Describe what this policy monitors...")
            end

            div(class: "form-check mb-3") do
              form.check_box(:active, class: "form-check-input")
              form.label(:active, "Active (evaluations will run)", class: "form-check-label")
            end
          end
        end

        def render_targeting_fields(form)
          div(class: "mb-4") do
            h5(class: "card-title") { "Targeting" }

            div(class: "mb-3") do
              form.label(:agent_name, "Agent Name", class: "form-label")
              if @agents.any?
                form.select(:agent_name,
                  [["All agents", ""]] + @agents.map { |a| [a, a] },
                  {},
                  class: "form-select")
              else
                form.text_field(:agent_name, class: "form-control", placeholder: "Leave blank for all agents")
              end
              small(class: "form-text text-muted") { "Filter spans by agent name. Leave blank to evaluate all agents." }
            end

            div(class: "mb-3") do
              form.label(:environment, "Environment", class: "form-label")
              if @environments.any?
                form.select(:environment,
                  [["All environments", ""]] + @environments.map { |e| [e, e] },
                  {},
                  class: "form-select")
              else
                form.text_field(:environment, class: "form-control", placeholder: "e.g., production, staging")
              end
              small(class: "form-text text-muted") { "Filter by environment. Leave blank for all environments." }
            end

            div(class: "mb-3") do
              form.label(:model_pattern, "Model Pattern (optional)", class: "form-label")
              form.text_field(:model_pattern, class: "form-control", placeholder: "e.g., gpt-4*, claude-*")
              small(class: "form-text text-muted") { "Regex pattern to filter by model name. Leave blank for all models." }
            end
          end
        end

        def render_sampling_fields(form)
          div(class: "mb-4") do
            h5(class: "card-title") { "Sampling Configuration" }

            div(class: "mb-3") do
              form.label(:sampling_mode, "Sampling Mode", class: "form-label")
              form.select(:sampling_mode,
                [
                  ["All spans", "all"],
                  ["Percentage-based", "percentage"],
                  ["Every Nth span", "every_n"]
                ],
                {},
                class: "form-select",
                data: { action: "change->policy-form#updateSamplingFields" })
              small(class: "form-text text-muted") { "How to sample spans for evaluation" }
            end

            div(class: "mb-3", id: "sample-rate-field") do
              form.label(:sample_rate, "Sample Rate (%)", class: "form-label")
              form.number_field(:sample_rate, class: "form-control", min: 0, max: 100, step: 0.1, placeholder: "10.0")
              small(class: "form-text text-muted") { "Percentage of spans to evaluate (0-100)" }
            end

            div(class: "mb-3", id: "sample-every-n-field") do
              form.label(:sample_every_n, "Evaluate Every N Spans", class: "form-label")
              form.number_field(:sample_every_n, class: "form-control", min: 1, placeholder: "10")
              small(class: "form-text text-muted") { "Evaluate every Nth span (e.g., every 10th span)" }
            end
          end
        end

        def render_limits_fields(form)
          div(class: "mb-4") do
            h5(class: "card-title") { "Limits & Retention" }

            div(class: "mb-3") do
              form.label(:max_daily_evaluations, "Max Daily Evaluations (optional)", class: "form-label")
              form.number_field(:max_daily_evaluations, class: "form-control", min: 0, placeholder: "1000")
              small(class: "form-text text-muted") { "Maximum evaluations per day. Leave blank for unlimited." }
            end

            div(class: "mb-3") do
              form.label(:retention_days, "Result Retention (days)", class: "form-label")
              form.number_field(:retention_days, class: "form-control", min: 1, value: 30)
              small(class: "form-text text-muted") { "How long to keep evaluation results (default: 30 days)" }
            end
          end
        end

        def render_evaluator_selection(form)
          div(class: "mb-4") do
            h5(class: "card-title") { "Evaluators" }

            if @evaluators.any?
              div(class: "list-group") do
                @evaluators.each do |evaluator|
                  render_evaluator_checkbox(form, evaluator)
                end
              end
            else
              div(class: "alert alert-warning") do
                strong { "No evaluators available" }
                p(class: "mb-0") { "Please register evaluators before creating policies." }
              end
            end
          end
        end

        def render_evaluator_checkbox(form, evaluator)
          div(class: "list-group-item") do
            div(class: "form-check") do
              # This assumes evaluator is a hash with keys like name, type, cost
              checkbox_tag("policy[evaluator_ids][]", evaluator[:id],
                @policy.evaluator_ids&.include?(evaluator[:id]),
                class: "form-check-input",
                id: "evaluator_#{evaluator[:id]}")
              label(for: "evaluator_#{evaluator[:id]}", class: "form-check-label w-100") do
                div(class: "d-flex justify-content-between align-items-start") do
                  div do
                    strong { evaluator[:name] }
                    br
                    small(class: "text-muted") { evaluator[:description] }
                  end
                  div do
                    render_evaluator_badges(evaluator)
                  end
                end
              end
            end
          end
        end

        def render_evaluator_badges(evaluator)
          span(class: "badge bg-#{evaluator_type_color(evaluator[:type])} me-1") { evaluator[:type] }
          if evaluator[:uses_llm]
            span(class: "badge bg-warning text-dark") { "Uses LLM" }
          end
        end

        def render_advanced_fields(form)
          div(class: "mb-4") do
            h5(class: "card-title") do
              plain "Advanced Settings "
              small(class: "text-muted") { "(optional)" }
            end

            div(class: "mb-3") do
              form.label(:priority, "Queue Priority", class: "form-label")
              form.number_field(:priority, class: "form-control", min: 0, max: 100, value: 50)
              small(class: "form-text text-muted") { "Higher priority evaluations run first (0-100, default: 50)" }
            end

            div(class: "mb-3") do
              form.label(:queue_name, "Queue Name (optional)", class: "form-label")
              form.text_field(:queue_name, class: "form-control", placeholder: "default")
              small(class: "form-text text-muted") { "Solid Queue queue name. Leave blank for default queue." }
            end
          end
        end

        def render_actions(form)
          div(class: "d-flex justify-content-between mt-4") do
            div do
              form.submit("Save Policy", class: "btn btn-primary")
              link_to("Cancel", continuous_policies_path, class: "btn btn-outline-secondary ms-2")
            end

            if @policy.persisted?
              link_to("Delete Policy",
                continuous_policy_path(@policy),
                method: :delete,
                class: "btn btn-outline-danger",
                data: { confirm: "Are you sure? This will delete all associated data." })
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

        def evaluator_type_color(type)
          case type.to_s
          when "rule" then "success"
          when "statistical" then "info"
          when "llm_judge" then "warning"
          else "secondary"
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
