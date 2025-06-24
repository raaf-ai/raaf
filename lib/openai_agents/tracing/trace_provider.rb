# frozen_string_literal: true

require_relative "spans"
require_relative "batch_processor"
require_relative "openai_processor"

module OpenAIAgents
  module Tracing
    # Global singleton that manages tracing configuration and processors
    #
    # TraceProvider is the central coordination point for the tracing system.
    # It manages:
    # - Global tracing configuration
    # - Tracer instances
    # - Span processors
    # - Lifecycle management (flush, shutdown)
    #
    # ## Architecture
    #
    # The provider follows a singleton pattern with class-level delegation
    # to an instance. This allows both class and instance method usage:
    #
    # ```ruby
    # # Class methods (recommended)
    # TraceProvider.tracer
    # TraceProvider.add_processor(processor)
    #
    # # Instance methods
    # provider = TraceProvider.instance
    # provider.tracer
    # ```
    #
    # ## Configuration
    #
    # By default, TraceProvider sets up an OpenAI processor if an API key
    # is available. Additional processors can be added or replaced.
    #
    # @example Configure custom processors
    #   TraceProvider.configure do |provider|
    #     provider.add_processor(MyCustomProcessor.new)
    #   end
    #
    # @example Replace all processors
    #   TraceProvider.set_processors(
    #     FileProcessor.new("traces.log"),
    #     CustomBackendProcessor.new
    #   )
    class TraceProvider
      class << self
        # @api private
        attr_writer :instance

        # Returns the global TraceProvider instance
        #
        # @return [TraceProvider] The singleton instance
        def instance
          @instance ||= new
        end

        # Configures the trace provider
        #
        # @yield [provider] Configuration block
        # @yieldparam provider [TraceProvider] The provider instance
        # @return [void]
        def configure(&block)
          instance.configure(&block)
        end

        # Returns a tracer instance
        #
        # @param name [String, nil] Optional tracer name
        # @return [SpanTracer, NoOpTracer] The tracer instance
        def tracer(name = nil)
          instance.tracer(name)
        end

        # Adds a processor to receive span events
        #
        # @param processor [Object] Processor implementing span callbacks
        # @return [void]
        def add_processor(processor)
          instance.add_processor(processor)
        end
        
        # Replaces all processors with the provided ones
        #
        # @param processors [Array<Object>] New processors
        # @return [void]
        def set_processors(*processors)
          instance.set_processors(*processors)
        end

        # Shuts down the trace provider
        #
        # @return [void]
        def shutdown
          instance.shutdown
        end

        # Forces all processors to flush buffered data
        #
        # @return [void]
        def force_flush
          instance.force_flush
        end

        # Checks if tracing is disabled
        #
        # @return [Boolean] true if disabled
        def disabled?
          instance.disabled?
        end

        # Disables tracing globally
        #
        # @return [void]
        def disable!
          instance.disable!
        end

        # Enables tracing globally
        #
        # @return [void]
        def enable!
          instance.enable!
        end
      end

      # @return [Array<Object>] Active span processors
      attr_reader :processors
      
      # @return [Boolean] Whether tracing is disabled
      attr_reader :disabled

      # Creates a new TraceProvider instance
      #
      # Automatically sets up default processors based on environment
      # configuration unless tracing is disabled.
      def initialize
        @processors = []
        @tracers = {}
        @disabled = ENV["OPENAI_AGENTS_DISABLE_TRACING"] == "true"
        @shutdown = false
        
        # Set up default processors based on environment
        setup_default_processors unless @disabled
      end

      # Configures the trace provider
      #
      # @yield [self] Configuration block
      # @yieldparam self [TraceProvider] The provider instance
      # @return [void]
      #
      # @example
      #   provider.configure do |p|
      #     p.add_processor(ConsoleSpanProcessor.new)
      #     p.disable! if ENV["NO_TRACING"]
      #   end
      def configure
        yield self if block_given?
      end

      # Returns or creates a tracer instance
      #
      # Tracers are cached by name to ensure consistent behavior within
      # an application. Returns a NoOpTracer when tracing is disabled.
      #
      # @param name [String, nil] Optional tracer name (defaults to "openai-agents")
      # @return [SpanTracer, NoOpTracer] The tracer instance
      def tracer(name = nil)
        return NoOpTracer.new if @disabled
        
        name ||= "openai-agents"
        @tracers[name] ||= SpanTracer.new(self)
      end

      # Adds a processor to receive span events
      #
      # Processors are notified when spans start and end. Multiple processors
      # can be active simultaneously.
      #
      # @param processor [Object] Processor implementing:
      #   - on_span_start(span) - Called when spans start
      #   - on_span_end(span) - Called when spans end
      #   - force_flush (optional) - Flush buffered data
      #   - shutdown (optional) - Clean up resources
      # @return [void]
      def add_processor(processor)
        @processors << processor unless @disabled
      end
      
      # Replaces all processors with new ones
      #
      # This method shuts down existing processors before replacing them.
      # Use this when you want complete control over where traces are sent.
      #
      # @param processors [Array<Object>] New processors to use
      # @return [void]
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

      # Removes a specific processor
      #
      # @param processor [Object] The processor to remove
      # @return [Object, nil] The removed processor or nil if not found
      #
      # @example
      #   console_processor = ConsoleSpanProcessor.new
      #   provider.add_processor(console_processor)
      #   # Later...
      #   provider.remove_processor(console_processor)
      def remove_processor(processor)
        @processors.delete(processor)
      end

      # Notifies all processors that a span has started
      #
      # This method is called internally by SpanTracer when a new span
      # begins. It safely invokes on_span_start on all registered processors,
      # catching and logging any errors to prevent processor failures from
      # disrupting tracing.
      #
      # @param span [Span] The span that has started
      # @return [void]
      #
      # @api private
      def on_span_start(span)
        return if @disabled || @shutdown
        
        @processors.each do |processor|
          processor.on_span_start(span) if processor.respond_to?(:on_span_start)
        rescue StandardError => e
          warn "[TraceProvider] Error in processor.on_span_start: #{e.message}"
        end
      end

      # Notifies all processors that a span has ended
      #
      # This method is called internally by SpanTracer when a span
      # finishes. It safely invokes on_span_end on all registered processors,
      # catching and logging any errors.
      #
      # @param span [Span] The span that has ended
      # @return [void]
      #
      # @api private
      def on_span_end(span)
        return if @disabled || @shutdown
        
        @processors.each do |processor|
          processor.on_span_end(span) if processor.respond_to?(:on_span_end)
        rescue StandardError => e
          warn "[TraceProvider] Error in processor.on_span_end: #{e.message}"
        end
      end

      # Shuts down the trace provider and all processors
      #
      # This method performs a graceful shutdown:
      # 1. Prevents new spans from being processed
      # 2. Calls shutdown on all processors that support it
      # 3. Marks the provider as shut down
      #
      # Once shut down, the provider cannot be restarted. Create a new
      # instance if you need to resume tracing.
      #
      # @return [void]
      #
      # @example
      #   # At application exit
      #   at_exit do
      #     TraceProvider.shutdown
      #   end
      def shutdown
        return if @shutdown
        
        @shutdown = true
        @processors.each do |processor|
          processor.shutdown if processor.respond_to?(:shutdown)
        rescue StandardError => e
          warn "[TraceProvider] Error shutting down processor: #{e.message}"
        end
      end

      # Forces all processors to flush buffered data
      #
      # This method requests all processors to immediately export any
      # buffered span data. Useful for ensuring data is sent before
      # critical operations or application shutdown.
      #
      # Note: This is a synchronous operation that may block while
      # processors export data.
      #
      # @return [void]
      #
      # @example Flush before shutdown
      #   provider.force_flush
      #   sleep(1)  # Give time for network requests
      #   provider.shutdown
      def force_flush
        @processors.each do |processor|
          processor.force_flush if processor.respond_to?(:force_flush)
        rescue StandardError => e
          warn "[TraceProvider] Error flushing processor: #{e.message}"
        end
      end

      # Checks if tracing is disabled
      #
      # @return [Boolean] true if tracing is disabled, false otherwise
      #
      # @example
      #   if provider.disabled?
      #     puts "Tracing is disabled"
      #   end
      def disabled?
        @disabled
      end

      # Disables tracing
      #
      # When disabled, no new spans will be processed and tracers will
      # return NoOpTracer instances. Existing processors are retained
      # but won't receive new span events.
      #
      # @return [void]
      #
      # @example Temporarily disable tracing
      #   provider.disable!
      #   # Perform operations without tracing
      #   provider.enable!
      def disable!
        @disabled = true
      end

      # Enables tracing
      #
      # Re-enables tracing after it has been disabled. If no processors
      # are configured, default processors will be automatically set up
      # based on environment configuration.
      #
      # @return [void]
      #
      # @example Re-enable tracing
      #   provider.enable!
      #   # Tracing is now active again
      def enable!
        @disabled = false
        setup_default_processors if @processors.empty?
      end

      private

      # Sets up default processors based on environment configuration
      #
      # This method is called automatically during initialization and when
      # re-enabling tracing with no processors. It configures:
      #
      # 1. OpenAI processor (if OPENAI_API_KEY is set) with batching
      # 2. Console processor (in development or if explicitly enabled)
      #
      # Environment variables:
      # - OPENAI_API_KEY: Enables OpenAI processor
      # - OPENAI_AGENTS_TRACE_BATCH_SIZE: Batch size (default: 50)
      # - OPENAI_AGENTS_TRACE_FLUSH_INTERVAL: Flush interval in seconds (default: 5)
      # - OPENAI_AGENTS_ENVIRONMENT: Set to "development" for console output
      # - OPENAI_AGENTS_TRACE_CONSOLE: Set to "true" to force console output
      # - OPENAI_AGENTS_TRACE_DEBUG: Set to "true" for debug logging
      #
      # @return [void]
      #
      # @api private
      def setup_default_processors
        # Add OpenAI processor if API key is available
        if ENV["OPENAI_API_KEY"]
          puts "[TraceProvider] Setting up OpenAI trace processor" if ENV["OPENAI_AGENTS_TRACE_DEBUG"] == "true"
          batch_processor = BatchTraceProcessor.new(
            OpenAIProcessor.new,
            batch_size: ENV.fetch("OPENAI_AGENTS_TRACE_BATCH_SIZE", 10).to_i,
            flush_interval: ENV.fetch("OPENAI_AGENTS_TRACE_FLUSH_INTERVAL", 2.0).to_f
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

    # No-operation tracer returned when tracing is disabled
    #
    # NoOpTracer implements the same interface as SpanTracer but performs
    # no actual tracing operations. This allows code to work transparently
    # whether tracing is enabled or disabled, without requiring conditional
    # checks throughout the codebase.
    #
    # All methods return quickly with minimal overhead, making the disabled
    # state very efficient.
    #
    # @example Usage is identical to SpanTracer
    #   tracer = TraceProvider.tracer  # Returns NoOpTracer when disabled
    #   
    #   tracer.span("operation") do |span|
    #     span.set_attribute("key", "value")  # No-op
    #     # Your code runs normally
    #   end
    #
    # @api private
    class NoOpTracer
      # Creates a no-op span that performs no tracing
      #
      # @param name [String] Span name (ignored)
      # @param type [Symbol, nil] Span type (ignored)
      # @param attributes [Hash] Span attributes (ignored)
      # @yield [span] Optional block to execute
      # @yieldparam span [NoOpSpan] A no-op span instance
      # @return [NoOpSpan] A no-op span
      def span(name, type: nil, **attributes)
        yield NoOpSpan.new if block_given?
        NoOpSpan.new
      end

      # Creates a no-op agent span
      #
      # @param name [String] Agent name (ignored)
      # @param attributes [Hash] Span attributes (ignored)
      # @yield [span] Optional block to execute
      # @return [NoOpSpan] A no-op span
      def agent_span(name, **attributes, &block)
        span(name, type: :agent, **attributes, &block)
      end

      # Creates a no-op tool span
      #
      # @param name [String] Tool name (ignored)
      # @param attributes [Hash] Span attributes (ignored)
      # @yield [span] Optional block to execute
      # @return [NoOpSpan] A no-op span
      def tool_span(name, **attributes, &block)
        span(name, type: :tool, **attributes, &block)
      end

      # Creates a no-op LLM span
      #
      # @param model [String] Model name (ignored)
      # @param attributes [Hash] Span attributes (ignored)
      # @yield [span] Optional block to execute
      # @return [NoOpSpan] A no-op span
      def llm_span(model, **attributes, &block)
        span("llm_call", type: :llm, model: model, **attributes, &block)
      end

      # Creates a no-op handoff span
      #
      # @param from_agent [String] Source agent (ignored)
      # @param to_agent [String] Target agent (ignored)
      # @param attributes [Hash] Span attributes (ignored)
      # @yield [span] Optional block to execute
      # @return [NoOpSpan] A no-op span
      def handoff_span(from_agent, to_agent, **attributes, &block)
        span("handoff", type: :handoff, from: from_agent, to: to_agent, **attributes, &block)
      end
    end

    # No-operation span returned by NoOpTracer
    #
    # NoOpSpan implements the same interface as Span but performs no
    # actual operations. This ensures code can interact with spans
    # uniformly regardless of whether tracing is enabled.
    #
    # @api private
    class NoOpSpan
      # Sets an attribute (no-op)
      # @param key [String, Symbol] Attribute key (ignored)
      # @param value [Object] Attribute value (ignored)
      # @return [void]
      def set_attribute(key, value); end
      
      # Sets multiple attributes (no-op)
      # @param attributes [Hash] Attributes to set (ignored)
      # @return [void]
      def set_attributes(attributes); end
      
      # Adds an event (no-op)
      # @param name [String] Event name (ignored)
      # @param attributes [Hash] Event attributes (ignored)
      # @return [void]
      def add_event(name, attributes = {}); end
      
      # Sets span status (no-op)
      # @param status [Symbol] Status code (ignored)
      # @param message [String, nil] Status message (ignored)
      # @return [void]
      def set_status(status, message = nil); end
      
      # Records an exception (no-op)
      # @param exception [Exception] Exception to record (ignored)
      # @return [void]
      def record_exception(exception); end
      
      # Ends the span (no-op)
      # @return [void]
      def end_span; end
    end
  end
end