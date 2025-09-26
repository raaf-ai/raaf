# frozen_string_literal: true

require_relative "base_collector"

module RAAF
  module Tracing
    module SpanCollectors
      # Specialized collector for Job components that captures background job execution
      # details, queue information, arguments, and execution status. This collector
      # provides visibility into asynchronous agent workflows and job processing.
      #
      # @example Basic usage with background job
      #   class AgentProcessingJob < ApplicationJob
      #     queue_as :agent_processing
      #
      #     def perform(user_id, task_data)
      #       # Job execution logic
      #     end
      #   end
      #
      #   job = AgentProcessingJob.new(123, {task: "analyze"})
      #   collector = JobCollector.new
      #   attributes = collector.collect_attributes(job)
      #   result_attrs = collector.collect_result(job, execution_result)
      #
      # @example Captured job information
      #   # Job identification and queue
      #   attributes["job.queue"]  # => "agent_processing"
      #
      #   # Job arguments and parameters (truncated for readability)
      #   attributes["job.arguments"]  # => "[123, {:task=>\"analyze\"}]"
      #
      #   # Job execution results
      #   result_attrs["result.status"]  # => "completed"
      #
      # @example Integration with job processing
      #   class AgentJob < ApplicationJob
      #     include RAAF::Tracing::Traceable
      #
      #     def perform(*args)
      #       # Job automatically traced with queue and argument details
      #     end
      #   end
      #
      # @note Queue names help organize and filter job traces by processing category
      # @note Arguments are truncated to first 100 characters to prevent huge spans
      # @note Job status extraction depends on the job framework's result structure
      # @note Useful for tracking agent workflows that run asynchronously
      #
      # @see BaseCollector For DSL methods and common attribute handling
      # @see AgentCollector For agent tracing that might be triggered by jobs
      # @see RAAF::Tracing::Traceable For job integration patterns
      #
      # @since 1.0.0
      # @author RAAF Team
      class JobCollector < BaseCollector
        # Job queue and processing information
        span queue: ->(comp) { comp.respond_to?(:queue_name) ? comp.queue_name : "default" }

        # Job arguments with length limiting to prevent oversized spans
        span arguments: ->(comp) do
          if comp.respond_to?(:arguments)
            comp.arguments.inspect[0..100] # Truncate long arguments
          else
            "N/A"
          end
        end

        # ============================================================================
        # JOB EXECUTION RESULTS
        # These attributes capture job completion status and execution outcomes.
        # ============================================================================

        # Job execution status extracted from result object
        # @return [String] Job status ("completed", "failed", "unknown", etc.)
        result status: ->(result, comp) { result.respond_to?(:status) ? result.status : "unknown" }
      end
    end
  end
end
