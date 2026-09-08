# frozen_string_literal: true

module RAAF
  module Rails
    module Eval
      ##
      # One experiment, from the Experiment screen in RAAF Eval.dc.html: a
      # header carrying the name, what it ran against and its state; the four
      # run metrics; the aggregate scores; and the per-item results.
      #
      # Two departures from the canvas, both because of what is stored rather
      # than how it looks:
      #
      # - **No score deltas.** The design prints each aggregate score against
      #   the previous run. Nothing links an experiment to the run before it,
      #   so a delta here would be invented.
      # - **No result filters.** The design offers All / Failed / Low score.
      #   A result's score is averaged in Ruby out of a jsonb hash, so "low
      #   score" cannot be a query, and filtering the page already loaded
      #   would silently mean "low among the last hundred". Filtering by
      #   status, which the database can answer for the whole run, lives on
      #   the results screen this card links to.
      #
      class ExperimentShow < RAAF::Rails::Tracing::BaseComponent
        # Columns and fr weights taken from RAAF Eval.dc.html.
        COLUMNS = [
          { label: "Item", span: 0.55 },
          { label: "Status", span: 0.9 },
          { label: "Score", span: 0.6, align: :right },
          { label: "Output", span: 2.6 }
        ].freeze

        # @param results [Enumerable<ExperimentResult>] the page being shown
        # @param total_results [Integer, nil] how many exist, when more were
        #   recorded than are drawn
        def initialize(experiment:, results:, total_results: nil)
          @experiment = experiment
          @results = results
          @total_results = total_results
        end

        def view_template
          div(class: "raaf-page") do
            header
            metrics
            aggregate_scores
            results
          end
        end

        private

        # ── Header ────────────────────────────────────────────────────────

        def header
          render(Organisms::RecordHead.new(
                   title: @experiment.name,
                   description: @experiment.description,
                   status: @experiment.status,
                   meta: head_meta,
                   action: { label: "Edit experiment", icon: "sliders2",
                             href: edit_eval_experiment_path(@experiment) }
                 )) { run_control }
        end

        def head_meta
          [@experiment.agent_name.presence,
           @experiment.model.presence,
           @experiment.provider.presence,
           @experiment.dataset&.name].compact.join(" · ")
        end

        # Running and cancelling are POSTs, so they are forms rather than
        # links — as links they were GETs that no route answers.
        def run_control
          case @experiment.status
          when "pending" then post_button("Run", "play-fill", run_path)
          when "running" then post_button("Cancel", "stop-fill", cancel_path, variant: :danger)
          end

          compare_link
        end

        # The scores below stand alone, and a number with nothing to stand
        # against cannot be judged. Offered once the run has something settled
        # to compare.
        def compare_link
          return unless %w[completed failed].include?(@experiment.status)

          render Atoms::Link.new("compare with another run", mono: true,
                                 href: compare_eval_experiment_path(@experiment))
        end

        def post_button(label, icon, action, variant: nil)
          form(action: action, method: "post", class: "raaf-inline-form") do
            input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
            render Atoms::Button.new(label: label, icon: icon, size: :sm, variant: variant,
                                     type: "submit")
          end
        end

        def run_path
          "#{eval_experiment_path(@experiment)}/run"
        end

        def cancel_path
          "#{eval_experiment_path(@experiment)}/cancel"
        end

        # ── Run metrics ───────────────────────────────────────────────────

        def metrics
          render Organisms::MetricGrid.new(metrics: [
                                             { label: "Progress", value: "#{@experiment.progress_percentage.round}%",
                                               icon: "bar-chart", hint: items_hint },
                                             { label: "Completed", value: @experiment.completed_items.to_s,
                                               icon: "check-circle", tone: :success, hint: "items scored" },
                                             { label: "Failed", value: @experiment.failed_items.to_s,
                                               icon: "x-circle", tone: failed? ? :danger : nil,
                                               hint: failed? ? "items that errored" : "nothing errored" },
                                             { label: "Duration", value: duration_text, icon: "clock", tone: :warning,
                                               hint: started_hint }
                                           ])
        end

        def items_hint
          total = @experiment.total_items.to_i
          return "not started" if total.zero?

          "#{@experiment.completed_items.to_i + @experiment.failed_items.to_i} of #{total} items"
        end

        def failed?
          @experiment.failed_items.to_i.positive?
        end

        def duration_text
          duration = @experiment.duration
          return "—" unless duration

          format_duration(duration * 1000)
        end

        def started_hint
          return "still running" if @experiment.in_progress?
          return "never run" unless @experiment.started_at

          "started #{time_ago(@experiment.started_at)}"
        end

        # ── Aggregate scores ──────────────────────────────────────────────

        # Written once when the run completes, so an experiment that has not
        # finished has nothing to draw here rather than a row of zeroes.
        def aggregate_scores
          scores = stored_scores
          return if scores.empty?

          render(Organisms::Card.new(title: "Aggregate scores")) do
            scores.each { |name, stats| score_row(name, stats) }
          end
        end

        def stored_scores
          metrics = @experiment.aggregate_metrics
          stored = metrics.is_a?(Hash) ? metrics["scores"] : nil
          return {} unless stored.is_a?(Hash)

          stored.select { |_, stats| stats.is_a?(Hash) && stats["avg"] }
        end

        def score_row(name, stats)
          average = stats["avg"].to_f

          render Molecules::MeterRow.new(
            name: name.to_s.tr("_", " "),
            value: "%.2f" % average,
            pct: (average * 100).round,
            tone: score_tone(average),
            sub: spread(stats),
            tip: score_tip(average, stats)
          )
        end

        # The bar's fill is the mean on a nought-to-one scale, which the row
        # never says — 0.62 beside a bar filled to two thirds is only obvious
        # once you already know what the scale is.
        def score_tip(average, stats)
          ["mean #{'%.2f' % average} of a possible 1.00", spread(stats).presence]
            .compact.join(" · ")
        end

        def spread(stats)
          range = [stats["min"], stats["max"]].compact.map { |value| "%.2f" % value.to_f }
          count = stats["count"].to_i

          [range.any? ? range.join(" – ") : nil,
           count.positive? ? pluralize(count, "result") : nil].compact.join(" · ")
        end

        # ── Results ───────────────────────────────────────────────────────

        def results
          render(Organisms::Card.new(title: "Results", subtitle: results_subtitle,
                                     flush: true)) do |card|
            card.actions { all_results_link }

            render(Organisms::DataGrid.new(
                     columns: COLUMNS,
                     empty: { icon: "list-check", title: "No results",
                              text: "Run the experiment to score the dataset." }
                   )) do |grid|
              @results.each { |result| result_row(grid, result) }
            end
          end
        end

        def all_results_link
          render Atoms::Button.new(label: "All results", size: :sm, icon: "list-ul",
                                   href: eval_experiment_results_path(@experiment))
        end

        # Says so when the table is a window onto a longer run, rather than
        # letting a hundred rows read as the whole thing.
        def results_subtitle
          shown = @results.size
          return nil if shown.zero?
          return pluralize(shown, "result") if @total_results.nil? || @total_results <= shown

          "#{shown} of #{@total_results} results"
        end

        def result_row(grid, result)
          score = result.overall_score

          grid.row(href: eval_experiment_result_path(@experiment, result), cells: [
                     { value: Atoms::Mono.new("##{result.dataset_item_id}", tone: :muted) },
                     { value: Atoms::StatusBadge.new(result.status) },
                     { value: Atoms::Mono.new(score_text(score), tone: score_tone(score)),
                       align: :right },
                     { value: Atoms::Mono.new(output_preview(result), tone: :muted,
                                                                      class: "raaf-cell-indent") }
                   ])
        end

        # A failed result has no output worth printing; what went wrong is the
        # only thing the row can say.
        def output_preview(result)
          return result.error_message.to_s.truncate(160) if result.error_message.present?

          output = result.output
          text = output.is_a?(Hash) || output.is_a?(Array) ? output.to_json : output.to_s
          text.presence&.truncate(160) || "—"
        end
      end
    end
  end
end
