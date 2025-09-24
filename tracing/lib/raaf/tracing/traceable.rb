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
        puts "🔍 [TRACEABLE] Starting with_tracing for #{self.class.name}.#{method_name}"
        puts "🔍 [TRACEABLE] Full metadata: #{metadata.inspect}"
        puts "🔍 [TRACEABLE] Parent component: #{parent_component&.class&.name || 'nil'}"
        puts "🔍 [TRACEABLE] Current span: #{@current_span&.dig(:span_id) || 'nil'}"

        # Smart span lifecycle management: detect if we're already in a compatible span
        existing_span = detect_existing_span(method_name, parent_component)
        puts "🔍 [TRACEABLE] Existing span detected: #{!existing_span.nil?}"

        if existing_span
          # Reuse existing span, just add metadata and execute
          existing_span[:attributes].merge!(metadata)
          puts "🔍 [TRACEABLE] Reusing existing span: #{existing_span[:name]}"
          return block.call
        end

        puts "🔍 [TRACEABLE] Creating new span..."
        span_data = create_span(method_name, parent_component, metadata)
        puts "🔍 [TRACEABLE] Created span: #{span_data[:name]} (ID: #{span_data[:span_id]}, Parent: #{span_data[:parent_id]})"

        previous_span = @current_span

        begin
          # Ask class what attributes it wants to store
          class_attributes = collect_span_attributes
          span_data[:attributes].merge!(class_attributes)

          # Add any method-specific metadata
          span_data[:attributes].merge!(metadata)

          # Store current span for child components
          @current_span = span_data

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
          raise
        ensure
          # Clean up current span - restore previous span if nested
          @current_span = previous_span
        end
      end

      # DEFAULT IMPLEMENTATIONS - Classes can override these methods

      # Override this method to define what your class stores in spans
      #
      # @return [Hash] Attributes to include in the span
      def collect_span_attributes
        # Base implementation provides minimal framework data
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
        # Base implementation provides basic result summary
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
      attr_reader :current_span

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

      # Detect if there's an existing compatible span that should be reused
      # This prevents duplicate spans in nested execution contexts
      #
      # @param method_name [Symbol, String, nil] Name of the method being traced
      # @param parent_component_arg [Object, nil] Explicit parent component
      # @return [Hash, nil] Existing span data if reusable, nil if new span needed
      def detect_existing_span(method_name, parent_component_arg)
        # Check if we already have an active span for this component
        return nil unless @current_span

        # Check if the existing span is for the same component type and method
        component_type = self.class.trace_component_type
        existing_component_type = @current_span[:kind]

        # Allow reuse if same component type and method
        if existing_component_type == component_type
          # Check method compatibility
          existing_name = @current_span[:name] || ""
          method_str = method_name&.to_s

          # Reuse span if:
          # 1. Same method name, OR
          # 2. Generic methods (run, execute) can be reused
          # 3. No method specified (generic execution)
          if method_str.nil? ||
             existing_name.include?(method_str) ||
             (method_str == "run" && existing_name.include?("run")) ||
             (method_str == "execute" && existing_name.include?("execute"))
            return @current_span
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

        puts "🔍 [CREATE_SPAN] Creating span for class: #{component_name}"
        puts "🔍 [CREATE_SPAN] Component type: #{component_type}"
        puts "🔍 [CREATE_SPAN] Method name: #{method_name}"
        puts "🔍 [CREATE_SPAN] Parent component arg: #{parent_component_arg&.class&.name || 'nil'}"
        puts "🔍 [CREATE_SPAN] Metadata keys: #{metadata.keys}"
        puts "🔍 [CREATE_SPAN] Agent name in metadata: #{metadata[:agent_name]}"

        parent_span_id = get_parent_span_id(parent_component_arg)
        puts "🔍 [CREATE_SPAN] Resolved parent span ID: #{parent_span_id}"

        trace_id = get_trace_id(parent_component_arg)
        puts "🔍 [CREATE_SPAN] Resolved trace ID: #{trace_id}"

        # Use agent_name from metadata if available, otherwise use class name
        display_name = metadata[:agent_name] || component_name
        puts "🔍 [CREATE_SPAN] Display name: #{display_name} (from metadata: #{!metadata[:agent_name].nil?})"

        span_name = build_span_name(component_type, display_name, method_name)
        puts "🔍 [CREATE_SPAN] Built span name: #{span_name}"

        span = {
          span_id: span_id,
          trace_id: trace_id,
          parent_id: parent_span_id,
          name: span_name,
          kind: component_type,
          start_time: Time.now.utc,
          attributes: {}, # Classes will populate this via collect_span_attributes
          events: [],
          status: :ok
        }

        puts "🔍 [CREATE_SPAN] Final span structure:"
        puts "  span_id: #{span[:span_id]}"
        puts "  trace_id: #{span[:trace_id]}"
        puts "  parent_id: #{span[:parent_id]}"
        puts "  name: #{span[:name]}"
        puts "  kind: #{span[:kind]}"

        span
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
        puts "🔍 [PARENT_SPAN] Looking for parent span ID"
        puts "🔍 [PARENT_SPAN] Parent component arg: #{parent_component_arg&.class&.name || 'nil'}"
        puts "🔍 [PARENT_SPAN] Instance @parent_component: #{@parent_component&.class&.name || 'nil'}"

        # Priority: explicit parent_component > @parent_component > job context > no parent
        parent_component = parent_component_arg || @parent_component
        puts "🔍 [PARENT_SPAN] Using parent component: #{parent_component&.class&.name || 'nil'}"

        parent_id = case parent_component
        when nil
          puts "🔍 [PARENT_SPAN] No parent component, checking job span context"
          # Check for job span context (for nested operations in jobs)
          job_span = Thread.current[:raaf_job_span]
          if job_span && job_span.respond_to?(:current_span) && job_span.current_span
            result = job_span.current_span[:span_id]
            puts "🔍 [PARENT_SPAN] Got parent span ID from job context: #{result}"
            result
          else
            puts "🔍 [PARENT_SPAN] No job span context, this will be a root span"
            # No parent = root span
            nil
          end
        when Hash
          puts "🔍 [PARENT_SPAN] Parent is a Hash, extracting span_id"
          # Legacy: span hash directly (backward compatibility)
          result = parent_component[:span_id] || parent_component["span_id"]
          puts "🔍 [PARENT_SPAN] Got parent span ID from hash: #{result}"
          result
        else
          puts "🔍 [PARENT_SPAN] Parent is object, checking for current_span method"
          puts "🔍 [PARENT_SPAN] Parent responds to current_span?: #{parent_component.respond_to?(:current_span)}"
          # Extract span from component object
          if parent_component.respond_to?(:current_span) && parent_component.current_span
            result = parent_component.current_span[:span_id]
            puts "🔍 [PARENT_SPAN] Got parent span ID from component: #{result}"
            puts "🔍 [PARENT_SPAN] Parent component current span: #{parent_component.current_span[:name]}"
            result
          else
            puts "🔍 [PARENT_SPAN] Parent component has no current span, checking job context fallback"
            # Check for job span context as fallback
            job_span = Thread.current[:raaf_job_span]
            if job_span && job_span.respond_to?(:current_span) && job_span.current_span
              result = job_span.current_span[:span_id]
              puts "🔍 [PARENT_SPAN] Got parent span ID from job context fallback: #{result}"
              result
            else
              puts "🔍 [PARENT_SPAN] No valid parent found, this will be a root span"
              # No valid parent = root span
              nil
            end
          end
        end

        puts "🔍 [PARENT_SPAN] Final parent span ID: #{parent_id}"
        parent_id
      end

      # Get trace ID from parent component or create new one
      #
      # @param parent_component_arg [Object, nil] Explicit parent component
      # @return [String] Trace ID
      def get_trace_id(parent_component_arg)
        parent_component = parent_component_arg || @parent_component

        if parent_component&.respond_to?(:current_span) && parent_component.current_span
          parent_component.current_span[:trace_id]
        elsif parent_component.is_a?(Hash) && parent_component[:trace_id]
          parent_component[:trace_id]
        else
          # Check for job span context to continue the same trace
          job_span = Thread.current[:raaf_job_span]
          if job_span && job_span.respond_to?(:current_span) && job_span.current_span
            job_span.current_span[:trace_id]
          else
            # Create new trace
            "trace_#{SecureRandom.hex(16)}"
          end
        end
      end

      # Build standardized span name
      #
      # @param component_type [Symbol] Type of component
      # @param component_name [String] Name of the component class
      # @param method_name [Symbol, String, nil] Name of the method being traced
      # @return [String] Formatted span name
      def build_span_name(component_type, component_name, method_name)
        base_name = "run.workflow.#{component_type}"

        # Always include component name if available
        if component_name && component_name != "Runner"
          base_name = "#{base_name}.#{component_name}"
        end

        # Add method name if it's not the default 'run' method
        if method_name && method_name.to_s != "run"
          base_name = "#{base_name}.#{method_name}"
        end

        base_name
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
          tracer.processors.each { |processor| processor.on_span_end(span_obj) if processor.respond_to?(:on_span_end) }

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
        # 2. RAAF::Tracing::TracingRegistry.current_tracer (NEW)
        # 3. TraceProvider singleton
        # 4. RAAF global tracer
        # 5. nil (no tracing)

        # 1. Check instance tracer first
        return @tracer if defined?(@tracer) && @tracer

        # 2. Try TracingRegistry current tracer
        begin
          if defined?(RAAF::Tracing::TracingRegistry)
            registry_tracer = RAAF::Tracing::TracingRegistry.current_tracer
            # Return any tracer from registry, including NoOpTracer (which is a valid tracer for disabled tracing)
            return registry_tracer if registry_tracer
          end
        rescue StandardError
          # TracingRegistry not available or failed, continue to next priority
        end

        # 3. Try TraceProvider singleton
        if defined?(RAAF::Tracing::TraceProvider)
          begin
            provider = RAAF::Tracing::TraceProvider.instance
            return provider if provider&.respond_to?(:processors)
          rescue StandardError
            # TraceProvider not available or failed
          end
        end

        # 4. Try RAAF global tracer
        if defined?(RAAF) && RAAF.respond_to?(:tracer) && RAAF.tracer
          return RAAF.tracer
        end

        # 5. No tracer available
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
    end
  end
end
