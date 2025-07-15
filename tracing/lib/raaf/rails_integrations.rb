# frozen_string_literal: true

module RubyAIAgentsFactory
  module Tracing
    # Rails-specific integrations for OpenAI Agents tracing
    #
    # This module provides Rails-specific helpers and integrations including:
    # - ActiveJob automatic tracing
    # - Middleware for HTTP request correlation
    # - Console helpers for debugging
    # - Rake task integrations
    module RailsIntegrations
      # ActiveJob integration for automatic tracing
      #
      # Include this module in your ApplicationJob to automatically trace
      # all background jobs with OpenAI Agents tracing.
      #
      # @example Enable for all jobs
      #   class ApplicationJob < ActiveJob::Base
      #     include RubyAIAgentsFactory::Tracing::RailsIntegrations::JobTracing
      #   end
      #
      # @example Enable for specific jobs
      #   class ProcessDataJob < ApplicationJob
      #     include RubyAIAgentsFactory::Tracing::RailsIntegrations::JobTracing
      #
      #     def perform(data_id)
      #       # Job automatically traced with job class name as workflow
      #       agent.run("Process data: #{data_id}")
      #     end
      #   end
      module JobTracing
        extend ActiveSupport::Concern

        included do
          around_perform :trace_job_execution
        end

        private

        def trace_job_execution
          workflow_name = "#{self.class.name} Job"

          OpenAIAgents.trace(workflow_name) do |trace|
            # Add job-specific metadata
            trace.metadata.merge!(
              job_id: job_id,
              job_class: self.class.name,
              queue_name: queue_name,
              arguments: arguments,
              executions: executions,
              enqueued_at: enqueued_at&.iso8601
            )

            yield
          end
        end
      end

      # Middleware for correlating HTTP requests with traces
      #
      # Add this middleware to automatically add correlation IDs to traces
      # that match HTTP request IDs, making it easier to connect web
      # requests with background processing.
      #
      # @example Add to Rails application
      #   # config/application.rb
      #   config.middleware.use RubyAIAgentsFactory::Tracing::RailsIntegrations::CorrelationMiddleware
      class CorrelationMiddleware
        def initialize(app)
          @app = app
        end

        def call(env)
          request = ActionDispatch::Request.new(env)

          # Store request ID for potential trace correlation
          Thread.current[:openai_agents_request_id] = request.request_id
          Thread.current[:openai_agents_user_agent] = request.user_agent
          Thread.current[:openai_agents_remote_ip] = request.remote_ip

          @app.call(env)
        ensure
          # Clean up thread locals
          Thread.current[:openai_agents_request_id] = nil
          Thread.current[:openai_agents_user_agent] = nil
          Thread.current[:openai_agents_remote_ip] = nil
        end
      end

      # Console helpers for debugging traces in Rails console
      #
      # @example Load helpers in Rails console
      #   include RubyAIAgentsFactory::Tracing::RailsIntegrations::ConsoleHelpers
      #
      #   # Find recent traces
      #   recent_traces
      #
      #   # Find traces by workflow
      #   traces_for("Customer Support")
      #
      #   # Find slow operations
      #   slow_spans(threshold: 5000) # > 5 seconds
      module ConsoleHelpers
        # Get recent traces
        #
        # @param limit [Integer] Number of traces to return
        # @return [Array<Trace>] Recent traces
        def recent_traces(limit: 10)
          return [] unless defined?(RubyAIAgentsFactory::Tracing::Trace)

          RubyAIAgentsFactory::Tracing::Trace.recent.limit(limit).includes(:spans)
        end

        # Get traces for a specific workflow
        #
        # @param workflow_name [String] Workflow name to search for
        # @param limit [Integer] Number of traces to return
        # @return [Array<Trace>] Matching traces
        def traces_for(workflow_name, limit: 10)
          return [] unless defined?(RubyAIAgentsFactory::Tracing::Trace)

          RubyAIAgentsFactory::Tracing::Trace.by_workflow(workflow_name)
                                      .recent.limit(limit).includes(:spans)
        end

        # Get failed traces
        #
        # @param limit [Integer] Number of traces to return
        # @return [Array<Trace>] Failed traces
        def failed_traces(limit: 10)
          return [] unless defined?(RubyAIAgentsFactory::Tracing::Trace)

          RubyAIAgentsFactory::Tracing::Trace.failed.recent.limit(limit).includes(:spans)
        end

        # Get slow spans
        #
        # @param threshold [Integer] Duration threshold in milliseconds
        # @param limit [Integer] Number of spans to return
        # @return [Array<Span>] Slow spans
        def slow_spans(threshold: 1000, limit: 20)
          return [] unless defined?(RubyAIAgentsFactory::Tracing::Span)

          RubyAIAgentsFactory::Tracing::Span.slow(threshold)
                                     .recent.limit(limit).includes(:trace)
        end

        # Get error spans
        #
        # @param limit [Integer] Number of spans to return
        # @return [Array<Span>] Error spans
        def error_spans(limit: 20)
          return [] unless defined?(RubyAIAgentsFactory::Tracing::Span)

          RubyAIAgentsFactory::Tracing::Span.errors.recent.limit(limit).includes(:trace)
        end

        # Get trace by ID
        #
        # @param trace_id [String] Trace ID to find
        # @return [Trace, nil] The trace if found
        def trace(trace_id)
          return nil unless defined?(RubyAIAgentsFactory::Tracing::Trace)

          RubyAIAgentsFactory::Tracing::Trace.find_by(trace_id: trace_id)
        end

        # Get span by ID
        #
        # @param span_id [String] Span ID to find
        # @return [Span, nil] The span if found
        def span(span_id)
          return nil unless defined?(RubyAIAgentsFactory::Tracing::Span)

          RubyAIAgentsFactory::Tracing::Span.find_by(span_id: span_id)
        end

        # Print trace summary
        #
        # @param trace_id [String] Trace ID to summarize
        def trace_summary(trace_id)
          t = trace(trace_id)
          return puts "Trace not found: #{trace_id}" unless t

          puts "\n=== Trace Summary ==="
          puts "ID: #{t.trace_id}"
          puts "Workflow: #{t.workflow_name}"
          puts "Status: #{t.status}"
          puts "Duration: #{(t.duration_ms || 0).round(2)}ms"
          puts "Spans: #{t.spans.count}"
          puts "Errors: #{t.spans.where(status: "error").count}"
          puts "Started: #{t.started_at}"
          puts "Ended: #{t.ended_at}" if t.ended_at

          if t.spans.any?
            puts "\n--- Spans ---"
            t.spans.order(:start_time).each do |span|
              status_icon = span.status == "error" ? "❌" : "✅"
              puts "#{status_icon} #{span.name} (#{span.kind}) - #{(span.duration_ms || 0).round(2)}ms"
            end
          end

          nil
        end

        # Show performance stats
        def performance_stats(timeframe: 24.hours)
          return puts "Tracing models not available" unless defined?(RubyAIAgentsFactory::Tracing::Trace)

          start_time = timeframe.ago
          end_time = Time.current

          traces = RubyAIAgentsFactory::Tracing::Trace.within_timeframe(start_time, end_time)
          spans = RubyAIAgentsFactory::Tracing::Span.within_timeframe(start_time, end_time)

          puts "\n=== Performance Stats (#{timeframe.inspect}) ==="
          puts "Traces: #{traces.count}"
          puts "  Completed: #{traces.completed.count}"
          puts "  Failed: #{traces.failed.count}"
          puts "  Running: #{traces.running.count}"
          puts "Spans: #{spans.count}"
          puts "  Errors: #{spans.errors.count}"
          puts "Success Rate: #{traces.any? ? ((traces.completed.count.to_f / traces.count) * 100).round(2) : 0}%"

          avg_duration = traces.where.not(ended_at: nil)
                               .average("EXTRACT(EPOCH FROM (ended_at - started_at))")
          puts "Avg Duration: #{avg_duration ? (avg_duration * 1000).round(2) : "N/A"}ms"

          nil
        end
      end

      # Rake task helpers for maintenance and analysis
      class RakeTasks
        # Clean up old traces
        #
        # @param older_than [ActiveSupport::Duration] Age threshold
        def self.cleanup_old_traces(older_than: 30.days)
          return 0 unless defined?(RubyAIAgentsFactory::Tracing::Trace)

          deleted_count = RubyAIAgentsFactory::Tracing::Trace.cleanup_old_traces(older_than: older_than)
          puts "Cleaned up #{deleted_count} traces older than #{older_than.inspect}"
          deleted_count
        end

        # Generate performance report
        def self.performance_report(timeframe: 24.hours)
          return unless defined?(RubyAIAgentsFactory::Tracing::Trace)

          start_time = timeframe.ago
          end_time = Time.current

          puts "\n=== OpenAI Agents Performance Report ==="
          puts "Time Range: #{start_time.strftime("%Y-%m-%d %H:%M")} to #{end_time.strftime("%Y-%m-%d %H:%M")}"
          puts "=" * 50

          # Overall stats
          stats = RubyAIAgentsFactory::Tracing::Trace.performance_stats(timeframe: start_time..end_time)
          puts "Total Traces: #{stats[:total_traces]}"
          puts "Success Rate: #{stats[:success_rate]}%"
          puts "Average Duration: #{stats[:avg_duration] ? (stats[:avg_duration] * 1000).round(2) : "N/A"}ms"

          # Top workflows
          puts "\n--- Top Workflows ---"
          top_workflows = RubyAIAgentsFactory::Tracing::Trace.top_workflows(limit: 10, timeframe: start_time..end_time)
          top_workflows.each do |workflow|
            puts "#{workflow[:workflow_name]}: #{workflow[:trace_count]} traces (#{workflow[:success_rate]}% success)"
          end

          # Error analysis
          error_analysis = RubyAIAgentsFactory::Tracing::Span.error_analysis(timeframe: start_time..end_time)
          if error_analysis[:total_errors] > 0
            puts "\n--- Error Analysis ---"
            puts "Total Errors: #{error_analysis[:total_errors]}"
            error_analysis[:errors_by_kind].each do |kind, count|
              puts "  #{kind}: #{count}"
            end
          end

          nil
        end
      end
    end
  end
end

# Auto-include console helpers in Rails console
if defined?(Rails::Console)
  Rails::Console.class_eval do
    def start_with_tracing_helpers
      # Extend the console instance with helper methods
      IRB::ExtendCommandBundle.include(RubyAIAgentsFactory::Tracing::RailsIntegrations::ConsoleHelpers)
      start_without_tracing_helpers
    end

    alias_method :start_without_tracing_helpers, :start
    alias_method :start, :start_with_tracing_helpers
  end
end
