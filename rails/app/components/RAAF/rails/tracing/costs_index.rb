# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      ##
      # Monitor › Cost & usage: what the window cost, then where it went.
      #
      # Four figures over two equal breakdowns, as RAAF Console.dc.html draws
      # it. The dashboard splits the second one by agent rather than by
      # workflow: an agent is the thing somebody can change the model or the
      # prompt of, and it is the same unit the Agents screen bills, so the two
      # cannot disagree.
      #
      # The breakdowns arrive titled rather than as fixed keys, because the
      # older /tracing/costs route reaches this screen with a workflow split
      # and a panel headed "By agent" over workflow rows would be a lie.
      #
      # Every breakdown is MeterRow, which is also what pipeline heat and eval
      # scores use — the inventory is explicit that it should not be forked.
      #
      # Two of the four figures carry a delta, as the design draws them: a
      # bill is only readable against the one before it, and $2.57 over a week
      # says nothing about whether the week was expensive. The comparison is
      # the window immediately preceding this one, of the same length, which
      # is the same basis the Errors screen trends its signatures on.
      #
      # Projected month deliberately carries none. The design compares it to a
      # budget, and there is no budget on this route to compare it to; a
      # percentage against the preceding window would repeat Spend's exactly,
      # since both divide the same two totals by the same number of hours.
      #
      class CostsIndex < BaseComponent
        # @param cost_data [Hash] :total_cost, :total_tokens, :input_tokens,
        #   :output_tokens, :runs, :window_hours, :breakdowns — an array of
        #   +{ title:, rows: [{ name:, cost:, tokens: }] }+ — and :preceding,
        #   +{ total_cost:, runs: }+ for the window before this one or nil
        def initialize(cost_data:, params: {})
          @cost_data = cost_data
          @params = params
        end

        def view_template
          div(class: "raaf-page") do
            kpis
            render(Organisms::CardGrid.new) do
              @cost_data[:breakdowns].to_a.each { |panel| breakdown(panel) }
            end
          end
        end

        private

        def kpis
          render Organisms::StatGrid.new(stats: kpi_stats)
        end

        def kpi_stats
          [
            { label: "Spend", value: money(@cost_data[:total_cost]), tone: spend_tone,
              delta: spend_delta, note: spend_note, icon: "cash-stack" },
            { label: "Tokens", value: compact(@cost_data[:total_tokens]), tone: :info,
              note: token_split, icon: "hash" },
            { label: "Cost / run", value: money(cost_per_run, places: 3), tone: cost_per_run_tone,
              delta: cost_per_run_delta, note: cost_per_run_note, icon: "receipt" },
            { label: "Projected month", value: money(projected_month), tone: :ok,
              note: projection_note, icon: "graph-up" }
          ]
        end

        # What the same length of time immediately before this window cost, or
        # nil where the controller did not carry one — the older /tracing/costs
        # route bills from CostManager and has no preceding window to hand.
        def preceding
          @cost_data[:preceding].presence
        end

        # Percent change in spend, as the design writes a KPI delta: signed, no
        # arrow, and "flat" rather than "+0.0%" for a window that did not move.
        def spend_delta
          return nil unless preceding

          percent_delta(@cost_data[:total_cost].to_f, preceding[:total_cost].to_f)
        end

        # Spending less is the good direction, so the tone is inverted against
        # what a rising figure means on Runs or Success rate. Tone colours the
        # icon with the delta, which is why it moves with the comparison rather
        # than staying the fixed :info this card carried before.
        def spend_tone
          direction_tone(spend_change)
        end

        def spend_note
          return "in the selected range" unless preceding

          "vs #{money(preceding[:total_cost])} in the preceding #{window_phrase}"
        end

        def spend_change
          return nil unless preceding

          @cost_data[:total_cost].to_f - preceding[:total_cost].to_f
        end

        # In dollars rather than percent: the figure it sits beside is already
        # a fraction of a cent, and "+9%" of $0.064 is not a number anybody can
        # act on without doing the arithmetic back.
        def cost_per_run_delta
          change = cost_per_run_change
          return nil if change.nil?
          return "flat" if change.round(3).zero?

          "#{change.negative? ? '-' : '+'}#{money(change.abs, places: 3)}"
        end

        # Falls back to the fixed :warn this card carried before there was
        # anything to compare it with, so a window with no predecessor looks
        # exactly as it did.
        def cost_per_run_tone
          preceding ? direction_tone(cost_per_run_change) : :warn
        end

        def cost_per_run_note
          billed = "#{number(runs)} #{'run'.pluralize(runs)} billed"
          return billed unless preceding

          "#{billed} · #{money(preceding_cost_per_run, places: 3)} before"
        end

        def cost_per_run_change
          return nil unless preceding

          cost_per_run - preceding_cost_per_run
        end

        def preceding_cost_per_run
          runs_before = preceding[:runs].to_i
          runs_before.zero? ? 0.0 : preceding[:total_cost].to_f / runs_before
        end

        def percent_delta(current, previous)
          return nil unless previous.positive?

          pct = ((current - previous) / previous) * 100
          return "flat" if pct.round(1).zero?

          "#{pct.positive? ? '+' : '-'}#{pct.abs.round(1)}%"
        end

        # A bill that grew is worth a second look; one that shrank is not. No
        # comparison means no claim, so the card falls back to :info.
        def direction_tone(change)
          return :info if change.nil? || change.round(6).zero?

          change.positive? ? :warn : :ok
        end

        # The preceding window is as long as this one, so it is named by this
        # one's length rather than by the range chip — an explicit
        # start_time/end_time overrides the chip, and "the preceding 24h" over
        # a three-day window would be wrong about what it compared.
        def window_phrase
          hours = @cost_data[:window_hours].to_f
          return "window" unless hours.positive?
          return "#{(hours / 24).round}d" if hours >= 24

          "#{hours.round}h"
        end

        def token_split
          input = @cost_data[:input_tokens].to_i
          output = @cost_data[:output_tokens].to_i
          return "input and output combined" if (input + output).zero?

          "#{compact(input)} in · #{compact(output)} out"
        end

        def runs
          @cost_data[:runs].to_i
        end

        def cost_per_run
          runs.zero? ? 0.0 : @cost_data[:total_cost].to_f / runs
        end

        # The window's burn rate over thirty days. Deliberately a rate rather
        # than a forecast: nobody has told this screen what the month's traffic
        # will look like, so it says what a month at this pace costs and labels
        # it as exactly that.
        #
        # The window length comes from the controller rather than from the
        # range chip, because an explicit start_time/end_time overrides the
        # chip and the projection would otherwise be scaled from the wrong span
        # of time.
        def projected_month
          hours = @cost_data[:window_hours].to_f
          return 0.0 unless hours.positive?

          (@cost_data[:total_cost].to_f / hours) * 24 * 30
        end

        def projection_note
          "at the pace of the selected range"
        end

        def breakdown(panel)
          rows = panel[:rows].to_a

          render(Molecules::Panel.new(title: panel[:title], icon: "bar-chart", pad: rows.empty?)) do
            if rows.empty?
              render Molecules::EmptyState.new(icon: "cash-stack", title: "Nothing billed",
                                               text: nothing_billed_text)
            else
              base = share_base(rows)
              rows.each { |row| meter(row, base) }
            end
          end
        end

        # Why the panel is empty, which "No spend recorded in this range" on
        # its own cannot say. A window that ends before the last run is the
        # common case on a dev database and on any quiet account, and a bare
        # $0.00 over it reads as a broken page rather than as a correct answer
        # about a window where nothing happened.
        def nothing_billed_text
          last = @cost_data[:last_billed_at]
          return "No spend has been recorded yet." unless last

          "No spend in this range. The most recent billed run was #{time_ago(last)}."
        end

        # The design scales each bar against the largest row rather than
        # against the total, so the smallest entries stay visible instead of
        # collapsing into the same hairline.
        def share_base(rows)
          rows.map { |row| row[:cost].to_f }.max.to_f
        end

        def meter(row, base)
          cost = row[:cost].to_f
          pct = base.positive? ? (cost / base) * 100 : 0

          render Molecules::MeterRow.new(
            name: row[:name].to_s.presence || "—",
            value: money(cost),
            pct: pct,
            meta: compact(row[:tokens]),
            tone: (pct > 66 ? :warn : nil),
            tip: meter_tip(row, cost)
          )
        end

        # The bar is scaled against the largest row so the small entries stay
        # visible, which means its fill is *not* the share of the bill — the
        # figure a reader actually wants off a cost breakdown. The readout is
        # where that share is stated, against the window's total.
        def meter_tip(row, cost)
          total = @cost_data[:total_cost].to_f
          share = total.positive? ? (cost / total * 100).round(1) : nil

          [row[:name].to_s.presence || "unattributed",
           "#{money(cost)}#{" · #{share}% of the bill" if share}",
           "#{number(row[:tokens])} tokens"].join(" · ")
        end

        # Kernel#format is shadowed in the view context; use String#% directly.
        def money(value, places: 2)
          "$#{"%.#{places}f" % value.to_f}"
        end

        # Token counts run to millions, where every digit past the first two is
        # noise beside the figure it explains.
        def compact(value)
          count = value.to_i
          return "#{(count / 1_000_000.0).round(1)}M" if count >= 1_000_000
          return "#{(count / 1000.0).round(1)}k" if count >= 1000

          count.to_s
        end

        def number(value)
          value.to_i.to_s.reverse.scan(/\d{1,3}/).join(",").reverse
        end
      end
    end
  end
end
