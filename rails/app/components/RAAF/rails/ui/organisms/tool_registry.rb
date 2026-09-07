# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Organisms
        ##
        # ToolRegistry — every tool the agents can call, as cards.
        #
        # The grid reflows on `auto-fill` rather than breakpoints, so a
        # registry of three tools and one of thirty both look deliberate. Each
        # card closes with a `MetricTriple`: calls, error rate, p95.
        #
        # @example
        #   render Organisms::ToolRegistry.new(tools: [
        #     { name: "crm_upsert", icon: "database-add", tag: "write", tone: :bad,
        #       description: "Upserts enriched company records into the CRM.",
        #       calls: "8.1k", error_rate: "8.1%", p95: "4.0s" }
        #   ])
        #
        class ToolRegistry < Base
          TONES = %i[ok warn bad info neutral].freeze

          # @param tools [Array<Hash>] :name, :icon, :tag, :tone, :description,
          #   :calls, :error_rate, :p95, :href
          # @param empty [Hash, nil] arguments for Molecules::EmptyState
          def initialize(tools:, empty: nil, class: nil, **attrs)
            @tools = Array(tools)
            @empty = empty
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template
            if @tools.empty?
              render Molecules::EmptyState.new(**(@empty || default_empty))
              return
            end

            div(class: tokens("raaf-tools", @class), **@attrs) do
              @tools.each { |tool| card(tool) }
            end
          end

          private

          def default_empty
            { icon: "tools", title: "No tools recorded",
              text: "No tool spans have been traced in this time range." }
          end

          def card(tool)
            tag = tool[:href] ? :a : :div
            attributes = { class: "raaf-tool-card" }
            attributes[:href] = tool[:href] if tool[:href]

            public_send(tag, **attributes) do
              head(tool)
              p(class: "raaf-tool-desc") { tool[:description] } if tool[:description]
              footer(tool)
            end
          end

          def head(tool)
            div(class: "raaf-tool-head") do
              render Atoms::Icon.new(tool[:icon] || "wrench-adjustable", tone: :accent)
              span(class: "raaf-tool-name") { tool[:name] }
              next unless tool[:tag]

              span(class: tokens("raaf-tool-tag",
                                 modifier("raaf-tool-tag", tool[:tone], TONES))) { tool[:tag] }
            end
          end

          def footer(tool)
            render Molecules::MetricTriple.new(metrics: [
                                                 { label: "Calls", value: tool[:calls] || "—" },
                                                 { label: "Errors", value: tool[:error_rate] || "—",
                                                   tone: tool[:error_tone] },
                                                 { label: "p95", value: tool[:p95] || "—" }
                                               ])
          end
        end
      end
    end
  end
end
