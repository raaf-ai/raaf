# frozen_string_literal: true

# Load ActiveRecord models if available
begin
  require_relative "../../../app/models/raaf/tracing/trace"
  require_relative "../../../app/models/raaf/tracing/span"
rescue LoadError
  # Models will be loaded by Rails engine
end

require "digest"
require "set"
require "raaf/logging"
require_relative "tracing/base_processor"

module RAAF
  module Tracing
    # Processor that saves spans and traces to a Rails database using ActiveRecord
    #
    # ActiveRecordProcessor integrates with the RAAF tracing system to
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
    #   RAAF::Tracing.configure do |config|
    #     config.auto_configure = true
    #   end
    #
    # @example Manual configuration
    #   processor = RAAF::Tracing::ActiveRecordProcessor.new
    #   RAAF::tracer.add_processor(processor)
    #
    # @example With custom options
    #   processor = RAAF::Tracing::ActiveRecordProcessor.new(
    #     sampling_rate: 0.1,  # Sample 10% of traces
    #     batch_size: 100      # Batch 100 spans before saving
    #   )
    #
    # ## Database Requirements
    #
    # This processor requires the Rails database migration to be run:
    #
    #   rails generate raaf:tracing:install
    #   rails db:migrate
    #
    # ## Performance Considerations
    #
    # - Uses batch processing to reduce database load
    # - Supports sampling to limit data volume
    # - Optimized for high-throughput applications
    # - Background processing for non-blocking operation
    class ActiveRecordProcessor < BaseProcessor
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

        # Initialize base processor with ActiveRecord-specific options
        super(batch_size: batch_size,
              sampling_rate: sampling_rate,
              auto_cleanup: auto_cleanup,
              cleanup_older_than: cleanup_older_than)
      end

      # Hook for ActiveRecord-specific initialization after BaseProcessor setup
      #
      # @param options [Hash] Options passed to initialize
      # @return [void]
      def post_initialize(options)
        @sampling_rate = options[:sampling_rate].clamp(0.0, 1.0)
        @auto_cleanup = options[:auto_cleanup]
        @cleanup_older_than = options[:cleanup_older_than]

        @trace_buffer = {}
        @last_cleanup = Time.current

        # Lazy validation flag
        @database_validated = false

        log_info("ActiveRecord processor initialized",
          sampling_rate_percent: (@sampling_rate * 100).round(1),
          batch_size: @batch_size
        )
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
      # BaseProcessor handles the main processing logic. This method just
      # performs ActiveRecord-specific cleanup tasks.
      #
      # @param span [Span] The span that ended
      # @return [void]
      def on_span_end(span)
        # Call parent class to handle buffering and batching
        super(span)

        # Periodic cleanup if enabled
        perform_cleanup_if_needed
      end

      protected

      # Determines if a span should be processed (BaseProcessor abstract method)
      #
      # @param span [Span] The span to evaluate
      # @return [Boolean] true if span should be processed
      def should_process?(span)
        return false unless ensure_database_validated
        # Extract trace_id in a way that works for both Span objects and sanitized hashes
        trace_id = span.is_a?(Hash) ? span[:trace_id] : span.trace_id
        should_sample?(trace_id)
      end

      # Transforms a span for database storage (BaseProcessor abstract method)
      #
      # @param span [Span, Hash] The span to transform (can be Span object or sanitized hash)
      # @return [Hash, nil] Transformed span data or nil to skip
      def process_span(span)
        # Extract values in a way that works for both Span objects and sanitized hashes
        span_id = span.is_a?(Hash) ? span[:span_id] : span.span_id
        trace_id = span.is_a?(Hash) ? span[:trace_id] : span.trace_id
        parent_id = span.is_a?(Hash) ? span[:parent_id] : span.parent_id
        name = span.is_a?(Hash) ? span[:name] : span.name
        kind = span.is_a?(Hash) ? span[:kind] : span.kind
        start_time = span.is_a?(Hash) ? span[:start_time] : span.start_time
        end_time = span.is_a?(Hash) ? span[:end_time] : span.end_time
        status = span.is_a?(Hash) ? span[:status] : span.status
        attributes = span.is_a?(Hash) ? (span[:attributes] || {}) : (span.attributes || {})
        events = span.is_a?(Hash) ? (span[:events] || []) : (span.events || [])

        log_debug_tracing("ActiveRecord process_span", span_kind: kind, span_name: name, span_id: span_id)

        ensure_trace_exists(span, trace_id)

        # Return sanitized span data to prevent circular reference issues
        # This is critical for BatchTraceProcessor flow where unsanitized spans
        # can cause stack overflow in HashWithIndifferentAccess
        sanitized_span_data = {
          span_id: span_id,
          trace_id: trace_id,
          parent_id: parent_id,
          name: name,
          kind: kind,
          start_time: start_time,
          end_time: end_time,
          status: status,
          attributes: sanitize_attributes(attributes),
          events: sanitize_events(events)
        }

        log_debug_tracing("ActiveRecord process_span returning sanitized data",
                          span_kind: sanitized_span_data[:kind],
                          span_name: sanitized_span_data[:name],
                          attributes_count: sanitized_span_data[:attributes]&.keys&.size || 0)

        sanitized_span_data
      end

      # Exports a batch of spans to the database (BaseProcessor abstract method)
      #
      # @param spans [Array] Array of spans to save
      # @return [void]
      def export_batch(spans)
        process_batch(spans)
      end

      private

      # Ensure database has been validated (lazy loading)
      def ensure_database_validated
        return true if @database_validated

        # NOTE: This method is called from within mutex-synchronized blocks
        # so additional synchronization is not needed here
        begin
          validate_database_setup
          @database_validated = true
          true
        rescue StandardError => e
          log_error("Database validation failed", error: e.message, error_class: e.class.name)
          false
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
      def ensure_trace_exists(span, trace_id = nil)
        # NOTE: This method is called from within a mutex-synchronized block in process_span
        # so no additional synchronization is needed here

        # Extract trace_id - use parameter if provided, otherwise extract from span
        actual_trace_id = trace_id || (span.is_a?(Hash) ? span[:trace_id] : span.trace_id)

        return if @trace_buffer[actual_trace_id]

        # Check if trace already exists in database
        existing_trace = ::RAAF::Tracing::TraceRecord.find_by(trace_id: actual_trace_id)
        if existing_trace
          @trace_buffer[actual_trace_id] = existing_trace
          return
        end

        # Extract trace information from span attributes
        trace_attrs = extract_trace_attributes(span)

        begin
          # Extract start_time for trace creation
          start_time = span.is_a?(Hash) ? span[:start_time] : span.start_time

          trace = ::RAAF::Tracing::TraceRecord.create!(
            trace_id: actual_trace_id,
            workflow_name: trace_attrs[:workflow_name] || "Unknown Workflow",
            group_id: trace_attrs[:group_id],
            metadata: trace_attrs[:metadata] || {},
            started_at: start_time,
            status: "running"
          )
          @trace_buffer[actual_trace_id] = trace
        rescue ActiveRecord::RecordInvalid => e
          log_warn("Failed to create trace", error: e.message, error_class: e.class.name)
        end
      end

      # Extract trace attributes from span
      #
      # @param span [Span] The span containing trace data
      # @return [Hash] Trace attributes
      def extract_trace_attributes(span)
        # Extract attributes and name in a way that works for both Span objects and sanitized hashes
        attributes = span.is_a?(Hash) ? (span[:attributes] || {}) : (span.attributes || {})
        name = span.is_a?(Hash) ? span[:name] : span.name

        {
          workflow_name: attributes["trace.workflow_name"] ||
            attributes["agent.name"] ||
            name.to_s.split(".").first,
          group_id: attributes["trace.group_id"],
          metadata: attributes["trace.metadata"] || {}
        }
      end



      # Process a batch of spans
      #
      # @param spans [Array<Span>] Spans to process
      # @return [void]
      def process_batch(spans)
        return if spans.empty?

        begin
          ::RAAF::Tracing::SpanRecord.transaction do
            spans.each do |span|
              save_span_to_database(span)
            end
          end

          log_debug_tracing("Saved batch of spans", spans_count: spans.size)
        rescue StandardError => e
          log_error("Failed to save span batch", error: e.message, error_class: e.class.name)
        end
      end

      # Save individual span to database
      #
      # @param span [Span, Hash] The span to save (can be Span object or sanitized hash from process_span)
      # @return [void]
      def save_span_to_database(span)
        # Handle both Span objects and sanitized hash data from process_span
        if span.is_a?(Hash)
          # Already sanitized data from process_span
          span_kind = span[:kind]
          span_name = span[:name]
          span_id = span[:span_id]
        else
          # Original Span object
          span_kind = span.kind
          span_name = span.name
          span_id = span.span_id
        end

        log_debug_tracing("ActiveRecord save_span_to_database", span_kind: span_kind, span_name: span_name, span_id: span_id)

        # Skip trace-level spans as they're handled separately
        if span_kind == :trace
          log_debug_tracing("ActiveRecord skipping trace-level span", span_kind: span_kind, span_name: span_name)
          return
        end

        if span.is_a?(Hash)
          # Use already sanitized data from process_span (prevents double sanitization)
          span_attributes = {
            span_id: span[:span_id],
            trace_id: span[:trace_id],
            parent_id: span[:parent_id],
            name: span[:name],
            kind: span[:kind].to_s,
            start_time: span[:start_time],
            end_time: span[:end_time],
            duration_ms: calculate_duration_from_times(span[:start_time], span[:end_time]),
            span_attributes: span[:attributes] || {},  # Already sanitized
            events: span[:events] || [],               # Already sanitized
            status: span[:status].to_s
          }
        else
          # Process original Span object with sanitization
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
        end

        log_debug_tracing("ActiveRecord creating span record", span_kind: span_attributes[:kind], span_name: span_attributes[:name], span_id: span_attributes[:span_id])

        ::RAAF::Tracing::SpanRecord.create!(span_attributes)
      rescue ActiveRecord::RecordInvalid => e
        log_warn("Failed to save span", span_id: span.span_id, error: e.message, error_class: e.class.name)
      rescue StandardError => e
        log_error("Unexpected error saving span", error: e.message, error_class: e.class.name)
      end

      # Calculate duration in milliseconds
      #
      # @param span [Span] The span
      # @return [Float, nil] Duration in milliseconds
      def calculate_duration_ms(span)
        return nil unless span.start_time && span.end_time

        ((span.end_time - span.start_time) * 1000).round(2)
      end

      # Calculate duration from separate start and end times
      #
      # @param start_time [Time] Start time
      # @param end_time [Time] End time
      # @return [Float, nil] Duration in milliseconds
      def calculate_duration_from_times(start_time, end_time)
        return nil unless start_time && end_time

        ((end_time - start_time) * 1000).round(2)
      end

      # Sanitize span attributes for database storage
      #
      # @param attributes [Hash] Raw attributes
      # @return [Hash] Sanitized attributes
      def sanitize_attributes(attributes)
        return {} unless attributes.is_a?(Hash)

        # Remove or truncate large values to prevent database issues
        sanitized = {}
        visited = Set.new
        attributes.each do |key, value|
          sanitized[key.to_s] = sanitize_value(value, visited)
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
      # @param visited [Set] Set of visited object IDs to prevent circular references
      # @return [Object] Sanitized value
      def sanitize_value(value, visited = Set.new)
        # Prevent circular references by tracking visited objects
        if value.is_a?(Hash) || value.is_a?(Array)
          object_id = value.object_id
          return "[CIRCULAR_REFERENCE]" if visited.include?(object_id)
          visited = visited.dup.add(object_id)
        end

        case value
        when String
          # Truncate very long strings
          value.length > 10_000 ? "#{value[0..9997]}..." : value
        when Hash
          # Recursively sanitize nested hashes with circular reference protection
          sanitized = {}
          value.each do |k, v|
            sanitized[k.to_s] = sanitize_value(v, visited)
          end
          sanitized
        when Array
          # Limit array size and sanitize elements with circular reference protection
          limited_array = value.first(100)
          limited_array.map { |v| sanitize_value(v, visited) }
        else
          value
        end
      end


      # Perform cleanup if needed
      #
      # @return [void]
      def perform_cleanup_if_needed
        return unless @auto_cleanup
        return if Time.current - @last_cleanup < 1.hour

        Thread.new do
          deleted_count = ::RAAF::Tracing::TraceRecord.cleanup_old_traces(older_than: @cleanup_older_than)
          log_info("Cleaned up old traces", deleted_count: deleted_count) if deleted_count > 0
        rescue StandardError => e
          log_error("Cleanup error", error: e.message, error_class: e.class.name)
        ensure
          @last_cleanup = Time.current
        end
      end

      # Performs processor-specific shutdown logic (BaseProcessor hook)
      #
      # @return [void]
      def perform_shutdown
        # Stop background thread if it exists
        @background_thread&.kill
        log_debug("#{self.class.name} shut down", processor: self.class.name)
      end

      # Validate that database tables exist
      #
      # @raise [StandardError] If tables don't exist
      def validate_database_setup
        unless ::RAAF::Tracing::TraceRecord.table_exists?
          raise "RAAF tracing tables not found. " \
                "Run: rails generate raaf:tracing:install && rails db:migrate"
        end

        return if ::RAAF::Tracing::SpanRecord.table_exists?

        raise "RAAF tracing tables not found. " \
              "Run: rails generate raaf:tracing:install && rails db:migrate"
      end
    end
  end
end
