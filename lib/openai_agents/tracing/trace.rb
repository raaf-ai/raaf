# frozen_string_literal: true

require "securerandom"
require "thread"

module OpenAIAgents
  module Tracing
    # Thread-local storage for current trace and span
    class Context
      TRACE_KEY = :openai_agents_current_trace
      SPAN_KEY = :openai_agents_current_span
      
      class << self
        def current_trace
          Thread.current[TRACE_KEY]
        end
        
        def current_trace=(trace)
          Thread.current[TRACE_KEY] = trace
        end
        
        def current_span
          Thread.current[SPAN_KEY]
        end
        
        def current_span=(span)
          Thread.current[SPAN_KEY] = span
        end
        
        def clear
          Thread.current[TRACE_KEY] = nil
          Thread.current[SPAN_KEY] = nil
        end
      end
    end
    
    # Represents a trace that can contain multiple spans
    #
    # @example Using trace as a context manager
    #   Tracing.trace("My workflow") do |trace|
    #     # Your code here - spans will be part of this trace
    #   end
    #
    # @example Manual trace management
    #   trace = Trace.new("My workflow")
    #   trace.start(mark_as_current: true)
    #   # Your code here
    #   trace.finish(reset_current: true)
    class Trace
      attr_reader :trace_id, :workflow_name, :group_id, :metadata, :started_at, :ended_at
      attr_accessor :disabled
      
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
      end
      
      # Start the trace
      #
      # @param mark_as_current [Boolean] Whether to set this as the current trace
      def start(mark_as_current: true)
        return if @started || @disabled
        
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
      
      # Finish the trace
      #
      # @param reset_current [Boolean] Whether to reset the current trace
      def finish(reset_current: true)
        return if @finished || @disabled || !@started
        
        @finished = true
        @ended_at = Time.now.utc
        
        # Finish root span
        @tracer&.finish_span(@root_span) if @root_span
        
        # Reset current trace
        if reset_current
          Context.current_trace = @previous_trace
        end
        
        # Notify trace provider
        notify_trace_complete
        
        self
      end
      
      # Use the trace as a context manager
      def self.create(workflow_name, **options)
        trace = new(workflow_name, **options)
        
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
      
      # Add span to this trace
      def add_span(span)
        @spans << span unless @disabled
      end
      
      # Check if trace is active
      def active?
        @started && !@finished
      end
      
      private
      
      def generate_trace_id
        "trace_#{SecureRandom.alphanumeric(32)}"
      end
      
      def notify_trace_complete
        # This is where we would notify processors about trace completion
        # For now, the spans handle their own notification
      end
    end
    
    # Convenience method to create a trace
    #
    # @example
    #   trace("My workflow") do
    #     result = runner.run(agent, "Hello")
    #   end
    def self.trace(workflow_name, **options, &block)
      Trace.create(workflow_name, **options, &block)
    end
  end
end