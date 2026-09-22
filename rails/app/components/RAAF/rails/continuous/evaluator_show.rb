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
      #
      # It rendered in the light theme, and it was in no menu; both are fixed
      # under #1023, in that order — the nav should not lead from a dark
      # section into a white card.
      class EvaluatorShow < RAAF::Rails::Tracing::BaseComponent
        CHECK_COLUMNS = [
          { label: "Check", span: 2.4 },
          { label: "Field", span: 1.4 },
          { label: "Type", span: 0.9, align: :right }
        ].freeze

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
          div(class: "raaf-page") do
            header
            checks_card
            details_card
            policies_card
            span_panels
          end
        end

        POLICY_COLUMNS = [
          { label: "Policy", span: 2.4 },
          { label: "State", span: 0.8, align: :right }
        ].freeze

        private

        def header
          render Organisms::RecordHead.new(
            parent: { label: "Evaluators", href: continuous_evaluators_path },
            title: @evaluator[:name].to_s,
            mono: true,
            description: @evaluator[:description].presence,
            badges: [type_badge].compact,
            meta: @evaluator[:class_name].to_s,
            stats: head_stats
          )
        end

        def head_stats
          [{ label: "Checks", value: @evaluator[:checks].to_a.size.to_s },
           { label: "Policies", value: @policies.size.to_s },
           { label: "Costs a call", value: judged_by_llm? ? "yes" : "no",
             tone: judged_by_llm? ? :warn : nil }]
        end

        def type_badge
          label = self.class.format_type(@evaluator[:type])
          return nil if label.nil?

          Atoms::Badge.for_check_type(@evaluator[:type], size: :sm)
        end

        # ── Checks ────────────────────────────────────────────────────────

        def checks_card
          render(Organisms::Card.new(
                   title: "Checks",
                   subtitle: "What one evaluation of this evaluator grades, field by field.",
                   flush: true
                 )) do
            render(Organisms::DataGrid.new(
                     columns: CHECK_COLUMNS,
                     empty: { icon: "sliders", title: "No checks",
                              text: "This evaluator declares no checks, so a policy " \
                                    "naming it would grade nothing." }
                   )) do |grid|
              @evaluator[:checks].to_a.each { |check| check_row(grid, check) }
            end
          end
        end

        def check_row(grid, check)
          grid.row(cells: [
                     { value: Molecules::TitleMeta.new(check_name(check),
                                                       check[:description].presence),
                       primary: true },
                     { value: Atoms::Mono.new(check[:field_name].to_s, tone: :muted) },
                     { value: Atoms::Badge.for_check_type(check[:check_type], size: :sm),
                       align: :right }
                   ])
        end

        def check_name(check)
          check[:display_name].presence || check[:field_name].to_s.humanize
        end

        # ── Details ───────────────────────────────────────────────────────

        def details_card
          render(Organisms::Card.new(title: "Details", flush: true)) do
            render Molecules::KeyValueList.new(pairs: detail_pairs, layout: :rows,
                                               mono: true, flush: true)
          end
        end

        def detail_pairs
          options = @evaluator[:configurable_options].to_a

          { "Type" => self.class.format_type(@evaluator[:type]) || "—",
            "Class" => @evaluator[:class_name].to_s,
            "Agent" => @evaluator[:agent_name].presence || "—",
            "Billed model call" => judged_by_llm? ? "yes" : "no",
            "Options" => options.any? ? options.map(&:to_s).join(", ") : "—" }
        end

        # ── Policies ──────────────────────────────────────────────────────

        def policies_card
          render(Organisms::Card.new(title: "Graded by", subtitle: policies_subtitle,
                                     flush: true)) do
            render(Organisms::DataGrid.new(
                     columns: POLICY_COLUMNS,
                     empty: { icon: "clipboard-check", title: "No policy names this evaluator",
                              text: "Nothing grades with it, and nothing will until a " \
                                    "policy does — being registered is not being used." }
                   )) do |grid|
              @policies.each { |policy| policy_row(grid, policy) }
            end
          end
        end

        def policies_subtitle
          return nil if @policies.empty?

          "#{pluralize(@policies.size, 'policy')} names this evaluator"
        end

        def policy_row(grid, policy)
          grid.row(href: continuous_policy_path(policy), cells: [
                     { value: policy.name.to_s, primary: true },
                     { value: Atoms::StatusBadge.new(policy.active? ? "active" : "inactive"),
                       align: :right }
                   ])
        end

        # ── Grade a span now ──────────────────────────────────────────────

        # One panel per policy, because "grade this now" is a question only a
        # policy can answer: the checks that run, the cap and the counter all
        # belong to it, not to the evaluator.
        def span_panels
          return if @policies.empty?

          @policies.each do |policy|
            render(Organisms::Card.new(title: "Grade a span with #{policy.name}",
                                       flush: true)) do
              render MatchingSpansPanel.new(policy: policy, spans: @spans_by_policy[policy.id].to_a)
            end
          end

          overflow_note unless @unpanelled.zero?
        end

        def overflow_note
          render Atoms::Text.new(
            "#{pluralize(@unpanelled, 'further policy')} also uses this evaluator; " \
            "open it from the list to grade a span with it.",
            size: :sm, tone: :muted
          )
        end

        # The evaluator's own type is often unset, so the checks are asked
        # instead: each one names the evaluator that runs it, and an LLM judge
        # among them is what makes an evaluation cost a model call.
        def judged_by_llm?
          return true if @evaluator[:uses_llm]

          @evaluator[:checks].to_a.any? { |check| check[:check_type].to_s == "llm_judge" }
        end
      end
    end
  end
end
