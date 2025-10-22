# frozen_string_literal: true

require "securerandom"
require "set"
require_relative "tracing_registry"
require_relative "no_op_tracer"

module RAAF
  module Tracing
    # Unified tracing module where classes control their own span content
    # Traceable provides framework (timing, hierarchy, errors) + asks classes what to store
    #
    # This module provides a clean abstraction for tracing that:
    # - Handles span lifecycle management automatically
    # - Supports both explicit parent passing and auto-detection
    # - Enables classes to control their own span attributes
    # - Maintains thread safety for concurrent execution
    # - Provides consistent error handling and cleanup
    #
    # @example Basic usage
    #   class MyAgent
    #     include RAAF::Tracing::Traceable
    #     trace_as :agent
    #
    #     def run(message)
    #       traced_run(message) do
    #         # Your agent logic here
    #         process_message(message)
    #       end
    #     end
    #   end
    #
    # @example With parent component
    #   child_agent = MyAgent.new(parent_component: pipeline)
    #   child_agent.run("message") # Automatically creates child span
    #
    module Traceable
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        # Define what type of component this is for tracing
        #
        # @param component_type [Symbol] The component type (:agent, :pipeline, :tool, etc.)
        # @return [void]
        def trace_as(component_type)
          @trace_component_type = component_type
        end

        # Get the component type for tracing
        #
        # @return [Symbol] The component type
        def trace_component_type
          @trace_component_type || infer_component_type
        end

        private

        # Infer component type from class name
        #
        # @return [Symbol] Inferred component type
        def infer_component_type
          case name
          when /Agent$/ then :agent
          when /Pipeline$/ then :pipeline
          when /Runner$/ then :runner
          when /Tool$/ then :tool
          when /Job$/ then :job
          else
            # Check if this is an ActiveJob class
            if defined?(ActiveJob::Base) && self < ActiveJob::Base
              :job
            else
              :component
            end
          end
        end
      end

      # Main tracing wrapper - handles framework concerns, asks class for content
      # Includes smart span lifecycle management to avoid duplicates
      #
      # @param method_name [Symbol, String, nil] Name of the method being traced
      # @param parent_component [Object, nil] Explicit parent component for span hierarchy
      # @param metadata [Hash] Additional metadata to include in span
      # @yield Block to execute within the span context
      # @return [Object] Result of the block execution
      def with_tracing(method_name = nil, parent_component: nil, **metadata, &block)
        # Smart span lifecycle management: detect if we're already in a compatible span
        existing_span = detect_existing_span(method_name, parent_component)

        if existing_span
          # Reuse existing span, just add metadata and execute
          existing_span[:attributes].merge!(metadata)
          return block.call
        end

        span_data = create_span(method_name, parent_component, metadata)

        push_span(span_data)

        begin
          # Ask class what attributes it wants to store
          class_attributes = collect_span_attributes
          span_data[:attributes].merge!(class_attributes)

          # Add any method-specific metadata
          span_data[:attributes].merge!(metadata)

          # Execute the block
          result = block.call

          # Ask class to add result-specific attributes
          result_attributes = collect_result_attributes(result)
          span_data[:attributes].merge!(result_attributes)

          # Complete span and send to tracer
          complete_span(span_data, result)
          send_span(span_data)

          result
        rescue StandardError => e
          # Mark span as failed and send to tracer
          fail_span(span_data, e)
          send_span(span_data)

          # Force flush traces to ensure error span is sent immediately
          force_flush_traces

          raise
        ensure
          # Clean up current span - remove from stack for this fiber/thread
          pop_span
        end
      end

      # DEFAULT IMPLEMENTATIONS - Classes can override these methods

      # Override this method to define what your class stores in spans
      #
      # @return [Hash] Attributes to include in the span
      def collect_span_attributes
        # Delegate to collector system if available, fallback to original implementation
        if defined?(RAAF::Tracing::SpanCollectors)
          begin
            collector = RAAF::Tracing::SpanCollectors.collector_for(self)
            return collector.collect_attributes(self)
          rescue StandardError => e
            # Log error and fall back to original implementation
            # Note: Using puts for now since logger may not be available
            # TODO: Replace with proper logging when available
            puts "Warning: Collector error, falling back to original implementation: #{e.message}" if ENV['RAAF_DEBUG_CATEGORIES']&.include?('tracing')
          end
        end

        # Base implementation provides minimal framework data (fallback)
        {
          "component.type" => self.class.trace_component_type.to_s,
          "component.name" => self.class.name
        }
      end

      # Override this method to store result-specific data in spans
      #
      # @param result [Object] The result returned by the traced operation
      # @return [Hash] Result-specific attributes to include in the span
      def collect_result_attributes(result)
        # Delegate to collector system if available, fallback to original implementation
        if defined?(RAAF::Tracing::SpanCollectors)
          begin
            collector = RAAF::Tracing::SpanCollectors.collector_for(self)
            return collector.collect_result(self, result)
          rescue StandardError => e
            # Log error and fall back to original implementation
            # Note: Using puts for now since logger may not be available
            # TODO: Replace with proper logging when available
            puts "Warning: Collector error, falling back to original implementation: #{e.message}" if ENV['RAAF_DEBUG_CATEGORIES']&.include?('tracing')
          end
        end

        # Base implementation provides basic result summary (fallback)
        {
          "result.type" => result.class.name,
          "result.success" => !result.nil?
        }
      end

      # Convenience method for tracing run methods
      #
      # @param args [Array] Arguments to pass to the block
      # @param kwargs [Hash] Keyword arguments to pass to the block
      # @yield Block to execute within the span context
      # @return [Object] Result of the block execution
      def traced_run(*args, **kwargs, &block)
        with_tracing(:run, **kwargs) do
          if block_given?
            block.call(*args, **kwargs)
          else
            super(*args, **kwargs)
          end
        end
      end

      # Convenience method for tracing execute methods
      #
      # @param args [Array] Arguments to pass to the block
      # @param kwargs [Hash] Keyword arguments to pass to the block
      # @yield Block to execute within the span context
      # @return [Object] Result of the block execution
      def traced_execute(*args, **kwargs, &block)
        with_tracing(:execute, **kwargs) do
          if block_given?
            block.call(*args, **kwargs)
          else
            super(*args, **kwargs)
          end
        end
      end

      # DEFINED INTERFACE CONTRACT: How components expose their active span
      # All Traceable components MUST implement this interface for consistent hierarchy

      # Expose current_span for child components to access
      def current_span
        fiber_store = span_storage[Fiber.current.object_id]
        return nil unless fiber_store

        stack = fiber_store[self.object_id]
        stack&.last
      end

      # Interface method: get the component's trace-propagation data
      #
      # @return [Hash, nil] Current span data or nil if not tracing
      def trace_parent_span
        current_span
      end

      # Interface method: check if component is currently being traced
      #
      # @return [Boolean] true if component has an active span
      def traced?
        !current_span.nil?
      end

      # Interface method: check if we should create a new span or reuse existing
      #
      # @param method_name [Symbol, String, nil] Name of the method being traced
      # @param context [Hash] Additional context for span determination
      # @return [Boolean] true if a new span should be created
      def should_create_span?(method_name = nil, context = {})
        # Don't create span if already tracing the same method
        return false if traced? && current_span[:name]&.include?(method_name.to_s)

        # Don't create span if parent context indicates span reuse
        return false if context[:reuse_span] == true

        # Create span by default
        true
      end

      # Interface method: get trace ID for context propagation
      #
      # @return [String, nil] Current trace ID or nil if not tracing
      def trace_id
        current_span&.dig(:trace_id)
      end

      private

      def push_span(span_data)
        fiber_store = span_storage[Fiber.current.object_id] ||= {}
        stack = fiber_store[self.object_id] ||= []
        stack.push(span_data)
      end

      def pop_span
        fiber_store = span_storage[Fiber.current.object_id]
        return unless fiber_store

        stack = fiber_store[self.object_id]
        return unless stack

        stack.pop

        if stack.empty?
          fiber_store.delete(self.object_id)
          span_storage.delete(Fiber.current.object_id) if fiber_store.empty?
        end
      end

      def span_storage
        Thread.current[:raaf_traceable_span_storage] ||= {}
      end

      # Detect if there's an existing compatible span that should be reused
      # This prevents duplicate spans in nested execution contexts
      #
      # @param method_name [Symbol, String, nil] Name of the method being traced
      # @param parent_component_arg [Object, nil] Explicit parent component
      # @return [Hash, nil] Existing span data if reusable, nil if new span needed
      def detect_existing_span(method_name, parent_component_arg)
        # Check if we already have an active span for this component
        current = current_span
        return nil unless current

        # Check if the existing span is for the same component type and method
        component_type = self.class.trace_component_type
        existing_component_type = current[:kind]

        # Allow reuse if same component type and method
        if existing_component_type == component_type
          # Check method compatibility
          existing_name = current[:name] || ""
          method_str = method_name&.to_s

          # Reuse span if:
          # 1. Same method name, OR
          # 2. Generic methods (run, execute) can be reused
          # 3. No method specified (generic execution)
          if method_str.nil? ||
             existing_name.include?(method_str) ||
             (method_str == "run" && existing_name.include?("run")) ||
             (method_str == "execute" && existing_name.include?("execute"))
            return current
          end
        end

        nil
      end

      # Create a new span with proper hierarchy and metadata
      #
      # @param method_name [Symbol, String, nil] Name of the method being traced
      # @param parent_component_arg [Object, nil] Explicit parent component
      # @param metadata [Hash] Additional metadata for span creation
      # @return [Hash] Created span data
      def create_span(method_name, parent_component_arg, metadata = {})
        component_type = self.class.trace_component_type
        component_name = self.class.name
        span_id = "span_#{SecureRandom.hex(16)}"


        parent_span_id = get_parent_span_id(parent_component_arg)
        trace_id = get_trace_id(parent_component_arg)

        # Override span kind and name for specific method types
        if method_name == :execute_tool && metadata[:tool_name]
          # This is a tool execution, override the component type and display name
          actual_kind = :tool
          display_name = metadata[:tool_name]
        elsif method_name == :llm_call
          # This is an LLM API call, use more descriptive naming
          actual_kind = :llm

          # Determine the type of LLM operation from metadata
          if metadata[:streaming]
            display_name = "streaming"
          elsif metadata[:tool_calls]
            display_name = "tool_call"
          else
            display_name = "completion"
          end

          # Set method_name to match display_name to prevent duplication
          method_name = display_name
        else
          # Use agent_name from metadata if available, otherwise use class name
          actual_kind = component_type
          display_name = metadata[:agent_name] || component_name
        end

        span_name = build_span_name(actual_kind, display_name, method_name)

        {
          span_id: span_id,
          trace_id: trace_id,
          parent_id: parent_span_id,
          name: span_name,
          kind: actual_kind,
          start_time: Time.now.utc,
          attributes: {}, # Classes will populate this via collect_span_attributes
          events: [],
          status: :ok
        }
      end

      # Determine parent span ID using priority order:
      # 1. Explicit parent_component parameter
      # 2. Instance @parent_component
      # 3. Job span context (for nested operations in jobs)
      # 4. Execution context auto-detection
      #
      # @param parent_component_arg [Object, nil] Explicit parent component
      # @return [String, nil] Parent span ID or nil for root spans
      def get_parent_span_id(parent_component_arg)
        # Priority: explicit parent_component > @parent_component > job context > agent context > no parent
        parent_component = parent_component_arg || @parent_component

        case parent_component
        when nil
          # CRITICAL FIX: For tool execution within agent context, use ORIGINAL agent span as parent
          # Check for original agent span first (prevents tool-to-tool nesting)
          original_agent_span = Thread.current[:original_agent_span]
          if original_agent_span && original_agent_span[:span_id]
            return original_agent_span[:span_id]
          end

          # Fallback: Check if we're in an agent context (thread-local storage)
          agent_context = Thread.current[:current_agent]
          if agent_context&.respond_to?(:current_span) && agent_context.current_span
            return agent_context.current_span[:span_id]
          end

          # Check for job span context (for nested operations in jobs)
          job_span = Thread.current[:raaf_job_span]
          if job_span && job_span.respond_to?(:current_span) && job_span.current_span
            job_span.current_span[:span_id]
          else
            # No parent = root span
            nil
          end
        when Hash
          # Legacy: span hash directly (backward compatibility)
          parent_component[:span_id] || parent_component["span_id"]
        else
          # Extract span from component object
          if parent_component.respond_to?(:current_span) && parent_component.current_span
            parent_component.current_span[:span_id]
          else
            # Check for job span context as fallback
            job_span = Thread.current[:raaf_job_span]
            if job_span && job_span.respond_to?(:current_span) && job_span.current_span
              job_span.current_span[:span_id]
            else
              # No valid parent = root span
              nil
            end
          end
        end
      end

      # Get trace ID from parent component or create new one
      #
      # @param parent_component_arg [Object, nil] Explicit parent component
      # @return [String] Trace ID
      def get_trace_id(parent_component_arg)
        parent_component = parent_component_arg || @parent_component

        if parent_component&.respond_to?(:current_span) && parent_component.current_span
          return parent_component.current_span[:trace_id]
        elsif parent_component.is_a?(Hash) && parent_component[:trace_id]
          return parent_component[:trace_id]
        end

        # CRITICAL FIX: Check for original agent span first (prevents trace fragmentation)
        original_agent_span = Thread.current[:original_agent_span]
        if original_agent_span && original_agent_span[:trace_id]
          return original_agent_span[:trace_id]
        end

        # Fallback: Check agent context for trace ID inheritance
        agent_context = Thread.current[:current_agent]
        if agent_context&.respond_to?(:current_span) && agent_context.current_span
          return agent_context.current_span[:trace_id]
        end

        # Check for job span context to continue the same trace
        job_span = Thread.current[:raaf_job_span]
        if job_span && job_span.respond_to?(:current_span) && job_span.current_span
          return job_span.current_span[:trace_id]
        end

        # Create new trace
        "trace_#{SecureRandom.hex(16)}"
      end

      # Build standardized span name
      #
      # @param component_type [Symbol] Type of component
      # @param component_name [String] Name of the component class
      # @param method_name [Symbol, String, nil] Name of the method being traced
      # @return [String] Formatted span name
      def build_span_name(component_type, component_name, method_name)
        if defined?(RAAF::Tracing::SpanNamingConfig) && RAAF::Tracing.span_naming_config
          RAAF::Tracing.span_naming_config.build_name(component_type, component_name, method_name)
        else
          # Fallback to improved default implementation from Phase 1
          base_name = "run.workflow.#{component_type}"

          # Always include component name if available and not "Runner"
          if component_name && component_name != "Runner"
            base_name = "#{base_name}.#{component_name}"
          end

          # Add method name if it's not the default 'run' method
          # AND it's not the same as the component name (prevents duplication)
          if method_name &&
             method_name.to_s != "run" &&
             method_name.to_s != component_name&.to_s
            base_name = "#{base_name}.#{method_name}"
          end

          base_name
        end
      end

      # Mark span as completed successfully
      #
      # @param span_data [Hash] Span data to complete
      # @param result [Object] Result of the operation
      # @return [void]
      def complete_span(span_data, result)
        span_data[:end_time] = Time.now.utc
        span_data[:attributes]["duration_ms"] = calculate_duration(span_data)
        span_data[:attributes]["success"] = true
      end

      # Mark span as failed
      #
      # @param span_data [Hash] Span data to mark as failed
      # @param error [StandardError] Error that caused the failure
      # @return [void]
      def fail_span(span_data, error)
        span_data[:end_time] = Time.now.utc
        span_data[:attributes]["duration_ms"] = calculate_duration(span_data)
        span_data[:attributes]["success"] = false
        span_data[:attributes]["error.type"] = error.class.name
        span_data[:attributes]["error.message"] = error.message
        span_data[:attributes]["error.backtrace"] = error.backtrace&.first(5)&.join("\n")
        span_data[:status] = :error
      end

      # Send span to configured tracer with duplicate prevention
      #
      # @param span_data [Hash] Completed span data
      # @return [void]
      def send_span(span_data)
        # Get tracer from multiple sources (priority order)
        tracer = get_tracer_for_span_sending

        # Only send if there's a tracer available - don't normalize unless sending
        if tracer
          # Check for duplicate spans before sending
          return if span_already_sent?(span_data)

          # Make a copy and normalize it for sending
          normalized_span = span_data.dup
          normalize_span_data!(normalized_span)

          # Create actual Span object for processor compatibility
          span_obj = create_span_object(normalized_span)

          tracer.processors.each do |processor|
            processor.on_span_end(span_obj) if processor.respond_to?(:on_span_end)
          end

          # Mark span as sent
          mark_span_as_sent(span_data)
        end
      end

      # Create a Span object from span data for processor compatibility
      #
      # @param span_data [Hash] Span data to convert
      # @return [Object] Span-like object for processors
      def create_span_object(span_data)
        # Create a simple object that responds to the methods processors expect
        span_obj = Object.new
        span_obj.define_singleton_method(:span_id) { span_data[:span_id] }
        span_obj.define_singleton_method(:trace_id) { span_data[:trace_id] }
        span_obj.define_singleton_method(:parent_id) { span_data[:parent_id] }
        span_obj.define_singleton_method(:name) { span_data[:name] }
        span_obj.define_singleton_method(:kind) { span_data[:kind] }
        span_obj.define_singleton_method(:start_time) { span_data[:start_time] }
        span_obj.define_singleton_method(:end_time) { span_data[:end_time] }
        span_obj.define_singleton_method(:attributes) { span_data[:attributes] }
        span_obj.define_singleton_method(:events) { span_data[:events] }
        span_obj.define_singleton_method(:status) { span_data[:status] }
        span_obj.define_singleton_method(:duration) { calculate_duration(span_data) }
        span_obj.define_singleton_method(:finished?) { !span_data[:end_time].nil? }
        span_obj.define_singleton_method(:to_h) { span_data }
        span_obj
      end

      # Check if a span has already been sent to prevent duplicates
      #
      # @param span_data [Hash] Span data to check
      # @return [Boolean] true if span already sent
      def span_already_sent?(span_data)
        @sent_spans ||= Set.new
        span_id = span_data[:span_id]
        @sent_spans.include?(span_id)
      end

      # Mark a span as sent to prevent duplicate sending
      #
      # @param span_data [Hash] Span data to mark as sent
      # @return [void]
      def mark_span_as_sent(span_data)
        @sent_spans ||= Set.new
        span_id = span_data[:span_id]
        @sent_spans.add(span_id)

        # Clean up old sent spans to prevent memory leaks
        # Keep only last 1000 span IDs
        if @sent_spans.size > 1000
          old_spans = @sent_spans.to_a[0..-501]  # Remove oldest 500
          old_spans.each { |id| @sent_spans.delete(id) }
        end
      end

      # Normalize span data to RAAF format
      #
      # @param span_data [Hash] Span data to normalize
      # @return [Hash] Normalized span data
      def normalize_span_data!(span_data)
        # Ensure all required fields are present for RAAF compatibility
        span_data[:span_id] ||= span_data[:id] || "span_#{SecureRandom.hex(16)}"
        span_data[:attributes] ||= {}
        span_data[:events] ||= []

        # Ensure Time objects are in UTC for consistency but keep as Time objects
        [:start_time, :end_time].each do |time_field|
          if span_data[time_field].is_a?(Time)
            span_data[time_field] = span_data[time_field].utc
          end
        end

        span_data
      end

      # Get tracer for span sending with priority order
      #
      # @return [Object, nil] Tracer object or nil if none available
      def get_tracer_for_span_sending
        # Priority order:
        # 1. Instance tracer (@tracer)
        # 2. Parent component tracer (critical for tool execution context)
        # 3. TraceProvider singleton
        # 4. TracingRegistry current tracer (but reject NoOpTracer)
        # 5. RAAF global tracer
        # 6. nil (no tracing)

        # 1. Check instance tracer first
        return @tracer if defined?(@tracer) && @tracer

        # 2. Try parent component tracer (critical for tool execution context)
        if defined?(@parent_component) && @parent_component&.respond_to?(:trace_parent_span)
          parent_span = @parent_component.trace_parent_span
          if parent_span && @parent_component.respond_to?(:get_tracer_for_span_sending)
            parent_tracer = @parent_component.get_tracer_for_span_sending
            return parent_tracer if parent_tracer && !parent_tracer.is_a?(RAAF::Tracing::NoOpTracer)
          end
        end

        # 3. Try TraceProvider singleton (prioritize over TracingRegistry to avoid NoOpTracer)
        if defined?(RAAF::Tracing::TraceProvider)
          begin
            provider = RAAF::Tracing::TraceProvider.instance
            return provider if provider&.respond_to?(:processors) && provider.processors.any?
          rescue StandardError
            # TraceProvider not available or failed
          end
        end

        # 4. Try TracingRegistry current tracer (but reject NoOpTracer)
        begin
          if defined?(RAAF::Tracing::TracingRegistry)
            registry_tracer = RAAF::Tracing::TracingRegistry.current_tracer
            return registry_tracer if registry_tracer && !registry_tracer.is_a?(RAAF::Tracing::NoOpTracer)
          end
        rescue StandardError
          # TracingRegistry not available or failed, continue to next priority
        end

        # 5. Try RAAF global tracer
        return RAAF.tracer if defined?(RAAF) && RAAF.respond_to?(:tracer) && RAAF.tracer

        # 6. No tracer available
        nil
      end

      # Calculate span duration in milliseconds
      #
      # @param span_data [Hash] Span data with start and end times
      # @return [Float, nil] Duration in milliseconds or nil if times missing
      def calculate_duration(span_data)
        return nil unless span_data[:start_time] && span_data[:end_time]

        start_time = span_data[:start_time].is_a?(Time) ? span_data[:start_time] : Time.parse(span_data[:start_time])
        end_time = span_data[:end_time].is_a?(Time) ? span_data[:end_time] : Time.parse(span_data[:end_time])
        ((end_time - start_time) * 1000).round(2)
      end

      # Force flush all traces to backend immediately
      #
      # Call this before re-raising exceptions to ensure error spans are sent.
      # This method ensures that error spans don't get lost due to buffering
      # or process termination.
      #
      # @return [void]
      #
      # @example Usage in error handling
      #   rescue StandardError => e
      #     force_flush_traces  # Ensure error span is sent
      #     raise
      #   end
      def force_flush_traces
        begin
          if defined?(RAAF::Tracing::TraceProvider)
            RAAF::Tracing::TraceProvider.force_flush

            # Give network time to complete (critical for error scenarios)
            # This small sleep ensures HTTP requests complete before process exits
            sleep(0.1)
          end
        rescue StandardError => e
          # Don't let flushing errors hide the original error
          # Use warn instead of raise to prevent masking the real exception
          warn "[Traceable] Failed to flush traces: #{e.message}"
        end
      end
    end
  end
end
