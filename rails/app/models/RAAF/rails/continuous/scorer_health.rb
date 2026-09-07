# frozen_string_literal: true

module RAAF
  module Rails
    module Continuous
      ##
      # Whether the scorers themselves can still be trusted.
      #
      # Every other continuous screen reads an evaluation as a verdict on an
      # agent. This one turns the question round and reads it as a measurement
      # of the evaluator: what it scores on average, whether that average has
      # moved, how long it takes, what it costs, and how much of the traffic it
      # ever sees. A judge whose mean drifts six percent overnight has not
      # discovered that the fleet got worse.
      #
      # Every read the Health screen makes lives here, so the SQL is in one
      # place and the screen holds none of it.
      #
      # Two windows, always: the one being reported, and the one of equal
      # length immediately before it. Drift is the first compared against the
      # second. The design names a fixed 30-day baseline, but the range control
      # belongs to the reader, and a 30-day baseline behind a 7-day window
      # would compare a population with itself.
      #
      # Every read degrades to empty rather than raising. The continuous tables
      # belong to raaf-eval, and a host application that mounted the dashboard
      # without running its migrations should get an empty screen that says so,
      # not a 500.
      class ScorerHealth
        # A mean that moved by less than this is noise on any sample this
        # console is likely to hold.
        DRIFT_THRESHOLD = 0.02

        # A scorer silent through more than half the window has stopped running
        # rather than started agreeing. Half rather than something tighter
        # because a nightly policy is *supposed* to be quiet most of the time,
        # and calling it stale every morning teaches the reader to ignore the
        # word.
        STALE_FRACTION = 0.5

        # Sparkline resolution. Twenty-four bars read as a day-shaped trend at
        # any window length, which is all the bars are for.
        BUCKETS = 24

        # Rows the tables and lists cut to. Long enough to hold every scorer a
        # real policy set declares, short enough that the page stays a page.
        SCORER_LIMIT = 20
        COVERAGE_LIMIT = 8
        EVENT_LIMIT = 8

        # Where an evaluation's own spend is recorded. `metrics["cost"]` beside
        # it is what the graded span cost, which is a different bill.
        COST_KEY = "evaluation_cost"

        # The judge models an LLM evaluator called, recorded per result.
        MODELS_KEY = "evaluation_models"

        # Worst first: a drifting scorer is the reason to open this screen, a
        # stale one is the reason nobody noticed.
        STATE_ORDER = { "drifting" => 0, "stale" => 1, "healthy" => 2 }.freeze

        # The two spellings of the agent name RAAF has written over time,
        # lower-cased because the policy matcher compares case-insensitively.
        AGENT_NAME_SQL =
          "lower(coalesce(span_attributes ->> 'agent.name', span_attributes ->> 'agent_name'))"

        P95_SQL = "percentile_cont(0.95) WITHIN GROUP (ORDER BY evaluation_duration_ms)"

        STATS_SQL = <<~SQL.squish
          evaluator_name, count(*), avg(score),
          count(*) FILTER (WHERE status = 'error'),
          max(evaluator_type), max(created_at)
        SQL

        def initialize(window: 7.days, now: Time.current)
          @window = window
          @now = now
        end

        attr_reader :window, :now

        def from = @now - @window
        def baseline_from = @now - (@window * 2)

        # Whether the continuous tables are there to be read at all.
        def available?
          return @available if defined?(@available)

          @available = defined?(RAAF::Eval::Models::ContinuousEvaluationResult) &&
                       RAAF::Eval::Models::ContinuousEvaluationResult.table_exists?
        rescue StandardError
          @available = false
        end

        # ── The four headline figures ─────────────────────────────────────

        # How many evaluations the window holds. Nothing else on the page means
        # anything without it.
        def evaluations = totals[:count]

        def scored_spans
          @scored_spans ||= scored_by_agent.values.sum
        end

        # Judge agreement with the people who scored the same spans by hand.
        #
        # The design pairs this figure with a 250-span audit. RAAF runs no
        # audit, but it does have `FeedbackScore`, which is where a human
        # verdict on a span is recorded — so the number is real wherever
        # anybody has scored one, and honestly absent where nobody has. Human
        # scores are normalised onto 0–1 through their definition's range
        # first: a 4 on a 1–5 scale is agreement, not a rout.
        #
        # Agreement is one minus the mean absolute gap, so 1.00 is two scorers
        # that always land on the same number.
        #
        # @return [Hash] :value (0–1, or nil), :spans compared
        def agreement
          @agreement ||= compute_agreement
        end

        # p95 of how long an evaluation took to produce, in milliseconds.
        def latency_p95_ms
          return @latency_p95_ms if defined?(@latency_p95_ms)

          @latency_p95_ms = scoped(from..@now)
                            .where.not(evaluation_duration_ms: nil)
                            .pick(Arel.sql(P95_SQL))&.to_f
        rescue StandardError
          @latency_p95_ms = nil
        end

        # The share of evaluations that could not be produced at all. `error`
        # is the evaluator breaking; `bad` is the evaluator working and not
        # liking what it saw, which is the system doing its job.
        def error_rate
          return nil if totals[:count].zero?

          totals[:errors].to_f / totals[:count]
        end

        def error_count = totals[:errors]

        # What a thousand evaluations cost to run, priced from the judge tokens
        # each one recorded. A rule-based scorer spends nothing and records
        # zero, which is a measurement rather than a gap — so a policy set with
        # no LLM judge in it correctly reports $0.00 rather than nothing.
        def cost_per_1k
          return nil if totals[:count].zero?

          totals[:cost] / totals[:count] * 1000
        end

        def total_cost = totals[:cost]

        # ── Sparklines ────────────────────────────────────────────────────

        # One value per bucket, oldest first, for each headline card.
        #
        # @return [Hash] :evaluations, :latency, :errors, :cost
        def series
          @series ||= {
            evaluations: buckets.map { |b| b[:count] },
            latency: buckets.map { |b| b[:p95].to_f },
            errors: buckets.map { |b| b[:errors] },
            cost: buckets.map { |b| b[:cost] }
          }
        end

        # When each bucket began. The bars are cut evenly across the window,
        # so this is arithmetic rather than a second query — and without it a
        # sparkline can show a spike without saying which hour it was.
        #
        # @return [Array<Time>] BUCKETS entries, oldest first
        def bucket_starts
          @bucket_starts ||= begin
            span = (@now - from) / BUCKETS
            Array.new(BUCKETS) { |index| from + (span * index) }
          end
        end

        # ── Scorer health ─────────────────────────────────────────────────

        # One row per evaluator, worst first.
        #
        # The row set is the union of both windows, so an evaluator that ran
        # last week and has since stopped is listed as stale rather than
        # quietly disappearing — which is the failure this table exists to
        # catch.
        #
        # @return [Array<Hash>] :name, :kind, :models, :mean, :baseline,
        #   :drift, :p95_ms, :count, :errors, :last_at, :state
        def scorers
          @scorers ||= (current_stats.keys | baseline_stats.keys)
                       .map { |name| scorer_row(name) }
                       .sort_by { |row| [STATE_ORDER.fetch(row[:state], 9), -row[:count]] }
                       .first(SCORER_LIMIT)
        end

        # ── Coverage ──────────────────────────────────────────────────────

        # How much of each agent's gradeable traffic was actually graded.
        #
        # The denominator is the population a policy could grade, not every
        # span recorded: an agent span carrying a final response that an
        # evaluation did not itself produce. That is the population
        # `PolicySpanLookup` offers, so a policy sampling one span in ten
        # should read 10% here rather than some smaller share of a larger
        # number.
        #
        # @return [Array<Hash>] :agent, :scored, :eligible, :pct, :policies
        def coverage
          @coverage ||= (policy_agents.keys | scored_by_agent.keys | eligible_by_agent.keys)
                        .map { |key| coverage_row(key) }
                        .sort_by { |row| [governed(row), row[:pct] || -1, -row[:eligible]] }
                        .first(COVERAGE_LIMIT)
        end

        # ── Events ────────────────────────────────────────────────────────

        # What the alert checker has had to say lately, newest first.
        #
        # The design's list mixes alerts with configuration changes — a policy
        # paused, a sampling rate raised. RAAF keeps no audit trail of those: a
        # policy carries its current state and an `updated_at`, which cannot
        # say what changed. Alerts are the events RAAF actually records.
        #
        # @return [Array<RAAF::Eval::Models::EvaluationAlert>]
        def events
          @events ||= alerts.where(triggered_at: from..@now)
                            .order(triggered_at: :desc)
                            .limit(EVENT_LIMIT).to_a
        rescue StandardError
          []
        end

        # The one thing wrong right now, for the banner: the most severe
        # unresolved alert, and the newest of that severity.
        #
        # @return [RAAF::Eval::Models::EvaluationAlert, nil]
        def headline_alert
          return @headline_alert if defined?(@headline_alert)

          unresolved = alerts.unresolved.to_a
          @headline_alert = %w[critical warning info].filter_map do |severity|
            unresolved.select { |alert| alert.severity == severity }.max_by(&:triggered_at)
          end.first
        rescue StandardError
          @headline_alert = nil
        end

        def unresolved_count
          @unresolved_count ||= alerts.unresolved.count
        rescue StandardError
          0
        end

        # A judge model swapped underneath a scorer, which moves its scores
        # without anything about the agent having changed. The design's banner
        # is exactly this event; here it is read back out of what each
        # evaluation recorded about the models it called.
        #
        # @return [Array<Hash>] :scorer, :was, :now
        def judge_changes
          @judge_changes ||= (current_models.keys & baseline_models.keys).filter_map do |name|
            was = baseline_models[name].sort
            became = current_models[name].sort
            next if was == became

            { scorer: name, was: was, now: became }
          end
        end

        private

        def result_class = RAAF::Eval::Models::ContinuousEvaluationResult

        def scoped(range)
          result_class.where(created_at: range)
        end

        def alerts = RAAF::Eval::Models::EvaluationAlert.all

        # ── The one read the cards and sparklines share ────────────────────

        # Count, errors, p95 latency and spend, per bucket, in a single pass.
        #
        # Every headline figure is a total over these buckets rather than a
        # query of its own, so the cards and the sparkline under each of them
        # cannot come to disagree about the same window.
        #
        # `width_bucket` does the bucketing in the database; the `least` caps
        # a row landing exactly on the window's upper bound, which it puts in
        # an overflow bucket of its own.
        #
        # @return [Array<Hash>] BUCKETS entries, oldest first
        def buckets
          @buckets ||= begin
            empty = Array.new(BUCKETS) { { count: 0, errors: 0, p95: 0.0, cost: 0.0 } }
            bucket_rows.each_with_object(empty) do |(index, count, errors, p95, cost), acc|
              slot = index.to_i - 1
              next unless slot.between?(0, BUCKETS - 1)

              acc[slot] = { count: count.to_i, errors: errors.to_i,
                            p95: p95.to_f, cost: cost.to_f }
            end
          end
        end

        def bucket_rows
          return [] unless available?

          sql = result_class.sanitize_sql_array(
            [<<~SQL.squish, from.to_f, @now.to_f, from, @now]
              SELECT least(width_bucket(extract(epoch from created_at), ?, ?, #{BUCKETS}), #{BUCKETS}),
                     count(*),
                     count(*) FILTER (WHERE status = 'error'),
                     coalesce(percentile_cont(0.95) WITHIN GROUP (ORDER BY evaluation_duration_ms), 0),
                     coalesce(sum(coalesce((metrics ->> '#{COST_KEY}')::numeric, 0)), 0)
              FROM #{result_class.table_name}
              WHERE created_at >= ? AND created_at <= ?
              GROUP BY 1
            SQL
          )

          result_class.connection.select_rows(sql)
        rescue StandardError
          []
        end

        # The headline figures, summed off the same buckets the sparklines
        # draw, so a card and the bars under it always agree.
        def totals
          @totals ||= buckets.each_with_object({ count: 0, errors: 0, cost: 0.0 }) do |bucket, acc|
            acc[:count] += bucket[:count]
            acc[:errors] += bucket[:errors]
            acc[:cost] += bucket[:cost]
          end
        end

        # ── Scorer rows ───────────────────────────────────────────────────

        def scorer_row(name)
          stats = current_stats[name]
          baseline = baseline_stats[name]
          mean = stats && stats[:mean]
          drift = drift_for(mean, baseline && baseline[:mean])
          last_at = (stats || baseline || {})[:last_at]

          { name: name,
            kind: (stats || baseline || {})[:kind],
            models: current_models[name] || baseline_models[name] || [],
            mean: mean,
            baseline: baseline && baseline[:mean],
            drift: drift,
            p95_ms: p95_by_scorer[name],
            count: stats ? stats[:count] : 0,
            errors: stats ? stats[:errors] : 0,
            last_at: last_at,
            state: state_for(stats, drift, last_at) }
        end

        # Relative movement of the mean, which is how a score reads: a judge
        # that fell from 0.87 to 0.82 lost six percent of its verdict, not five
        # points of something.
        def drift_for(mean, baseline)
          return nil if mean.nil? || baseline.nil? || baseline.zero?

          (mean - baseline) / baseline
        end

        # Drift is asked first. A scorer that moved and then went quiet is both
        # things, and the drift is the one somebody has to do something about —
        # answering "stale" there would file the finding under "nothing has
        # happened lately", which is the opposite of what happened.
        def state_for(stats, drift, last_at)
          return "drifting" if drift && drift.abs >= DRIFT_THRESHOLD
          return "stale" if stats.nil?
          return "stale" if last_at && last_at < @now - (@window * STALE_FRACTION)

          "healthy"
        end

        def current_stats = @current_stats ||= stats_for(from..@now)
        def baseline_stats = @baseline_stats ||= stats_for(baseline_from...from)

        # Count, mean, errors, kind and last run per evaluator, in one grouped
        # query. `max(evaluator_type)` rather than a group on it: an evaluator
        # that changed type mid-window is still one row in this table, and the
        # type is a label on it rather than part of its identity.
        def stats_for(range)
          return {} unless available?

          rows = scoped(range).group(:evaluator_name).pluck(Arel.sql(STATS_SQL))

          rows.to_h do |name, count, mean, errors, kind, last_at|
            [name, { count: count.to_i, mean: mean&.to_f, errors: errors.to_i,
                     kind: kind, last_at: last_at }]
          end
        rescue StandardError
          {}
        end

        # p95 stays in the database: it is the one per-scorer figure that would
        # otherwise need every row's duration loaded.
        def p95_by_scorer
          @p95_by_scorer ||= scoped(from..@now)
                             .where.not(evaluation_duration_ms: nil)
                             .group(:evaluator_name)
                             .pluck(Arel.sql("evaluator_name, #{P95_SQL}"))
                             .to_h { |name, p95| [name, p95&.to_f] }
        rescue StandardError
          {}
        end

        def current_models = @current_models ||= models_for(from, @now)
        def baseline_models = @baseline_models ||= models_for(baseline_from, from)

        # Which judge models each scorer called in a window, busiest first.
        #
        # The array lives inside the metrics document, so it is unnested in SQL
        # rather than by loading every row. A rule-based scorer records no
        # array at all, and `jsonb_typeof` is what keeps that from raising.
        def models_for(range_from, range_to)
          return {} unless available?

          sql = result_class.sanitize_sql_array(
            [<<~SQL.squish, range_from, range_to]
              SELECT evaluator_name, model, count(*) AS uses FROM (
                SELECT evaluator_name,
                       jsonb_array_elements_text(metrics -> '#{MODELS_KEY}') AS model
                FROM #{result_class.table_name}
                WHERE created_at >= ? AND created_at < ?
                  AND jsonb_typeof(metrics -> '#{MODELS_KEY}') = 'array'
              ) unnested
              GROUP BY 1, 2
              ORDER BY uses DESC
            SQL
          )

          result_class.connection.select_rows(sql).each_with_object({}) do |(name, model, _uses), models|
            (models[name] ||= []) << model
          end
        rescue StandardError
          {}
        end

        # ── Agreement ─────────────────────────────────────────────────────

        def compute_agreement
          human = human_scores_by_span
          return { value: nil, spans: 0 } if human.empty?

          judged = scoped(from..@now).where(span_id: human.keys)
                                     .where.not(score: nil)
                                     .group(:span_id).average(:score)
          return { value: nil, spans: 0 } if judged.empty?

          gaps = judged.map { |span_id, score| (human[span_id] - score.to_f).abs }
          { value: 1.0 - (gaps.sum / gaps.size), spans: gaps.size }
        rescue StandardError
          { value: nil, spans: 0 }
        end

        # Human verdicts on spans in the window, normalised onto 0–1 through
        # each score's own definition. A score with no definition is taken to
        # be on 0–1 already, which is what `FeedbackScore` documents; one whose
        # value falls outside its declared range is dropped rather than
        # clamped, because a value that cannot be placed on the scale it claims
        # says nothing about agreement.
        def human_scores_by_span
          scores = RAAF::Eval::Models::FeedbackScore
                   .from_humans.numerical
                   .where.not(span_id: nil)
                   .where(created_at: from..@now)
                   .pluck(:span_id, :name, :value)
          return {} if scores.empty?

          ranges = definition_ranges(scores.map { |(_span, name, _value)| name }.uniq)

          scores.filter_map do |span_id, name, value|
            normalised = normalise(value, ranges[name])
            [span_id, normalised] if normalised
          end.group_by(&:first)
                .transform_values { |pairs| pairs.sum { |(_span, value)| value } / pairs.size }
        rescue StandardError
          {}
        end

        def definition_ranges(names)
          RAAF::Eval::Models::FeedbackScoreDefinition
            .where(name: names, score_type: "numerical")
            .pluck(:name, :min_value, :max_value)
            .to_h { |name, min, max| [name, [min, max]] }
        rescue StandardError
          {}
        end

        def normalise(value, range)
          min, max = range || [0.0, 1.0]
          min = min.nil? ? 0.0 : min.to_f
          max = max.nil? ? 1.0 : max.to_f
          return nil if max <= min || value < min || value > max

          (value - min) / (max - min)
        end

        # ── Coverage ──────────────────────────────────────────────────────

        # An agent a policy names, or one something has actually graded, is what
        # this card is about. An agent with neither sorts after them and is the
        # first thing the cut drops: it is ungoverned traffic, which the Agents
        # screen is the place to read.
        def governed(row)
          row[:policies].any? || row[:scored].positive? ? 0 : 1
        end

        def coverage_row(key)
          eligible = eligible_by_agent[key].to_i
          scored = scored_by_agent[key].to_i

          { agent: display_names[key] || key,
            scored: scored,
            eligible: eligible,
            pct: eligible.positive? ? (scored.to_f / eligible * 100).clamp(0, 100) : nil,
            policies: Array(policy_agents[key]) }
        end

        # Spans a policy could have graded, per agent, keyed case-insensitively
        # because that is how the policy matcher compares names.
        def eligible_by_agent
          @eligible_by_agent ||= RAAF::Rails::Tracing::SpanRecord
                                 .where("kind = 'agent'")
                                 .where(start_time: from..@now)
                                 .where("span_attributes ->> 'agent.final_agent_response' IS NOT NULL")
                                 .where("span_attributes ->> 'source' IS DISTINCT FROM 'evaluation_run'")
                                 .group(Arel.sql(AGENT_NAME_SQL))
                                 .count
                                 .except(nil)
        rescue StandardError
          {}
        end

        # Distinct spans graded, per agent. One span graded by four checks is
        # one span covered, not four.
        def scored_by_agent
          @scored_by_agent ||= compute_scored_by_agent
        end

        def compute_scored_by_agent
          return {} unless available?

          scoped(from..@now).group(:agent_name).distinct.count(:span_id)
                            .transform_keys { |name| name.to_s.downcase }
                            .except("")
        rescue StandardError
          {}
        end

        # The agents policies name, and which policies name them. Wildcards and
        # "all" are left out: a policy matching everything has no coverage of
        # its own to report, and inventing a row per agent it happens to have
        # touched would say something the policy does not.
        def policy_agents
          @policy_agents ||= declared_agents.each_with_object({}) do |(policy, agent), map|
            (map[agent.downcase] ||= []) << policy
          end
        end

        # The spelling to show, since the coverage key is lower-cased so the
        # two sides can be matched.
        def display_names
          @display_names ||= declared_agents.to_h { |(_policy, agent)| [agent.downcase, agent] }
                                            .merge(result_agent_names)
        end

        # @return [Array<Array(String, String)>] policy name, agent name
        def declared_agents
          @declared_agents ||= RAAF::Eval::Models::EvaluationPolicy
                               .pluck(:name, :agent_name)
                               .flat_map do |policy, declared|
            declared.to_s.split(",").map(&:strip)
                    .reject { |agent| agent.blank? || agent == "all" || agent.include?("*") }
                    .map { |agent| [policy, agent] }
          end
        rescue StandardError
          []
        end

        def result_agent_names
          return {} unless available?

          scoped(from..@now).distinct.pluck(:agent_name).compact
                            .index_by { |name| name.downcase }
        rescue StandardError
          {}
        end
      end
    end
  end
end
