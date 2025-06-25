# frozen_string_literal: true

# Load ActiveRecord models if available
begin
  require_relative "../../../app/models/openai_agents/tracing/trace"
  require_relative "../../../app/models/openai_agents/tracing/span"
rescue LoadError
  # Models will be loaded by Rails engine
end

module OpenAIAgents
  module Tracing
    # Processor that saves spans and traces to a Rails database using ActiveRecord
    #
    # ActiveRecordProcessor integrates with the OpenAI Agents tracing system to
    # store traces and spans in your Rails application's database. This enables:
    #
    # - Local storage without external dependencies
    # - Integration with Rails database tooling
    # - Web interface for trace visualization
    # - Performance analytics and cost tracking
    # - Error monitoring and alerting
    #
    # ## Usage
    #
    # The processor is typically configured automatically via the Rails engine,
    # but can also be set up manually:
    #
    # @example Automatic configuration (via initializer)
    #   OpenAIAgents::Tracing.configure do |config|
    #     config.auto_configure = true
    #   end
    #
    # @example Manual configuration
    #   processor = OpenAIAgents::Tracing::ActiveRecordProcessor.new
    #   OpenAIAgents.tracer.add_processor(processor)
    #
    # @example With custom options
    #   processor = OpenAIAgents::Tracing::ActiveRecordProcessor.new(
    #     sampling_rate: 0.1,  # Sample 10% of traces
    #     batch_size: 100      # Batch 100 spans before saving
    #   )
    #
    # ## Database Requirements
    #
    # This processor requires the Rails database migration to be run:
    #
    #   rails generate openai_agents:tracing:install
    #   rails db:migrate
    #
    # ## Performance Considerations
    #
    # - Uses batch processing to reduce database load
    # - Supports sampling to limit data volume
    # - Optimized for high-throughput applications
    # - Background processing for non-blocking operation
    class ActiveRecordProcessor
      # Default sampling rate (capture all traces)
      DEFAULT_SAMPLING_RATE = 1.0

      # Default batch size for database operations
      DEFAULT_BATCH_SIZE = 50

      # @return [Float] Current sampling rate (0.0 to 1.0)
      attr_reader :sampling_rate

      # @return [Integer] Batch size for database operations
      attr_reader :batch_size

      # Creates a new ActiveRecord processor
      #
      # @param sampling_rate [Float] Rate of traces to capture (0.0 to 1.0)
      # @param batch_size [Integer] Number of spans to batch before saving
      # @param auto_cleanup [Boolean] Whether to enable automatic cleanup
      # @param cleanup_older_than [ActiveSupport::Duration] Age threshold for cleanup
      def initialize(sampling_rate: DEFAULT_SAMPLING_RATE, batch_size: DEFAULT_BATCH_SIZE,
                     auto_cleanup: false, cleanup_older_than: 30.days)
        @sampling_rate = sampling_rate.clamp(0.0, 1.0)
        @batch_size = batch_size
        @auto_cleanup = auto_cleanup
        @cleanup_older_than = cleanup_older_than

        @span_buffer = []
        @trace_buffer = {}
        @mutex = Mutex.new
        @last_cleanup = Time.current

        # Lazy validation flag
        @database_validated = false

        # Start background processing if batch size > 1
        start_background_processing if @batch_size > 1

        Rails.logger.info "[OpenAI Agents Tracing] ActiveRecord processor initialized " \
                          "(sampling: #{(@sampling_rate * 100).round(1)}%, batch: #{@batch_size})"
      end

      # Called when a span starts
      #
      # For ActiveRecord storage, we only process completed spans, so this
      # method creates or updates the trace record if needed.
      #
      # @param span [Span] The span that started
      # @return [void]
      def on_span_start(span)
        ensure_database_validated
        return unless should_sample?(span.trace_id)

        ensure_trace_exists(span)
      end

      # Called when a span ends
      #
      # This is where the main processing happens. The span is saved to the
      # database (directly or via batching) and the trace status is updated.
      #
      # @param span [Span] The span that ended
      # @return [void]
      def on_span_end(span)
        ensure_database_validated
        return unless should_sample?(span.trace_id)

        if @batch_size > 1
          add_to_batch(span)
        else
          save_span_immediately(span)
        end

        # Periodic cleanup if enabled
        perform_cleanup_if_needed
      end

      # Forces immediate processing of all buffered spans
      #
      # @return [void]
      def flush
        @mutex.synchronize do
          process_batch(@span_buffer.dup)
          @span_buffer.clear
        end
      end

      # Shuts down the processor
      #
      # Flushes any remaining spans and stops background processing.
      #
      # @return [void]
      def shutdown
        flush
        @background_thread&.kill
        Rails.logger.info "[OpenAI Agents Tracing] ActiveRecord processor shut down"
      end

      private

      # Ensure database has been validated (lazy loading)
      def ensure_database_validated
        return if @database_validated

        @mutex.synchronize do
          return if @database_validated

          validate_database_setup
          @database_validated = true
        end
      end

      # Check if trace should be sampled based on sampling rate
      #
      # @param trace_id [String] The trace ID
      # @return [Boolean] Whether to process this trace
      def should_sample?(trace_id)
        return true if @sampling_rate >= 1.0
        return false if @sampling_rate <= 0.0

        # Use trace ID for consistent sampling decisions
        hash = Digest::MD5.hexdigest(trace_id).to_i(16)
        (hash % 10_000) < (@sampling_rate * 10_000)
      end

      # Ensure trace record exists in database
      #
      # @param span [Span] Span containing trace information
      # @return [void]
      def ensure_trace_exists(span)
        @mutex.synchronize do
          return if @trace_buffer[span.trace_id]

          # Check if trace already exists in database
          existing_trace = ::OpenAIAgents::Tracing::TraceRecord.find_by(trace_id: span.trace_id)
          if existing_trace
            @trace_buffer[span.trace_id] = existing_trace
            return
          end

          # Extract trace information from span attributes
          trace_attrs = extract_trace_attributes(span)

          begin
            trace = ::OpenAIAgents::Tracing::TraceRecord.create!(
              trace_id: span.trace_id,
              workflow_name: trace_attrs[:workflow_name] || "Unknown Workflow",
              group_id: trace_attrs[:group_id],
              metadata: trace_attrs[:metadata] || {},
              started_at: span.start_time,
              status: "running"
            )
            @trace_buffer[span.trace_id] = trace
          rescue ActiveRecord::RecordInvalid => e
            Rails.logger.warn "[OpenAI Agents Tracing] Failed to create trace: #{e.message}"
          end
        end
      end

      # Extract trace attributes from span
      #
      # @param span [Span] The span containing trace data
      # @return [Hash] Trace attributes
      def extract_trace_attributes(span)
        attributes = span.attributes || {}

        {
          workflow_name: attributes["trace.workflow_name"] ||
            attributes["agent.name"] ||
            span.name.split(".").first,
          group_id: attributes["trace.group_id"],
          metadata: attributes["trace.metadata"] || {}
        }
      end

      # Add span to batch for later processing
      #
      # @param span [Span] The span to add
      # @return [void]
      def add_to_batch(span)
        @mutex.synchronize do
          @span_buffer << span

          if @span_buffer.size >= @batch_size
            process_batch(@span_buffer.dup)
            @span_buffer.clear
          end
        end
      end

      # Save span immediately (non-batched mode)
      #
      # @param span [Span] The span to save
      # @return [void]
      def save_span_immediately(span)
        ensure_trace_exists(span)
        save_span_to_database(span)
      end

      # Process a batch of spans
      #
      # @param spans [Array<Span>] Spans to process
      # @return [void]
      def process_batch(spans)
        return if spans.empty?

        begin
          ::OpenAIAgents::Tracing::SpanRecord.transaction do
            spans.each { |span| save_span_to_database(span) }
          end

          Rails.logger.debug "[OpenAI Agents Tracing] Saved batch of #{spans.size} spans"
        rescue StandardError => e
          Rails.logger.error "[OpenAI Agents Tracing] Failed to save span batch: #{e.message}"
        end
      end

      # Save individual span to database
      #
      # @param span [Span] The span to save
      # @return [void]
      def save_span_to_database(span)
        # Skip trace-level spans as they're handled separately
        return if span.kind == :trace

        span_attributes = {
          span_id: span.span_id,
          trace_id: span.trace_id,
          parent_id: span.parent_id,
          name: span.name,
          kind: span.kind.to_s,
          start_time: span.start_time,
          end_time: span.end_time,
          duration_ms: calculate_duration_ms(span),
          span_attributes: sanitize_attributes(span.attributes),
          events: sanitize_events(span.events),
          status: span.status.to_s
        }

        ::OpenAIAgents::Tracing::SpanRecord.create!(span_attributes)
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.warn "[OpenAI Agents Tracing] Failed to save span #{span.span_id}: #{e.message}"
      rescue StandardError => e
        Rails.logger.error "[OpenAI Agents Tracing] Unexpected error saving span: #{e.message}"
      end

      # Calculate duration in milliseconds
      #
      # @param span [Span] The span
      # @return [Float, nil] Duration in milliseconds
      def calculate_duration_ms(span)
        return nil unless span.start_time && span.end_time

        ((span.end_time - span.start_time) * 1000).round(2)
      end

      # Sanitize span attributes for database storage
      #
      # @param attributes [Hash] Raw attributes
      # @return [Hash] Sanitized attributes
      def sanitize_attributes(attributes)
        return {} unless attributes.is_a?(Hash)

        # Remove or truncate large values to prevent database issues
        sanitized = {}
        attributes.each do |key, value|
          sanitized[key.to_s] = sanitize_value(value)
        end
        sanitized
      end

      # Sanitize span events for database storage
      #
      # @param events [Array] Raw events
      # @return [Array] Sanitized events
      def sanitize_events(events)
        return [] unless events.is_a?(Array)

        events.map do |event|
          next unless event.is_a?(Hash)

          {
            "name" => event["name"]&.to_s,
            "timestamp" => event["timestamp"],
            "attributes" => sanitize_attributes(event["attributes"] || {})
          }
        end.compact
      end

      # Sanitize individual value
      #
      # @param value [Object] Value to sanitize
      # @return [Object] Sanitized value
      def sanitize_value(value)
        case value
        when String
          # Truncate very long strings
          value.length > 10_000 ? "#{value[0..9997]}..." : value
        when Hash
          # Recursively sanitize nested hashes
          value.transform_keys(&:to_s).transform_values { |v| sanitize_value(v) }
        when Array
          # Limit array size and sanitize elements
          limited_array = value.first(100)
          limited_array.map { |v| sanitize_value(v) }
        else
          value
        end
      end

      # Start background processing thread
      #
      # @return [void]
      def start_background_processing
        @background_thread = Thread.new do
          loop do
            sleep(5) # Process every 5 seconds

            next if @span_buffer.empty?

            @mutex.synchronize do
              if @span_buffer.any?
                process_batch(@span_buffer.dup)
                @span_buffer.clear
              end
            end
          rescue StandardError => e
            Rails.logger.error "[OpenAI Agents Tracing] Background processing error: #{e.message}"
          end
        end
        @background_thread.name = "OpenAI-Agents-Tracing"
      end

      # Perform cleanup if needed
      #
      # @return [void]
      def perform_cleanup_if_needed
        return unless @auto_cleanup
        return if Time.current - @last_cleanup < 1.hour

        Thread.new do
          deleted_count = ::OpenAIAgents::Tracing::TraceRecord.cleanup_old_traces(older_than: @cleanup_older_than)
          Rails.logger.info "[OpenAI Agents Tracing] Cleaned up #{deleted_count} old traces" if deleted_count > 0
        rescue StandardError => e
          Rails.logger.error "[OpenAI Agents Tracing] Cleanup error: #{e.message}"
        ensure
          @last_cleanup = Time.current
        end
      end

      # Validate that database tables exist
      #
      # @raise [StandardError] If tables don't exist
      def validate_database_setup
        unless ::OpenAIAgents::Tracing::TraceRecord.table_exists?
          raise "OpenAI Agents tracing tables not found. " \
                "Run: rails generate openai_agents:tracing:install && rails db:migrate"
        end

        return if ::OpenAIAgents::Tracing::SpanRecord.table_exists?

        raise "OpenAI Agents tracing tables not found. " \
              "Run: rails generate openai_agents:tracing:install && rails db:migrate"
      end
    end
  end
end
