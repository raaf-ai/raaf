# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      ##
      # The dashboard landing page: headline figures, then the two lists that
      # answer "what ran" and "what broke".
      #
      # Composed entirely from Glass Morph components — the page describes what
      # it shows, and the library decides how it looks.
      #
      class DashboardIndex < BaseComponent
        # @param error_signatures [Array<Hash>] rows from
        #   {SpanRecord.error_signatures} — already grouped, already windowed
        # @param workflow_spend [Hash] workflow name => cost in USD; a missing
        #   workflow recorded no usage at all
        # @param agent_series [Hash] workflow name => `{ counts:, tones: }` per
        #   time bucket, for the sparkline the design puts on each agent card
        # @param workflow_models [Hash] workflow name => the model it mostly
        #   ran; a missing workflow recorded no model at all
        def initialize(overview_stats:, top_workflows:, recent_traces:, error_signatures: [],
                       workflow_spend: {}, agent_series: {}, workflow_models: {})
          @overview_stats = overview_stats
          @top_workflows = top_workflows
          @recent_traces = recent_traces
          @error_signatures = error_signatures || []
          @workflow_spend = workflow_spend || {}
          @agent_series = agent_series || {}
          @workflow_models = workflow_models || {}
        end

        # The design's Overview is the KPI row and the split beneath it. The
        # date-range form that used to sit between them is not in it — and
        # since the topbar's range control now drives this screen, it was a
        # second, larger control for the same window. "Top workflows" is not in
        # it either: it ranked the same agents the health grid already shows,
        # by the same numbers.
        def view_template
          kpis
          overview_split
        end

        # The exception class carries most of what a reader needs, so it leads.
        # "Error" and "No message recorded" are what the grouping substitutes
        # for a span that recorded neither, and neither is worth printing
        # beside something real.
        PLACEHOLDERS = ["Error", "No message recorded"].freeze

        TRACE_TONES = { "completed" => :ok, "ok" => :ok, "running" => :info,
                        "failed" => :bad, "error" => :bad }.freeze

        private

        # The KPI row from RAAF Console.dc.html — label + icon, a 30px tabular
        # figure with its delta, and a supporting note.
        def kpis
          render Organisms::StatGrid.new(stats: kpi_stats)
        end

        def kpi_stats
          [
            { label: "Runs", value: number(@overview_stats[:total_traces]), tone: :accent,
              note: "traces started · selected range", icon: "diagram-3" },
            { label: "Failure rate", value: failure_rate, tone: :danger,
              note: "#{number(@overview_stats[:failed_traces])} failed · " \
                    "#{number(@overview_stats[:error_spans])} error spans",
              icon: "exclamation-octagon", href: dashboard_errors_path },
            { label: "Avg duration", value: average_duration, tone: :warning,
              note: "across #{number(@overview_stats[:total_spans])} spans", icon: "speedometer2" },
            { label: "Spend", value: total_spend, tone: :success,
              note: spend_note, icon: "cash-stack", href: dashboard_costs_path }
          ]
        end

        # Spend takes the fourth slot from Success rate, which was Failure
        # rate's complement: the two differed only by the traces still
        # running, so one of them restated the other and the row carried
        # three figures in four tiles. What the window cost is not derivable
        # from anything else on the screen.
        def total_spend
          return "—" if @workflow_spend.empty?

          "$#{'%.2f' % @workflow_spend.values.sum(0.0)}"
        end

        def spend_note
          return "nothing billed · selected range" if @workflow_spend.empty?

          "#{pluralize(@workflow_spend.size, 'workflow')} billed"
        end

        # The Overview's main split, per RAAF Console.dc.html: the agent fleet
        # on the left, the two watchlists stacked on the right.
        def overview_split
          div(class: "raaf-split-main") do
            render Organisms::AgentHealthGrid.new(agents: agent_tiles,
                                                  note: "By agent, over the selected range")

            div(class: "raaf-split-side") do
              render Organisms::FailingNowPanel.new(groups: error_groups,
                                                    action_href: dashboard_errors_path)
              render Organisms::LiveRunsPanel.new(traces: live_runs,
                                                  action_href: tracing_traces_path)
            end
          end
        end

        def agent_tiles
          @top_workflows.to_a.map do |workflow|
            rate = (100 - workflow[:success_rate].to_f).round(1)
            health = health_for(rate)
            series = @agent_series[workflow[:workflow_name]] || {}

            {
              name: workflow[:workflow_name],
              model: @workflow_models[workflow[:workflow_name]],
              runs: number(workflow[:trace_count]),
              health: health,
              error_rate: "#{rate}%",
              p95: format_duration(workflow[:p95_duration] && (workflow[:p95_duration] * 1000)),
              spend: spend_for(workflow[:workflow_name]),
              series: series[:counts],
              series_tones: series[:tones],
              series_tips: agent_series_tips(series),
              href: tracing_traces_path(workflow: workflow[:workflow_name])
            }
          end
        end

        # What each bar in an agent tile stands for. A red bar says something
        # failed but not when, and "when" is the only question a spike raises.
        def agent_series_tips(series)
          counts = Array(series[:counts])
          return [] if counts.empty?

          starts = Array(series[:starts])
          fails = Array(series[:fails])

          counts.each_index.map do |index|
            failed = fails[index].to_i

            [bucket_at(starts[index]),
             pluralize(counts[index].to_i, "run"),
             failed.positive? ? "#{number(failed)} failed" : nil].compact.join(" · ")
          end
        end

        def bucket_at(at)
          at&.strftime("%b %-d %H:%M")
        end

        # The error signatures for the window, most frequent first.
        #
        # Grouping happens in {SpanRecord.error_signatures} rather than here,
        # so this panel names a failure exactly as the Errors screen does. The
        # grouping it replaced dug a symbol-keyed hash with a string key, which
        # always missed: every failure in the window collapsed into one row
        # reading "Unknown error", whatever the exceptions actually were.
        def error_groups
          @error_signatures.to_a.map do |row|
            {
              kind: row[:kind],
              agent: row[:agent],
              count: row[:count],
              message: error_message(row),
              meta: error_meta(row),
              href: trace_span_path(row[:span_id], row[:trace_id])
            }
          end
        end

        def error_message(row)
          parts = [row[:exception], row[:message]]
                  .map(&:presence)
                  .reject { |part| part.nil? || PLACEHOLDERS.include?(part) }

          parts.join(": ").presence || "Unknown error"
        end

        # When it started, how fast it is arriving, and which way it is going —
        # what the design's meta line carries. The last occurrence alone cannot
        # separate a failure that began ten minutes ago from one that has been
        # firing all week.
        def error_meta(row)
          [first_seen_phrase(row), rate_phrase(row), trend_phrase(row[:trend])].compact.join(" · ")
        end

        def first_seen_phrase(row)
          seen = row[:first_seen] || row[:last_seen]

          "first seen #{time_ago(seen)}" if seen
        end

        # Occurrences a minute across the stretch the signature has been
        # firing. Under one a minute a rate rounds away to nothing worth
        # reading, so the trace count carries the row instead.
        def rate_phrase(row)
          traces = pluralize(row[:traces].to_i, "trace")
          minutes = error_minutes(row)
          return traces if minutes.nil? || row[:count].to_i < 2

          per_minute = row[:count].to_f / minutes
          per_minute >= 1 ? "#{per_minute.round}/min" : traces
        end

        def error_minutes(row)
          first = row[:first_seen]
          last = row[:last_seen]
          return nil unless first && last

          minutes = (last - first) / 60.0
          minutes.positive? ? minutes : nil
        end

        # Nil trend means the signature did not fire in the preceding window at
        # all, which is "new" rather than "up 100%".
        def trend_phrase(trend)
          return "new" if trend.nil?
          return nil if trend.zero?

          trend.positive? ? "up #{trend}%" : "down #{trend.abs}%"
        end

        # Nothing billed at all is not the same as billing zero: a workflow
        # that never called a model has no spend to report, and printing
        # $0.00 for it claims a measurement nobody took.
        def spend_for(workflow_name)
          cost = @workflow_spend[workflow_name]
          return "—" if cost.nil?

          "$#{'%.2f' % cost.to_f}"
        end

        def live_runs
          @recent_traces.to_a.map do |trace|
            {
              workflow: trace.workflow_name,
              spans: pluralize(trace.spans.count, "span"),
              started: time_ago(trace.started_at),
              duration: format_duration(trace.duration_ms),
              tone: TRACE_TONES.fetch(trace.status.to_s, :idle),
              href: tracing_trace_path(trace.trace_id)
            }
          end
        end

        # The workflow table keeps its place below the fold.
        def failure_rate
          total = @overview_stats[:total_traces].to_i
          return "0%" if total.zero?

          "#{((@overview_stats[:failed_traces].to_i / total.to_f) * 100).round(1)}%"
        end

        # Thousands separators without pulling in a view helper.
        def number(value)
          value.to_i.to_s.reverse.scan(/\d{1,3}/).join(",").reverse
        end

        def average_duration
          format_duration(@overview_stats[:avg_trace_duration] && (@overview_stats[:avg_trace_duration] * 1000))
        end
      end
    end
  end
end
