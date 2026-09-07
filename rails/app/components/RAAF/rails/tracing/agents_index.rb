# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      ##
      # Monitor › Agents: the fleet as one table.
      #
      # The Overview draws the same agents as tiles, which is the right shape
      # for six of them and unreadable at forty. This is the other half of that
      # screen from RAAF Console.dc.html: one row per agent, ranked by how much
      # it ran, with the health filters over the top so "what is failing" is a
      # click rather than a scan.
      #
      class AgentsIndex < BaseComponent
        # The design's legend, as filters. The values are the tones
        # {#health_for} returns, so the chip and the dot cannot disagree about
        # what "degraded" means.
        HEALTH_FILTERS = [
          { label: "All", value: nil },
          { label: "Healthy", value: "ok" },
          { label: "Degraded", value: "warn" },
          { label: "Failing", value: "bad" }
        ].freeze

        # The accessible name each health dot carries, so the state reaches a
        # screen reader that never sees the colour.
        HEALTH_STATES = { ok: "Healthy", warn: "Degraded", bad: "Failing" }.freeze

        # @param agents [Array<Hash>] rows from SpanRecord.agent_rollup
        def initialize(agents:, params: {})
          @agents = agents.to_a
          @params = params
        end

        def view_template
          div(class: "raaf-page") do
            filters
            body
          end
        end

        private

        # Columns and fr weights taken from RAAF Console.dc.html.
        #
        # Its "Spend 24h" header is just "Spend" here: the topbar owns the
        # window now, and a column that says 24h while the range says 7d is
        # worse than one that says neither.
        def columns
          [
            { label: "Agent", span: 2.3 },
            { label: "Kind", span: 0.9 },
            { label: "Model", span: 1.05 },
            { label: "Runs", span: 0.65, align: :right },
            { label: "Errors", span: 0.7, align: :right },
            { label: "p95", span: 0.65, align: :right },
            { label: "Spend", span: 0.95, align: :right }
          ]
        end

        # Chips left, the kind summary right — the design's header strip. The
        # summary counts the whole fleet, not the filtered view, so it stays a
        # fixed point to filter against.
        def filters
          render(Molecules::FilterBar.new(chips: health_chips, panel: true)) do
            render Atoms::Mono.new(fleet_summary, tone: :muted)
          end
        end

        def health_chips
          counts = @agents.group_by { |agent| health_for(agent[:error_rate]).to_s }
                          .transform_values(&:size)

          HEALTH_FILTERS.map do |filter|
            { label: filter[:label],
              active: @params[:health].presence == filter[:value],
              count: (filter[:value] ? counts.fetch(filter[:value], 0) : @agents.size).nonzero?,
              href: dashboard_agents_path(filter_params(health: filter[:value])) }
          end
        end

        # Keeps the range, so filtering by health does not silently reset the
        # window the numbers were read over.
        def filter_params(overrides)
          { range: @params[:range], health: @params[:health] }
            .merge(overrides).compact.reject { |_, value| value.to_s.empty? }
        end

        def visible_agents
          @visible_agents ||=
            if @params[:health].present?
              @agents.select { |agent| health_for(agent[:error_rate]).to_s == @params[:health] }
            else
              @agents
            end
        end

        def fleet_summary
          return "no agents" if @agents.empty?

          @agents.group_by { |agent| agent[:kind].to_s }
                 .sort_by { |kind, group| [-group.size, kind] }
                 .map { |kind, group| pluralize(group.size, kind) }
                 .join(" · ")
        end

        def body
          return empty_state if visible_agents.empty?

          render(Organisms::Card.new(flush: true)) do
            render(Organisms::DataGrid.new(columns: columns)) do |grid|
              visible_agents.each { |agent| row(grid, agent) }
            end
          end
        end

        def row(grid, agent)
          health = health_for(agent[:error_rate])

          grid.row(href: agent_spans_path(agent), cells: [
                     { value: name_cell(agent, health), primary: true },
                     { value: Atoms::KindBadge.new(agent[:kind]) },
                     { value: Atoms::Mono.new(agent[:model] || "—", tone: :muted) },
                     { value: Atoms::Mono.new(number(agent[:runs])), align: :right },
                     { value: error_cell(agent, health), align: :right },
                     { value: Atoms::Mono.new(format_duration(agent[:p95_ms])), align: :right },
                     { value: Atoms::Mono.new(spend(agent[:spend])), align: :right }
                   ])
        end

        def name_cell(agent, health)
          Molecules::DotLabel.new(agent[:name], tone: health, pulse: health == :bad,
                                                state: HEALTH_STATES.fetch(health))
        end

        # A rate with no failures behind it reads better as a plain zero than
        # as "0.0%" in the same red the failing rows use.
        def error_cell(agent, health)
          return Atoms::Mono.new("0%", tone: :muted) if agent[:errors].to_i.zero?

          Atoms::Mono.new("#{agent[:error_rate]}%", tone: health)
        end

        # Sub-cent spend rounds to $0.00, which reads as free rather than as
        # small, so it keeps the digits that show it is not.
        #
        # `%` rather than Kernel#format: phlex-rails defines its own `format`
        # on the component (the request format), so calling the Kernel one by
        # name inside a component raises ArgumentError at render time.
        def spend(amount)
          value = amount.to_f
          return "—" if value.zero?
          return "<$0.01" if value < 0.005

          "$#{'%.2f' % value}"
        end

        # The agent's own runs, in the span list — the nearest thing to the
        # design's agent detail screen, which the engine does not route yet.
        def agent_spans_path(agent)
          tracing_spans_path({ kind: agent[:kind], search: agent[:name],
                               range: @params[:range].presence }.compact)
        end

        def empty_state
          render Molecules::EmptyState.new(
            icon: "cpu",
            title: @params[:health].present? ? "No agents in that state" : "No agents traced yet",
            text: "Agent and pipeline spans recorded in the selected range appear here."
          )
        end

        def number(value)
          value.to_i.to_s.reverse.scan(/\d{1,3}/).join(",").reverse
        end
      end
    end
  end
end
