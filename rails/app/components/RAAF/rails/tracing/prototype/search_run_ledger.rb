# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      module Prototype
        ##
        # PROTOTYPE — throwaway. Variant C: the run ledger.
        #
        # The position: a single search call is meaningless. Nobody asks "was
        # that query worth $0.001". They ask "this discovery run cost forty
        # cents and found eight companies — which of its forty queries were
        # the waste". So the list unit is the buying run, and calls exist only
        # nested underneath it.
        #
        # This is the variant that says a plugin screen is a trace view
        # specialised to one source, which makes it the most expensive of the
        # three to build and the only one that gives search calls a
        # denominator.
        #
        # What this variant asks the contract for: a grouping key (the parent
        # span), an outcome the run is judged by, and a nested renderer. The
        # grouping key is the honest weak point — SearchCostTracking has no
        # trace id, so the runs below are inferred from account + caller + a
        # two-minute gap, and the yield column has nothing real behind it at
        # all. Both are visible in the screen rather than smoothed over,
        # because whether they are worth storing is the decision.
        #
        class SearchRunLedger < BaseComponent
          include Figures

          def initialize(calls:, runs:, params: {})
            @calls = calls
            @runs = runs
            @params = params
            @open = params[:run].presence
          end

          def view_template
            div(class: "raaf-page") do
              render Molecules::Alert.new(:info, **thesis)
              render Molecules::Alert.new(:warning, **caveat)
              headline
              ledger
            end

            render Switcher.new(current: "C", note: "The list unit here is one buying run.")
          end

          private

          def thesis
            { title: "Variant C — Run ledger",
              text: "One buying run per row, calls nested underneath. A call is judged by what the run it " \
                    "belonged to bought, not on its own. Click a run to open its calls." }
          end

          def caveat
            { title: "Two columns here are not real",
              text: "This store has no parent trace, so runs are inferred from account + caller + a " \
                    "two-minute gap. And nothing records what a run yielded, so \"Bought\" counts search " \
                    "results rather than companies. If this is the variant that wins, both become " \
                    "contract requirements: a grouping key and a declared outcome." }
          end

          def headline
            render Organisms::StatGrid.new(stats: [
              { label: "Runs", value: count(@runs.size), icon: "diagram-3", tone: :accent,
                note: "#{count(@calls.size)} calls, #{Kernel.format("%.1f", calls_per_run)} per run" },
              { label: "Cost / run", value: usd(cost_per_run, places: 3), icon: "cash-stack", tone: :warning,
                note: "#{usd(@calls.sum(&:cost_usd))} total" },
              { label: "Runs that bought nothing", value: count(barren.size), icon: "exclamation-triangle",
                tone: barren.empty? ? :success : :danger,
                note: "#{pct(barren.size, @runs.size)} of runs · #{usd(barren.sum { |r| r[:cost_usd] }, places: 3)} spent" },
              { label: "Widest run", value: count(widest[:calls].size), icon: "layers", tone: :accent,
                note: widest.then { |r| "#{short_agent(r[:agent])} · #{usd(r[:cost_usd], places: 3)}" } }
            ])
          end

          def calls_per_run = @runs.empty? ? 0 : @calls.size.to_f / @runs.size

          def cost_per_run = @runs.empty? ? 0 : @calls.sum(&:cost_usd) / @runs.size

          def barren = @barren ||= @runs.select { |run| run[:results].zero? }

          def widest = @widest ||= @runs.max_by { |run| run[:calls].size } || { calls: [], agent: "—", cost_usd: 0 }

          def ledger
            render(Molecules::SectionHeader.new(title: "Buying runs", meta: "newest first"))

            render(Organisms::DataRows.new) do
              @runs.first(40).each { |run| run_block(run) }
            end
          end

          def run_block(run)
            render(Organisms::DataRow.new(
                     title: run_title(run), meta: run_meta(run), icon: "diagram-3",
                     tone: run[:results].zero? ? :danger : :accent, href: run_href(run)
                   )) do
              render Molecules::TagList.new(run[:providers].map { |p| provider_label(p) }, limit: 3)
              render Atoms::Mono.new(usd(run[:cost_usd], places: 3), tone: :accent)
              render Atoms::Mono.new("#{count(run[:results])} bought",
                                     tone: run[:results].zero? ? :bad : :ok)
              render Atoms::Caret.new(open: open?(run))
            end

            calls_table(run) if open?(run)
          end

          def open?(run) = @open.to_s == run[:id].to_s

          def run_href(run)
            open?(run) ? "/raaf/prototype/search?variant=C" : "/raaf/prototype/search?variant=C&run=#{run[:id]}"
          end

          def run_title(run)
            "#{short_agent(run[:agent])} · account #{run[:account_id]}"
          end

          def run_meta(run)
            span_seconds = (run[:ended_at] - run[:started_at]).round
            "#{clock(run[:started_at])} · #{count(run[:calls].size)} calls over #{span_seconds}s · " \
              "#{run[:empty]} empty"
          end

          def calls_table(run)
            render(Organisms::DataGrid.new(columns: call_columns, class: "raaf-tbl--nested")) do |grid|
              run[:calls].each { |call| call_row(grid, call, run) }
            end
          end

          def call_columns
            [ { label: "When", span: 1 }, { label: "Provider", span: 0.9 },
              { label: "Query", span: 3.2 }, { label: "Results", span: 0.6, align: :right },
              { label: "Cost", span: 0.7, align: :right }, { label: "Share of run", span: 0.9, align: :right } ]
          end

          def call_row(grid, call, run)
            grid.row(cells: [
                       { value: Atoms::Mono.new(clock(call.at), tone: :muted) },
                       { value: Atoms::Badge.new(provider_label(call.provider), variant: :slate) },
                       { value: call.query.presence || "(empty query)", primary: true },
                       { value: Atoms::Mono.new(call.results.to_s, tone: yield_tone(call.results)), align: :right },
                       { value: Atoms::Mono.new(usd(call.cost_usd, places: 4)), align: :right },
                       { value: Atoms::Mono.new(pct(call.cost_usd, run[:cost_usd]), tone: :muted), align: :right }
                     ])
          end
        end
      end
    end
  end
end
