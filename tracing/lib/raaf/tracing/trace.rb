# frozen_string_literal: true

require "securerandom"

module RAAF
  module Tracing
    # Thread-local context management for traces and spans
    #
    # The Context class provides thread-safe storage for the current trace
    # and span, enabling proper nesting and association of operations within
    # a trace. This is essential for maintaining trace context across
    # method calls and ensuring spans are properly linked.
    #
    # ## Thread Safety
    #
    # Each thread maintains its own trace/span context, allowing concurrent
    # operations to maintain separate trace hierarchies without interference.
    #
    # @example Accessing current context
    #   current_trace = Context.current_trace
    #   current_span = Context.current_span
    #
    # @api private
    class Context
      # Key for storing current trace in thread-local storage
      TRACE_KEY = :openai_agents_current_trace

      # Key for storing current span in thread-local storage
      SPAN_KEY = :openai_agents_current_span

      class << self
        # Returns the current trace for this thread
        #
        # @return [Trace, nil] The current trace or nil if not in a trace context
        def current_trace
          Thread.current[TRACE_KEY]
        end

        # Sets the current trace for this thread
        #
        # @param trace [Trace, nil] The trace to set as current
        # @return [Trace, nil] The trace that was set
        def current_trace=(trace)
          Thread.current[TRACE_KEY] = trace
        end

        # Returns the current span for this thread
        #
        # @return [Span, nil] The current span or nil if not in a span context
        def current_span
          Thread.current[SPAN_KEY]
        end

        # Sets the current span for this thread
        #
        # @param span [Span, nil] The span to set as current
        # @return [Span, nil] The span that was set
        def current_span=(span)
          Thread.current[SPAN_KEY] = span
        end

        # Clears all context for the current thread
        #
        # This removes both trace and span context, typically called
        # during cleanup or thread termination.
        #
        # @return [void]
        def clear
          Thread.current[TRACE_KEY] = nil
          Thread.current[SPAN_KEY] = nil
        end
      end
    end

    # High-level container for grouping related spans in a workflow
    #
    # A Trace represents a complete end-to-end workflow execution, containing
    # multiple spans that represent individual operations. Traces provide:
    #
    # - Logical grouping of related operations
    # - Workflow identification and naming
    # - Metadata and context propagation
    # - Automatic span association
    #
    # ## Trace Lifecycle
    #
    # 1. **Creation**: Trace is initialized with workflow name and options
    # 2. **Start**: Trace context is established and root span created
    # 3. **Execution**: Operations create spans within the trace context
    # 4. **Finish**: Trace is finalized and context is cleaned up
    #
    # ## Context Management
    #
    # Traces use thread-local storage to maintain context, ensuring all
    # operations within the trace are properly associated without requiring
    # explicit trace passing.
    #
    # @example Using trace as a context manager
    #   Tracing.trace("Order Processing") do |trace|
    #     # All operations here are part of this trace
    #     process_order(order_id)
    #     send_confirmation_email(order_id)
    #   end
    #
    # @example Manual trace management
    #   trace = Trace.new("Data Pipeline",
    #     group_id: "batch_123",
    #     metadata: { source: "api", version: "2.0" }
    #   )
    #   trace.start(mark_as_current: true)
    #   begin
    #     process_data_batch()
    #   ensure
    #     trace.finish(reset_current: true)
    #   end
    #
    # @example Checking trace status
    #   if trace.active?
    #     # Trace is currently running
    #   end
    class Trace
      # @return [String] Unique identifier for this trace
      attr_reader :trace_id

      # @return [String] Human-readable workflow name
      attr_reader :workflow_name

      # @return [String, nil] Optional group identifier for linking related traces
      attr_reader :group_id

      # @return [Hash] Custom metadata attached to the trace
      attr_reader :metadata

      # @return [Time, nil] When the trace started
      attr_reader :started_at

      # @return [Time, nil] When the trace ended
      attr_reader :ended_at

      # @return [Boolean] Whether this trace is disabled
      attr_accessor :disabled

      # Creates a new trace instance
      #
      # @param workflow_name [String] Name of the workflow this trace represents
      # @param trace_id [String, nil] Custom trace ID. Must match format
      #   `trace_<32_alphanumeric>`. Auto-generated if not provided.
      # @param group_id [String, nil] Optional group ID for linking related traces
      # @param metadata [Hash, nil] Custom metadata to attach to the trace
      # @param disabled [Boolean] Whether this trace should be disabled
      #
      # @raise [ArgumentError] If trace_id is provided but doesn't match required format
      def initialize(workflow_name, trace_id: nil, group_id: nil, metadata: nil, disabled: false)
        @workflow_name = workflow_name
        @trace_id = trace_id || generate_trace_id
        @group_id = group_id
        @metadata = metadata || {}
        @disabled = disabled
        @started = false
        @finished = false
        @spans = []
        @tracer = nil

        validate_trace_id! if trace_id
      end

      # Starts the trace and establishes trace context
      #
      # This method:
      # - Marks the trace as started
      # - Records the start time
      # - Sets up thread-local context (if requested)
      # - Creates a root span for the trace
      #
      # @param mark_as_current [Boolean] Whether to set this trace as the
      #   current trace in thread-local context. Default: true
      #
      # @return [Trace] Returns self for method chaining
      #
      # @example Start a trace
      #   trace = Trace.new("Data Processing")
      #   trace.start
      #   # Perform operations
      #   trace.finish
      def start(mark_as_current: true)
        return self if @started || @disabled

        @started = true
        @started_at = Time.now.utc

        # Set as current trace
        if mark_as_current
          @previous_trace = Context.current_trace
          Context.current_trace = self
        end

        # Get or create tracer
        @tracer = TraceProvider.instance.tracer

        # Create root span for the trace
        if @tracer && !@tracer.is_a?(NoOpTracer)
          @root_span = @tracer.start_span(
            "trace.#{@workflow_name}",
            kind: :trace,
            "trace.id" => @trace_id,
            "trace.workflow_name" => @workflow_name,
            "trace.group_id" => @group_id,
            "trace.metadata" => @metadata
          )
        end

        self
      end

      # Finishes the trace and cleans up context
      #
      # This method:
      # - Marks the trace as finished
      # - Records the end time
      # - Finishes the root span
      # - Restores previous trace context (if requested)
      # - Notifies processors of trace completion
      #
      # @param reset_current [Boolean] Whether to restore the previous trace
      #   context. Default: true
      #
      # @return [Trace] Returns self for method chaining
      #
      # @example Finish a trace
      #   trace.finish
      #
      # @example Keep trace as current
      #   trace.finish(reset_current: false)
      def finish(reset_current: true)
        return self if @finished || @disabled || !@started

        @finished = true
        @ended_at = Time.now.utc

        # Finish root span
        @tracer&.finish_span(@root_span) if @root_span

        # Reset current trace
        Context.current_trace = @previous_trace if reset_current

        # Notify trace provider
        notify_trace_complete

        self
      end

      # Creates and manages a trace with automatic cleanup
      #
      # This is the recommended way to create traces as it ensures proper
      # cleanup even if exceptions occur. When called with a block, the trace
      # is automatically started before the block and finished after.
      #
      # @param workflow_name [String] Name of the workflow
      # @param options [Hash] Options passed to Trace.new
      # @yield [trace] Block to execute within trace context
      # @yieldparam trace [Trace] The created trace
      # @return [Trace] The trace object
      #
      # @example With block (recommended)
      #   Trace.create("Order Processing") do |trace|
      #     process_order()
      #   end
      #
      # @example Without block (manual management)
      #   trace = Trace.create("Order Processing")
      #   trace.start
      #   # ... operations ...
      #   trace.finish
      def self.create(workflow_name, **)
        trace = new(workflow_name, **)

        if block_given?
          trace.start
          begin
            yield trace
          ensure
            trace.finish
          end
        else
          trace
        end
      end

      # Adds a span to this trace's span collection
      #
      # This method is typically called internally by the tracing system
      # when spans are created within this trace's context.
      #
      # @param span [Span] The span to add
      # @return [void]
      #
      # @api private
      def add_span(span)
        @spans << span unless @disabled
      end

      # Checks if the trace is currently active
      #
      # A trace is active if it has been started but not yet finished.
      #
      # @return [Boolean] true if trace is active, false otherwise
      #
      # @example
      #   if trace.active?
      #     # Trace is running
      #   end
      def active?
        @started && !@finished
      end

      private

      # Generates a valid trace ID
      #
      # @return [String] A trace ID in format `trace_<32_hex>`
      # @api private
      def generate_trace_id
        "trace_#{SecureRandom.hex(16)}"
      end

      # Validates the format of a custom trace ID
      #
      # @raise [ArgumentError] If trace_id doesn't match required format
      # @api private
      def validate_trace_id!
        return if @trace_id.match?(/\Atrace_[a-fA-F0-9]{32}\z/)

        raise ArgumentError,
              "Invalid trace_id format. Expected 'trace_<32_hex>', got '#{@trace_id}'"
      end

      # Notifies processors that the trace has completed
      #
      # @api private
      def notify_trace_complete
        # This is where we would notify processors about trace completion
        # For now, the spans handle their own notification
      end
    end

    # Creates a trace with automatic lifecycle management
    #
    # This is a convenience method that creates a trace and ensures it's
    # properly started and finished, even if exceptions occur.
    #
    # @param workflow_name [String] Name of the workflow
    # @param options [Hash] Options for trace creation
    # @option options [String] :trace_id Custom trace ID
    # @option options [String] :group_id Group ID for related traces
    # @option options [Hash] :metadata Custom metadata
    # @option options [Boolean] :disabled Whether to disable the trace
    # @yield [trace] Block to execute within the trace
    # @yieldparam trace [Trace] The created trace
    # @return [Trace] The trace object
    #
    # @example Simple usage
    #   trace("Order Processing") do
    #     process_order(order_id)
    #   end
    #
    # @example With options
    #   trace("Batch Job",
    #     group_id: "batch_123",
    #     metadata: { job_type: "daily", priority: "high" }
    #   ) do
    #     run_batch_job()
    #   end
    def self.trace(workflow_name, **, &)
      Trace.create(workflow_name, **, &)
    end
  end
end
