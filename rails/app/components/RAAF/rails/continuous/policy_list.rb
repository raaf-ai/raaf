# frozen_string_literal: true

module RAAF
  module Rails
    module Continuous
      ##
      # The policy listing, from RAAF Continuous.dc.html: a row of headline
      # stats, a bare filter rail with the count opposite it, and the table.
      #
      # This screen was still the original Tailwind markup — a white card on a
      # grey page, inside a console that is dark everywhere else. It is now on
      # the same library as the Tracing screens, so a change to a badge or a
      # column happens in one place for all of them.
      #
      class PolicyList < RAAF::Rails::Tracing::BaseComponent
        # Columns and fr weights taken from RAAF Continuous.dc.html.
        COLUMNS = [
          { label: "Policy", span: 2.2 },
          { label: "Agent", span: 1.4 },
          { label: "Evaluators", span: 1.5 },
          { label: "Sample", span: 0.6, align: :right },
          { label: "Status", span: 0.8, align: :right },
          { label: "Last run", span: 0.85, align: :right },
          { label: "", span: 0.7, align: :right }
        ].freeze

        FILTERS = [
          { label: "All", value: nil },
          { label: "Active", value: "true" },
          { label: "Paused", value: "false" }
        ].freeze

        # @param policies [Enumerable<EvaluationPolicy>] the current page
        # @param stats [Hash] :total, :active, :evaluated_today, :daily_cap
        # @param last_runs [Hash] policy id => the time it last produced a result
        def initialize(policies:, stats: {}, last_runs: {}, params: {})
          @policies = policies
          @stats = stats || {}
          @last_runs = last_runs || {}
          @params = params
        end

        def view_template
          div(class: "raaf-page") do
            headline
            filters
            table
          end
        end

        private

        def headline
          render Organisms::MetricGrid.new(metrics: [
                                             { label: "Policies", value: @stats[:total].to_s, icon: "clipboard-check",
                                               hint: "configured" },
                                             { label: "Active", value: @stats[:active].to_s, icon: "play-circle",
                                               tone: :success, hint: "evaluating new spans" },
                                             { label: "Evaluated today", value: @stats[:evaluated_today].to_s, icon: "check2-circle",
                                               hint: "across every policy" },
                                             { label: "Daily cap", value: @stats[:daily_cap].to_s, icon: "shield-check",
                                               hint: "evaluations a day, all policies" }
                                           ])
        end

        # Plain pills on the page — the design gives this rail neither the
        # Traces container nor the Spans badge outline.
        def filters
          render(Molecules::FilterBar.new(chips: filter_chips, grouped: false)) do
            render Atoms::Mono.new(count_label, tone: :muted)
          end
        end

        def filter_chips
          FILTERS.map do |filter|
            { label: filter[:label],
              active: @params[:active].presence == filter[:value],
              href: filtered_path(filter[:value]) }
          end
        end

        def filtered_path(value)
          value ? continuous_policies_path(active: value) : continuous_policies_path
        end

        def count_label
          pluralize(@stats[:total].to_i, "policy")
        end

        def table
          render(Organisms::Card.new(flush: true)) do
            render(Organisms::DataGrid.new(
                     columns: COLUMNS,
                     empty: { icon: "clipboard-check", title: "No policies",
                              text: "Nothing is evaluating spans automatically yet." }
                   )) do |grid|
              @policies.each { |policy| row(grid, policy) }
            end
          end
        end

        def row(grid, policy)
          grid.row(href: continuous_policy_path(policy), data: { policy_id: policy.id }, cells: [
                     { value: Molecules::TitleMeta.new(policy.name, trigger_for(policy)) },
                     { value: Atoms::Mono.new(policy.agent_name.presence || "any agent", tone: :muted) },
                     { value: evaluators_for(policy) },
                     { value: Atoms::Mono.new(sample_for(policy)), align: :right },
                     { value: Atoms::StatusBadge.new(policy.active? ? "active" : "paused"),
                       align: :right },
                     { value: Atoms::Mono.new(time_ago(@last_runs[policy.id]), tone: :muted),
                       align: :right },
                     { value: toggle_for(policy), align: :right, interactive: true }
                   ])
        end

        # Pausing is the one thing this screen does rather than reports, and it
        # belongs here: a policy is judged against the other five, so the
        # decision to stop one is taken while looking at the list. The cell is
        # marked interactive, which moves the row's link into the first cell —
        # a form cannot live inside an anchor.
        def toggle_for(policy)
          action = if policy.active?
                     { label: "Pause", href: deactivate_continuous_policy_path(policy) }
                   else
                     { label: "Resume", href: activate_continuous_policy_path(policy) }
                   end

          Molecules::RowActions.new(actions: [action.merge(method: :post)])
        end

        # The second line under the name: what makes this policy fire.
        def trigger_for(policy)
          scope = policy.environment.presence
          scope = nil if scope == "all"

          [policy.description.presence, scope && "#{scope} only"].compact.join(" · ").presence ||
            "every environment"
        end

        # The evaluators a policy names, not the checks inside them: a policy
        # stores one entry per evaluator, and each of those declares several
        # checks of its own. The detail page lists those.
        def evaluators_for(policy)
          names = Array(policy.evaluators).filter_map do |evaluator|
            evaluator.is_a?(Hash) ? (evaluator["name"] || evaluator[:name]) : evaluator
          end

          return Atoms::Mono.new("—", tone: :muted) if names.empty?

          Molecules::TagList.new(names, limit: 3)
        end

        # Sampling reads as a rate when it is one, and as a stride when the
        # policy takes every Nth span instead.
        def sample_for(policy)
          case policy.sampling_mode
          when "every_n" then "1/#{policy.sample_every_n}"
          when "percentage" then "#{policy.sample_rate}%"
          else "all"
          end
        end
      end
    end
  end
end
