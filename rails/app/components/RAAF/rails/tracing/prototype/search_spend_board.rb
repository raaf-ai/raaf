# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      module Prototype
        ##
        # PROTOTYPE — throwaway. Variant B: the spend board.
        #
        # The position: nobody opens this screen to read one call. They open
        # it because search cost more than it should, or because a provider
        # started returning nothing. So the list unit is the provider, the
        # primary affordance is the comparison between providers, and
        # individual calls are a drill-down you reach after you already know
        # which provider you are angry at.
        #
        # This is the variant that says the console's job for a non-AI source
        # is money and yield, not the audit trail — and #1089 found the costs
        # screen breaks down by model only, so search spend currently
        # disappears into the total. This screen is what fixes that.
        #
        # What this variant asks the contract for: a rollup dimension, a set
        # of named metrics with their good direction, and a cost model. It
        # needs no payload renderer at all.
        #
        class SearchSpendBoard < BaseComponent
          include Figures

          def initialize(calls:, params: {})
            @calls = calls
            @params = params
            @drilled = params[:provider].presence
          end

          def view_template
            div(class: "raaf-page") do
              render Molecules::Alert.new(:info, **thesis)
              headline
              render Molecules::FilterBar.new(chips: provider_chips, grouped: false, outlined: true)
              render(Organisms::CardGrid.new) do
                spend_panel
                yield_panel
              end
              consumers_panel
              drill_down if drilled_calls.any?
            end

            render Switcher.new(current: "B", note: "The list unit here is one provider.")
          end

          private

          def thesis
            { title: "Variant B — Spend board",
              text: "One provider per row. The screen answers \"where did the money go and what did it buy\" " \
                    "before it answers \"what happened at 14:03\". Click a provider to drop into its calls." }
          end

          def total_cost = @total_cost ||= @calls.sum(&:cost_usd)

          def total_results = @total_results ||= @calls.sum(&:results)

          def empties = @empties ||= @calls.count { |c| c.results.zero? }

          def headline
            render Organisms::StatGrid.new(stats: [
              { label: "Search spend", value: usd(total_cost), icon: "cash-stack", tone: :accent,
                layout: :leading, note: "across #{providers.size} providers" },
              { label: "Cost / result", value: usd(total_results.zero? ? 0 : total_cost / total_results, places: 4),
                icon: "receipt", tone: :success, layout: :leading, note: "#{count(total_results)} results bought" },
              { label: "Wasted calls", value: pct(empties, @calls.size), icon: "trash",
                tone: empties.zero? ? :success : :danger, layout: :leading,
                note: "#{count(empties)} returned nothing", series: waste_series }
            ])
          end

          # Zero-result share per provider, biggest first — the shape of the
          # waste, on the card that names it.
          def waste_series
            providers.map { |_, calls| ((calls.count { |c| c.results.zero? }.to_f / calls.size) * 100).round }
          end

          def provider_chips
            all = { label: "All providers", active: @drilled.nil?, count: @calls.size,
                    href: "/raaf/prototype/search?variant=B" }
            [ all ] + providers.map do |name, calls|
              { label: provider_label(name), active: @drilled == name, count: calls.size,
                href: "/raaf/prototype/search?variant=B&provider=#{name}" }
            end
          end

          def providers
            @providers ||= @calls.group_by(&:provider).sort_by { |_, calls| -calls.sum(&:cost_usd) }
          end

          def spend_panel
            render(Molecules::Panel.new(title: "Spend by provider", icon: "cash-stack")) do
              providers.each do |name, calls|
                spend = calls.sum(&:cost_usd)
                render Molecules::MeterRow.new(
                  name: provider_label(name), value: usd(spend),
                  pct: total_cost.zero? ? 0 : ((spend / total_cost) * 100).round,
                  sub: "#{count(calls.size)} calls · #{usd(spend / calls.size, places: 4)} each",
                  meta: pct(spend, total_cost)
                )
              end
            end
          end

          # The figure the spend panel cannot show: a provider can be cheap
          # per call and still the worst buy on the board.
          def yield_panel
            render(Molecules::Panel.new(title: "What each provider bought", icon: "graph-up")) do
              by_yield.each do |name, calls|
                bought = calls.sum(&:results)
                per = bought.zero? ? nil : calls.sum(&:cost_usd) / bought
                render Molecules::MeterRow.new(
                  name: provider_label(name), value: per ? usd(per, places: 4) : "nothing",
                  pct: waste_pct(calls), tone: waste_pct(calls) > 20 ? :bad : :ok,
                  value_tone: per ? nil : :bad,
                  sub: "#{count(bought)} results · #{pct(calls.count { |c| c.results.zero? }, calls.size)} empty",
                  meta: "cost / result"
                )
              end
            end
          end

          def by_yield
            providers.sort_by { |_, calls| -waste_pct(calls) }
          end

          def waste_pct(calls)
            ((calls.count { |c| c.results.zero? }.to_f / calls.size) * 100).round
          end

          # Who is spending it. The account is the tenant being billed and the
          # agent is the thing somebody can change — the same split the costs
          # screen already makes for models.
          def consumers_panel
            render(Molecules::Panel.new(title: "Who is buying", icon: "people")) do
              render(Organisms::DataGrid.new(columns: consumer_columns)) do |grid|
                consumers.first(12).each do |(account_id, agent), calls|
                  consumer_row(grid, account_id, agent, calls)
                end
              end
            end
          end

          def consumers
            @consumers ||= @calls.group_by { |c| [ c.account_id, c.agent ] }
                                 .sort_by { |_, calls| -calls.sum(&:cost_usd) }
          end

          def consumer_columns
            [ { label: "Account", span: 0.6 }, { label: "Caller", span: 2 },
              { label: "Providers", span: 1.4 }, { label: "Calls", span: 0.6, align: :right },
              { label: "Spend", span: 0.8, align: :right }, { label: "Empty", span: 0.7, align: :right } ]
          end

          def consumer_row(grid, account_id, agent, calls)
            grid.row(cells: [
                       { value: Atoms::Mono.new(account_id.to_s, tone: :muted) },
                       { value: Molecules::TitleMeta.new(short_agent(agent), agent), primary: true },
                       { value: Molecules::TagList.new(calls.map(&:provider).uniq.map { |p| provider_label(p) }, limit: 3) },
                       { value: Atoms::Mono.new(count(calls.size)), align: :right },
                       { value: Atoms::Mono.new(usd(calls.sum(&:cost_usd), places: 3), tone: :accent), align: :right },
                       { value: Atoms::Mono.new(pct(calls.count { |c| c.results.zero? }, calls.size),
                                                tone: waste_pct(calls) > 20 ? :bad : :muted), align: :right }
                     ])
          end

          def drilled_calls
            @drilled_calls ||= @drilled ? @calls.select { |c| c.provider == @drilled } : []
          end

          def drill_down
            render(Molecules::Panel.new(title: "#{provider_label(@drilled)} — recent calls", icon: "search",
                                        action: "Back to all providers",
                                        action_href: "/raaf/prototype/search?variant=B")) do
              render(Organisms::DataGrid.new(columns: drill_columns)) do |grid|
                drilled_calls.first(40).each { |call| drill_row(grid, call) }
              end
            end
          end

          def drill_columns
            [ { label: "When", span: 1 }, { label: "Query", span: 3.4 },
              { label: "Results", span: 0.6, align: :right }, { label: "Cost", span: 0.7, align: :right } ]
          end

          def drill_row(grid, call)
            grid.row(cells: [
                       { value: Atoms::Mono.new(clock(call.at), tone: :muted) },
                       { value: call.query.presence || "(empty query)", primary: true },
                       { value: Atoms::Mono.new(call.results.to_s, tone: yield_tone(call.results)), align: :right },
                       { value: Atoms::Mono.new(usd(call.cost_usd, places: 4)), align: :right }
                     ])
          end
        end
      end
    end
  end
end
