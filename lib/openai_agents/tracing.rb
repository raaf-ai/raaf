# frozen_string_literal: true

require "json"
require "time"
require_relative "tracing/spans"
require_relative "tracing/trace"
require_relative "tracing/openai_processor"
require_relative "tracing/trace_provider"

module OpenAIAgents
  # Comprehensive tracing system for OpenAI Agents
  #
  # The Tracing module provides a complete observability solution for agent workflows,
  # allowing you to track, debug, and monitor agent executions. Traces are automatically
  # sent to the OpenAI platform dashboard for visualization.
  #
  # ## Overview
  #
  # Tracing captures a hierarchical record of operations:
  # - **Traces**: Top-level containers representing complete workflows
  # - **Spans**: Individual operations within a trace (agent calls, LLM generations, tools, etc.)
  #
  # ## Key Features
  #
  # - Automatic tracing of agent runs, LLM calls, and tool executions
  # - Support for custom spans and metadata
  # - Thread-safe context tracking
  # - Batched export to OpenAI platform
  # - Configurable processors for custom destinations
  # - Sensitive data protection options
  #
  # ## Basic Usage
  #
  # ```ruby
  # # Automatic tracing (enabled by default)
  # runner = OpenAIAgents::Runner.new(agent: agent)
  # result = runner.run(messages)  # Automatically traced
  #
  # # Group multiple operations in a trace
  # OpenAIAgents::Tracing.trace("Customer Support") do
  #   result1 = runner.run(agent1, "Hello")
  #   result2 = runner.run(agent2, "Process: #{result1}")
  # end
  #
  # # Custom spans
  # tracer = OpenAIAgents.tracer
  # tracer.custom_span("data_processing", { rows: 1000 }) do |span|
  #   span.set_attribute("processing.type", "batch")
  #   # Your processing code
  # end
  # ```
  #
  # ## Configuration
  #
  # Tracing can be configured via environment variables:
  # - `OPENAI_AGENTS_DISABLE_TRACING=1` - Disable all tracing
  # - `OPENAI_AGENTS_TRACE_BATCH_SIZE=100` - Set batch size for exports
  # - `OPENAI_AGENTS_TRACE_FLUSH_INTERVAL=10` - Set flush interval in seconds
  #
  # @see https://platform.openai.com/traces OpenAI Traces Dashboard
  module Tracing
    class << self
      # Creates a trace that groups multiple operations under a single workflow
      #
      # This method creates a new trace context that all subsequent operations
      # will be associated with. It's the primary way to group related agent
      # runs, tool calls, and other operations.
      #
      # @param workflow_name [String] Name of the workflow to display in traces
      # @param trace_id [String, nil] Optional custom trace ID. Must match format
      #   `trace_<32_alphanumeric>`. Auto-generated if not provided.
      # @param group_id [String, nil] Optional group ID to link related traces
      #   (e.g., conversation thread ID)
      # @param metadata [Hash, nil] Optional metadata to attach to the trace
      # @param disabled [Boolean] Whether to disable this specific trace
      #
      # @yield [trace] Block to execute within the trace context
      # @yieldparam trace [Trace] The trace object
      # @return [Trace] The trace object (when used without block)
      #
      # @example Group multiple agent runs
      #   OpenAIAgents::Tracing.trace("Customer Support") do
      #     result1 = runner.run(agent1, "Hello")
      #     result2 = runner.run(agent2, "Process: #{result1}")
      #   end
      #
      # @example With custom metadata
      #   OpenAIAgents::Tracing.trace("Data Processing",
      #     trace_id: "trace_#{SecureRandom.hex(16)}",
      #     group_id: "session_123",
      #     metadata: { user_id: "user_456", version: "1.0" }
      #   ) do
      #     # Your workflow code
      #   end
      def trace(workflow_name, **options, &block)
        Trace.create(workflow_name, **options, &block)
      end
      
      # Adds a custom trace processor to receive span events
      #
      # Processors receive notifications when spans start and end, allowing
      # you to send trace data to additional destinations beyond OpenAI.
      #
      # @param processor [Object] Processor object that implements:
      #   - `on_span_start(span)` - Called when a span starts
      #   - `on_span_end(span)` - Called when a span ends
      #   - `force_flush` (optional) - Called to flush buffered data
      #   - `shutdown` (optional) - Called during shutdown
      #
      # @example Add a custom processor
      #   class MyProcessor
      #     def on_span_start(span)
      #       puts "Span started: #{span.name}"
      #     end
      #     
      #     def on_span_end(span)
      #       puts "Span ended: #{span.name} (#{span.duration}ms)"
      #     end
      #   end
      #   
      #   OpenAIAgents::Tracing.add_trace_processor(MyProcessor.new)
      def add_trace_processor(processor)
        TraceProvider.add_processor(processor)
      end
      
      # Replaces all trace processors with the provided ones
      #
      # This method removes all existing processors (including the default
      # OpenAI processor) and replaces them with the provided processors.
      # Use this when you want complete control over trace destinations.
      #
      # @param processors [Array<Object>] New processors to use
      #
      # @example Replace default processor
      #   OpenAIAgents::Tracing.set_trace_processors(
      #     MyCustomProcessor.new,
      #     FileProcessor.new("traces.log")
      #   )
      def set_trace_processors(*processors)
        TraceProvider.set_processors(*processors)
      end
      
      # Returns the global tracer instance
      #
      # The tracer provides methods for creating spans of various types.
      # It returns a NoOpTracer when tracing is disabled.
      #
      # @return [SpanTracer, NoOpTracer] The tracer instance
      #
      # @example Create custom spans
      #   tracer = OpenAIAgents::Tracing.tracer
      #   tracer.custom_span("data_processing", { rows: 1000 }) do |span|
      #     span.set_attribute("status", "processing")
      #     # Your code here
      #   end
      def tracer
        TraceProvider.tracer
      end
      
      # Checks if tracing is globally disabled
      #
      # @return [Boolean] true if tracing is disabled
      def disabled?
        TraceProvider.disabled?
      end
      
      # Disables tracing globally
      #
      # This prevents any new traces or spans from being created.
      # Existing processors are retained but won't receive new data.
      #
      # @example
      #   OpenAIAgents::Tracing.disable!
      #   # No traces will be created after this point
      def disable!
        TraceProvider.disable!
      end
      
      # Enables tracing globally
      #
      # Re-enables tracing after it has been disabled. If no processors
      # are configured, default processors will be set up.
      #
      # @example
      #   OpenAIAgents::Tracing.enable!
      #   # Tracing is now active again
      def enable!
        TraceProvider.enable!
      end
      
      # Forces all processors to flush buffered data immediately
      #
      # Use this to ensure all trace data is sent before your application
      # exits or at critical checkpoints.
      #
      # @example
      #   # At application shutdown
      #   OpenAIAgents::Tracing.force_flush
      #   sleep(1)  # Give time for network requests
      def force_flush
        TraceProvider.force_flush
      end
      
      # Shuts down the tracing system
      #
      # This method flushes all pending data and releases resources.
      # After shutdown, no new traces can be created.
      #
      # @example
      #   at_exit { OpenAIAgents::Tracing.shutdown }
      def shutdown
        TraceProvider.shutdown
      end
    end
  end
  
  # Legacy Tracer class for backward compatibility
  class Tracer
    attr_reader :traces

    def initialize
      @traces = []
      @processors = []
    end

    def add_processor(processor)
      @processors << processor
    end

    def trace(event_type, data = {})
      trace_entry = {
        timestamp: Time.now.utc.iso8601,
        event_type: event_type,
        data: data
      }

      @traces << trace_entry

      # Process with all registered processors
      @processors.each do |processor|
        processor.call(trace_entry)
      rescue StandardError => e
        # Silently ignore processor errors to prevent disrupting tracing
        warn "Trace processor failed: #{e.message}" if $DEBUG
      end

      trace_entry
    end

    def clear
      @traces.clear
    end

    def to_json(*_args)
      JSON.pretty_generate(@traces)
    end

    def save_to_file(filename)
      File.write(filename, to_json)
    end
  end

  class ConsoleProcessor
    def call(trace_entry)
      puts "[#{trace_entry[:timestamp]}] #{trace_entry[:event_type]}: #{trace_entry[:data]}"
    end
  end

  class FileProcessor
    def initialize(filename)
      @filename = filename
    end

    def call(trace_entry)
      File.open(@filename, "a") do |f|
        f.puts JSON.generate(trace_entry)
      end
    end
  end
  
  # Module-level convenience methods
  class << self
    # Create a trace
    #
    # @example
    #   OpenAIAgents.trace("My Workflow") do
    #     # Your code here
    #   end
    def trace(workflow_name, **options, &block)
      Tracing.trace(workflow_name, **options, &block)
    end
    
    # Get the global tracer instance
    def tracer
      @tracer ||= Tracing.tracer
    end
  end
end

# Ensure tracing is properly cleaned up on exit
at_exit do
  OpenAIAgents::Tracing.shutdown
end