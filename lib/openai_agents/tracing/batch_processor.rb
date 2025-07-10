# frozen_string_literal: true

require "concurrent"
require_relative "../logging"

module OpenAIAgents
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
        @worker_thread.name = "OpenAIAgents::BatchTraceProcessor"

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
      #
      # @param batch [Array<Span>] The spans to export
      # @return [void]
      #
      # @api private
      def export_batch(batch)
        return if batch.empty?

        # Debug logging now handled by category system

        begin
          log_debug_tracing("[BatchTraceProcessor] Exporting #{batch.size} spans to #{@exporter.class.name}",
                            batch_size: batch.size, exporter: @exporter.class.name)
          @exporter.export(batch)
          log_debug_tracing("[BatchTraceProcessor] Export completed successfully", batch_size: batch.size)
        rescue StandardError => e
          warn "[BatchTraceProcessor] Export error: #{e.message}"
          log_debug_tracing("Export error backtrace", error: e.message, backtrace: e.backtrace.first(5).join("\n"))
        end

        @last_flush_time.set(Time.now)
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
