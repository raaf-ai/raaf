# frozen_string_literal: true

module RAAF
  module Tracing
    # NoOpTracer provides a zero-overhead tracer implementation for disabled tracing.
    #
    # This tracer implements the same interface as SpanTracer but performs no actual
    # tracing operations. It's designed to have absolutely minimal performance impact
    # when tracing is disabled, allowing applications to call tracing methods without
    # any overhead.
    #
    # ## Design Philosophy
    #
    # The NoOpTracer follows the Null Object pattern, providing a "do nothing"
    # implementation that maintains interface compatibility. This allows RAAF
    # components to call tracing methods unconditionally without performance
    # penalties when tracing is disabled.
    #
    # ## Key Features
    #
    # - **Zero performance overhead** - All methods are no-ops that return immediately
    # - **Full interface compatibility** - Implements all SpanTracer public methods
    # - **Memory efficient** - No state accumulation or object creation
    # - **Thread safe** - Stateless design ensures thread safety
    # - **Graceful degradation** - Applications work identically with/without tracing
    #
    # ## Usage
    #
    # NoOpTracer is typically used automatically by TracingRegistry when no
    # tracer is configured, but can also be used explicitly to disable tracing:
    #
    # ```ruby
    # # Explicit usage
    # noop_tracer = RAAF::Tracing::NoOpTracer.new
    # runner = RAAF::Runner.new(agent: agent, tracer: noop_tracer)
    # runner.run("Hello") # No tracing overhead
    #
    # # Automatic usage via TracingRegistry
    # # When no tracer configured, current_tracer returns NoOpTracer
    # tracer = TracingRegistry.current_tracer # => NoOpTracer instance
    # ```
    #
    # @example Performance comparison
    #   # With real tracer - creates spans, processes data, sends to processors
    #   real_tracer = SpanTracer.new
    #   real_tracer.agent_span("test") { expensive_work() }
    #
    #   # With NoOpTracer - zero overhead, same interface
    #   noop_tracer = NoOpTracer.new
    #   noop_tracer.agent_span("test") { expensive_work() } # Just calls block
    #
    class NoOpTracer
      # Initialize a new NoOpTracer instance.
      #
      # @return [NoOpTracer] New tracer instance
      def initialize
        # No initialization needed for no-op implementation
      end

      # Create an agent span (no-op implementation).
      #
      # @param span_name [String] Name of the span (ignored)
      # @param metadata [Hash] Span metadata (ignored)
      # @yield Block to execute
      # @return [Object] Result of block execution
      def agent_span(span_name, metadata = {}, &block)
        # Just execute the block without creating any span
        block.call if block_given?
      end

      # Create a tool span (no-op implementation).
      #
      # @param span_name [String] Name of the span (ignored)
      # @param metadata [Hash] Span metadata (ignored)
      # @yield Block to execute
      # @return [Object] Result of block execution
      def tool_span(span_name, metadata = {}, &block)
        # Just execute the block without creating any span
        block.call if block_given?
      end

      # Create a custom span (no-op implementation).
      #
      # @param span_name [String] Name of the span (ignored)
      # @param metadata [Hash] Span metadata (ignored)
      # @yield [NoOpSpan] Block to execute with span
      # @return [Object] Result of block execution
      def custom_span(span_name, metadata = {}, &block)
        if block_given?
          # Provide a NoOpSpan if block expects span parameter
          if block.arity > 0
            block.call(NoOpSpan.new)
          else
            block.call
          end
        end
      end

      # Create a pipeline span (no-op implementation).
      #
      # @param span_name [String] Name of the span (ignored)
      # @param metadata [Hash] Span metadata (ignored)
      # @yield Block to execute
      # @return [Object] Result of block execution
      def pipeline_span(span_name, metadata = {}, &block)
        # Just execute the block without creating any span
        block.call if block_given?
      end

      # Create a response span (no-op implementation).
      #
      # @param span_name [String] Name of the span (ignored)
      # @param metadata [Hash] Span metadata (ignored)
      # @yield Block to execute
      # @return [Object] Result of block execution
      def response_span(span_name, metadata = {}, &block)
        # Just execute the block without creating any span
        block.call if block_given?
      end

      # Add a processor (no-op implementation).
      #
      # @param processor [Object] Processor to add (ignored)
      # @return [void]
      def add_processor(processor)
        # Do nothing - no processors in no-op tracer
      end

      # Get processors (no-op implementation).
      #
      # @return [Array] Empty array
      def processors
        @processors ||= []
      end

      # Force flush (no-op implementation).
      #
      # @return [void]
      def force_flush
        # Nothing to flush
      end

      # Shutdown (no-op implementation).
      #
      # @return [void]
      def shutdown
        # Nothing to shut down
      end

      # Check if tracer is disabled.
      #
      # @return [Boolean] Always true for NoOpTracer
      def disabled?
        true
      end

      # Handle any undefined methods by doing nothing.
      #
      # This ensures that even if new methods are added to the real tracer
      # interface, the NoOpTracer will continue to work without errors.
      #
      # @param method_name [Symbol] Name of called method
      # @param args [Array] Method arguments (ignored)
      # @param block [Proc] Block argument
      # @return [Object] Result of block execution if block given, nil otherwise
      def method_missing(method_name, *args, &block)
        # If a block is given, execute it (maintaining expected behavior)
        if block_given?
          if block.arity > 0
            # If block expects arguments, provide a NoOpSpan
            block.call(NoOpSpan.new)
          else
            block.call
          end
        else
          # Return self for method chaining compatibility
          self
        end
      end

      # Indicate that this object responds to any method.
      #
      # @param method_name [Symbol] Method to check
      # @param include_private [Boolean] Whether to include private methods
      # @return [Boolean] Always true
      def respond_to_missing?(method_name, include_private = false)
        true
      end

      # String representation for debugging.
      #
      # @return [String] Human-readable representation
      def to_s
        "#<RAAF::Tracing::NoOpTracer:#{object_id} (disabled)>"
      end

      # Inspection string for debugging.
      #
      # @return [String] Detailed representation
      def inspect
        to_s
      end
    end

    # NoOpSpan provides a zero-overhead span implementation for disabled tracing.
    #
    # This class is used by NoOpTracer when code expects to interact with
    # span objects (e.g., setting attributes, adding events). It implements
    # the span interface but performs no operations.
    #
    class NoOpSpan
      # Initialize a new NoOpSpan instance.
      #
      # @return [NoOpSpan] New span instance
      def initialize
        # No initialization needed for no-op implementation
      end

      # Set span attribute (no-op implementation).
      #
      # @param key [String] Attribute key (ignored)
      # @param value [Object] Attribute value (ignored)
      # @return [NoOpSpan] Self for chaining
      def set_attribute(key, value)
        self
      end

      # Add span event (no-op implementation).
      #
      # @param name [String] Event name (ignored)
      # @param attributes [Hash] Event attributes (ignored)
      # @return [NoOpSpan] Self for chaining
      def add_event(name, attributes = {})
        self
      end

      # Set span status (no-op implementation).
      #
      # @param status [Symbol] Status (ignored)
      # @return [NoOpSpan] Self for chaining
      def set_status(status)
        self
      end

      # Record span exception (no-op implementation).
      #
      # @param exception [Exception] Exception to record (ignored)
      # @return [NoOpSpan] Self for chaining
      def record_exception(exception)
        self
      end

      # Finish the span (no-op implementation).
      #
      # @return [void]
      def finish
        # Nothing to finish
      end

      # Check if span is finished.
      #
      # @return [Boolean] Always true for no-op spans
      def finished?
        true
      end

      # Get span attributes.
      #
      # @return [Hash] Empty hash
      def attributes
        @attributes ||= {}
      end

      # Get span events.
      #
      # @return [Array] Empty array
      def events
        @events ||= []
      end

      # Handle any undefined methods by doing nothing.
      #
      # @param method_name [Symbol] Name of called method
      # @param args [Array] Method arguments (ignored)
      # @param block [Proc] Block argument
      # @return [NoOpSpan] Self for chaining
      def method_missing(method_name, *args, &block)
        # Execute block if provided
        block.call if block_given?
        # Return self for method chaining
        self
      end

      # Indicate that this object responds to any method.
      #
      # @param method_name [Symbol] Method to check
      # @param include_private [Boolean] Whether to include private methods
      # @return [Boolean] Always true
      def respond_to_missing?(method_name, include_private = false)
        true
      end

      # String representation for debugging.
      #
      # @return [String] Human-readable representation
      def to_s
        "#<RAAF::Tracing::NoOpSpan:#{object_id} (disabled)>"
      end

      # Inspection string for debugging.
      #
      # @return [String] Detailed representation
      def inspect
        to_s
      end
    end
  end
end