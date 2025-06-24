# frozen_string_literal: true

require "concurrent"

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
        
        # Start background thread for processing
        @worker_thread = Thread.new { run_worker }
        @worker_thread.name = "OpenAIAgents::BatchTraceProcessor"
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
        
        debug = ENV["OPENAI_AGENTS_TRACE_DEBUG"] == "true"
        if debug
          puts "[BatchTraceProcessor] Added span '#{span.name}' to queue (#{@queue.size}/#{@batch_size})"
        end
        
        # Trigger flush if we've reached batch size
        if @queue.size >= @batch_size
          puts "[BatchTraceProcessor] Batch size reached, triggering flush" if debug
          @force_flush.set
        end
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
        @force_flush.set
        # Wait a bit for flush to complete
        sleep(0.1) until @queue.empty? || @shutdown.true?
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
        
        @shutdown.make_true
        @force_flush.set # Wake up worker thread
        
        # Wait for worker thread to finish
        @worker_thread.join(5.0) # 5 second timeout
        
        # Process any remaining spans
        unless @queue.empty?
          remaining_spans = @queue.to_a
          @queue.clear
          export_batch(remaining_spans)
        end
        
        # Shutdown exporter
        @exporter.shutdown if @exporter.respond_to?(:shutdown)
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
        debug = ENV["OPENAI_AGENTS_TRACE_DEBUG"] == "true"
        puts "[BatchTraceProcessor] Worker thread started (flush interval: #{@flush_interval}s)" if debug
        
        loop do
          # Wait for flush interval or force flush signal
          @force_flush.wait(@flush_interval)
          @force_flush.reset
          
          # Export current batch
          batch = []
          while batch.size < @batch_size && !@queue.empty?
            span = @queue.shift
            batch << span if span
          end
          
          if debug && !batch.empty?
            puts "[BatchTraceProcessor] Flushing batch of #{batch.size} spans (#{@queue.size} remaining in queue)"
          end
          
          export_batch(batch) unless batch.empty?
          
          # Break after processing if shutdown is requested
          break if @shutdown.true?
        end
      rescue StandardError => e
        warn "[BatchTraceProcessor] Worker thread error: #{e.message}"
        warn e.backtrace.first(5).join("\n") if debug
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
        
        debug = ENV["OPENAI_AGENTS_TRACE_DEBUG"] == "true"
        
        begin
          puts "[BatchTraceProcessor] Exporting #{batch.size} spans to #{@exporter.class.name}" if debug
          @exporter.export(batch)
          puts "[BatchTraceProcessor] Export completed successfully" if debug
        rescue StandardError => e
          warn "[BatchTraceProcessor] Export error: #{e.message}"
          warn e.backtrace.first(5).join("\n") if debug
        end
      end
    end
  end
end