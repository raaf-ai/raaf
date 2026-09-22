# frozen_string_literal: true

module RAAF
  module Rails
    module Continuous
      ##
      # Every evaluator's score, bucket by bucket — the data behind the Score
      # trends screen in RAAF Eval.dc.html, which the console carries under
      # Continuous rather than Evaluate: what it reads is the continuous
      # pipeline's own results table.
      #
      # One row per evaluator, one cell per bucket, oldest first. A bucket
      # nothing was scored in carries `nil` rather than zero, so the screen can
      # draw it as a gap: an evaluator that ran on Tuesday and not on Wednesday
      # did not score 0.0 on Wednesday.
      #
      # Two of the design's readings are not here, and both are data rather
      # than layout:
      #
      # - **Weights.** The design's headline row is a weighted mean and each
      #   evaluator carries a weight. Nothing stores one — an evaluator's
      #   `config` is empty — so the headline is the plain mean across
      #   evaluators and says so, rather than presenting a made-up weighting as
      #   a measurement.
      # - **Thresholds.** The design tones a cell against a per-evaluator
      #   threshold. Only the console-wide score tiers exist, so those are what
      #   the absolute mode uses.
      #
      # The bucket boundaries are worked out in Ruby rather than by `date_trunc`,
      # for the same reasons the policy trend's are: there is no portable
      # spelling for "the minute this row falls in, counted back from now", and
      # stepping by duration keeps the day the clocks go back one day long
      # instead of drifting an hour through every bucket after it. The rows are
      # then put into those buckets by the database, which is where a month of
      # them can be added up without being carried anywhere first.
      #
      class ScoreTrendSeries
        # What one cell covers, per topbar range. A day per cell says nothing
        # over an hour, and a minute per cell is 43,200 cells over a month.
        BUCKETS = {
          "1h" => { size: 1.minute, unit: "minute", format: "%H:%M" },
          "24h" => { size: 1.hour, unit: "hour", format: "%H:%M" },
          "7d" => { size: 1.day, unit: "day", format: "%b %d" },
          "30d" => { size: 1.day, unit: "day", format: "%b %d" }
        }.freeze

        # How the window is said out loud, in the meta line and the empty state.
        WINDOWS = { "1h" => "1 hour", "24h" => "24 hours",
                    "7d" => "7 days", "30d" => "30 days" }.freeze

        # `evaluator_type` in the console's words. The design writes "rule" and
        # "LLM judge" on the row, not the enum value.
        KINDS = { "rule_based" => "rule", "llm_judge" => "LLM judge",
                  "statistical" => "statistical", "custom" => "custom" }.freeze

        # Feedback scores are attached to a span or a trace, never to an agent,
        # so the human rows say so instead of leaving the column blank.
        HUMAN = "human"
        HUMAN_AGENT = "all agents"

        # The grid is a row per evaluator and the screen has to stay a screen.
        # The busiest evaluators win the space, and the count of what was left
        # out is reported rather than silently dropped.
        MAX_ROWS = 24

        # @param range [String] one of {RAAF::Rails::TimeRange::RANGES}
        # @return [Hash] see {#call}
        def self.call(range: "30d")
          new(range: range).call
        end

        def initialize(range: "30d")
          @range = BUCKETS.key?(range) ? range : "30d"
          @bucket = BUCKETS.fetch(@range)
        end

        # @return [Hash]
        #   :range, :window ("30 days"), :unit ("day"), :delta_window ("7d"),
        #   :buckets — one per cell, each :at, :label and :release
        #   :rows — one per evaluator, each :name, :agent, :kind, :series,
        #     :count, :current, :median and :delta
        #   :overall — :series, :current and :delta across every row
        #   :total_rows, :hidden_rows
        def call
          rows = ranked_rows

          { range: @range, window: WINDOWS.fetch(@range), unit: @bucket[:unit],
            delta_window: delta_window, buckets: buckets, rows: rows.first(MAX_ROWS),
            overall: overall(rows.first(MAX_ROWS)),
            total_rows: rows.size, hidden_rows: [rows.size - MAX_ROWS, 0].max }
        rescue StandardError => e
          empty(e)
        end

        private

        # ── The grid ──────────────────────────────────────────────────────

        # The newest bucket starts at the top of the one the clock is in, so
        # the last cell covers a whole bucket rather than however many seconds
        # have passed since it opened.
        def starts
          @starts ||= begin
            size = @bucket[:size]
            last = bucket_start(Time.current, size)
            (0...bucket_count).map { |index| last - ((bucket_count - 1 - index) * size) }
          end
        end

        def bucket_count
          @bucket_count ||= (RAAF::Rails::TimeRange::RANGES.fetch(@range) / @bucket[:size]).round
        end

        def bucket_start(time, size)
          case size
          when 1.day then time.beginning_of_day
          when 1.hour then time.beginning_of_hour
          else time.beginning_of_minute
          end
        end

        def window_start
          starts.first
        end

        def buckets
          @buckets ||= starts.each_with_index.map do |at, index|
            { at: at, label: at.strftime(@bucket[:format]), release: releases[index] }
          end
        end

        # ── Rows ──────────────────────────────────────────────────────────

        def ranked_rows
          (evaluator_rows + feedback_rows).sort_by { |row| -row[:count] }
        end

        # One row per check, keyed by the four things that make a line on this
        # screen distinct: what the evaluator is called, which check of it this
        # is, what it grades and how it grades. The same check run against two
        # agents is two rows, because a drift in one of them is not a drift in
        # the other.
        #
        # The check is in the key because two evaluators on one field used to
        # share a score: a rule and a judge grading `confidence` produced one
        # number, plotted once under the evaluator's name, and neither of them
        # could be watched on its own. Rows recorded before that changed carry
        # no check and stay one line per evaluator, which is all they can be.
        def evaluator_rows
          totals = Hash.new { |hash, key| hash[key] = {} }

          bucketed(result_model, keys: evaluator_keys, score: "score")
            .each do |name, agent, type, check, index, sum, count|
              totals[[name, agent, type, check]][index.to_i] = { sum: sum.to_f, count: count.to_i }
            end

          totals.map do |(name, agent, type, check), buckets_seen|
            row(name: line_name(name, check), agent: agent,
                kind: KINDS.fetch(type.to_s, type.to_s), buckets_seen: buckets_seen)
          end
        end

        # A console whose database has not been migrated to record the check
        # asks for a column that is not there otherwise.
        def evaluator_keys
          keys = %w[evaluator_name agent_name evaluator_type]
          keys << (result_model.check_key_stored? ? "check_key" : "NULL::text")
        end

        # The evaluator names the row; the check says which of its questions
        # this line answers, and only where there is one to say.
        def line_name(name, check)
          check.presence ? "#{name} · #{check}" : name.to_s
        end

        # Human scores are a real trend line and the design gives them a row of
        # their own. Only numerical ones: a categorical "good" has no position
        # on a 0–1 scale, and inventing one would tone the grid off a guess.
        def feedback_rows
          return [] unless feedback_model&.table_exists?

          totals = Hash.new { |hash, key| hash[key] = {} }

          bucketed(feedback_model, keys: %w[name], score: "value")
            .each do |name, index, sum, count|
              totals[name][index.to_i] = { sum: sum.to_f, count: count.to_i }
            end

          totals.map do |name, buckets_seen|
            row(name: name, agent: HUMAN_AGENT, kind: HUMAN, buckets_seen: buckets_seen)
          end
        rescue StandardError
          []
        end

        def row(name:, agent:, kind:, buckets_seen:)
          series = Array.new(bucket_count) do |index|
            entry = buckets_seen[index]
            entry && (entry[:sum] / entry[:count])
          end

          { name: name.to_s, agent: agent.to_s, kind: kind, series: series,
            count: buckets_seen.values.sum { |entry| entry[:count] },
            current: series.compact.last, median: median(series.compact),
            delta: delta(series) }
        end

        # ── The headline row ──────────────────────────────────────────────

        # The mean across evaluators per bucket, not the mean across results:
        # a rule firing on every span would otherwise drown out a judge that
        # samples one in fifty, and the screen is about the evaluators.
        def overall(rows)
          series = Array.new(bucket_count) do |index|
            scores = rows.filter_map { |row| row[:series][index] }
            scores.empty? ? nil : scores.sum / scores.size
          end

          { series: series, current: series.compact.last, delta: delta(series) }
        end

        # ── Movement ──────────────────────────────────────────────────────

        # The design compares the last week against the week before it on a
        # 30-day grid. A quarter of the window either side is that rule said in
        # a way the other three windows can answer too.
        def half
          @half ||= [(bucket_count / 4.0).floor, 1].max
        end

        def delta_window
          duration = half * @bucket[:size]

          case @bucket[:unit]
          when "day" then "#{(duration / 1.day).round}d"
          when "hour" then "#{(duration / 1.hour).round}h"
          else "#{(duration / 1.minute).round}m"
          end
        end

        # Nil unless both halves have something in them — "no change" and "we
        # have not scored anything since Tuesday" are different answers, and
        # only one of them is reassuring.
        def delta(series)
          recent = series.last(half).compact
          prior = series[-(half * 2), half].to_a.compact
          return nil if recent.empty? || prior.empty?

          (recent.sum / recent.size) - (prior.sum / prior.size)
        end

        def median(values)
          return nil if values.empty?

          values.sort[values.size / 2]
        end

        # ── Releases ──────────────────────────────────────────────────────

        # The design marks the day a version shipped against the grid, which is
        # the whole point of reading a score by day: a step down on the column
        # a release lands in is the release. `agent_version` is what records it,
        # and a console that never sets it simply gets no markers.
        #
        # Only versions whose first result of all falls inside the window: one
        # that was already running when the window opened is not news.
        #
        # That reading used to be taken by grouping the whole table by version
        # and keeping the debuts that landed in the window — a scan of every
        # result there has ever been, to mark at most a handful of columns, and
        # one that cost the same whether the window was an hour or a month.
        # The scan is the window now, and a version seen in it earns its marker
        # by there being nothing of that version before the window opened,
        # which migration 011 answers from an index rather than another scan.
        # The rescue is inside the memo so a console without the tables asks
        # once rather than once per column of the grid.
        def releases
          @releases ||= begin
            debuts.each_with_object({}) do |(version, index), marks|
              marks[index] = [marks[index], version].compact.join(" · ")
            end
          rescue StandardError
            {}
          end
        end

        # @return [Array<Array(String, Integer)>] version and the bucket it
        #   first appears in, ordered by version so two in one bucket read the
        #   same way twice.
        def debuts
          model = result_model
          sql = model.sanitize_sql_array([<<~SQL.squish, window_start, window_start])
            SELECT r.agent_version, #{bucket_of('min(r.created_at)')}
            FROM #{model.table_name} r
            WHERE r.created_at >= ?::timestamptz AND r.agent_version IS NOT NULL
            GROUP BY r.agent_version
            HAVING NOT EXISTS (
              SELECT 1 FROM #{model.table_name} p
              WHERE p.agent_version = r.agent_version AND p.created_at < ?::timestamptz
            )
            ORDER BY r.agent_version
          SQL

          model.connection.select_rows(sql).map { |version, index| [version, index.to_i] }
        end

        # ── Reading ───────────────────────────────────────────────────────

        # The scores in the window, summed and counted per key per bucket.
        #
        # One GROUP BY, where this used to pluck every scored row in the window
        # and fold it up in Ruby. A month of continuous evaluation is a month of
        # results crossing the wire to become twenty-four rows of thirty numbers
        # — and the same code looked fine at an hour's range, which is why only
        # the long windows felt slow.
        #
        # @return [Array<Array>] the key columns, then bucket index, sum, count
        def bucketed(model, keys:, score:)
          sql = model.sanitize_sql_array([<<~SQL.squish, window_start])
            SELECT #{keys.join(', ')}, #{bucket_of('created_at')}, sum(#{score}), count(*)
            FROM #{model.table_name}
            WHERE created_at >= ?::timestamptz AND #{score} IS NOT NULL
            GROUP BY #{(1..(keys.size + 1)).to_a.join(', ')}
          SQL

          model.connection.select_rows(sql)
        end

        # Which bucket a timestamp falls in, in SQL.
        #
        # `width_bucket` is the same binary search this did per row in Ruby, run
        # over the very bucket starts computed above — so the boundaries are
        # still the ones worked out there, and the reasoning about the day the
        # clocks go back still holds. `date_trunc` would have had to rediscover
        # them, and could not have expressed a minute counted back from now.
        #
        # The thresholds are written into the statement rather than bound: a
        # bound Ruby array is quoted as a comma-separated list, not as an array
        # literal, and these are floats this class produced itself.
        def bucket_of(column)
          thresholds = starts.map { |at| at.to_f.round(3) }.join(", ")

          "width_bucket(extract(epoch from #{column})::float8, ARRAY[#{thresholds}]::float8[]) - 1"
        end

        # ── Models ────────────────────────────────────────────────────────

        def result_model
          RAAF::Eval::Models::ContinuousEvaluationResult
        end

        def feedback_model
          return nil unless defined?(RAAF::Eval::Models::FeedbackScore)

          RAAF::Eval::Models::FeedbackScore
        end

        # A console whose evaluation tables have not been migrated in should
        # lose the numbers, not the page.
        def empty(error)
          { range: @range, window: WINDOWS.fetch(@range), unit: @bucket[:unit],
            delta_window: delta_window, buckets: buckets, rows: [],
            overall: { series: [], current: nil, delta: nil },
            total_rows: 0, hidden_rows: 0, error: error.message }
        end
      end
    end
  end
end
