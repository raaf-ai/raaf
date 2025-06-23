# frozen_string_literal: true

require "json"
require "time"
require_relative "tracing/spans"
require_relative "tracing/openai_processor"

module OpenAIAgents
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
end
