# frozen_string_literal: true

require "securerandom"
require "time"

module OpenAIAgents
  module Tracing
    class Span
      attr_reader :span_id, :trace_id, :parent_id, :name, :start_time, :end_time,
                  :attributes, :events, :status, :kind

      def initialize(name:, trace_id: nil, parent_id: nil, kind: :internal)
        @span_id = SecureRandom.hex(8)
        @trace_id = trace_id || SecureRandom.hex(16)
        @parent_id = parent_id
        @name = name
        @kind = kind
        @start_time = Time.now.utc
        @end_time = nil
        @attributes = {}
        @events = []
        @status = :ok
        @finished = false
      end

      def set_attribute(key, value)
        @attributes[key.to_s] = value
        self
      end

      def attributes=(attrs)
        attrs.each { |k, v| set_attribute(k, v) }
      end

      def add_event(name, attributes: {}, timestamp: nil)
        event = {
          name: name,
          timestamp: timestamp || Time.now.utc.iso8601,
          attributes: attributes
        }
        @events << event
        self
      end

      def set_status(status, description: nil)
        @status = status
        @attributes["status.description"] = description if description
        self
      end

      def finish(end_time: nil)
        return if @finished

        @end_time = end_time || Time.now.utc
        @finished = true

        # Calculate duration
        @attributes["duration_ms"] = ((@end_time - @start_time) * 1000).round(2)

        self
      end

      def finished?
        @finished
      end

      def duration
        return nil unless @end_time

        @end_time - @start_time
      end

      def to_h
        {
          span_id: @span_id,
          trace_id: @trace_id,
          parent_id: @parent_id,
          name: @name,
          kind: @kind,
          start_time: @start_time.iso8601,
          end_time: @end_time&.iso8601,
          duration_ms: @attributes["duration_ms"],
          attributes: @attributes,
          events: @events,
          status: @status
        }
      end

      def to_json(*)
        JSON.generate(to_h, *)
      end
    end

    class SpanContext
      attr_reader :current_span, :trace_id

      def initialize
        @span_stack = []
        @trace_id = nil
        @spans = []
      end

      def start_span(name, kind: :internal, parent: nil)
        parent_span = parent || @span_stack.last
        trace_id = parent_span&.trace_id || SecureRandom.hex(16)
        parent_id = parent_span&.span_id

        span = Span.new(
          name: name,
          trace_id: trace_id,
          parent_id: parent_id,
          kind: kind
        )

        @span_stack.push(span)
        @spans << span
        @trace_id = trace_id

        if block_given?
          begin
            yield span
          ensure
            finish_span
          end
        else
          span
        end
      end

      def finish_span(span = nil)
        span_to_finish = span || @span_stack.pop
        span_to_finish&.finish
        span_to_finish
      end

      # rubocop:disable Lint/DuplicateMethods
      def current_span
        @span_stack.last
      end
      # rubocop:enable Lint/DuplicateMethods

      def all_spans
        @spans.dup
      end

      def clear
        @span_stack.clear
        @spans.clear
        @trace_id = nil
      end

      def trace_summary
        return nil if @spans.empty?

        root_spans = @spans.select { |s| s.parent_id.nil? }
        total_duration = @spans.map(&:duration).compact.sum

        {
          trace_id: @trace_id,
          total_spans: @spans.length,
          root_spans: root_spans.length,
          total_duration_ms: (total_duration * 1000).round(2),
          start_time: @spans.map(&:start_time).min&.iso8601,
          end_time: @spans.map(&:end_time).compact.max&.iso8601,
          status: @spans.any? { |s| s.status == :error } ? :error : :ok
        }
      end
    end

    # Tracer with span support
    class SpanTracer
      attr_reader :context, :processors

      def initialize
        @context = SpanContext.new
        @processors = []
        @config = {
          max_spans_per_trace: 1000,
          max_events_per_span: 100,
          max_attribute_length: 4096
        }
      end

      def add_processor(processor)
        @processors << processor
      end

      def start_span(name, kind: :internal, **attributes)
        span = @context.start_span(name, kind: kind)
        span.attributes = attributes unless attributes.empty?

        # Notify processors
        @processors.each do |processor|
          processor.on_start(span) if processor.respond_to?(:on_start)
        end

        if block_given?
          begin
            result = yield span
            span.set_status(:ok)
            result
          rescue StandardError => e
            span.set_status(:error, description: e.message)
            span.add_event("exception", attributes: {
                             "exception.type" => e.class.name,
                             "exception.message" => e.message,
                             "exception.stacktrace" => e.backtrace&.join("\n")
                           })
            raise
          ensure
            @context.finish_span(span)
            @processors.each do |processor|
              processor.on_end(span) if processor.respond_to?(:on_end)
            end
          end
        else
          span
        end
      end

      def current_span
        @context.current_span
      end

      def add_event(name, **attributes)
        span = current_span
        span&.add_event(name, attributes: attributes)
      end

      def set_attribute(key, value)
        span = current_span
        span&.set_attribute(key, value)
      end

      def finish_span(span = nil)
        finished_span = @context.finish_span(span)

        if finished_span
          @processors.each do |processor|
            processor.on_end(finished_span) if processor.respond_to?(:on_end)
          end
        end

        finished_span
      end

      def trace_summary
        @context.trace_summary
      end

      def export_spans(format: :json)
        spans = @context.all_spans.map(&:to_h)

        case format
        when :json
          JSON.pretty_generate({
                                 trace_id: @context.trace_id,
                                 spans: spans,
                                 summary: trace_summary
                               })
        when :hash
          {
            trace_id: @context.trace_id,
            spans: spans,
            summary: trace_summary
          }
        else
          raise ArgumentError, "Unsupported format: #{format}"
        end
      end

      def clear
        @context.clear
      end

      # Convenience methods for common span types
      def agent_span(agent_name, **attributes)
        start_span("agent.#{agent_name}", kind: :agent,
                                          "agent.name" => agent_name, **attributes)
      end

      def tool_span(tool_name, **attributes)
        start_span("tool.#{tool_name}", kind: :tool,
                                        "tool.name" => tool_name, **attributes)
      end

      def llm_span(model_name, **attributes)
        start_span("llm.completion", kind: :llm,
                                     "llm.model" => model_name, **attributes)
      end

      def handoff_span(from_agent, to_agent, **attributes)
        start_span("handoff", kind: :handoff,
                              "handoff.from" => from_agent,
                              "handoff.to" => to_agent,
                              **attributes)
      end
    end

    # Span processors
    class ConsoleSpanProcessor
      def on_start(span)
        puts "[SPAN START] #{span.name} (#{span.span_id})"
      end

      def on_end(span)
        duration = span.duration ? "#{(span.duration * 1000).round(2)}ms" : "unknown"
        status_icon = span.status == :error ? "❌" : "✅"
        puts "[SPAN END] #{status_icon} #{span.name} (#{span.span_id}) - #{duration}"

        return unless span.status == :error && span.attributes["status.description"]

        puts "  Error: #{span.attributes["status.description"]}"
      end
    end

    class FileSpanProcessor
      def initialize(filename)
        @filename = filename
      end

      def on_start(span)
        write_span_event("start", span)
      end

      def on_end(span)
        write_span_event("end", span)
      end

      private

      def write_span_event(event_type, span)
        data = {
          event: event_type,
          timestamp: Time.now.utc.iso8601,
          span: span.to_h
        }

        File.open(@filename, "a") do |f|
          f.puts JSON.generate(data)
        end
      end
    end

    class MemorySpanProcessor
      attr_reader :spans

      def initialize
        @spans = []
      end

      def on_start(span)
        # Could track start events if needed
      end

      def on_end(span)
        @spans << span.to_h
      end

      def clear
        @spans.clear
      end
    end
  end
end
