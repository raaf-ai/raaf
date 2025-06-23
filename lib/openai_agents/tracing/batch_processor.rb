# frozen_string_literal: true

require "concurrent"

module OpenAIAgents
  module Tracing
    # Batches spans and sends them to a backend processor in the background
    class BatchTraceProcessor
      DEFAULT_BATCH_SIZE = 50
      DEFAULT_FLUSH_INTERVAL = 5.0 # seconds
      DEFAULT_MAX_QUEUE_SIZE = 2048

      attr_reader :batch_size, :flush_interval

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

      def on_span_start(span)
        # BatchProcessor only cares about completed spans
      end

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

      def force_flush
        @force_flush.set
        # Wait a bit for flush to complete
        sleep(0.1) until @queue.empty? || @shutdown.true?
      end

      def shutdown
        return if @shutdown.true?
        
        @shutdown.make_true
        @force_flush.set # Wake up worker thread
        
        # Wait for worker thread to finish
        @worker_thread.join(5.0) # 5 second timeout
        
        # Process any remaining spans
        export_batch(@queue.clear) unless @queue.empty?
        
        # Shutdown exporter
        @exporter.shutdown if @exporter.respond_to?(:shutdown)
      end

      private

      def run_worker
        debug = ENV["OPENAI_AGENTS_TRACE_DEBUG"] == "true"
        puts "[BatchTraceProcessor] Worker thread started (flush interval: #{@flush_interval}s)" if debug
        
        loop do
          # Wait for flush interval or force flush signal
          @force_flush.wait(@flush_interval)
          @force_flush.reset
          
          break if @shutdown.true?
          
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
        end
      rescue StandardError => e
        warn "[BatchTraceProcessor] Worker thread error: #{e.message}"
        warn e.backtrace.first(5).join("\n") if debug
      end

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