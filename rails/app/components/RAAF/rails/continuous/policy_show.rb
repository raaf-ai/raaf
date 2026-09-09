# frozen_string_literal: true

module RAAF
  module Rails
    module Continuous
      ##
      # One policy, from RAAF Continuous.dc.html: a header panel carrying the
      # name, what it does and its headline numbers; the checks beside the
      # configuration; and the score trend underneath.
      #
      # Two of the design's sections are not here, and both are data rather
      # than layout:
      #
      # - **Weights and thresholds.** The design gives each check a weight and
      #   draws a threshold marker on its bar. Neither is stored — every
      #   evaluator's `config` is empty — so the bar shows the score alone.
      # - **Alert routing.** The design lists where a breach is sent. There is
      #   no alerting configuration on the model at all, so the section would
      #   be a picture of something that does not exist.
      #
      class PolicyShow < RAAF::Rails::Tracing::BaseComponent
        include CheckSampling

        # Above this a score is healthy, below the lower bound it is failing.

        # @param check_scores [Hash] field name => { average:, count: }
        # @param trend [Array<Hash>] one bucket per bar, oldest first, each
        #   carrying :at, its axis :label and a :score that is nil where
        #   nothing ran
        # @param trend_window [String] the window the topbar is set to, said
        #   out loud — "24 hours"
        # @param trend_unit [String] what one bar covers — "hour"
        def initialize(policy:, today_stats: {}, recent_results: [], matching_spans: [],
                       check_scores: {}, trend: [], trend_window: "30 days",
                       trend_unit: "day")
          @policy = policy
          @today_stats = today_stats || {}
          @recent_results = recent_results
          @matching_spans = matching_spans
          @check_scores = check_scores || {}
          @trend = trend || []
          @trend_window = trend_window
          @trend_unit = trend_unit
        end

        def view_template
          div(class: "raaf-page") do
            header_panel
            div(class: "raaf-policy-split") do
              checks_card
              configuration
            end
            trend
            recent_results
            matching_spans
          end
        end

        private

        # The one thing on this page that does something rather than reports.
        # The canvas has no such panel — a policy there is four readings — so
        # it goes last, leaving the designed order intact. Without it a check
        # whose trigger mode is Manual has no button anywhere except on a span
        # somebody already went looking for.
        #
        # Rendered even with nothing to show: its empty state says why the
        # policy matches no span, and an absent panel reads as an absent
        # feature, which is exactly how this went missing before.
        def matching_spans
          render MatchingSpansPanel.new(policy: @policy, spans: @matching_spans)
        end

        # The individual verdicts behind every number above. The page reported
        # averages, a trend and a check breakdown, and gave no way to read a
        # single one of the results they are made of — the controller has
        # loaded them since this page was written, and nothing rendered them.
        #
        # Ten rows, because the point is to reach one and read it, not to
        # browse the set; "All results" leads to the table filtered to this
        # policy for that.
        def recent_results
          render(Organisms::Card.new(title: "Recent results", subtitle: RESULTS_SUBTITLE,
                                     flush: true)) do |card|
            card.actions { all_results_link }

            if @recent_results.blank?
              render Molecules::EmptyState.new(
                icon: "clipboard-check", title: "No results yet",
                text: "Nothing this policy graded has been recorded. Evaluate a span below " \
                      "to produce the first one."
              )
            else
              @recent_results.each { |result| result_row(result) }
            end
          end
        end

        RESULTS_SUBTITLE = "One row per graded field, newest first. Open one to read the " \
                           "score, the reasoning and the span it came from."

        def all_results_link
          render Atoms::Button.new(label: "All results", size: :sm, icon: "list-ul",
                                   href: continuous_results_path(policy: @policy.id))
        end

        # The same row the result screens list a neighbour with, so a result
        # reads the same wherever it is listed — and in the order the results
        # table puts it in: what it is, then its score, then its status. The
        # spans below stay their own idiom because their row holds a form.
        def result_row(result)
          render Molecules::ResultRow.new(
            href: continuous_result_path(result),
            title: result_label(result), meta: result_meta(result),
            status: result.status,
            value: score_text(result.score), value_tone: score_tone(result.score)
          )
        end

        # A result is about one field of one evaluator, and the field is what
        # distinguishes ten rows a policy wrote for the same span. Where a
        # result records no field, the evaluator's own name is the best label
        # left.
        def result_label(result)
          field = result.details&.dig("field_name") || result.metadata&.dig("field_name")
          return titles.label(result.evaluator_name) if field.blank?

          titles.check_label(result.evaluator_name, field)
        end

        def result_meta(result)
          [result.evaluator_name.presence && titles.label(result.evaluator_name),
           result.agent_name.presence,
           result.created_at && time_ago(result.created_at)].compact.join(" · ")
        end

        # What each evaluator calls itself, so the line under a result says
        # "DMU Title Relevance" rather than the symbol the policy names it with.
        def titles = @titles ||= EvaluatorTitles.new

        # ── Header ────────────────────────────────────────────────────────

        def header_panel
          render(Organisms::RecordHead.new(
                   title: @policy.name,
                   description: @policy.description,
                   status: @policy.active? ? "active" : "paused",
                   meta: head_meta,
                   action: { label: "Edit policy", icon: "sliders2",
                             href: edit_continuous_policy_path(@policy) },
                   stats: head_stats
                 )) { pause_control }
        end

        # Whether the policy is running was until now only changeable through
        # the edit form's checkbox, three screens from the badge that reports
        # it. Pausing is a POST, so it is a form rather than a link — as a link
        # it would be a GET that no route answers.
        def pause_control
          if @policy.active?
            post_button("Pause", "pause-fill", deactivate_continuous_policy_path(@policy))
          else
            post_button("Resume", "play-fill", activate_continuous_policy_path(@policy))
          end
        end

        def post_button(label, icon, action)
          form(action: action, method: "post", class: "raaf-inline-form") do
            input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
            render Atoms::Button.new(label: label, icon: icon, size: :sm,
                                     variant: :secondary, type: "submit")
          end
        end

        def head_meta
          [@policy.agent_name.presence || "any agent",
           environment_label,
           sample_label].compact.join(" · ")
        end

        def head_stats
          [{ label: "Today", value: @today_stats[:total].to_i.to_s },
           { label: "Avg score", value: score_text(@today_stats[:avg_score]),
             tone: score_tone(@today_stats[:avg_score]) },
           { label: "Good", value: good_share }]
        end

        # The share of today's evaluations that came back good — the number a
        # policy exists to move.
        def good_share
          total = @today_stats[:total].to_i
          return "—" if total.zero?

          "#{((@today_stats[:good].to_i / total.to_f) * 100).round}%"
        end

        # ── Checks ────────────────────────────────────────────────────────

        def checks_card
          render(Organisms::Card.new(title: "Checks", flush: true)) do
            if checks.empty?
              render Molecules::EmptyState.new(icon: "sliders", title: "No checks",
                                               text: "This policy declares no checks.")
            else
              checks.each { |evaluator, check| check_row(evaluator, check) }
            end
          end
        end

        # A check is named by whoever wrote it — "Confidence In Range" — and
        # `confidence:value_range` is the key a policy stores it under. The
        # name goes above the bar and the key under it, because the key is what
        # the results below are grouped by and what an edit form is written in.
        def check_row(evaluator, check)
          measured = measured_for(check)
          title = titles.check(evaluator, check)&.dig(:display_name).presence

          div(class: "raaf-scorer") do
            div(class: "raaf-scorer-head") do
              render Atoms::Text.new(title || check.to_s.tr("_", " "), as: :span,
                                     mono: title.blank?, class: "raaf-scorer-name")
              render Atoms::Mono.new(score_text(measured&.dig(:average)),
                                     tone: score_tone(measured&.dig(:average)))
            end

            render Atoms::ProgressBar.new(value: (measured&.dig(:average).to_f * 100).round,
                                          tone: bar_tone(measured&.dig(:average)))

            render Atoms::Text.new(check_note(measured, key: title && check, check: check),
                                   size: :sm, tone: :muted)
          end
        end

        # A check is named `field:evaluator`, and a result is now recorded
        # under that same name — one row per check rather than one per field —
        # so this is an exact lookup.
        #
        # It could not be while a field's evaluators were combined before the
        # row was written: two checks on one field reported one number between
        # them, and the bar had to fall back to the field's figure to show
        # anything at all.
        def measured_for(check)
          @check_scores[check]
        end

        # What a field scored before its evaluators were recorded separately.
        # Several verdicts went into it and the parts were never written down,
        # so it cannot be split now, and it is not any one check's score.
        def combined_for(check)
          @check_scores[check.to_s.split(":", 2).first]
        end

        # The key is printed as the policy stores it, underscores and all: it is
        # an identifier to match against the edit form, not a phrase to read.
        #
        # How often the check fires and whether it fires on its own belong
        # here too: the card said what each check scored and nothing about
        # when it runs, which is the other half of reading a policy.
        def check_note(measured, key: nil, check: nil)
          count = measured.nil? ? "No results yet" : "#{pluralize(measured[:count], 'evaluation')} scored"

          [key.presence, sampling_note(check), count, combined_note(check)]
            .compact.join(" · ")
        end

        def sampling_note(check)
          entry = sampling_by_check[check.to_s]
          return nil unless entry

          entry[:trigger] == "manual" ? "manual" : entry[:sampling]
        end

        # Evaluations of this field that no evaluator can be credited with:
        # those recorded before a field's evaluators were kept apart, and those
        # from an evaluator that reports no breakdown of its own. Neither is
        # this check's score, and neither can be made into one, so they are
        # counted where the reader can see what they are rather than folded
        # into the bar.
        def combined_note(check)
          combined = combined_for(check)
          return nil if combined.nil?

          "#{pluralize(combined[:count], 'evaluation')} scored this field's checks together"
        end

        def sampling_by_check
          @sampling_by_check ||= check_sampling(@policy).index_by { |entry| entry[:check] }
        end

        # The checks every evaluator on the policy declares, in order, each
        # kept with the evaluator that declared it — which is the only way back
        # to what the check is called.
        #
        # @return [Array<Array(String, String)>] evaluator name, check key
        def checks
          @checks ||= Array(@policy.evaluators).flat_map do |evaluator|
            next [] unless evaluator.is_a?(Hash)

            name = (evaluator["name"] || evaluator[:name]).to_s
            Array(evaluator["checks"] || evaluator[:checks])
              .map { |check| [name, check.to_s] }
          end.uniq { |(_name, check)| check }
        end

        # ── Configuration ─────────────────────────────────────────────────

        def configuration
          render(Organisms::Card.new(title: "Configuration", flush: true)) do
            config_rows.each { |label, value| config_row(label, value) }
          end
        end

        def config_row(label, value)
          div(class: "raaf-config-row") do
            span(class: "raaf-config-label") { label }
            render Atoms::Mono.new(value, class: "raaf-config-value")
          end
        end

        def config_rows
          [["Agent", @policy.agent_name.presence || "any agent"],
           ["Environment", environment_label],
           ["Sampling", sample_label],
           ["Triggers", trigger_label],
           ["Daily cap", @policy.max_daily_evaluations.to_i.positive? ? @policy.max_daily_evaluations.to_s : "none"],
           ["Concurrency", @policy.max_concurrent_evaluations.to_s],
           ["Retries", @policy.max_retries.to_s],
           ["Priority", @policy.priority.to_s],
           ["Queue", @policy.queue_name.presence || "default"],
           ["Retention", retention_label]]
        end

        def environment_label
          @policy.environment.presence == "all" ? "every environment" : @policy.environment.to_s
        end

        # A check whose trigger is manual does not fire on its own however it
        # is sampled, and that was visible nowhere outside the edit form.
        def trigger_label
          manual = check_sampling(@policy).count { |entry| entry[:trigger] == "manual" }
          return "every check runs automatically" if manual.zero?

          "#{pluralize(manual, 'check')} run only when started by hand"
        end

        # What the checks are actually sampled at, not the minimum the
        # controller writes onto the policy on save. See {CheckSampling}.
        def sample_label
          policy_sampling_label(@policy)
        end

        def retention_label
          days = @policy.retention_days.to_i
          count = @policy.retention_count.to_i

          [days.positive? && "#{days} days", count.positive? && "#{count} results"]
            .select { |part| part }.join(" · ").presence || "unlimited"
        end

        # ── Trend ─────────────────────────────────────────────────────────

        def trend
          render(Organisms::Card.new(title: "Composite score · #{@trend_window}",
                                     subtitle: trend_summary)) do
            if @trend.none? { |point| point[:score] }
              render Molecules::EmptyState.new(icon: "bar-chart", title: "No history",
                                               text: "This policy has not scored anything in the last #{@trend_window}.")
            else
              div(class: "raaf-trend") { @trend.each { |point| trend_bar(point) } }
              div(class: "raaf-trend-axis") { trend_axis.each { |label| span { label } } }
            end
          end
        end

        # A bucket with no evaluations is a gap, not a zero — it draws as a
        # stub so the eye does not read it as a failure.
        #
        # The bar hangs in a full-height cell, which is both the hover target
        # and what the readout is anchored to. A 2% stub is not something a
        # mouse can land on, and it is exactly the bucket worth asking about.
        # The readout was a `title` attribute, which waits a second, cannot be
        # styled and does not survive a touch — the console's tooltip molecule
        # is the same thing done once, everywhere.
        def trend_bar(point)
          score = point[:score]
          # `tokens` is a Ui::Base helper; this component descends from the
          # tracing BaseComponent, so the class list is built plainly.
          css = ["raaf-trend-bar",
                 score ? "raaf-trend-bar--#{score_tone(score)}" : "raaf-trend-bar--empty"].join(" ")

          div(class: "raaf-trend-cell raaf-tooltip") do
            div(class: css, style: "--raaf-bar-pct: #{score ? (score * 100).round : 2}%")
            span(class: "raaf-tooltip-content", role: "tooltip") { trend_tip(point) }
          end
        end

        def trend_tip(point)
          score = point[:score]
          return "#{point[:label]} · no evaluations" unless score

          "#{point[:label]} · #{score_text(score)}"
        end

        def trend_summary
          scored = @trend.filter_map { |point| point[:score] }
          return "no evaluations in the window" if scored.empty?

          poor = scored.count { |score| score < GOOD_SCORE }
          "#{pluralize(scored.size, @trend_unit)} scored · " \
            "#{pluralize(poor, @trend_unit)} below #{GOOD_SCORE}"
        end

        def trend_axis
          labels = @trend.filter_map { |point| point[:label] }
          return [] if labels.empty?

          [labels.first, labels[labels.size / 2], labels.last]
        end

        # ── Scores ────────────────────────────────────────────────────────

        # ProgressBar names its tones for the bar, not for the reading.
        def bar_tone(score)
          { warn: :warning, bad: :danger }[score_tone(score)]
        end
      end
    end
  end
end
