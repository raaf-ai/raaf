# frozen_string_literal: true

require "json"
require "time"
require_relative "tracing/spans"
require_relative "tracing/trace"
require_relative "tracing/openai_processor"
require_relative "tracing/trace_provider"

module OpenAIAgents
  # Main module for tracing functionality
  module Tracing
    class << self
      # Create a trace for grouping multiple operations
      #
      # @param workflow_name [String] Name of the workflow
      # @param trace_id [String, nil] Optional trace ID
      # @param group_id [String, nil] Optional group ID to link traces
      # @param metadata [Hash, nil] Optional metadata
      # @param disabled [Boolean] Whether to disable this trace
      #
      # @example
      #   OpenAIAgents::Tracing.trace("Customer Support") do
      #     result1 = runner.run(agent1, "Hello")
      #     result2 = runner.run(agent2, "Process: #{result1}")
      #   end
      def trace(workflow_name, **options, &block)
        Trace.create(workflow_name, **options, &block)
      end
      
      # Add a trace processor
      #
      # @param processor [Object] Processor that responds to on_span_start/on_span_end
      def add_trace_processor(processor)
        TraceProvider.add_processor(processor)
      end
      
      # Replace all trace processors
      #
      # @param processors [Array<Object>] New processors to use
      def set_trace_processors(*processors)
        TraceProvider.set_processors(*processors)
      end
      
      # Get the current tracer
      #
      # @return [SpanTracer, NoOpTracer]
      def tracer
        TraceProvider.tracer
      end
      
      # Check if tracing is disabled
      #
      # @return [Boolean]
      def disabled?
        TraceProvider.disabled?
      end
      
      # Disable tracing globally
      def disable!
        TraceProvider.disable!
      end
      
      # Enable tracing globally
      def enable!
        TraceProvider.enable!
      end
      
      # Force flush all trace processors
      def force_flush
        TraceProvider.force_flush
      end
      
      # Shutdown tracing
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