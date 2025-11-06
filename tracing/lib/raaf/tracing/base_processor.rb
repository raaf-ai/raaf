# frozen_string_literal: true

require "raaf/logging"

module RAAF
  module Tracing
    # Base class for all trace processors
    #
    # BaseProcessor provides common functionality for all trace processors,
    # including thread-safe buffering, batch management, and a consistent
    # interface. Subclasses implement specific export logic for different
    # backends (OpenAI, ActiveRecord, Datadog, etc.).
    #
    # ## Common Features
    #
    # - Thread-safe span buffering with automatic batch flushing
    # - Configurable batch sizes for performance optimization
    # - Consistent logging and error handling
    # - Standard processor interface methods
    # - Graceful shutdown with final flush
    #
    # ## Subclass Implementation
    #
    # Subclasses must implement these abstract methods:
    #
    # - `should_process?(span)` - Determine if span should be processed
    # - `process_span(span)` - Transform span for backend format
    # - `export_batch(spans)` - Send batch of spans to backend
    #
    # @example Creating a custom processor
    #   class MyProcessor < BaseProcessor
    #     def should_process?(span)
    #       span.end_time.present?  # Only process finished spans
    #     end
    #
    #     def process_span(span)
    #       { id: span.span_id, name: span.name }  # Transform to custom format
    #     end
    #
    #     def export_batch(spans)
    #       MyBackend.send_spans(spans)  # Send to backend
    #     end
    #   end
    #
    # @example Using a processor
    #   processor = MyProcessor.new(batch_size: 100)
    #   tracer.add_processor(processor)
    class BaseProcessor
      include Logger

      # @return [Integer] Number of spans to batch before automatic export
      attr_reader :batch_size

      # Creates a new base processor
      #
      # @param batch_size [Integer] Number of spans to accumulate before
      #   automatic export. Default: 50
      # @param options [Hash] Additional options passed to subclass
      def initialize(batch_size: 50, **options)
        @batch_size = batch_size
        @span_buffer = []
        @mutex = Mutex.new

        # Allow subclasses to perform additional initialization
        post_initialize(options)

        log_debug("#{self.class.name} initialized",
                 processor: self.class.name, batch_size: @batch_size)
      end

      # Hook for subclass initialization
      #
      # Override this method in subclasses to perform additional setup
      # after the base processor has been initialized.
      #
      # @param options [Hash] Options passed to initialize
      # @return [void]
      def post_initialize(options)
        # Default: no-op
        # Override in subclasses for custom initialization
      end

      # Called when a span starts
      #
      # Default implementation is a no-op. Override in subclasses
      # if span start events need to be handled.
      #
      # @param span [Span] The span that started
      # @return [void]
      def on_span_start(span)
        # Default: no-op
        # Override in subclasses if needed
      end

      # Called when a span ends
      #
      # This is the main processing method. It checks if the span should
      # be processed, transforms it, adds it to the buffer, and triggers
      # batch export when the buffer is full.
      #
      # @param span [Span] The span that ended
      # @return [void]
      def on_span_end(span)
        return unless should_process?(span)

        begin
          @mutex.synchronize do
            processed = process_span(span)
            @span_buffer << processed if processed

            flush_buffer if @span_buffer.size >= @batch_size
          end
        rescue StandardError => e
          # Log error but don't re-raise - one span failure shouldn't break the system
          log_error("Failed to process span", span_id: span.span_id, error: e.message)
          # Don't re-raise - preserve buffer integrity and allow other spans to process
        end
      end

      # Exports a batch of spans
      #
      # This method is typically called by BatchTraceProcessor for
      # accumulated spans from multiple span end events.
      #
      # @param spans [Array<Span>] Array of spans to export
      # @return [void]
      def export(spans)
        return if spans.empty?

        # Filter and process spans
        processed_spans = spans.filter_map do |span|
          next unless should_process?(span)

          process_span(span)
        end

        return if processed_spans.empty?

        export_batch(processed_spans)
      rescue StandardError => e
        handle_export_error(e, processed_spans || spans)
      end

      # Forces immediate export of all buffered spans
      #
      # @return [void]
      def force_flush
        @mutex.synchronize do
          flush_buffer
        end
      end

      # Shuts down the processor
      #
      # Flushes any remaining spans and performs cleanup.
      # After shutdown, the processor should not be used.
      #
      # @return [void]
      def shutdown
        force_flush
        perform_shutdown
        log_debug("#{self.class.name} shut down", processor: self.class.name)
      end

      protected

      # Determines if a span should be processed
      #
      # Subclasses must implement this method to define their filtering logic.
      # Common patterns include checking for finished spans, sampling rates,
      # or span types.
      #
      # @param span [Span] The span to evaluate
      # @return [Boolean] true if span should be processed, false otherwise
      #
      # @abstract Subclasses must implement this method
      def should_process?(span)
        raise NotImplementedError, "#{self.class.name} must implement #should_process?"
      end

      # Transforms a span for the target backend format
      #
      # Subclasses must implement this method to convert spans from the
      # RAAF internal format to whatever format their backend expects.
      #
      # @param span [Span] The span to transform
      # @return [Object, nil] Transformed span data, or nil to skip
      #
      # @abstract Subclasses must implement this method
      def process_span(span)
        raise NotImplementedError, "#{self.class.name} must implement #process_span"
      end

      # Exports a batch of processed spans to the backend
      #
      # Subclasses must implement this method to send the transformed
      # spans to their target backend (database, API, file, etc.).
      #
      # @param spans [Array] Array of processed span data
      # @return [void]
      #
      # @abstract Subclasses must implement this method
      def export_batch(spans)
        raise NotImplementedError, "#{self.class.name} must implement #export_batch"
      end

      # Performs processor-specific shutdown logic
      #
      # Override this method in subclasses to perform cleanup operations
      # during shutdown (closing connections, stopping threads, etc.).
      #
      # @return [void]
      def perform_shutdown
        # Default: no-op
        # Override in subclasses if cleanup is needed
      end

      private

      # Flushes the current buffer of spans
      #
      # This method is called internally when the buffer reaches capacity
      # or during force_flush. It exports all buffered spans and clears
      # the buffer.
      #
      # @return [void]
      def flush_buffer
        return if @span_buffer.empty?

        spans_to_export = @span_buffer.dup
        @span_buffer.clear

        log_debug("Flushing #{spans_to_export.size} spans",
                 processor: self.class.name, span_count: spans_to_export.size)

        export_batch(spans_to_export)
      rescue StandardError => e
        handle_export_error(e, spans_to_export)
      end

      # Handles errors during span export
      #
      # This method provides consistent error handling across all processors.
      # Subclasses can override for custom error handling behavior.
      #
      # @param error [StandardError] The error that occurred
      # @param spans [Array] The spans that failed to export
      # @return [void]
      def handle_export_error(error, spans)
        log_error("Failed to export #{spans&.size || 0} spans: #{error.message}",
                 processor: self.class.name, error_class: error.class.name)
        log_debug("Export error backtrace: #{error.backtrace&.first(5)&.join("\n")}",
                 processor: self.class.name)
      end
    end
  end
end