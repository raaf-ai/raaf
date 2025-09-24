# frozen_string_literal: true

require "active_job"
require_relative "traceable"
require_relative "tracing_registry"

module RAAF
  module Tracing
    # Base class for ActiveJob classes that need automatic tracing
    #
    # This class provides automatic span creation for job execution with:
    # - Job-level spans that act as roots for nested operations
    # - Automatic extraction of job metadata (id, queue, arguments, etc.)
    # - Proper error handling and status tracking
    # - Integration with RAAF TraceProvider for processor configuration
    #
    # @example Basic usage
    #   class MyJob < RAAF::Tracing::TracedJob
    #     def perform(user_id)
    #       # Your job logic here - automatically traced
    #       User.find(user_id).process!
    #     end
    #   end
    #
    # @example With nested operations
    #   class ComplexJob < RAAF::Tracing::TracedJob
    #     def perform(data)
    #       # Job span created automatically
    #       agent = MyAgent.new # Agent spans become children of job span
    #       agent.run(data)
    #     end
    #   end
    #
    class TracedJob < ActiveJob::Base
      include Traceable
      trace_as :job

      around_perform :with_job_tracing

      private

      # Execute job within a traced span
      #
      # This method automatically creates a job-level span that captures:
      # - Job execution timing
      # - Job metadata (id, queue, arguments, etc.)
      # - Success/failure status
      # - Error information if job fails
      #
      # @param block [Proc] The job's perform method
      # @return [Object] Result of the job execution
      def with_job_tracing(&block)
        ensure_tracer_context do
          # Create a job-level span with job metadata and custom workflow name
          job_metadata = extract_job_metadata.merge("trace.workflow_name" => self.class.name)

          with_tracing(:perform, **job_metadata) do
            begin
              # Make job span available to nested components
              store_job_span_context
              block.call
            ensure
              # Always clean up span context
              cleanup_job_span_context
            end
          end
        end
      end

      # Ensure we have a tracer context for the job
      #
      # Jobs should use the globally configured TraceProvider which already
      # has the correct processors (OpenAI, ActiveRecord, etc.) configured
      # in the Rails application.
      #
      # @param block [Proc] Block to execute with tracer context
      # @return [Object] Result of block execution
      def ensure_tracer_context(&block)
        current_tracer = TracingRegistry.current_tracer

        # If we don't have a tracer or only have NoOpTracer, try to get the configured one
        if current_tracer.nil? || current_tracer.is_a?(NoOpTracer)
          if defined?(RAAF::Tracing::TraceProvider)
            provider = RAAF::Tracing::TraceProvider.instance
            if provider && provider.respond_to?(:processors) && !provider.processors.empty?
              # Use the configured TraceProvider
              TracingRegistry.with_tracer(provider, &block)
            else
              # No configured provider, execute without tracing
              block.call
            end
          else
            # TraceProvider not available, execute without tracing
            block.call
          end
        else
          # Use existing tracer
          block.call
        end
      end

      # Store job span context in the thread for nested components to access
      #
      # This method makes the job's current span available to any nested operations
      # so they can properly establish parent-child relationships in the trace hierarchy.
      def store_job_span_context
        if current_span
          Thread.current[:raaf_job_span] = self
        end
      end

      # Clean up job span context
      def cleanup_job_span_context
        Thread.current[:raaf_job_span] = nil
      end

      # Extract job metadata for span attributes
      #
      # This method extracts all relevant job information that should be
      # included in the job span for observability and debugging.
      #
      # @return [Hash] Job metadata to include in span attributes
      def extract_job_metadata
        {
          "job.class" => self.class.name,
          "job.id" => job_id,
          "job.queue" => queue_name,
          "job.priority" => priority_for_tracing,
          "job.arguments" => sanitized_arguments,
          "job.enqueued_at" => enqueued_at&.iso8601,
          "job.scheduled_at" => scheduled_at_for_tracing,
          "job.provider_job_id" => provider_job_id_for_tracing,
          "job.executions" => executions_for_tracing
        }.compact
      end

      # Get job priority safely
      #
      # @return [Integer, nil] Job priority or nil if not available
      def priority_for_tracing
        respond_to?(:priority) ? priority : nil
      end

      # Get scheduled at time safely
      #
      # @return [String, nil] ISO8601 formatted scheduled time or nil
      def scheduled_at_for_tracing
        respond_to?(:scheduled_at) && scheduled_at ? scheduled_at.iso8601 : nil
      end

      # Get provider job ID safely
      #
      # @return [String, nil] Provider job ID or nil if not available
      def provider_job_id_for_tracing
        respond_to?(:provider_job_id) ? provider_job_id : nil
      end

      # Get execution count safely
      #
      # @return [Integer, nil] Number of executions or nil if not available
      def executions_for_tracing
        respond_to?(:executions) ? executions : nil
      end

      # Sanitize job arguments to prevent logging sensitive data
      #
      # This method processes the job arguments to:
      # - Truncate very long strings
      # - Limit hash/array sizes
      # - Remove or mask potentially sensitive data
      #
      # @return [Array] Sanitized job arguments
      def sanitized_arguments
        arguments.map do |arg|
          sanitize_argument(arg)
        end
      rescue StandardError => e
        # If sanitization fails, return a safe fallback
        ["<arguments could not be sanitized: #{e.class.name}>"]
      end

      # Sanitize a single argument
      #
      # @param arg [Object] Argument to sanitize
      # @return [Object] Sanitized argument
      def sanitize_argument(arg)
        case arg
        when Hash
          # Limit hash size and sanitize values
          sanitized_hash = {}
          arg.each_with_index do |(key, value), index|
            break if index >= 10 # Limit to first 10 keys

            sanitized_key = sanitize_hash_key(key)
            sanitized_hash[sanitized_key] = sanitize_hash_value(key, value)
          end

          if arg.size > 10
            sanitized_hash["..."] = "#{arg.size - 10} more keys"
          end

          sanitized_hash
        when Array
          # Limit array size
          if arg.size <= 5
            arg.map { |item| sanitize_argument(item) }
          else
            arg.first(5).map { |item| sanitize_argument(item) } + ["...#{arg.size - 5} more items"]
          end
        when String
          # Truncate long strings
          if arg.length > 200
            "#{arg[0..200]}... (#{arg.length} chars)"
          else
            arg
          end
        when Numeric, TrueClass, FalseClass, NilClass
          # Safe primitive types
          arg
        else
          # For other objects, use safe string representation
          begin
            arg.class.name
          rescue StandardError
            "<#{arg.class}>"
          end
        end
      end

      # Sanitize hash key for logging
      #
      # @param key [Object] Hash key
      # @return [Object] Sanitized key
      def sanitize_hash_key(key)
        case key
        when String, Symbol
          key
        else
          key.to_s rescue "<key>"
        end
      end

      # Sanitize hash value, being careful about sensitive data
      #
      # @param key [Object] Hash key (used to detect sensitive fields)
      # @param value [Object] Hash value
      # @return [Object] Sanitized value
      def sanitize_hash_value(key, value)
        key_str = key.to_s.downcase

        # Mask potentially sensitive fields
        if sensitive_field?(key_str)
          "<redacted>"
        else
          sanitize_argument(value)
        end
      end

      # Check if a field name indicates sensitive data
      #
      # @param field_name [String] Field name in lowercase
      # @return [Boolean] true if field appears to contain sensitive data
      def sensitive_field?(field_name)
        sensitive_patterns = %w[
          password token secret key api_key access_key
          private_key ssh_key auth authorization
          credit_card ssn social_security phone email
        ]

        sensitive_patterns.any? { |pattern| field_name.include?(pattern) }
      end

      # Override collect_span_attributes to include job-specific data
      #
      # @return [Hash] Span attributes including job metadata
      def collect_span_attributes
        base_attributes = super

        # Add job-specific attributes
        base_attributes.merge({
          "job.queue" => queue_name,
          "job.priority" => priority_for_tracing,
          "job.executions" => executions_for_tracing,
          "job.provider" => self.class.queue_adapter.class.name
        }.compact)
      rescue StandardError => e
        # If we can't collect job attributes, just use base attributes
        Rails.logger.warn "Failed to collect job span attributes: #{e.message}" if defined?(Rails)
        base_attributes
      end
    end
  end
end