# frozen_string_literal: true

module RAAF
  module Rails
    module Continuous
      ##
      # Scorer health, from the `isHealth` screen in RAAF Continuous.dc.html:
      # a drift banner, four headline cards each over its own sparkline, then
      # the scorer table beside Coverage by agent and Recent events.
      #
      # The screen holds no SQL. Every figure comes from {ScorerHealth}, which
      # is also where each measurement's definition is written down.
      #
      # Where the design assumes a shape RAAF does not have, the decision is
      # here rather than hidden in the data:
      #
      # - **The banner.** The design's is a judge-model roll. RAAF records the
      #   judge models every evaluation called, so that event is real and is
      #   the banner's fallback — but an unresolved alert outranks it, because
      #   an alert is something a person still has to answer.
      # - **Judge agreement.** The design measures it against a 250-span human
      #   audit. RAAF has no audit process, but `FeedbackScore` is where a
      #   human verdict on a span is recorded, so the card reports agreement
      #   over the spans that carry one and says plainly when none do.
      # - **Coverage colour.** The design tints a low percentage amber. Low
      #   coverage is usually the sampling rate working as configured — a
      #   policy asking for one span in ten is *supposed* to read 10% — so the
      #   only tinted row here is one at zero, which is a policy that has
      #   graded nothing at all.
      # - **Recent events.** The design mixes alerts with configuration
      #   changes. RAAF keeps no audit trail of a policy being paused or
      #   resampled, so the list is the alerts it does record.
      class HealthDashboard < RAAF::Rails::Tracing::BaseComponent
        SCORER_COLUMNS = [
          { label: "Scorer", span: 1.6 },
          { label: "Mean", span: 0.7, align: :right },
          { label: "Drift", span: 0.7, align: :right },
          { label: "p95", span: 0.7, align: :right },
          { label: "State", span: 0.8, align: :right }
        ].freeze

        ALERT_ICONS = {
          "quality_degradation" => "graph-down-arrow",
          "failure_spike" => "exclamation-triangle-fill",
          "queue_backlog" => "hourglass-split",
          "evaluator_error" => "x-octagon-fill",
          "policy_threshold" => "clipboard-check",
          "cost_exceeded" => "cash-stack"
        }.freeze

        SEVERITY_TONES = { "critical" => :danger, "warning" => :warning, "info" => :accent }.freeze
        SEVERITY_VARIANTS = { "critical" => :error, "warning" => :warning, "info" => :info }.freeze

        # Kinds spelled as the design does, since `rule_based` is a column
        # value rather than a phrase.
        KIND_LABELS = {
          "llm_judge" => "llm judge", "rule_based" => "rule based",
          "statistical" => "statistical", "custom" => "custom"
        }.freeze

        # @param health [ScorerHealth]
        # @param range [String] the window's label, for the copy that names it
        def initialize(health:, range: "7d")
          @health = health
          @range = range
        end

        def view_template
          div(class: "raaf-page") do
            if !@health.available?
              not_installed
            elsif @health.evaluations.zero?
              banner
              nothing_scored
            else
              banner
              stats
              div(class: "raaf-health-split") do
                scorer_table
                rail
              end
            end
          end
        end

        private

        # ── Banner ────────────────────────────────────────────────────────

        # One line at the top, or none. An unresolved alert first — somebody
        # still has to answer it — then a judge model that changed underneath a
        # scorer, which moves its scores without anything about the agent
        # having changed.
        def banner
          alert = @health.headline_alert
          return alert_banner(alert) if alert

          change = @health.judge_changes.first
          judge_banner(change) if change
        end

        def alert_banner(alert)
          variant = SEVERITY_VARIANTS.fetch(alert.severity, :info)

          render(Molecules::Alert.new(variant, title: alert.title)) do
            p(class: "raaf-alert-text") { alert_text(alert) }
            banner_link(alert)
          end
        end

        def alert_text(alert)
          [alert.message, "Triggered #{time_ago(alert.triggered_at)}.",
           other_alerts_line].compact.join(" ")
        end

        def other_alerts_line
          others = @health.unresolved_count - 1
          return nil unless others.positive?

          "#{pluralize(others, 'other alert')} unresolved."
        end

        def banner_link(alert)
          return unless alert.evaluation_policy_id

          render Atoms::Link.new("Review policy →",
                                 href: continuous_policy_path(alert.evaluation_policy_id),
                                 class: "raaf-health-banner-link")
        end

        def judge_banner(change)
          render Molecules::Alert.new(
            :info,
            title: "#{change[:scorer]} changed judge model",
            text: "It scored with #{change[:was].join(', ')} in the previous #{@range} and " \
                  "#{change[:now].join(', ')} in this one. A judge swap moves the scores it " \
                  "produces without anything about the agent having changed."
          )
        end

        # ── Headline cards ────────────────────────────────────────────────

        def stats
          series = @health.series

          render Organisms::StatGrid.new(stats: [
                                           agreement_card(series),
                                           latency_card(series),
                                           error_card(series),
                                           cost_card(series)
                                         ])
        end

        # Agreement is a comparison, so with nothing to compare against the
        # card says that rather than showing a zero that would read as total
        # disagreement.
        def agreement_card(series)
          agreement = @health.agreement
          value = agreement[:value]

          { label: "Judge agreement", icon: "people",
            value: value ? Kernel.format("%.2f", value) : "—",
            tone: value && agreement_tone(value),
            series: series[:evaluations],
            series_tips: bucket_tips(series[:evaluations]) { |v| pluralize(v.to_i, "evaluation") },
            note: agreement_note(agreement) }
        end

        def agreement_tone(value)
          return :ok if value >= 0.85
          return :warn if value >= 0.7

          :bad
        end

        def agreement_note(agreement)
          return "no span in this window carries a human score" if agreement[:spans].zero?

          "against #{pluralize(agreement[:spans], 'span')} scored by hand"
        end

        def latency_card(series)
          p95 = @health.latency_p95_ms

          { label: "Scorer latency p95", icon: "stopwatch",
            value: p95 ? format_duration(p95) : "—",
            tone: p95 && p95 > 5_000 ? :warn : nil,
            series: series[:latency],
            series_tips: bucket_tips(series[:latency]) { |v| "p95 #{format_duration(v)}" },
            note: slowest_note }
        end

        # The design's note reads "llm judges dominate the tail". Which scorer
        # actually owns the tail is a fact rather than a generalisation, so the
        # card names it.
        def slowest_note
          slowest = @health.scorers.select { |row| row[:p95_ms] }.max_by { |row| row[:p95_ms] }
          return "nothing recorded how long it took" unless slowest

          "#{slowest[:name]} owns the tail at #{format_duration(slowest[:p95_ms])}"
        end

        def error_card(series)
          rate = @health.error_rate

          { label: "Eval error rate", icon: "exclamation-octagon",
            value: rate ? Kernel.format("%.1f%%", rate * 100) : "—",
            tone: rate && error_tone(rate),
            series: series[:errors],
            series_tips: bucket_tips(series[:errors]) { |v| pluralize(v.to_i, "error") },
            note: "#{@health.error_count} of #{number(@health.evaluations)} could not be produced" }
        end

        def error_tone(rate)
          return :bad if rate >= 0.1
          return :warn if rate >= 0.02

          :ok
        end

        # Priced from the judge tokens each evaluation recorded. A policy set
        # with no LLM judge in it spends nothing and reports $0.00, which is a
        # measurement rather than a gap — so the note says which it is.
        def cost_card(series)
          per_1k = @health.cost_per_1k

          { label: "Cost per 1k evals", icon: "cash-stack",
            value: per_1k ? Kernel.format("$%.2f", per_1k) : "—",
            series: series[:cost],
            series_tips: bucket_tips(series[:cost]) { |v| Kernel.format("$%.4f", v.to_f) },
            note: cost_note }
        end

        def cost_note
          return "no scorer called a judge model" if @health.total_cost.zero?

          "#{Kernel.format('$%.2f', @health.total_cost)} across #{number(@health.evaluations)} evaluations"
        end

        # Each bar named by the hour it covers and the reading it stands for.
        # The four cards draw the same buckets, so the labelling is written
        # once and each card supplies only how to read its own numbers.
        def bucket_tips(values)
          starts = @health.bucket_starts

          Array(values).each_with_index.map do |value, index|
            at = starts[index]
            "#{at ? at.strftime('%b %-d %H:%M') : "bucket #{index + 1}"} · #{yield(value)}"
          end
        end

        # ── Scorer table ──────────────────────────────────────────────────

        def scorer_table
          rows = @health.scorers

          render(Organisms::Card.new(title: "Scorer health", subtitle: scorer_subtitle,
                                     flush: true)) do
            grid = Organisms::DataGrid.new(
              columns: SCORER_COLUMNS,
              empty: { icon: "clipboard-data", title: "No scorer has run",
                       text: "A policy's checks appear here once they have graded something." }
            )
            render(grid) { rows.each { |row| scorer_row(grid, row) } }
          end
        end

        def scorer_subtitle
          "Mean score against the previous #{@range}. A scorer that has not run " \
            "recently is stale rather than steady."
        end

        def scorer_row(grid, row)
          grid.row(cells: [
                     { value: scorer_cell(row) },
                     { value: Atoms::Mono.new(score(row[:mean]), tone: row[:mean] ? nil : :muted),
                       align: :right },
                     { value: drift_cell(row[:drift]), align: :right },
                     { value: Atoms::Mono.new(row[:p95_ms] ? format_duration(row[:p95_ms]) : "—",
                                              tone: :muted), align: :right },
                     { value: Atoms::StatusBadge.new(row[:state]), align: :right }
                   ])
        end

        # The design's second line is the scorer's kind. Errors go on the same
        # line when there are any: a judge failing half its calls is the reason
        # its mean moved, and the two belong side by side.
        def scorer_cell(row)
          Molecules::TitleMeta.new(row[:name], scorer_meta(row), mono: true)
        end

        def scorer_meta(row)
          kind = KIND_LABELS.fetch(row[:kind].to_s, row[:kind].presence || "unknown")
          parts = [kind]
          parts << row[:models].join(", ") if row[:models].any?
          parts << "#{row[:errors]} errored" if row[:errors].positive?
          parts.join(" · ")
        end

        # A judge that scores higher than it used to is as much a change as one
        # that scores lower; the colour follows the direction because that is
        # what the design does, and the sign is what carries the meaning.
        def drift_cell(drift)
          return Atoms::Mono.new("—", tone: :muted) if drift.nil?

          Atoms::Mono.new(Kernel.format("%+.1f%%", drift * 100), tone: drift_tone(drift))
        end

        def drift_tone(drift)
          return :muted if drift.abs < ScorerHealth::DRIFT_THRESHOLD

          drift.negative? ? :bad : :ok
        end

        # ── Right rail ────────────────────────────────────────────────────

        def rail
          div(class: "raaf-health-rail") do
            coverage
            events
          end
        end

        def coverage
          rows = @health.coverage

          render(Organisms::Card.new(title: "Coverage by agent", subtitle: coverage_subtitle)) do
            if rows.empty?
              render Molecules::EmptyState.new(
                icon: "diagram-3", title: "No agent to cover",
                text: "No policy names an agent, and no span was graded in this window."
              )
            else
              rows.each { |row| coverage_row(row) }
            end
          end
        end

        def coverage_subtitle
          "Spans graded against the spans a policy could have graded · " \
            "#{pluralize(@health.scored_spans, 'span')} graded in this window."
        end

        # A sampling policy is supposed to read low, so the bar is only tinted
        # when it reads zero — a policy that has graded nothing.
        def coverage_row(row)
          render Molecules::MeterRow.new(
            name: row[:agent],
            value: row[:pct] ? Kernel.format("%.0f%%", row[:pct]) : "—",
            pct: row[:pct] || 0,
            tone: row[:scored].zero? ? :bad : nil,
            sub: coverage_sub(row),
            tip: coverage_tip(row)
          )
        end

        # The row states what was graded; the bar's empty half is what was
        # not, and that is the half somebody would act on. Saying it as a
        # count rather than as the percentage already printed beside the name.
        def coverage_tip(row)
          missed = row[:eligible].to_i - row[:scored].to_i
          return "nothing eligible to grade" if row[:eligible].to_i.zero?
          return "every eligible span was graded" unless missed.positive?

          "#{number(missed)} eligible spans went ungraded"
        end

        def coverage_sub(row)
          counts = "#{number(row[:scored])} of #{number(row[:eligible])} spans"
          return counts if row[:policies].empty?

          "#{counts} · #{row[:policies].join(', ')}"
        end

        def events
          rows = @health.events

          render(Organisms::Card.new(title: "Recent events", flush: true)) do
            if rows.empty?
              render Molecules::EmptyState.new(
                icon: "bell", title: "Nothing raised",
                text: "The alert checker found nothing worth saying in this window."
              )
            else
              rows.each { |alert| event_row(alert) }
            end
          end
        end

        def event_row(alert)
          div(class: "raaf-health-event") do
            render Atoms::Icon.new(ALERT_ICONS.fetch(alert.alert_type, "info-circle"),
                                   tone: SEVERITY_TONES.fetch(alert.severity, :muted))
            div(class: "raaf-health-event-body") do
              span(class: "raaf-health-event-text") { alert.title }
              render Atoms::Mono.new(event_when(alert), tone: :muted)
            end
          end
        end

        def event_when(alert)
          resolved = alert.respond_to?(:resolved?) && alert.resolved?
          [time_ago(alert.triggered_at), resolved ? "resolved" : alert.severity].join(" · ")
        end

        # ── Empty screens ─────────────────────────────────────────────────

        def not_installed
          render(Organisms::Card.new(title: "Continuous evaluation is not installed")) do
            render Atoms::Text.new(
              "This screen reads the raaf-eval tables. They are not present in this database, " \
              "so there is nothing to measure yet — run the engine's migrations to create them.",
              tone: :secondary
            )
          end
        end

        def nothing_scored
          render(Organisms::Card.new(title: "Scorer health")) do
            render Molecules::EmptyState.new(
              icon: "clipboard-data", title: "Nothing was scored in this window",
              text: "A scorer can only be measured against its own output. Widen the range, " \
                    "or check that a policy is active and matching spans."
            )
          end
        end

        # ── Shared ────────────────────────────────────────────────────────

        # `format` is a Phlex::Rails helper that answers the request's format,
        # so the Kernel one has to be named.
        def score(value)
          value ? Kernel.format("%.2f", value) : "—"
        end

        def number(value)
          value.to_i.to_s.reverse.scan(/\d{1,3}/).join(",").reverse
        end
      end
    end
  end
end
