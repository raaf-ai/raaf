# frozen_string_literal: true

module RAAF
  module Rails
    module Continuous
      ##
      # The evaluation queue, from the `isQueue` screen in
      # RAAF Continuous.dc.html: four headline figures, then In flight beside
      # Throughput · 24h, then Waiting.
      #
      # It reads SolidQueue rather than `EvaluationQueueItem`. The RAAF table
      # records what RAAF decided to run; SolidQueue decides what a worker will
      # actually pick up, and the two part company the moment a worker dies
      # mid-run. A queue screen is for the second question.
      #
      # The buttons read it too. They used to move `EvaluationQueueItem` rows
      # while the cards counted SolidQueue's, so "Requeue failed" beside a
      # count of failures acted on a different set of failures. Every figure
      # and every control here now comes from the one table.
      #
      # Three places the design assumes a shape RAAF does not have, each one
      # decided rather than faked:
      #
      # - **Batches.** The design queues batches of spans and gives every row a
      #   span count. RAAF enqueues one job per span per policy, so that count
      #   is always one. The column carries the number that does vary — how
      #   many checks the job will run.
      # - **Progress bars on in-flight jobs.** A SolidQueue job reports no
      #   progress; there is nothing between claimed and finished. A bar drawn
      #   from elapsed time would read as progress and be a guess, so the row
      #   carries elapsed alone.
      # - **Estimated cost per row.** Nothing prices an evaluation before it
      #   runs — the same call the experiment editor's "Next run" makes.
      #
      # And one section the design does not have. It draws a healthy queue, so
      # it has nowhere for failures; on a real one they are the rows that
      # matter most, and the Failed card counts them whether or not they are
      # listed.
      class QueueList < RAAF::Rails::Tracing::BaseComponent
        WAITING_COLUMNS = [
          { label: "Span", span: 1.9 },
          { label: "Policy", span: 1.4 },
          { label: "Checks", span: 0.7, align: :right },
          { label: "Priority", span: 0.7, align: :right },
          { label: "Waiting", span: 0.75, align: :right }
        ].freeze

        FAILED_COLUMNS = [
          { label: "Span", span: 1.4 },
          { label: "Policy", span: 1.1 },
          { label: "Error", span: 2.4 },
          { label: "Failed", span: 0.75, align: :right }
        ].freeze

        # @param queue [JobQueue]
        def initialize(queue:)
          @queue = queue
        end

        def view_template
          div(class: "raaf-page") do
            if JobQueue.available?
              stats
              div(class: "raaf-queue-split") do
                in_flight
                throughput
              end
              waiting
              failed
            else
              no_backend
            end
          end
        end

        private

        # SolidQueue is the host application's choice, so its absence is a
        # configuration fact rather than an error.
        def no_backend
          render(Organisms::Card.new(title: "No job backend")) do
            render Atoms::Text.new(
              "This screen reads the SolidQueue tables directly. The application is running " \
              "a different Active Job adapter, so there is nothing here to read — evaluations " \
              "still run, and their results are on the policy screens.",
              tone: :secondary
            )
          end
        end

        # ── Headline ──────────────────────────────────────────────────────

        def stats
          render Organisms::StatGrid.new(layout: :leading, stats: [
                                           waiting_stat, in_flight_stat,
                                           throughput_stat, oldest_stat
                                         ])
        end

        def waiting_stat
          { label: "Queued", value: @queue.waiting_count.to_s, icon: "hourglass-split",
            tone: :accent, note: queued_note }
        end

        # Scheduled rows are retries waiting out their backoff. They are not
        # queued yet and would flatter the figure if counted, but a reader who
        # cannot see them cannot tell a quiet queue from a stalled one.
        def queued_note
          scheduled = @queue.scheduled_count
          return "jobs awaiting a worker" if scheduled.zero?

          "jobs awaiting a worker · #{pluralize(scheduled, 'retry')} scheduled"
        end

        def in_flight_stat
          { label: "In flight", value: @queue.in_flight_count.to_s, icon: "cpu",
            tone: :success,
            note: "#{pluralize(@queue.workers_alive, 'worker')} alive" }
        end

        def throughput_stat
          { label: "Throughput", value: "#{@queue.throughput_per_hour}/h", icon: "speedometer2",
            tone: :accent, note: "jobs finished, 24h average" }
        end

        # The design's fourth card pairs the oldest wait with an SLO. RAAF
        # stores no target to be within, so the card reports the wait and what
        # it is the age of.
        def oldest_stat
          seconds = @queue.oldest_wait_seconds

          { label: "Oldest wait", value: seconds ? duration(seconds) : "—",
            icon: "clock-history", tone: seconds && seconds > 300 ? :warning : nil,
            note: seconds ? "the job at the front of the queue" : "nothing is waiting" }
        end

        # ── In flight ─────────────────────────────────────────────────────

        def in_flight
          rows = @queue.in_flight

          render(Organisms::Card.new(title: "In flight", flush: true)) do |card|
            card.actions { workers_pip }

            if rows.empty?
              render Molecules::EmptyState.new(
                icon: "cpu", title: "Nothing running",
                text: "No evaluation job is claimed by a worker right now."
              )
            else
              rows.each { |row| in_flight_row(row) }
            end
          end
        end

        # The design puts a pulsing dot and a worker count opposite this
        # heading. `StatusPip` is that, and its `:live` state is the pulse.
        def workers_pip
          alive = @queue.workers_alive

          render Organisms::StatusPip.new(label: pluralize(alive, "worker"),
                                          state: alive.positive? ? :live : :error)
        end

        def in_flight_row(row)
          div(class: "raaf-queue-job") do
            render Atoms::Mono.new(row[:worker], tone: :muted, class: "raaf-queue-worker")
            span(class: "raaf-queue-policy") { row[:policy] || "unknown policy" }
            render Atoms::Mono.new(short_span(row[:span_id]), tone: :muted)
            render Atoms::Mono.new(duration(row[:elapsed]), align: :right,
                                                            class: "raaf-queue-elapsed")
          end
        end

        # ── Throughput ────────────────────────────────────────────────────

        def throughput
          series = @queue.throughput_series

          render(Organisms::Card.new(title: "Throughput · 24h")) do
            if series.sum { |bucket| bucket[:count] }.zero?
              render Molecules::EmptyState.new(
                icon: "bar-chart", title: "Nothing finished",
                text: "No evaluation job completed in the last 24 hours."
              )
            else
              render Molecules::Sparkbars.new(values: series.map { |b| b[:count] },
                                              tips: series.map { |b| throughput_tip(b) },
                                              label: "Jobs finished per hour",
                                              class: "raaf-queue-throughput")
            end

            div(class: "raaf-queue-meta") { meta_rows.each { |label, value| meta_row(label, value) } }
          end
        end

        # An hour with no jobs still gets a readout. A gap in the bars is the
        # thing somebody wants named — a worker that stopped reads as an empty
        # stretch, and hovering it should say which hours were empty rather
        # than nothing at all.
        def throughput_tip(bucket)
          at = bucket[:at]
          hour = at.respond_to?(:strftime) ? at.strftime("%a %H:%M") : at.to_s

          "#{hour} · #{pluralize(bucket[:count].to_i, 'job')} finished"
        end

        def meta_rows
          latency = @queue.latency

          [["Median latency", latency[:median] && duration(latency[:median])],
           ["p95 latency", latency[:p95] && duration(latency[:p95])],
           ["Finished · 24h", @queue.finished_in_window.to_s],
           ["Failed", @queue.failed_count.to_s]]
        end

        def meta_row(label, value)
          div(class: "raaf-queue-meta-row") do
            span(class: "raaf-queue-meta-label") { label }
            render Atoms::Mono.new(value || "—", tone: value ? nil : :muted)
          end
        end

        # ── Waiting ───────────────────────────────────────────────────────

        def waiting
          rows = @queue.waiting

          render(Organisms::Card.new(title: "Waiting", subtitle: waiting_subtitle,
                                     flush: true)) do
            grid = Organisms::DataGrid.new(
              columns: WAITING_COLUMNS,
              empty: { icon: "check2-circle", title: "Queue is clear",
                       text: "Every evaluation job has been picked up." }
            )
            render(grid) { rows.each { |row| waiting_row(grid, row) } }
          end
        end

        # Where a queue row's span is read.
        #
        # A span opens its trace with itself selected, and these rows come from
        # SolidQueue payloads that carry a span id and nothing else -- so the
        # trace has to be looked up. Once for the page, not once per row. A
        # span the tracer has since dropped gets no link rather than a link to
        # a page that would 404.
        def span_href(span_id)
          return nil if span_id.blank?

          trace_id = row_traces[span_id]
          trace_id.present? ? trace_span_path(span_id, trace_id) : nil
        end

        def row_traces
          @row_traces ||= begin
            ids = (@queue.waiting + @queue.failed).filter_map { |row| row[:span_id] }.uniq
            if ids.empty?
              {}
            else
              RAAF::Rails::Tracing::SpanRecord.where(span_id: ids)
                                              .pluck(:span_id, :trace_id).to_h
            end
          end
        end

        def waiting_subtitle
          count = @queue.waiting_count
          return nil if count.zero?

          oldest = @queue.oldest_wait_seconds
          [pluralize(count, "job"), oldest && "oldest #{duration(oldest)}"].compact.join(" · ")
        end

        def waiting_row(grid, row)
          grid.row(href: span_href(row[:span_id]), cells: [
                     { value: span_cell(row) },
                     { value: row[:policy] || "—" },
                     { value: Atoms::Mono.new(row[:checks]&.to_s || "—"), align: :right },
                     { value: Atoms::Mono.new(row[:priority].to_s), align: :right },
                     { value: Atoms::Mono.new(duration(row[:waited]), tone: :muted),
                       align: :right }
                   ])
        end

        # A manual run was started by a person who is waiting for it, so the
        # row says which ones those are.
        def span_cell(row)
          return Atoms::Mono.new("—", tone: :muted) if row[:span_id].blank?
          return Atoms::Mono.new(short_span(row[:span_id])) unless row[:manual]

          Atoms::Mono.new("#{short_span(row[:span_id])} · manual", tone: :accent)
        end

        # ── Failed ────────────────────────────────────────────────────────

        def failed
          rows = @queue.failed
          return if rows.empty?

          render(Organisms::Card.new(title: "Failed", subtitle: failed_subtitle,
                                     flush: true)) do |card|
            card.actions { failed_actions }
            grid = Organisms::DataGrid.new(columns: FAILED_COLUMNS)
            render(grid) { rows.each { |row| failed_row(grid, row) } }
          end
        end

        # The card's own subtitle promised jobs "stay here until they are
        # retried or discarded" and offered neither: retry moved RAAF's ledger
        # rows rather than these, and the second button cleared completed items
        # this screen does not list. Both now act on the rows above them.
        def failed_actions
          render Molecules::RowActions.new(actions: [
                                             { label: "Requeue failed",
                                               href: retry_failed_continuous_queue_index_path,
                                               method: :post,
                                               confirm: "Put every failed job back on the " \
                                                        "queue?" },
                                             { label: "Discard failed",
                                               href: discard_failed_continuous_queue_index_path,
                                               method: :delete, tone: :danger,
                                               confirm: "Drop every failed job? They will not " \
                                                        "run again." }
                                           ])
        end

        def failed_subtitle
          "#{pluralize(@queue.failed_count, 'job')} a worker gave up on. " \
            "They stay here until they are requeued or discarded."
        end

        def failed_row(grid, row)
          grid.row(href: span_href(row[:span_id]), cells: [
                     { value: span_cell(row) },
                     { value: row[:policy] || "—" },
                     { value: Atoms::Mono.new(row[:error] || "—", tone: :bad) },
                     { value: Atoms::Mono.new(time_ago(row[:failed_at]), tone: :muted),
                       align: :right }
                   ])
        end

        # ── Shared ────────────────────────────────────────────────────────

        # A queue is read in seconds and minutes; `format_duration` is built
        # for span timings and starts in milliseconds.
        def duration(seconds)
          seconds = seconds.to_f
          return "#{seconds.round}s" if seconds < 60
          return "#{(seconds / 60).floor}m #{(seconds % 60).round.to_s.rjust(2, '0')}s" if seconds < 3600

          "#{(seconds / 3600).floor}h #{((seconds % 3600) / 60).round}m"
        end

        def short_span(span_id)
          return "—" if span_id.blank?
          return span_id if span_id.length <= 16

          "#{span_id[0..7]}…#{span_id[-6..]}"
        end
      end
    end
  end
end
