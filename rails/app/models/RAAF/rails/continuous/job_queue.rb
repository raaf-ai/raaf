# frozen_string_literal: true

module RAAF
  module Rails
    module Continuous
      ##
      # The evaluation queue as the job backend actually holds it.
      #
      # `EvaluationQueueItem` is RAAF's own bookkeeping — one row per
      # evaluation RAAF decided to run, with a status RAAF writes. This reads
      # the other side: the SolidQueue rows that decide what a worker will
      # actually pick up. The two disagree whenever a worker dies mid-run,
      # which is the whole reason `StaleJobCleanupJob` exists and why the
      # matching-spans panel bounds its wait at five minutes.
      #
      # Every read is scoped to RAAF's own queues. The evaluation jobs declare
      # `queue_as :raaf_evaluations`, the periodic ones `:raaf_evaluations_low`
      # and `:raaf_maintenance`, so the prefix is the filter and a host
      # application's own jobs never appear here.
      #
      # SolidQueue is a host-application choice, not a RAAF dependency. Every
      # method degrades to empty when it is not the adapter, so the screen
      # renders an honest "no job backend" rather than raising.
      class JobQueue
        QUEUE_PREFIX = "raaf_"

        # A worker whose heartbeat stopped is a row nobody has cleaned up yet,
        # not a worker that could take the next job.
        WORKER_ALIVE_WITHIN = 5.minutes

        class << self
          def available?
            defined?(::SolidQueue::Job) && ::SolidQueue::Job.table_exists?
          rescue StandardError
            false
          end
        end

        def initialize(window: 24.hours)
          @window = window
        end

        # ── The four headline figures ─────────────────────────────────────

        def waiting_count = scoped(::SolidQueue::ReadyExecution).count

        def in_flight_count = scoped(::SolidQueue::ClaimedExecution).count

        def failed_count = scoped(::SolidQueue::FailedExecution).count

        # Retries wait here rather than being lost: ActiveJob's `retry_on`
        # re-enqueues with a delay, which SolidQueue holds as a scheduled row.
        def scheduled_count = scoped(::SolidQueue::ScheduledExecution).count

        def finished_in_window
          return 0 unless available?

          raaf_jobs.where(finished_at: @window.ago..).count
        end

        # Jobs an hour, over the window — the figure the design's card calls
        # throughput.
        def throughput_per_hour
          hours = @window / 3600.0
          return 0.0 if hours.zero?

          (finished_in_window / hours).round(1)
        end

        def workers_alive
          return 0 unless available?

          ::SolidQueue::Process.where(kind: "Worker")
                               .where(last_heartbeat_at: WORKER_ALIVE_WITHIN.ago..)
                               .count
        end

        # How long the job at the front of the queue has been there. Exact,
        # unlike anything derived from finished jobs.
        def oldest_wait_seconds
          oldest = scoped(::SolidQueue::ReadyExecution).minimum(:created_at)
          oldest && (Time.current - oldest)
        end

        # ── In flight ─────────────────────────────────────────────────────

        # @return [Array<Hash>] :worker, :policy, :span_id, :elapsed, :job_id
        def in_flight
          return [] unless available?

          claimed = scoped(::SolidQueue::ClaimedExecution).order(created_at: :asc).to_a
          jobs = jobs_by_id(claimed.map(&:job_id))
          processes = ::SolidQueue::Process.where(id: claimed.map(&:process_id)).index_by(&:id)

          claimed.filter_map do |execution|
            job = jobs[execution.job_id]
            next unless job

            payload = payload_for(job)
            { job_id: job.id,
              worker: worker_label(processes[execution.process_id]),
              policy: policy_name(payload["policy_id"]),
              span_id: payload["span_id"],
              elapsed: Time.current - execution.created_at }
          end
        end

        # ── Waiting ───────────────────────────────────────────────────────

        # @return [Array<Hash>] :span_id, :policy, :checks, :priority, :waited
        def waiting(limit: 25)
          rows_for(scoped(::SolidQueue::ReadyExecution).order(priority: :asc, created_at: :asc)
                                                       .limit(limit)) do |execution, payload|
            { priority: execution.priority,
              waited: Time.current - execution.created_at,
              checks: check_count(payload["policy_id"]) }
          end
        end

        # ── Failed ────────────────────────────────────────────────────────

        # @return [Array<Hash>] :span_id, :policy, :error, :failed_at
        def failed(limit: 10)
          rows_for(scoped(::SolidQueue::FailedExecution).order(created_at: :desc)
                                                        .limit(limit)) do |execution, _payload|
            { failed_at: execution.created_at, error: error_line(execution) }
          end
        end

        # ── Acting on the failed ──────────────────────────────────────────
        #
        # Both act on exactly the rows `failed` lists, which is the point:
        # the screen's controls used to move `EvaluationQueueItem` rows --
        # RAAF's record of what it decided to run -- while the card beside them
        # counted the jobs a worker gave up on. A job that died before RAAF
        # wrote its ledger row was in the count and out of the retry, and
        # nothing on the screen said so.

        # Re-enqueues every failed job. SolidQueue's own `retry` resets the
        # job's execution counters and puts it back on its queue, so a requeued
        # job goes through the same worker path it failed on.
        #
        # @return [Integer] jobs put back on the queue
        def retry_failed
          each_failed_execution(&:retry)
        end

        # Drops every failed job, the row and the job behind it. There is no
        # third state to move them to: a failure nobody retries stays in the
        # count for good otherwise.
        #
        # @return [Integer] jobs discarded
        def discard_failed
          each_failed_execution(&:discard)
        end

        # ── Throughput ────────────────────────────────────────────────────

        # One bucket per hour across the window, oldest first, so the bars read
        # left to right like every other trend in the console.
        #
        # @return [Array<Hash>] :at, :count
        def throughput_series(buckets: 24)
          return [] unless available?

          span = @window / buckets
          start = Time.current - @window
          counts = raaf_jobs.where(finished_at: start..).pluck(:finished_at)

          Array.new(buckets) do |index|
            from = start + (span * index)
            { at: from, count: counts.count { |at| at >= from && at < from + span } }
          end
        end

        # ── Latency ───────────────────────────────────────────────────────

        # Enqueue to finish, which is wait *plus* execution.
        #
        # It is not the design's "median wait". SolidQueue deletes the claimed
        # row when a job finishes, so the moment a finished job started running
        # is not recoverable — the split cannot be reconstructed after the
        # fact, only measured live. Reporting the whole latency and naming it
        # that is the honest half of the question.
        #
        # @return [Hash] :median, :p95, in seconds, or nil where nothing ran
        def latency
          return { median: nil, p95: nil } unless available?

          samples = raaf_jobs.where(finished_at: @window.ago..)
                             .pluck(:created_at, :finished_at)
                             .map { |created, finished| finished - created }
                             .sort

          return { median: nil, p95: nil } if samples.empty?

          { median: percentile(samples, 0.5), p95: percentile(samples, 0.95) }
        end

        private

        def available? = self.class.available?

        def raaf_jobs
          ::SolidQueue::Job.where(arel_prefix_match)
        end

        # `LIKE 'raaf_%'` would be wrong: `_` is a single-character wildcard in
        # SQL, so it would also match a host queue called "raafX…". The escape
        # keeps the underscore literal.
        def arel_prefix_match
          ["queue_name LIKE ? ESCAPE ?", "raaf\\_%", "\\"]
        end

        def scoped(relation)
          return relation.none unless available?

          relation.where(job_id: raaf_jobs.select(:id))
        end

        # Each row is read before it is acted on, because acting on one deletes
        # it: iterating the relation itself would walk a moving target. A row
        # another worker has already cleaned up is gone rather than an error,
        # so it is counted as neither.
        def each_failed_execution
          executions = scoped(::SolidQueue::FailedExecution).order(created_at: :desc).to_a

          executions.count do |execution|
            yield(execution)
            true
          rescue ActiveRecord::RecordNotFound
            false
          end
        end

        def jobs_by_id(ids)
          return {} if ids.empty?

          ::SolidQueue::Job.where(id: ids).index_by(&:id)
        end

        # Shared shape for the waiting and failed tables: both list a job, and
        # differ only in the columns the block adds.
        def rows_for(relation)
          return [] unless available?

          executions = relation.to_a
          jobs = jobs_by_id(executions.map(&:job_id))

          executions.filter_map do |execution|
            job = jobs[execution.job_id]
            next unless job

            payload = payload_for(job)
            { job_id: job.id,
              span_id: payload["span_id"],
              policy: policy_name(payload["policy_id"]),
              manual: payload["manual"] == true }.merge(yield(execution, payload))
          end
        end

        # The job's own keyword arguments, out of the ActiveJob envelope
        # SolidQueue stores. `_aj_ruby2_keywords` is serialisation bookkeeping
        # and is not one of them.
        def payload_for(job)
          arguments = job.arguments
          return {} unless arguments.is_a?(Hash)

          first = Array(arguments["arguments"]).first
          first.is_a?(Hash) ? first.except("_aj_ruby2_keywords") : {}
        end

        def policies
          @policies ||= RAAF::Eval::Models::EvaluationPolicy.all.index_by(&:id)
        rescue StandardError
          {}
        end

        def policy_name(id)
          policies[id]&.name
        end

        # How many checks the job will actually run, which is what the design's
        # "spans per batch" column would have said if RAAF batched. It does
        # not — one job grades one span — so the count that varies is this one.
        def check_count(id)
          policy = policies[id]
          return nil unless policy

          Array(policy.evaluators).sum do |evaluator|
            evaluator.is_a?(Hash) ? Array(evaluator["checks"] || evaluator[:checks]).size : 0
          end
        end

        def worker_label(process)
          return "—" if process.nil?

          # The name SolidQueue generates carries the host and pid; the pid
          # alone is what identifies it in a log.
          "pid #{process.pid}"
        end

        # A backtrace is not a table cell. The class and message are what says
        # whether these failures are all the same thing.
        def error_line(execution)
          error = execution.error
          return nil if error.blank?

          parsed = if error.is_a?(String)
                     begin
                       JSON.parse(error)
                     rescue StandardError
                       nil
                     end
                   else
                     error
                   end
          return error.to_s.lines.first.to_s.strip unless parsed.is_a?(Hash)

          [parsed["exception_class"], parsed["message"]].compact.join(": ").presence
        end

        def percentile(sorted, fraction)
          return nil if sorted.empty?

          sorted[[(sorted.size * fraction).ceil - 1, 0].max]
        end
      end
    end
  end
end
