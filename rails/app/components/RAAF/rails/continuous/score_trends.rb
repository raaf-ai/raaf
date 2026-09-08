# frozen_string_literal: true

module RAAF
  module Rails
    module Continuous
      ##
      # The Score trends screen, from RAAF Eval.dc.html: every evaluator as a
      # row, every bucket in the window as a cell, the whole console's score as
      # a line above them, and the two movement panels underneath.
      #
      # The grid is read for shape rather than for values. Two colourings
      # answer the two questions worth asking of it:
      #
      # - **Δ vs median** — each cell against that evaluator's own median, so a
      #   rule that lives at 0.99 and a judge that lives at 0.82 both read as
      #   flat, and a step in either shows up as a band of colour.
      # - **Pass rate** — each cell against the console's score tiers, which is
      #   the question when you want to know what is actually failing rather
      #   than what has changed.
      #
      # The design's per-evaluator weights are not here; nothing stores one, so
      # the headline row is a plain mean and says so. See
      # {RAAF::Rails::Continuous::ScoreTrendSeries}.
      #
      class ScoreTrends < RAAF::Rails::Tracing::BaseComponent
        # The colouring chips, in the design's order. The key is what travels
        # in the URL.
        MODES = { "median" => "Δ vs median", "absolute" => "Pass rate" }.freeze

        # Where a cell sits against its row's median. Read as "at least this
        # much above"; the first match wins.
        MEDIAN_STEPS = [[0.04, "up-2"], [0.016, "up-1"], [-0.016, "flat"],
                        [-0.04, "down-1"]].freeze

        # Where a cell sits on the absolute scale, from the design's six tiers.
        ABSOLUTE_STEPS = [[0.97, "t5"], [0.93, "t4"], [0.88, "t3"],
                          [0.82, "t2"], [0.74, "t1"]].freeze

        # The legends, worst first, so the strip reads left to right under the
        # "worse → better" rule the design puts around it.
        LEGENDS = {
          "median" => [["down-2", "−.04"], ["down-1", "−.02"], ["flat", "flat"],
                       ["up-1", "+.02"], ["up-2", "+.04"]],
          "absolute" => [["t0", "< .74"], ["t1", ".74"], ["t2", ".82"],
                         ["t3", ".88"], ["t4", ".93"], ["t5", ".97+"]]
        }.freeze

        # How many movers each panel names. Enough to see a pattern, few enough
        # that naming one means something.
        MOVERS = 3

        # Below this a move either way is noise, in the Δ column and in the two
        # movement panels alike.
        MOVEMENT = 0.005

        # The geometry of the headline sparkline, in its own viewBox units.
        LINE_WIDTH = 300
        LINE_HEIGHT = 34
        LINE_INSET = 4

        # @param trends [Hash] {RAAF::Rails::Continuous::ScoreTrendSeries#call}
        # @param mode [String] "median" or "absolute"
        # @param mode_href [Proc, nil] mode key => the URL that selects it
        def initialize(trends:, mode: "median", mode_href: nil)
          @trends = trends || {}
          @mode = MODES.key?(mode) ? mode : "median"
          @mode_href = mode_href
          @buckets = @trends[:buckets] || []
          @rows = @trends[:rows] || []
        end

        def view_template
          div(class: "raaf-page") do
            controls
            grid_card
            movement
          end
        end

        private

        # ── Controls ──────────────────────────────────────────────────────

        def controls
          render Molecules::FilterBar.new(chips: mode_chips) do
            render Atoms::Mono.new(meta, tone: :muted)
          end
        end

        def mode_chips
          MODES.map do |key, label|
            { label: label, active: @mode == key, href: @mode_href&.call(key) }
          end
        end

        # What the grid is of, said once, so no column header has to repeat it.
        def meta
          parts = [pluralize(@trends[:total_rows].to_i, "evaluator"), @trends[:window]]
          parts << "#{first_label} – #{last_label}" if first_label
          parts << "#{@trends[:hidden_rows]} not shown" if @trends[:hidden_rows].to_i.positive?

          parts.compact.join(" · ")
        end

        def first_label = @buckets.first&.fetch(:label)
        def last_label = @buckets.last&.fetch(:label)

        # ── The grid ──────────────────────────────────────────────────────

        def grid_card
          render(Organisms::Card.new(title: "Every evaluator, every #{@trends[:unit]}",
                                     flush: true)) do |card|
            card.actions { legend }

            if @rows.empty?
              render Molecules::EmptyState.new(
                icon: "graph-up", title: "Nothing scored yet",
                text: "No evaluator has recorded a score in the last #{@trends[:window]}. " \
                      "Run an experiment or let a continuous policy sample some spans."
              )
            else
              div(class: "raaf-heatgrid-scroll") { grid }
            end
          end
        end

        def legend
          div(class: "raaf-heat-legend") do
            span(class: "raaf-heatgrid-head") { "worse" }
            div(class: "raaf-heat-legend-swatches") do
              LEGENDS.fetch(@mode).each do |step, label|
                span(class: "raaf-heat raaf-heat--#{step}", title: label)
              end
            end
            span(class: "raaf-heatgrid-head") { "better" }
          end
        end

        def grid
          div(class: "raaf-heatgrid", style: "--raaf-heat-cols: #{@buckets.size}") do
            axis
            overall_row
            @rows.each { |row| evaluator_row(row) }
          end
        end

        # ── Axis ──────────────────────────────────────────────────────────

        # A label every seventh cell counting back from the newest, so the last
        # cell — the one being read — is always the one that is named.
        def axis
          div(class: "raaf-heatgrid-row raaf-heatgrid-row--axis") do
            span
            div(class: "raaf-heatgrid-cells") do
              @buckets.each_with_index { |bucket, index| axis_cell(bucket, index) }
            end
            span(class: "raaf-heatgrid-head raaf-heatgrid-head--right") { "Now" }
            span(class: "raaf-heatgrid-head raaf-heatgrid-head--right") do
              "Δ #{@trends[:delta_window]}"
            end
          end
        end

        def axis_cell(bucket, index)
          div(class: "raaf-heat-axis") do
            span(class: "raaf-heat-release") { bucket[:release] } if bucket[:release]
            span(class: css("raaf-heat-tick", bucket[:release] && "is-release"))
            span(class: "raaf-heat-date") { bucket[:label] } if dated?(index)
          end
        end

        # A date every quarter of the window, counting back from the newest so
        # the cell being read is always one of the named ones.
        #
        # A release marker wins the space where the two would land beside each
        # other. Both labels are wider than a cell, so a date next to a version
        # reads as neither, and which version shipped is the more useful of the
        # two on a screen about when a score moved.
        def dated?(index)
          step = [(@buckets.size / 4.0).round, 1].max
          return false unless (@buckets.size - 1 - index) % step == 0

          ((index - 1)..(index + 1)).none? do |near|
            near >= 0 && @buckets[near] && @buckets[near][:release]
          end
        end

        # ── Rows ──────────────────────────────────────────────────────────

        # The console's whole score, drawn as a line rather than as heat: it is
        # the one row where the absolute level is the point, and 30 cells of
        # near-identical green say much less than a line with a dip in it.
        def overall_row
          overall = @trends[:overall] || {}

          div(class: "raaf-heatgrid-row raaf-heatgrid-row--overall") do
            render Molecules::TitleMeta.new("Overall", "every evaluator, equally weighted")
            sparkline(overall[:series] || [])
            render Atoms::Mono.new(figure(overall[:current]))
            delta_cell(overall[:delta])
          end
        end

        def evaluator_row(row)
          div(class: "raaf-heatgrid-row") do
            row_name(row)
            div(class: "raaf-heatgrid-cells") do
              row[:series].each_with_index { |score, index| cell(row, score, index) }
            end
            render Atoms::Mono.new(figure(row[:current]), tone: score_tone(row[:current]))
            delta_cell(row[:delta])
          end
        end

        # A row is titled by what its evaluator calls itself where it calls itself
        # anything. The human-feedback row and any evaluator that declares no
        # title keep the recorded name, in mono: that is the string, not a name
        # for it.
        def row_name(row)
          title = titles[row[:name]].presence

          div(class: "raaf-heatgrid-name") do
            span(class: css("raaf-heatgrid-title", title ? nil : "raaf-mono")) { title || row[:name] }
            div(class: "raaf-heatgrid-meta") do
              span(class: "raaf-heat-kind raaf-heat-kind--#{kind_slug(row[:kind])}") { row[:kind] }
              span(class: "raaf-heatgrid-agent") { row[:agent] }
            end
          end
        end

        def titles = @titles ||= EvaluatorTitles.new

        def kind_slug(kind)
          kind.to_s.downcase.gsub(/[^a-z]+/, "-")
        end

        # ── Cells ─────────────────────────────────────────────────────────

        # The readout is the console's tooltip rather than a `title`, which
        # waits a second, cannot be styled and does not survive a touch.
        def cell(row, score, index)
          span(class: css("raaf-heat", "raaf-heat--#{step_for(row, score)}", "raaf-tooltip",
                          @buckets[index] && @buckets[index][:release] && "is-release")) do
            span(class: "raaf-tooltip-content", role: "tooltip") { tip(row, score, index) }
          end
        end

        def step_for(row, score)
          return "empty" if score.nil?
          return absolute_step(score) if @mode == "absolute"
          return "flat" if row[:median].nil?

          median_step(score - row[:median])
        end

        def median_step(distance)
          MEDIAN_STEPS.each { |threshold, step| return step if distance >= threshold }

          "down-2"
        end

        def absolute_step(score)
          ABSOLUTE_STEPS.each { |threshold, step| return step if score >= threshold }

          "t0"
        end

        def tip(row, score, index)
          bucket = @buckets[index] || {}
          parts = [row[:name], bucket[:label]]
          parts << (score ? figure(score) : "not scored")
          parts << "#{bucket[:release]} shipped" if bucket[:release]

          parts.compact.join(" · ")
        end

        # ── The headline line ─────────────────────────────────────────────

        # Scaled to its own range rather than to 0–1: the console's score sits
        # in a narrow band near the top, and a line drawn against the full
        # scale is a flat line whatever happens to it.
        def sparkline(series)
          points = line_points(series)

          if points.empty?
            div(class: "raaf-heat-line raaf-heat-line--empty")
            return
          end

          svg(viewBox: "0 0 #{LINE_WIDTH} #{LINE_HEIGHT}", preserveAspectRatio: "none",
              class: "raaf-heat-line", role: "img", "aria-label": line_label(series)) do |s|
            s.polygon(points: "0,#{LINE_HEIGHT} #{points} #{LINE_WIDTH},#{LINE_HEIGHT}",
                      class: "raaf-heat-line-area")
            s.polyline(points: points, fill: "none", class: "raaf-heat-line-stroke",
                       "vector-effect": "non-scaling-stroke")
          end
        end

        # Gaps are bridged rather than dropped to the floor: a bucket nothing
        # ran in is not a bucket the console scored zero in.
        def line_points(series)
          scored = series.each_with_index.reject { |score, _| score.nil? }
          return "" if scored.size < 2

          low, high = scored.map(&:first).minmax
          span = [high - low, 0.02].max
          step = LINE_WIDTH.to_f / [series.size - 1, 1].max
          usable = LINE_HEIGHT - (LINE_INSET * 2)

          scored.map do |score, index|
            y = LINE_HEIGHT - LINE_INSET - (((score - low) / span) * usable)
            "#{(index * step).round(1)},#{y.round(1)}"
          end.join(" ")
        end

        def line_label(series)
          scored = series.compact
          return "No scores in the window" if scored.empty?

          "Overall score, #{figure(scored.min)} to #{figure(scored.max)} over the window"
        end

        # ── Movement ──────────────────────────────────────────────────────

        def movement
          return if @rows.empty?

          render(Organisms::CardGrid.new) do
            mover_card("Losing ground", losing, :bad)
            mover_card("Gaining", gaining, :ok)
          end
        end

        # Only rows that actually moved. The same threshold the Δ column uses
        # to grey a number out: naming an evaluator that shifted by a
        # thousandth as "losing ground" is how a panel stops being read.
        def moved
          @moved ||= @rows.select { |row| row[:delta] && row[:delta].abs >= MOVEMENT }
                          .sort_by { |row| row[:delta] }
        end

        def losing
          moved.select { |row| row[:delta].negative? }.first(MOVERS)
        end

        def gaining
          moved.select { |row| row[:delta].positive? }.last(MOVERS).reverse
        end

        def mover_card(title, rows, tone)
          render(Organisms::Card.new(title: title, flush: true)) do
            if rows.empty?
              render Molecules::EmptyState.new(icon: "dash-lg", title: "Nothing moved",
                                               text: empty_movement(tone))
            else
              rows.each { |row| mover_row(row, tone) }
            end
          end
        end

        def empty_movement(tone)
          direction = tone == :bad ? "below" : "above"

          "No evaluator is meaningfully #{direction} where it was " \
            "#{@trends[:delta_window]} ago."
        end

        def mover_row(row, tone)
          div(class: "raaf-mover") do
            render Molecules::TitleMeta.new(row[:name], mover_note(row, tone), mono: true)
            render Atoms::Mono.new(figure(row[:current]))
            render Atoms::Badge.new(delta_text(row[:delta]),
                                    variant: tone == :bad ? :"soft-red" : :"soft-green")
          end
        end

        # Why this row is in this panel, said in terms of the row's own history
        # rather than as a second copy of the number beside it.
        def mover_note(row, tone)
          return "back above its own median for the window" if tone == :ok
          return "drifting down over the last #{@trends[:delta_window]}" unless below_median?(row)

          "below its own median for the window — check what shipped"
        end

        def below_median?(row)
          row[:median] && row[:current] && (row[:median] - row[:current]) > 0.04
        end

        # ── Formatting ────────────────────────────────────────────────────

        # `tokens` is a Ui::Base helper and this component descends from the
        # tracing BaseComponent, so the class list is joined here instead.
        def css(*names)
          names.compact.reject { |name| name == false }.join(" ")
        end

        def delta_cell(delta)
          render Atoms::Mono.new(delta_text(delta), tone: delta_tone(delta))
        end

        # A signed figure with the leading zero dropped, as the design writes
        # it: the numbers are all fractions and the zero is a column of noise.
        def delta_text(delta)
          return "—" if delta.nil?

          arrow = delta.negative? ? "▼" : "▲"
          "#{arrow} #{'%.3f' % delta.abs}".sub("0.", ".")
        end

        # A move smaller than {MOVEMENT} either way is not a move.
        def delta_tone(delta)
          return :muted if delta.nil? || delta.abs < MOVEMENT

          delta.negative? ? :bad : :ok
        end

        # `format` is not Kernel's here — Phlex's element methods take the name,
        # so the operator form is the one that survives.
        def figure(value)
          value.nil? ? "—" : "%.3f" % value.to_f
        end
      end
    end
  end
end
