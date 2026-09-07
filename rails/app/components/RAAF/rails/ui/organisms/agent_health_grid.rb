# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Organisms
        ##
        # AgentHealthGrid — the fleet at a glance.
        #
        # One tile per agent: a health dot, name and model, a sparkline of
        # recent runs, and the Errors / p95 / Spend triple. A failing agent's
        # tile takes a red edge so the eye finds it without reading.
        #
        # @example
        #   render Organisms::AgentHealthGrid.new(agents: [
        #     { name: "Company::EnrichAgent", model: "gpt-4o", runs: 3120,
        #       health: :bad, error_rate: "4.1%", p95: "8.2s", spend: "$41.20",
        #       series: [4, 6, 3, 9, 12], series_tips: ["09:00 · 4 runs", ...],
        #       href: agent_path }
        #   ])
        #
        class AgentHealthGrid < Base
          TITLE = "Agent health"

          # @param agents [Array<Hash>] see #tile for the keys used
          # @param note [String, nil] caption under the title
          def initialize(agents:, note: nil, class: nil, **attrs)
            @agents = agents
            @note = note
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template
            div(class: tokens(@class), **@attrs) do
              lead
              div(class: "raaf-agent-grid") { @agents.each { |agent| tile(agent) } }
            end
          end

          private

          def lead
            div(class: "raaf-section-lead") do
              div do
                h2(class: "raaf-section-lead-title") { TITLE }
                p(class: "raaf-section-lead-note") { @note } if @note
              end
              legend
            end
          end

          def legend
            div(class: "raaf-legend") do
              { ok: "Healthy", warn: "Degraded", bad: "Failing" }.each do |tone, label|
                span(class: "raaf-legend-item") do
                  render Atoms::Dot.new(tone: tone)
                  plain label
                end
              end
            end
          end

          def tile(agent)
            health = (agent[:health] || :ok).to_sym

            a(href: agent[:href] || "#",
              class: tokens("raaf-agent-tile", "raaf-agent-tile--#{health}")) do
              div(class: "raaf-agent-head") do
                render Atoms::Dot.new(tone: health, size: :lg, glow: true, pulse: health == :bad)
                div(class: "raaf-agent-id") do
                  span(class: "raaf-agent-name") { agent[:name] }
                  span(class: "raaf-agent-meta") { "#{agent[:model]} · #{agent[:runs]} runs" }
                end
                render Atoms::Icon.new("chevron-right", size: :sm, tone: :muted)
              end

              if agent[:series].present?
                render Molecules::Sparkbars.new(values: agent[:series], tones: agent[:series_tones].to_h,
                                                tips: Array(agent[:series_tips]),
                                                label: "Recent runs for #{agent[:name]}")
              end

              render Molecules::MetricTriple.new(metrics: [
                                                   { label: "Errors", value: agent[:error_rate],
                                                     tone: (health == :ok ? nil : health) },
                                                   { label: "p95", value: agent[:p95] },
                                                   { label: "Spend", value: agent[:spend] }
                                                 ])
            end
          end
        end
      end
    end
  end
end
