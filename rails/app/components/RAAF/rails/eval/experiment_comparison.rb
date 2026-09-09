# frozen_string_literal: true

module RAAF
  module Rails
    module Eval
      ##
      # Two runs of the same dataset, side by side.
      #
      # `ExperimentEngine#compare_experiments` has produced this since the
      # engine was written — aggregate deltas, deltas per score dimension, and
      # the two scores per dataset item — and had a spec and no caller. Nothing
      # in the console reached it, so an experiment's score stood alone, and a
      # figure with nothing to stand against is the whole of why a run could be
      # counted but not judged.
      #
      # `ExperimentShow` explains why it draws no deltas of its own: nothing
      # links a run to the one before it, so an automatic delta would be
      # invented. That holds. This screen asks the reader which run to compare
      # against instead, which is a question rather than a guess.
      #
      # The run being read is B and the chosen one is A, so a positive delta
      # means this run is the better of the two — the direction somebody reads
      # a change in when they ask whether the new prompt is an improvement.
      #
      class ExperimentComparison < RAAF::Rails::Tracing::BaseComponent
        COLUMNS = [
          { label: "Item", span: 0.6 },
          { label: "Was", span: 0.6, align: :right },
          { label: "Now", span: 0.6, align: :right },
          { label: "Change", span: 0.8, align: :right },
          { label: "Status", span: 0.8 }
        ].freeze

        # Below this a change is noise rather than a movement worth reading.
        NOISE = 0.005

        # @param experiment [Models::Experiment] the run being read
        # @param against [Models::Experiment, nil] the run it is held against
        # @param candidates [Array<Models::Experiment>] the other runs of this
        #   dataset, for the picker
        # @param comparison [Hash, nil] what the engine returned
        def initialize(experiment:, against: nil, candidates: [], comparison: nil)
          @experiment = experiment
          @against = against
          @candidates = candidates
          @comparison = comparison || {}
        end

        def view_template
          div(class: "raaf-page") do
            header
            picker

            if @against.nil?
              nothing_to_compare
            else
              metrics
              dimensions
              items
            end
          end
        end

        private

        def header
          render Organisms::RecordHead.new(
            parent: { label: @experiment.name, href: eval_experiment_path(@experiment) },
            title: @against ? "#{@experiment.name} vs #{@against.name}" : @experiment.name,
            description: header_description,
            status: @experiment.status,
            meta: [@experiment.agent_name.presence, @experiment.model.presence,
                   @experiment.dataset&.name].compact.join(" · ")
          )
        end

        def header_description
          return "No other run of this dataset to hold this one against." if @against.nil?

          "Both runs graded #{@experiment.dataset&.name}. A positive change means " \
            "#{@experiment.name} scored higher than #{@against.name}."
        end

        # The comparison is only meaningful within one dataset: two runs over
        # different cases share no item to line up, and their averages are over
        # different questions.
        def picker
          return if @candidates.empty?

          render(Molecules::FilterBar.new(panel: true)) do
            render Molecules::ScopeFilter.new(
              name: "against", value: @against&.id&.to_s,
              options: @candidates.map { |run| [run.name, run.id.to_s] },
              action: compare_eval_experiment_path(@experiment), prefix: "against",
              icon: "arrow-left-right", blank_label: "pick a run"
            )
          end
        end

        def nothing_to_compare
          render(Organisms::Card.new(flush: true)) do
            render Molecules::EmptyState.new(
              icon: "arrow-left-right", title: "Nothing to compare against",
              text: "This is the only run of #{@experiment.dataset&.name}. Run the dataset " \
                    "again after changing the prompt, the model or the scorers, and the two " \
                    "runs can be read against each other here."
            )
          end
        end

        # ── Aggregate ─────────────────────────────────────────────────────

        def metrics
          render Organisms::StatGrid.new(layout: :leading, stats: [
                                           success_metric, tokens_metric, moved_metric, regressed_metric
                                         ])
        end

        def success_metric
          success = metrics_comparison[:success_rate] || {}

          { label: "Success rate", value: percent(success[:b]), icon: "check-circle",
            tone: delta_tone(success[:delta]),
            note: comparison_note(percent(success[:a]), delta_percent(success[:delta])) }
        end

        # More tokens for the same answers is a cost the score does not show.
        def tokens_metric
          tokens = metrics_comparison[:tokens] || {}

          { label: "Tokens", value: tokens[:b] ? delimited(tokens[:b]) : "—", icon: "coin",
            tone: delta_tone(tokens[:delta], lower_is_better: true),
            note: comparison_note(tokens[:a] && delimited(tokens[:a]),
                                  tokens[:delta] && ("%+d" % tokens[:delta])) }
        end

        def moved_metric
          { label: "Cases moved", value: moved.size.to_s, icon: "arrow-left-right",
            note: "of #{pluralize(compared.size, 'case')} both runs scored" }
        end

        def regressed_metric
          { label: "Regressed", value: regressed.size.to_s, icon: "arrow-down-right",
            tone: regressed.any? ? :danger : :success,
            note: regressed.any? ? "cases this run scored lower" : "nothing scored lower" }
        end

        def comparison_note(was, delta)
          return nil if was.nil?

          delta ? "was #{was} · #{delta}" : "was #{was}"
        end

        # ── Score dimensions ──────────────────────────────────────────────

        def dimensions
          scores = metrics_comparison[:scores] || {}

          render(Organisms::Card.new(title: "Scores",
                                     subtitle: "this run against #{@against.name}")) do
            if scores.empty?
              render Molecules::EmptyState.new(
                icon: "sliders", title: "No aggregate scores",
                text: "Neither run recorded a score to compare."
              )
            else
              scores.each { |name, values| dimension_row(name, values) }
            end
          end
        end

        def dimension_row(name, values)
          now = values[:b].to_f

          render Molecules::MeterRow.new(
            name: name.to_s.split(":").map { |part| part.tr("_", " ") }.join(" · "),
            value: score_text(values[:b]),
            pct: (now * 100).round,
            tone: score_tone(values[:b]),
            meta: delta_text(values[:delta]),
            tip: "was #{score_text(values[:a])}, now #{score_text(values[:b])}"
          )
        end

        # ── Per case ──────────────────────────────────────────────────────

        # Worst first. A run is judged by what it broke, and a table that opens
        # on the cases that stayed the same buries the answer.
        def items
          render(Organisms::Card.new(title: "Cases", subtitle: items_subtitle, flush: true)) do
            render(Organisms::DataGrid.new(
                     columns: COLUMNS,
                     empty: { icon: "list-check", title: "No shared cases",
                              text: "The two runs scored no dataset item in common." }
                   )) do |grid|
              ordered_items.each { |entry| item_row(grid, entry) }
            end
          end
        end

        def items_subtitle
          return "nothing both runs scored" if compared.empty?

          if regressed.any?
            "#{pluralize(regressed.size, 'case')} scored lower, listed first"
          else
            "no case scored lower"
          end
        end

        def ordered_items
          @ordered_items ||= compared.sort_by { |entry| entry[:delta] }
        end

        def item_row(grid, entry)
          grid.row(href: eval_experiment_result_path(@experiment, entry[:result_id]),
                   cells: [
                     { value: Atoms::Mono.new("##{entry[:item_id]}", tone: :muted) },
                     { value: Atoms::Mono.new(score_text(entry[:was]), tone: :muted), align: :right },
                     { value: Atoms::Mono.new(score_text(entry[:now]), tone: score_tone(entry[:now])),
                       align: :right },
                     { value: Atoms::Mono.new(delta_text(entry[:delta]),
                                              tone: delta_tone(entry[:delta])), align: :right },
                     { value: Atoms::StatusBadge.new(entry[:status]) }
                   ])
        end

        # ── The comparison, read apart ────────────────────────────────────

        def metrics_comparison
          @comparison[:metrics_comparison] || {}
        end

        # Only the cases both runs actually scored. A case one run skipped has
        # no change to report, and counting it as a fall to zero would invent a
        # regression out of a gap.
        def compared
          @compared ||= Array(@comparison[:item_comparison]).filter_map do |entry|
            was = entry.dig(:a, :overall_score)
            now = entry.dig(:b, :overall_score)
            next if was.nil? || now.nil?

            { item_id: entry[:dataset_item_id], was: was, now: now,
              delta: now.to_f - was.to_f, status: entry.dig(:b, :status),
              result_id: entry.dig(:b, :id) }
          end
        end

        def moved
          @moved ||= compared.reject { |entry| entry[:delta].abs < NOISE }
        end

        def regressed
          @regressed ||= compared.select { |entry| entry[:delta] < -NOISE }
        end

        # ── Formatting ────────────────────────────────────────────────────

        # Nothing to compare against is not the same as no change.
        def delta_text(delta)
          return "—" if delta.nil?
          return "flat" if delta.abs < NOISE

          "%+.2f" % delta
        end

        # Already a percentage where it is stored, so neither of these scales it.
        def delta_percent(delta)
          return nil if delta.nil?

          "%+.1f%%" % delta.to_f
        end

        def delta_tone(delta, lower_is_better: false)
          return nil if delta.nil? || delta.abs < NOISE

          improved = lower_is_better ? delta.negative? : delta.positive?
          improved ? :success : :danger
        end

        def percent(value)
          return "—" if value.nil?

          "#{value.to_f.round(1)}%"
        end
      end
    end
  end
end
