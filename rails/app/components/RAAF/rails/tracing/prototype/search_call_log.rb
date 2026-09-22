# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      module Prototype
        ##
        # PROTOTYPE — throwaway. Variant A: the call log.
        #
        # The position: a search call is a span with better columns, and the
        # plugin's whole job is to say which columns and how to render the
        # payload. The list unit is one provider call. It reads like the Spans
        # screen because it is the Spans screen with search's own vocabulary
        # substituted for the generic key/value dump #1089 found there.
        #
        # What this variant asks the contract for: a column set, a row
        # renderer, a payload renderer, and one facet.
        #
        class SearchCallLog < BaseComponent
          include Figures

          def initialize(calls:, params: {})
            @calls = calls
            @params = params
            @provider = params[:provider].presence
          end

          def view_template
            div(class: "raaf-page") do
              render Molecules::Alert.new(:info, **thesis)
              render Organisms::StatGrid.new(stats: kpis)
              facets
              selected_call_panel if selected
              table
            end

            render Switcher.new(current: "A", note: "The list unit here is one provider call.")
          end

          private

          def thesis
            { title: "Variant A — Call log",
              text: "One provider call per row. Search is a span with search's own columns; " \
                    "the plugin declares the column set, the row renderer and the payload renderer. " \
                    "Click a row to see what the detail view would hold." }
          end

          def visible
            @visible ||= @provider ? @calls.select { |c| c.provider == @provider } : @calls
          end

          def kpis
            [
              { label: "Spend", value: usd(visible.sum(&:cost_usd)), icon: "cash-stack", tone: :accent,
                note: "#{count(visible.size)} calls in the window" },
              { label: "Calls", value: count(visible.size), icon: "search", tone: :accent,
                note: "#{count(visible.map(&:query).uniq.size)} distinct queries" },
              { label: "Zero-result rate", value: pct(empties, visible.size), icon: "exclamation-triangle",
                tone: empties.zero? ? :success : :warning,
                note: "#{count(empties)} calls returned nothing" },
              { label: "Cost / result", value: usd(cost_per_result, places: 4), icon: "receipt", tone: :success,
                note: "#{count(visible.sum(&:results))} results bought" }
            ]
          end

          def empties = @empties ||= visible.count { |c| c.results.zero? }

          def cost_per_result
            bought = visible.sum(&:results)
            bought.zero? ? 0 : visible.sum(&:cost_usd) / bought
          end

          def facets
            render Molecules::SectionHeader.new(title: "Calls", meta: "newest first")
            render Molecules::FilterBar.new(chips: provider_chips, grouped: false, outlined: true)
          end

          def provider_chips
            all = { label: "All", active: @provider.nil?, count: @calls.size,
                    href: "/raaf/prototype/search?variant=A" }
            [all] + providers.map do |name, calls|
              { label: provider_label(name), active: @provider == name, count: calls.size,
                href: "/raaf/prototype/search?variant=A&provider=#{name}" }
            end
          end

          def providers
            @providers ||= @calls.group_by(&:provider).sort_by { |_, calls| -calls.size }
          end

          def columns
            [{ label: "When", span: 1.1 }, { label: "Provider", span: 0.9 },
             { label: "Query", span: 3 }, { label: "Results", span: 0.6, align: :right },
             { label: "Cost", span: 0.7, align: :right }, { label: "Duration", span: 0.7, align: :right },
             { label: "Account", span: 0.6, align: :right }, { label: "Called by", span: 1.2, align: :right }]
          end

          def table
            render(Organisms::DataGrid.new(columns: columns, empty: empty_state)) do |grid|
              visible.first(150).each { |call| row(grid, call) }
            end
          end

          def empty_state
            { title: "No search calls recorded", icon: "search",
              text: "This database has no SearchCostTracking rows." }
          end

          def row(grid, call)
            grid.row(href: "/raaf/prototype/search?variant=A&provider=#{@provider}&call=#{call.id}", cells: [
                       { value: Atoms::Mono.new(clock(call.at), tone: :muted) },
                       { value: Atoms::Badge.new(provider_label(call.provider), variant: :slate) },
                       { value: Molecules::TitleMeta.new(call.query.presence || "(empty query)", call.model.presence),
                         primary: true },
                       { value: Atoms::Mono.new(call.results.to_s, tone: yield_tone(call.results)), align: :right },
                       { value: Atoms::Mono.new(usd(call.cost_usd, places: 3)), align: :right },
                       { value: Atoms::Mono.new("—", tone: :muted), align: :right },
                       { value: Atoms::Mono.new(call.account_id.to_s, tone: :muted), align: :right },
                       { value: Atoms::Mono.new(short_agent(call.agent), tone: :muted), align: :right }
                     ])
          end

          def selected
            @selected ||= @calls.find { |call| call.id.to_s == @params[:call].to_s }
          end

          # The detail view, and the honest part of this prototype: the two
          # fields it most wants are the two this store does not hold. Both
          # exist on the span — duration_ms and result.N.* — which is the
          # argument for the plugin writing to spans rather than here.
          def selected_call_panel
            render(Molecules::Panel.new(title: "Call ##{selected.id}", icon: "search",
                                        action: "Close", action_href: "/raaf/prototype/search?variant=A")) do
              render Molecules::KeyValueList.new(pairs: request_pairs, mono: true)
              render Molecules::SectionHeader.new(title: "Results", meta: "#{selected.results} returned", size: :sm)
              render Molecules::Alert.new(:warning, **missing_payload)
            end
          end

          def request_pairs
            { "Query" => selected.query.presence || "(empty)",
              "Provider" => provider_label(selected.provider),
              "Model" => selected.model.presence || "—",
              "Called by" => selected.agent.presence || "—",
              "Account" => selected.account_id.to_s,
              "At" => clock(selected.at),
              "Cost" => usd(selected.cost_usd, places: 4),
              "Duration" => "not stored",
              "Options" => selected.metadata.except("timestamp").to_json }
          end

          def missing_payload
            { title: "The returned URLs and snippets are not here",
              text: "collect_result_attributes already writes result.N.title / .url / .snippet / .score " \
                    "onto the span. SearchCostTracking keeps only the count, and no duration at all. " \
                    "Whichever store the plugin picks has to carry both, or this panel stays a stub." }
          end
        end
      end
    end
  end
end
