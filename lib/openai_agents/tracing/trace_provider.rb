# frozen_string_literal: true

require_relative "spans"
require_relative "batch_processor"
require_relative "openai_processor"

module OpenAIAgents
  module Tracing
    # Global trace provider that manages tracer instances and configuration
    class TraceProvider
      class << self
        attr_writer :instance

        def instance
          @instance ||= new
        end

        # Convenience methods that delegate to instance
        def configure(&block)
          instance.configure(&block)
        end

        def tracer(name = nil)
          instance.tracer(name)
        end

        def add_processor(processor)
          instance.add_processor(processor)
        end
        
        def set_processors(*processors)
          instance.set_processors(*processors)
        end

        def shutdown
          instance.shutdown
        end

        def force_flush
          instance.force_flush
        end

        def disabled?
          instance.disabled?
        end

        def disable!
          instance.disable!
        end

        def enable!
          instance.enable!
        end
      end

      attr_reader :processors, :disabled

      def initialize
        @processors = []
        @tracers = {}
        @disabled = ENV["OPENAI_AGENTS_DISABLE_TRACING"] == "true"
        @shutdown = false
        
        # Set up default processors based on environment
        setup_default_processors unless @disabled
      end

      def configure
        yield self if block_given?
      end

      def tracer(name = nil)
        return NoOpTracer.new if @disabled
        
        name ||= "openai-agents"
        @tracers[name] ||= SpanTracer.new(self)
      end

      def add_processor(processor)
        @processors << processor unless @disabled
      end
      
      def set_processors(*processors)
        unless @disabled
          # Shutdown existing processors
          @processors.each do |processor|
            processor.shutdown if processor.respond_to?(:shutdown)
          rescue StandardError => e
            warn "[TraceProvider] Error shutting down processor: #{e.message}"
          end
          
          # Replace with new processors
          @processors = processors
        end
      end

      def remove_processor(processor)
        @processors.delete(processor)
      end

      def on_span_start(span)
        return if @disabled || @shutdown
        
        @processors.each do |processor|
          processor.on_span_start(span) if processor.respond_to?(:on_span_start)
        rescue StandardError => e
          warn "[TraceProvider] Error in processor.on_span_start: #{e.message}"
        end
      end

      def on_span_end(span)
        return if @disabled || @shutdown
        
        @processors.each do |processor|
          processor.on_span_end(span) if processor.respond_to?(:on_span_end)
        rescue StandardError => e
          warn "[TraceProvider] Error in processor.on_span_end: #{e.message}"
        end
      end

      def shutdown
        return if @shutdown
        
        @shutdown = true
        @processors.each do |processor|
          processor.shutdown if processor.respond_to?(:shutdown)
        rescue StandardError => e
          warn "[TraceProvider] Error shutting down processor: #{e.message}"
        end
      end

      def force_flush
        @processors.each do |processor|
          processor.force_flush if processor.respond_to?(:force_flush)
        rescue StandardError => e
          warn "[TraceProvider] Error flushing processor: #{e.message}"
        end
      end

      def disabled?
        @disabled
      end

      def disable!
        @disabled = true
      end

      def enable!
        @disabled = false
        setup_default_processors if @processors.empty?
      end

      private

      def setup_default_processors
        # Add OpenAI processor if API key is available
        if ENV["OPENAI_API_KEY"]
          puts "[TraceProvider] Setting up OpenAI trace processor" if ENV["OPENAI_AGENTS_TRACE_DEBUG"] == "true"
          batch_processor = BatchTraceProcessor.new(
            OpenAIProcessor.new,
            batch_size: ENV.fetch("OPENAI_AGENTS_TRACE_BATCH_SIZE", 50).to_i,
            flush_interval: ENV.fetch("OPENAI_AGENTS_TRACE_FLUSH_INTERVAL", 5).to_f
          )
          add_processor(batch_processor)
          puts "[TraceProvider] OpenAI trace processor added" if ENV["OPENAI_AGENTS_TRACE_DEBUG"] == "true"
        else
          puts "[TraceProvider] No OPENAI_API_KEY found, skipping OpenAI processor" if ENV["OPENAI_AGENTS_TRACE_DEBUG"] == "true"
        end

        # Add console processor in development
        if ENV["OPENAI_AGENTS_ENVIRONMENT"] == "development" || ENV["OPENAI_AGENTS_TRACE_CONSOLE"] == "true"
          add_processor(ConsoleSpanProcessor.new)
        end
      end
    end

    # No-op tracer for when tracing is disabled
    class NoOpTracer
      def span(name, type: nil, **attributes)
        yield NoOpSpan.new if block_given?
        NoOpSpan.new
      end

      def agent_span(name, **attributes, &block)
        span(name, type: :agent, **attributes, &block)
      end

      def tool_span(name, **attributes, &block)
        span(name, type: :tool, **attributes, &block)
      end

      def llm_span(model, **attributes, &block)
        span("llm_call", type: :llm, model: model, **attributes, &block)
      end

      def handoff_span(from_agent, to_agent, **attributes, &block)
        span("handoff", type: :handoff, from: from_agent, to: to_agent, **attributes, &block)
      end
    end

    # No-op span for when tracing is disabled
    class NoOpSpan
      def set_attribute(key, value); end
      def set_attributes(attributes); end
      def add_event(name, attributes = {}); end
      def set_status(status, message = nil); end
      def record_exception(exception); end
      def end_span; end
    end
  end
end