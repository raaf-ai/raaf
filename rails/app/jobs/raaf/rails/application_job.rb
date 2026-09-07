# frozen_string_literal: true

require "raaf/tracing/traceable"

module RAAF
  module Rails
    ##
    # Base class for all RAAF Rails background jobs
    #
    # Records a span when the job runs inside another job's trace. Our scheduled
    # wrappers call these jobs with +perform_now+, so without a span of their own
    # the wrapper's trace shows a single job span and nothing about the work it
    # actually did — one bar, no waterfall.
    #
    # A job that runs on its own (+perform_later+ off the queue) is deliberately
    # left untraced. EvaluationJob fires once per sampled span, and giving each
    # run its own root trace would fill the tracing tables with single-span traces
    # that say nothing the evaluation results do not already say.
    class ApplicationJob < ActiveJob::Base
      include RAAF::Tracing::Traceable

      trace_as :job

      # Automatically retry jobs on transient errors
      retry_on StandardError, wait: :polynomially_longer, attempts: 3

      # Don't retry on permanent errors
      discard_on ActiveJob::DeserializationError

      around_perform :with_nested_job_tracing

      private

      # Run perform inside a child span of the enclosing job span
      #
      # @param block [Proc] the job's perform method
      # @return [Object] result of the job execution
      def with_nested_job_tracing(&block)
        return block.call unless enclosing_job_span

        with_tracing(:perform, **job_span_metadata) do
          previous_job_span = Thread.current[:raaf_job_span]
          Thread.current[:raaf_job_span] = self
          begin
            block.call
          ensure
            # Restore rather than clear: this job runs inside another one, and
            # clearing would orphan every span the caller creates after us.
            Thread.current[:raaf_job_span] = previous_job_span
          end
        end
      end

      # The job span this job is nested in, if any
      #
      # @return [Object, nil] the enclosing traced job, or nil when running standalone
      def enclosing_job_span
        job_span = Thread.current[:raaf_job_span]
        job_span if job_span.respond_to?(:current_span) && job_span.current_span
      end

      # Job metadata the JobCollector does not already capture
      #
      # @return [Hash] span attributes
      def job_span_metadata
        {
          "job.id" => job_id,
          "job.executions" => executions
        }.compact
      end
    end
  end
end
