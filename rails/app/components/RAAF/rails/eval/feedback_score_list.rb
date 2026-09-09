# frozen_string_literal: true

module RAAF
  module Rails
    module Eval
      ##
      # The feedback screen, from RAAF Eval.dc.html: the numerical headline
      # figures, the category distribution beside what each score name means,
      # and the recent scores underneath.
      #
      # The canvas puts the statistics on this screen rather than behind a
      # button, which is why the old "Statistics" link is gone: everything it
      # showed is here. `/raaf/eval/feedback_scores/statistics` still answers
      # JSON for anything reading it programmatically.
      #
      # Score names carry no description in the schema, so a definition row
      # says how many scores it has produced where the design writes prose.
      #
      class FeedbackScoreList < RAAF::Rails::Tracing::BaseComponent
        # Columns and fr weights taken from RAAF Eval.dc.html.
        COLUMNS = [
          { label: "Target", span: 1.1 },
          { label: "Definition", span: 1.5 },
          { label: "Value", span: 0.8, align: :right },
          { label: "By", span: 0.6, align: :right },
          { label: "Reason", span: 1.6 },
          { label: "When", span: 0.7, align: :right }
        ].freeze

        DEFINITION_COLUMNS = [
          { label: "Definition", span: 1.8 },
          { label: "Type", span: 0.7, align: :right },
          { label: "Range", span: 0.7, align: :right }
        ].freeze

        TYPE_VARIANTS = { "numerical" => :"tint-cyan", "categorical" => :"tint-violet" }.freeze

        # @param scores [Enumerable<FeedbackScore>] the recent scores to draw
        # @param stats [Hash] :count, :avg, :min, :max, :median over the
        #   numerical scores
        # @param distribution [Hash] category => how many scores carry it
        # @param definitions [Array<Hash>] :name, :type, :range, :count and
        #   :declared — false for a name scored under no definition
        def initialize(scores:, stats: {}, distribution: {}, definitions: [])
          @scores = scores
          @stats = stats || {}
          @distribution = distribution || {}
          @definitions = definitions || []
        end

        def view_template
          div(class: "raaf-page") do
            headline
            render(Organisms::CardGrid.new) do
              distribution
              definitions
            end
            recent
          end
        end

        private

        # ── Headline ──────────────────────────────────────────────────────

        # Only the average is toned. A score's scale is not stored, so a "4"
        # on a 1–5 rating and a 0.4 on a pass rate are indistinguishable here;
        # colouring every figure would be colouring a guess.
        def headline
          render Organisms::StatGrid.new(stats: [
                                           { label: "Scores", value: number(@stats[:count]), icon: "star",
                                             note: "numerical scores recorded" },
                                           { label: "Average", value: score_text(@stats[:avg]), icon: "graph-up",
                                             tone: average_tone, note: "across every definition" },
                                           { label: "Median", value: score_text(@stats[:median]),
                                             icon: "distribute-vertical" },
                                           { label: "Min", value: score_text(@stats[:min]), icon: "arrow-down" },
                                           { label: "Max", value: score_text(@stats[:max]), icon: "arrow-up" }
                                         ])
        end

        # `score_tone` answers in the dialect Mono, Bar and the meters speak,
        # which is the right word for the figures further down this screen. A
        # KPI tile's word is the semantic one, so the crossing is made here
        # rather than left to the card's aliases. A score too far from any tier
        # to colour comes back untoned, which is what the tile did with the
        # `:muted` it used to be handed.
        SCORE_TILE_TONES = { ok: :success, warn: :warning, bad: :danger }.freeze

        def average_tone
          SCORE_TILE_TONES[score_tone(@stats[:avg])]
        end

        # ── Category distribution ─────────────────────────────────────────

        def distribution
          render(Organisms::Card.new(title: "Category distribution")) do
            if @distribution.empty?
              render Molecules::EmptyState.new(icon: "pie-chart", title: "No categories",
                                               text: "Every score recorded so far is numerical.")
            else
              @distribution.sort_by { |_, count| -count.to_i }
                           .each { |category, count| distribution_row(category, count) }
            end
          end
        end

        def distribution_row(category, count)
          share = categorical_total.zero? ? 0 : (count.to_f / categorical_total * 100).round

          render Molecules::MeterRow.new(
            name: category.to_s, value: number(count), meta: "#{share}%", pct: share,
            tip: "#{number(count)} of #{number(categorical_total)} categorical scores"
          )
        end

        def categorical_total
          @categorical_total ||= @distribution.values.sum(&:to_i)
        end

        # ── Score definitions ─────────────────────────────────────────────

        def definitions
          render(Organisms::Card.new(title: "Score definitions", flush: true)) do
            render(Organisms::DataGrid.new(
                     columns: DEFINITION_COLUMNS,
                     empty: { icon: "list-check", title: "No definitions",
                              text: "Nothing declared and nothing scored." }
                   )) do |grid|
              @definitions.each { |definition| definition_row(grid, definition) }
            end
          end
        end

        def definition_row(grid, definition)
          grid.row(href: eval_feedback_scores_path(name: definition[:name]), cells: [
                     { value: Molecules::TitleMeta.new(definition[:name],
                                                       definition_meta(definition),
                                                       mono: true) },
                     { value: Atoms::Badge.new(definition[:type],
                                               variant: TYPE_VARIANTS.fetch(definition[:type],
                                                                            :slate)),
                       align: :right },
                     { value: Atoms::Mono.new(definition[:range], tone: :muted), align: :right }
                   ])
        end

        # A declared definition reports its declared range whether or not
        # anything has been scored against it. A name scored under no
        # definition is described from its scores instead, and says so — the
        # two are different facts and a reader comparing ranges needs to know
        # which kind a row is.
        def definition_meta(definition)
          scored = pluralize(definition[:count].to_i, "score")
          return "#{scored} · not declared" if definition[:declared] == false
          return "declared · never scored" if definition[:count].to_i.zero?

          scored
        end

        # ── Recent scores ─────────────────────────────────────────────────

        def recent
          render(Organisms::Card.new(title: "Recent scores", flush: true)) do
            render(Organisms::DataGrid.new(
                     columns: COLUMNS,
                     empty: { icon: "star", title: "No feedback scores",
                              text: "Score a trace or a span to track agent quality." }
                   )) do |grid|
              @scores.each { |score| score_row(grid, score) }
            end
          end
        end

        def score_row(grid, score)
          grid.row(href: target_path(score), cells: [
                     { value: Atoms::Mono.new(target_label(score), tone: :accent) },
                     { value: Molecules::TitleMeta.new(score.name, score.source, mono: true) },
                     { value: value_cell(score), align: :right },
                     { value: Atoms::Mono.new(score.scored_by.presence || "—", tone: :muted),
                       align: :right },
                     { value: Atoms::Mono.new(score.reason.presence || "—", tone: :muted,
                                                                            class: "raaf-cell-indent") },
                     { value: Atoms::Mono.new(time_ago(score.created_at), tone: :muted),
                       align: :right }
                   ])
        end

        # A numerical score reads as a figure in its tier's colour; a
        # categorical one is a word, and a pill is the only honest shape for it.
        def value_cell(score)
          return Atoms::Badge.new(score.category_value, variant: :"tint-violet") unless score.numerical?

          Atoms::Mono.new(score_text(score.value), tone: score_tone(score.value))
        end

        # The score hangs off a span or a trace, so the row opens the run it
        # was given — the only place the score means anything.
        def target_path(score)
          return trace_span_path(score.span_id, score.trace_id) if score.span_level?

          tracing_trace_path(score.trace_id)
        end

        def target_label(score)
          return "span #{truncate_id(score.span_id)}" if score.span_level?

          "trace #{truncate_id(score.trace_id)}"
        end

        # ── Formatting ────────────────────────────────────────────────────

        def number(value)
          value.to_i.to_s.reverse.scan(/\d{1,3}/).join(",").reverse
        end
      end
    end
  end
end
