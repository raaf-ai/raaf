# frozen_string_literal: true

module RAAF
  module Rails
    module Continuous
      # One evaluator: what it checks, which policies grade with it, and the
      # recent spans each of those policies could grade right now.
      #
      # This route answered HTML with no template, so the page did not exist —
      # which is why "run this evaluator on a recent span" had no home. It has
      # one now: every policy naming this evaluator brings its own panel of
      # matching spans, so the run starts from the evaluator you were reading
      # about rather than from a span you had to go and find.
      class EvaluatorShow < RAAF::Rails::Tracing::BaseComponent
        # Human wording for the three types the registry reports.
        #
        # An evaluator that declares `evaluator_type` and leaves it unset comes
        # back with an empty string rather than a fallback, which is most of
        # them in practice. That is reported as unknown instead of rendered as
        # an empty badge.
        #
        # The wording itself belongs to the badge: a result screen and an
        # evaluator screen naming the same thing two ways is how "LLM Judge"
        # and "LLM judge" both came to exist.
        def self.format_type(type)
          RAAF::Rails::Ui::Atoms::Badge.check_type_label(type)
        end

        # @param evaluator [Hash] one entry from EvaluatorDiscovery#evaluator_details
        # @param policies [Array<RAAF::Eval::Models::EvaluationPolicy>] policies naming it
        # @param spans_by_policy [Hash{Integer => Array}] matching spans, keyed by policy id
        # @param unpanelled [Integer] policies past the panel cap, named rather than dropped silently
        def initialize(evaluator:, policies: [], spans_by_policy: {}, unpanelled: 0)
          @evaluator = evaluator
          @policies = policies
          @spans_by_policy = spans_by_policy
          @unpanelled = unpanelled
        end

        def view_template
          div(class: "p-6") do
            render_header
            div(class: "grid grid-cols-1 lg:grid-cols-3 gap-6") do
              div(class: "lg:col-span-2 space-y-6") do
                render_checks
                render_span_panels
              end
              div(class: "space-y-6") do
                render_details_sidebar
                render_policies_sidebar
              end
            end
          end
        end

        private

        def render_header
          div(class: "sm:flex sm:items-center sm:justify-between mb-6 pb-4 border-b border-gray-200") do
            div do
              div(class: "flex items-center gap-3") do
                h1(class: "text-2xl font-bold text-gray-900") { @evaluator[:name].to_s }
                render_type_badge
              end
              p(class: "text-sm text-gray-500 mt-1") { @evaluator[:description] } if @evaluator[:description].present?
            end
            link_to(
              "All Evaluators",
              continuous_evaluators_path,
              class: "text-sm text-blue-600 hover:text-blue-500 flex-shrink-0"
            )
          end
        end

        def render_checks
          checks = @evaluator[:checks].to_a

          div(class: "bg-white shadow rounded-lg overflow-hidden") do
            div(class: "px-4 py-5 sm:px-6 border-b border-gray-200") do
              h3(class: "text-lg font-medium text-gray-900") { "Checks" }
              p(class: "text-sm text-gray-500 mt-1") do
                "What one evaluation of this evaluator grades, field by field."
              end
            end

            if checks.empty?
              div(class: "px-4 py-8 text-center text-sm text-gray-500") do
                "This evaluator declares no checks, so a policy naming it would grade nothing."
              end
            else
              div(class: "divide-y divide-gray-200") do
                checks.each { |check| render_check(check) }
              end
            end
          end
        end

        def render_check(check)
          div(class: "px-4 py-3 flex items-start justify-between gap-3") do
            div(class: "min-w-0 flex-1") do
              span(class: "text-sm font-medium text-gray-900") do
                plain(check[:display_name].presence || check[:field_name].to_s.humanize)
              end
              p(class: "text-xs text-gray-500 mt-0.5") { check[:description] } if check[:description].present?
              p(class: "text-xs text-gray-400 mt-0.5 font-mono") { check[:field_name].to_s }
            end
            span(class: "flex-shrink-0") { render_check_type_badge(check[:check_type]) }
          end
        end

        # One panel per policy, because "grade this now" is a question only a
        # policy can answer: the checks that run, the cap and the counter all
        # belong to it, not to the evaluator.
        def render_span_panels
          return render_unused_notice if @policies.empty?

          @policies.each do |policy|
            div do
              h3(class: "text-sm font-medium text-gray-700 mb-2") do
                link_to(policy.name, continuous_policy_path(policy), class: "text-blue-600 hover:text-blue-500")
              end
              render MatchingSpansPanel.new(policy: policy, spans: @spans_by_policy[policy.id].to_a)
            end
          end

          return if @unpanelled.zero?

          p(class: "text-xs text-gray-500") do
            "#{pluralize(@unpanelled, 'further policy')} also uses this evaluator; " \
              "open it from the list to grade a span with it."
          end
        end

        def render_unused_notice
          div(class: "bg-white shadow rounded-lg px-4 py-8 text-center") do
            i(class: "bi-exclamation-triangle text-amber-500 text-2xl")
            p(class: "text-sm text-gray-700 mt-2") { "No policy names this evaluator." }
            p(class: "text-xs text-gray-500 mt-1") do
              "Nothing grades with it, and nothing will until a policy does — being registered is not being used."
            end
            link_to(
              "Policies",
              continuous_policies_path,
              class: "inline-flex items-center gap-1 mt-3 text-sm text-blue-600 hover:text-blue-500"
            )
          end
        end

        def render_details_sidebar
          div(class: "bg-white shadow rounded-lg overflow-hidden") do
            div(class: "px-4 py-5 sm:px-6 border-b border-gray-200") do
              h3(class: "text-lg font-medium text-gray-900") { "Details" }
            end
            div(class: "px-4 py-4 space-y-3") do
              detail_row("Type", self.class.format_type(@evaluator[:type]) || "—")
              detail_row("Class", @evaluator[:class_name].to_s)
              detail_row("Agent", @evaluator[:agent_name].presence || "—")
              detail_row("Billed model call", judged_by_llm? ? "Yes" : "No")

              options = @evaluator[:configurable_options].to_a
              detail_row("Options", options.any? ? options.map(&:to_s).join(", ") : "—")
            end
          end
        end

        def render_policies_sidebar
          div(class: "bg-white shadow rounded-lg overflow-hidden") do
            div(class: "px-4 py-5 sm:px-6 border-b border-gray-200") do
              h3(class: "text-lg font-medium text-gray-900") { "Graded by" }
            end

            if @policies.empty?
              div(class: "px-4 py-4 text-sm text-gray-500") { "No policy." }
            else
              div(class: "divide-y divide-gray-200") do
                @policies.each do |policy|
                  link_to(
                    continuous_policy_path(policy),
                    class: "flex items-center justify-between px-4 py-3 hover:bg-gray-50"
                  ) do
                    span(class: "text-sm text-gray-700 truncate") { policy.name }
                    render_policy_state_badge(policy)
                  end
                end
              end
            end
          end
        end

        def detail_row(label, value)
          div(class: "flex items-start justify-between gap-3") do
            span(class: "text-sm text-gray-500 flex-shrink-0") { label }
            span(class: "text-sm text-gray-900 text-right break-all") { value.to_s }
          end
        end

        # The evaluator's own type is often unset, so the checks are asked
        # instead: each one names the evaluator that runs it, and an LLM judge
        # among them is what makes an evaluation cost a model call.
        def judged_by_llm?
          return true if @evaluator[:uses_llm]

          @evaluator[:checks].to_a.any? { |check| check[:check_type].to_s == "llm_judge" }
        end

        def render_type_badge
          label = self.class.format_type(@evaluator[:type])
          return if label.nil?

          classes = case @evaluator[:type].to_s
                    when "llm_judge" then "bg-purple-100 text-purple-800"
                    when "statistical" then "bg-blue-100 text-blue-800"
                    else "bg-gray-100 text-gray-700"
                    end

          span(class: "inline-flex items-center px-2 py-0.5 rounded text-xs font-medium #{classes}") do
            label
          end
        end

        def render_check_type_badge(check_type)
          label = self.class.format_type(check_type)
          return if label.nil?

          classes = case check_type.to_s
                    when "llm_judge" then "bg-purple-100 text-purple-800"
                    when "statistical" then "bg-blue-100 text-blue-800"
                    else "bg-gray-100 text-gray-700"
                    end

          span(class: "inline-flex items-center px-1.5 py-0.5 rounded text-xs font-medium #{classes}") do
            label
          end
        end

        def render_policy_state_badge(policy)
          if policy.active?
            span(class: "inline-flex items-center px-1.5 py-0.5 rounded text-xs font-medium bg-green-100 text-green-800") do
              "Active"
            end
          else
            span(class: "inline-flex items-center px-1.5 py-0.5 rounded text-xs font-medium bg-gray-100 text-gray-600") do
              "Inactive"
            end
          end
        end
      end
    end
  end
end
