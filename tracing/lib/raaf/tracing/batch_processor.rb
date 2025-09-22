# frozen_string_literal: true

require "concurrent"
require "set"
require_relative "../../../../core/lib/raaf/logging"

module RAAF
  module Tracing
    # Processor that batches spans and exports them efficiently in the background
    #
    # BatchTraceProcessor accumulates spans and exports them in batches to reduce
    # network overhead and improve performance. It runs a background thread that
    # periodically flushes accumulated spans to the configured exporter.
    #
    # ## Features
    #
    # - Automatic batching based on size and time intervals
    # - Background processing to avoid blocking application code
    # - Queue overflow protection with configurable limits
    # - Graceful shutdown with final flush
    # - Thread-safe operation
    #
    # ## Configuration
    #
    # The processor behavior can be tuned via initialization parameters:
    #
    # - `batch_size`: Number of spans to accumulate before export (default: 50)
    # - `flush_interval`: Maximum time between exports in seconds (default: 5.0)
    # - `max_queue_size`: Maximum spans to queue before dropping (default: 2048)
    #
    # ## Usage
    #
    # BatchTraceProcessor is typically used to wrap other processors that
    # perform expensive operations like network requests:
    #
    # @example Wrapping OpenAI processor
    #   openai_processor = OpenAIProcessor.new
    #   batch_processor = BatchTraceProcessor.new(
    #     openai_processor,
    #     batch_size: 100,
    #     flush_interval: 10.0
    #   )
    #   tracer.add_processor(batch_processor)
    #
    # @example With custom exporter
    #   class MyExporter
    #     def export(spans)
    #       # Send spans to backend
    #     end
    #   end
    #
    #   processor = BatchTraceProcessor.new(MyExporter.new)
    class BatchTraceProcessor
      include Logger
      # Default number of spans to accumulate before export
      DEFAULT_BATCH_SIZE = 50

      # Default maximum time between exports in seconds
      DEFAULT_FLUSH_INTERVAL = 5.0

      # Default maximum number of spans to queue
      DEFAULT_MAX_QUEUE_SIZE = 2048

      # @return [Integer] Number of spans per batch
      attr_reader :batch_size

      # @return [Float] Time interval between flushes in seconds
      attr_reader :flush_interval

      # Creates a new batch processor
      #
      # @param exporter [Object] The exporter to send batched spans to.
      #   Must implement `export(spans)` method.
      # @param batch_size [Integer] Number of spans to accumulate before
      #   automatic export. Default: 50
      # @param flush_interval [Float] Maximum seconds between exports.
      #   The processor will export even partial batches after this interval.
      #   Default: 5.0
      # @param max_queue_size [Integer] Maximum spans to queue before dropping.
      #   Prevents unbounded memory growth. Default: 2048
      #
      # @raise [ArgumentError] If exporter doesn't implement export method
      def initialize(exporter, batch_size: DEFAULT_BATCH_SIZE,
                     flush_interval: DEFAULT_FLUSH_INTERVAL,
                     max_queue_size: DEFAULT_MAX_QUEUE_SIZE)
        @exporter = exporter
        @batch_size = batch_size
        @flush_interval = flush_interval
        @max_queue_size = max_queue_size

        @queue = Concurrent::Array.new
        @shutdown = Concurrent::AtomicBoolean.new(false)
        @force_flush = Concurrent::Event.new
        @last_flush_time = Concurrent::AtomicReference.new(Time.now)

        # Start background thread for processing
        @worker_thread = Thread.new { run_worker }
        @worker_thread.name = "RAAF::BatchTraceProcessor"

        # Register multiple exit handlers to ensure flushing
        register_exit_handlers
      end

      # Called when a span starts (no-op)
      #
      # BatchProcessor only processes completed spans, so this method
      # does nothing. Spans are queued when they end.
      #
      # @param span [Span] The span that started (ignored)
      # @return [void]
      def on_span_start(span)
        # BatchProcessor only cares about completed spans
      end

      # Called when a span ends
      #
      # Adds the span to the queue for batched export. If the queue is full,
      # the span is dropped with a warning. If the batch size is reached,
      # triggers an immediate flush.
      #
      # @param span [Span] The span that ended
      # @return [void]
      def on_span_end(span)
        return if @shutdown.true?

        # Ensure span is finished before queuing
        unless span.finished?
          begin
            span.finish(end_time: Time.now.utc) unless span.end_time
            log_debug_tracing("[BatchTraceProcessor] Auto-finished span before queuing",
                              span_id: span.span_id, span_name: span.name)
          rescue StandardError => e
            log_debug_tracing("[BatchTraceProcessor] Failed to auto-finish span: #{e.message}",
                              span_id: span.span_id, error: e.message)
            return
          end
        end

        # Drop span if queue is full
        if @queue.size >= @max_queue_size
          warn "[BatchTraceProcessor] Queue full, dropping span: #{span.name}"
          return
        end

        @queue << span

        # Debug logging now handled by category system
        log_debug_tracing("[BatchTraceProcessor] Added span '#{span.name}' to queue (#{@queue.size}/#{@batch_size})",
                          span_name: span.name, queue_size: @queue.size, batch_size: @batch_size)

        # Trigger flush if we've reached batch size
        return unless @queue.size >= @batch_size

        log_debug_tracing("[BatchTraceProcessor] Batch size reached, triggering flush",
                          queue_size: @queue.size, batch_size: @batch_size)
        @force_flush.set
      end

      # Forces immediate export of all queued spans
      #
      # Triggers the background thread to export any accumulated spans
      # immediately, regardless of batch size. Blocks until the queue
      # is empty or shutdown occurs.
      #
      # @return [void]
      #
      # @example Force export before critical operation
      #   processor.force_flush
      #   # All spans exported
      def force_flush
        return if @shutdown.true?

        @force_flush.set
        # Wait for flush to complete with better timeout handling
        timeout = Time.now + 2.0 # 2 second timeout
        sleep(0.01) while !@queue.empty? && !@shutdown.true? && Time.now < timeout

        # If still not empty after timeout, flush synchronously
        return if @queue.empty? || @shutdown.true?

        emergency_flush
      end

      # Shuts down the batch processor
      #
      # Performs a graceful shutdown:
      # 1. Signals the worker thread to stop
      # 2. Waits for the thread to finish (5 second timeout)
      # 3. Exports any remaining spans in the queue
      # 4. Shuts down the exporter if it supports shutdown
      #
      # After shutdown, the processor cannot be reused.
      #
      # @return [void]
      def shutdown
        return if @shutdown.true?

        # Debug logging now handled by category system
        log_info("[BatchTraceProcessor] Starting shutdown (queue size: #{@queue.size})", queue_size: @queue.size)

        @shutdown.make_true
        @force_flush.set # Wake up worker thread

        # Python-style approach: Try background thread first, then synchronous fallback
        thread_finished = false

        # Wait for worker thread to finish (with shorter timeout for responsiveness)
        if @worker_thread.alive?
          log_debug_tracing("[BatchTraceProcessor] Waiting for worker thread to finish...")
          thread_finished = !@worker_thread.join(2.0).nil? # 2 second timeout
          log_debug_tracing("[BatchTraceProcessor] Worker thread #{thread_finished ? "finished" : "timed out"}")
        else
          thread_finished = true
        end

        # Synchronous fallback if thread didn't finish or queue still has spans
        if !thread_finished || !@queue.empty?
          log_debug_tracing("[BatchTraceProcessor] Using synchronous fallback export")
          synchronous_final_export
        end

        # Shutdown exporter
        @exporter.shutdown if @exporter.respond_to?(:shutdown)

        log_info("[BatchTraceProcessor] Shutdown complete")
      end

      private

      # Main worker loop that processes the span queue
      #
      # Runs in a background thread, periodically checking for spans to export.
      # Exports when:
      # - Batch size is reached
      # - Flush interval expires
      # - Force flush is triggered
      # - Shutdown is initiated
      #
      # @api private
      def run_worker
        # Debug logging now handled by category system
        log_debug_tracing("[BatchTraceProcessor] Worker thread started (flush interval: #{@flush_interval}s)", flush_interval: @flush_interval)

        loop do
          # Wait for flush interval or force flush signal
          @force_flush.wait(@flush_interval)
          @force_flush.reset

          # Check if we should flush due to time elapsed
          last_flush = @last_flush_time.get
          time_since_flush = Time.now - last_flush
          should_flush_time = time_since_flush >= @flush_interval

          # Export current batch (more aggressive - flush ANY pending spans)
          batch = []
          while !@queue.empty? && (batch.size < @batch_size || should_flush_time || @shutdown.true?)
            span = @queue.shift
            batch << span if span

            # Break if we hit batch size and it's not a forced flush
            break if batch.size >= @batch_size && !should_flush_time && !@shutdown.true?
          end

          unless batch.empty?
            reason = if @shutdown.true?
                       "shutdown"
                     else
                       (should_flush_time ? "time" : "batch_size")
                     end
            # Debug logging now handled by category system
            log_debug_tracing("[BatchTraceProcessor] Flushing batch of #{batch.size} spans (reason: #{reason}, #{@queue.size} remaining in queue)",
                              batch_size: batch.size, reason: reason, queue_remaining: @queue.size)
          end

          export_batch(batch) unless batch.empty?

          # Break after processing if shutdown is requested
          break if @shutdown.true?

          # Also break if queue was empty and we're shutting down
          break if @queue.empty? && @shutdown.true?
        end
      rescue StandardError => e
        warn "[BatchTraceProcessor] Worker thread error: #{e.message}"
        log_debug_tracing("Worker thread error backtrace", error: e.message, backtrace: e.backtrace.first(5).join("\n"))
      end

      # Exports a batch of spans to the configured exporter
      #
      # Calls the exporter's export method with the batch of spans.
      # Errors are caught and logged to prevent disrupting the worker thread.
      # Auto-finishes spans that have been running too long as a safety net.
      #
      # @param batch [Array<Span>] The spans to export
      # @return [void]
      #
      # @api private
      def export_batch(batch)
        return if batch.empty?

        # Auto-finish spans that have been running too long (safety net)
        processed_batch = batch.map { |span| auto_finish_stuck_spans(span) }

        begin
          log_debug_tracing("[BatchTraceProcessor] Exporting #{processed_batch.size} spans to #{@exporter.class.name}",
                            batch_size: processed_batch.size, exporter: @exporter.class.name)

          # Call the wrapped processor's export method with raw spans
          # The wrapped processor will handle its own processing and transformation
          @exporter.export(processed_batch)

          log_debug_tracing("[BatchTraceProcessor] Export completed successfully", batch_size: processed_batch.size)
        rescue StandardError => e
          warn "[BatchTraceProcessor] Export error: #{e.message}"
          log_debug_tracing("Export error backtrace", error: e.message, backtrace: e.backtrace.first(5).join("\n"))
        end

        @last_flush_time.set(Time.now)
      end

      # Auto-finishes spans that have been running too long as a safety net
      #
      # This method checks if a span has been running for more than 5 minutes
      # and automatically finishes it to prevent stuck spans from clogging the system.
      #
      # @param span [Span] The span to check and potentially finish
      # @return [Span] The span (potentially finished)
      #
      # @api private
      def auto_finish_stuck_spans(span)
        return span unless span.respond_to?(:finished?) && span.respond_to?(:start_time)

        # Skip if already finished
        return span if span.finished?

        # Check if span has been running too long (5 minutes)
        max_duration = 5 * 60  # 5 minutes in seconds
        current_time = Time.now.utc
        duration = current_time - span.start_time

        if duration > max_duration
          begin
            # Auto-finish the stuck span with error status
            span.set_status(:error, description: "Auto-finished: span exceeded maximum duration of #{max_duration} seconds")
            span.finish(end_time: current_time)

            log_debug_tracing("[BatchTraceProcessor] Auto-finished stuck span",
                              span_id: span.span_id,
                              duration_seconds: duration.round(2),
                              max_duration: max_duration)
          rescue StandardError => e
            log_debug_tracing("[BatchTraceProcessor] Failed to auto-finish stuck span: #{e.message}",
                              span_id: span.span_id,
                              error: e.message)
          end
        end

        span
      end

      # Sanitizes a span for export by converting to plain hash and removing circular references
      #
      # @param span [Span] The span to sanitize
      # @return [Hash] Sanitized span data safe for JSON conversion
      #
      # @api private
      def sanitize_span_for_export(span)
        # Convert span to plain hash with sanitized attributes
        {
          span_id: span.span_id,
          trace_id: span.trace_id,
          parent_id: span.parent_id,
          name: span.name,
          kind: span.kind,
          start_time: span.start_time,
          end_time: span.end_time,
          status: span.status,
          attributes: deep_sanitize_hash(span.attributes || {}),
          events: sanitize_events_for_export(span.events || [])
        }
      rescue StandardError => e
        # If sanitization fails, return minimal span data
        warn "[BatchTraceProcessor] Failed to sanitize span #{span.span_id}: #{e.message}"
        {
          span_id: span.span_id,
          trace_id: span.trace_id,
          name: span.name,
          kind: span.kind,
          start_time: span.start_time,
          end_time: span.end_time,
          status: span.status,
          attributes: {},
          events: []
        }
      end

      # Deep sanitizes hash data to remove circular references and convert HashWithIndifferentAccess
      #
      # @param hash [Hash] The hash to sanitize
      # @param visited [Set] Set of visited object IDs to prevent circular references
      # @return [Hash] Sanitized hash safe for JSON conversion
      #
      # @api private
      def deep_sanitize_hash(hash, visited = Set.new)
        return {} unless hash.respond_to?(:each)

        # Prevent circular references
        if visited.include?(hash.object_id)
          return "[CIRCULAR_REFERENCE]"
        end
        visited = visited.dup.add(hash.object_id)

        result = {}
        begin
          # Handle HashWithIndifferentAccess safely by iterating directly
          # instead of calling to_hash which can cause circular reference issues
          hash.each do |key, value|
            # Convert key to string safely
            sanitized_key = case key
                           when String then key
                           when Symbol then key.to_s
                           else key.to_s
                           end

            # Recursively sanitize values
            result[sanitized_key] = sanitize_value_for_export(value, visited)
          end
        rescue SystemStackError => e
          warn "[BatchTraceProcessor] Stack overflow in hash sanitization - returning empty hash: #{e.message}"
          return {}
        rescue StandardError => e
          warn "[BatchTraceProcessor] Hash iteration error: #{e.message}"
          return {}
        end

        result
      rescue StandardError => e
        warn "[BatchTraceProcessor] Hash sanitization error: #{e.message}"
        {}
      end

      # Sanitizes individual values for export
      #
      # @param value [Object] The value to sanitize
      # @param visited [Set] Set of visited object IDs to prevent circular references
      # @return [Object] Sanitized value safe for JSON conversion
      #
      # @api private
      def sanitize_value_for_export(value, visited = Set.new)
        case value
        when Hash
          deep_sanitize_hash(value, visited)
        when Array
          return "[CIRCULAR_REFERENCE]" if visited.include?(value.object_id)
          visited = visited.dup.add(value.object_id)
          begin
            value.map { |v| sanitize_value_for_export(v, visited) }
          rescue SystemStackError => e
            warn "[BatchTraceProcessor] Stack overflow in array sanitization: #{e.message}"
            ["[STACK_OVERFLOW_ERROR]"]
          end
        when String
          # Truncate very long strings
          value.length > 10_000 ? "#{value[0..9997]}..." : value
        when Time
          value.utc.strftime("%Y-%m-%dT%H:%M:%S.%6N+00:00")
        when Numeric, TrueClass, FalseClass, NilClass
          value
        else
          # Convert unknown objects to strings safely
          begin
            value.to_s
          rescue SystemStackError => e
            warn "[BatchTraceProcessor] Stack overflow in object conversion: #{e.message}"
            "[OBJECT_CONVERSION_ERROR]"
          rescue StandardError => e
            warn "[BatchTraceProcessor] Object conversion error: #{e.message}"
            "[OBJECT_CONVERSION_ERROR]"
          end
        end
      rescue SystemStackError => e
        warn "[BatchTraceProcessor] Stack overflow in value sanitization: #{e.message}"
        "[STACK_OVERFLOW_ERROR]"
      rescue StandardError => e
        warn "[BatchTraceProcessor] Value sanitization error: #{e.message}"
        "[SANITIZATION_ERROR]"
      end

      # Sanitizes events for export
      #
      # @param events [Array] The events to sanitize
      # @return [Array] Sanitized events safe for JSON conversion
      #
      # @api private
      def sanitize_events_for_export(events)
        return [] unless events.is_a?(Array)

        events.map do |event|
          next unless event.is_a?(Hash)

          {
            "name" => event["name"]&.to_s,
            "timestamp" => event["timestamp"],
            "attributes" => deep_sanitize_hash(event["attributes"] || {})
          }
        end.compact
      rescue StandardError => e
        warn "[BatchTraceProcessor] Events sanitization error: #{e.message}"
        []
      end

      # Emergency flush that bypasses normal queueing
      # Used as last resort when normal flush mechanisms fail
      def emergency_flush
        return if @queue.empty?

        log_debug_tracing("[BatchTraceProcessor] Emergency flush: #{@queue.size} spans", queue_size: @queue.size)

        # Take a snapshot and clear queue atomically
        emergency_spans = []
        until @queue.empty?
          span = @queue.shift
          emergency_spans << span if span
        end

        return if emergency_spans.empty?

        # Attempt direct export with retries
        3.times do |attempt|
          @exporter.export(emergency_spans)
          log_debug_tracing("[BatchTraceProcessor] Emergency flush succeeded on attempt #{attempt + 1}", attempt: attempt + 1)
          return
        rescue StandardError => e
          log_debug_tracing("[BatchTraceProcessor] Emergency flush attempt #{attempt + 1} failed: #{e.message}", attempt: attempt + 1, error: e.message)
          sleep(0.1) if attempt < 2
        end

        log_debug_tracing("[BatchTraceProcessor] Emergency flush failed after 3 attempts")
      end

      # Python-style synchronous final export
      # Exports all remaining spans without relying on background thread
      def synchronous_final_export
        # Debug logging now handled by category system

        attempts = 0
        max_attempts = 3

        while !@queue.empty? && attempts < max_attempts
          attempts += 1

          # Drain queue completely
          batch = []
          until @queue.empty?
            span = @queue.shift
            batch << span if span
          end

          next if batch.empty?

          log_debug_tracing("[BatchTraceProcessor] Synchronous export attempt #{attempts}: #{batch.size} spans", attempt: attempts, batch_size: batch.size)

          begin
            # Call the wrapped processor's export method with raw spans
            @exporter.export(batch)
            log_debug_tracing("[BatchTraceProcessor] Synchronous export succeeded", attempt: attempts)
            return # Success, we're done
          rescue StandardError => e
            log_debug_tracing("[BatchTraceProcessor] Synchronous export failed (attempt #{attempts}): #{e.message}", attempt: attempts, error: e.message)

            # On failure, put spans back for next attempt (if not last attempt)
            if attempts < max_attempts
              batch.each { |span| @queue << span }
              sleep(0.1)
            else
              # Last attempt failed, use emergency flush as final fallback
              log_debug_tracing("[BatchTraceProcessor] All synchronous attempts failed, using emergency flush", attempts: attempts)
              @queue.clear # Clear queue to avoid infinite loop
              emergency_spans = batch

              # Emergency direct export attempt
              begin
                @exporter.export(emergency_spans)
                log_debug_tracing("[BatchTraceProcessor] Emergency export succeeded", emergency_spans: emergency_spans.size)
              rescue StandardError => emergency_error
                warn "[BatchTraceProcessor] Final emergency export failed: #{emergency_error.message}"
              end
            end
          end
        end
      end

      # Register exit handlers (reduced scope since we have global atexit)
      def register_exit_handlers
        # Signal handlers for immediate termination
        %w[TERM INT QUIT].each do |signal|
          trap(signal) do
            log_debug_tracing("[BatchTraceProcessor] Received #{signal}, flushing traces...", signal: signal)
            synchronous_final_export
            exit(0)
          end
        rescue ArgumentError
          # Signal not supported on this platform, skip
        end

        # NOTE: Finalizer removed to avoid "finalizer references object to be finalized" warning
        # Cleanup is handled by signal handlers and global atexit registration
      end
    end
  end
end
