# frozen_string_literal: true

require "securerandom"
require "time"

module RAAF
  module Tracing
    # Represents a single operation within a trace
    #
    # A Span tracks the execution of a specific operation, including its
    # timing, status, attributes, and events. Spans form a hierarchical
    # structure within traces, with parent-child relationships representing
    # the call stack.
    #
    # ## Span Types (Kinds)
    #
    # - `:agent` - Agent execution spans
    # - `:llm` - LLM generation spans
    # - `:tool` - Tool/function execution spans
    # - `:handoff` - Agent handoff spans
    # - `:custom` - User-defined spans
    # - `:internal` - Internal operation spans
    #
    # ## Lifecycle
    #
    # 1. Created with start time
    # 2. Attributes and events added during execution
    # 3. Status set based on outcome
    # 4. Finished with end time and duration calculation
    #
    # @example Creating and using a span
    #   span = Span.new(
    #     name: "database.query",
    #     trace_id: current_trace.trace_id,
    #     parent_id: parent_span&.span_id,
    #     kind: :internal
    #   )
    #
    #   span.set_attribute("db.statement", "SELECT * FROM users")
    #   span.add_event("query.started")
    #
    #   begin
    #     result = execute_query()
    #     span.set_status(:ok)
    #   rescue => e
    #     span.set_status(:error, description: e.message)
    #     raise
    #   ensure
    #     span.finish
    #   end
    class Span
      # @return [String] Unique identifier for this span
      attr_reader :span_id

      # @return [String] Trace ID this span belongs to
      attr_reader :trace_id

      # @return [String, nil] Parent span ID if this is a child span
      attr_reader :parent_id

      # @return [String] Human-readable name for the operation
      attr_reader :name

      # @return [Time] When the span started
      attr_reader :start_time

      # @return [Time, nil] When the span ended
      attr_reader :end_time

      # @return [Hash] Key-value attributes attached to the span
      attr_reader :attributes

      # @return [Array<Hash>] Time-stamped events within the span
      attr_reader :events

      # @return [Symbol] Current status (:ok, :error, :cancelled)
      attr_reader :status

      # @return [Symbol] Type of span (agent, llm, tool, etc.)
      attr_reader :kind

      # Creates a new span
      #
      # @param name [String] Name of the operation this span represents
      # @param trace_id [String, nil] ID of the trace this span belongs to.
      #   Auto-generated if not provided.
      # @param parent_id [String, nil] ID of the parent span if this is a child
      # @param kind [Symbol] Type of span (:agent, :llm, :tool, :handoff, :custom, :internal)
      def initialize(name:, trace_id: nil, parent_id: nil, kind: :internal)
        @span_id = "span_#{SecureRandom.hex(12)}" # 24 chars hex
        @trace_id = trace_id || "trace_#{SecureRandom.hex(16)}" # 32 chars hex
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

      # Sets a single attribute on the span
      #
      # Attributes provide additional context about the operation. Keys are
      # converted to strings for consistency.
      #
      # @param key [String, Symbol] Attribute name
      # @param value [Object] Attribute value (will be serialized)
      # @return [Span] Returns self for method chaining
      #
      # @example
      #   span.set_attribute("http.method", "GET")
      #   span.set_attribute("http.status_code", 200)
      def set_attribute(key, value)
        @attributes[key.to_s] = value
        self
      end

      # Sets multiple attributes at once
      #
      # @param attrs [Hash] Attributes to set
      # @return [void]
      #
      # @example
      #   span.attributes = {
      #     "http.method" => "POST",
      #     "http.url" => "https://api.example.com/users"
      #   }
      def attributes=(attrs)
        attrs.each { |k, v| set_attribute(k, v) }
      end

      # Adds a timestamped event to the span
      #
      # Events mark significant points during the span's execution, such as
      # retries, state changes, or milestones.
      #
      # @param name [String] Event name
      # @param attributes [Hash] Additional event attributes
      # @param timestamp [Time, nil] Event timestamp (defaults to current time)
      # @return [Span] Returns self for method chaining
      #
      # @example
      #   span.add_event("cache.miss")
      #   span.add_event("retry.attempt", attributes: { attempt: 2, delay: 1000 })
      def add_event(name, attributes: {}, timestamp: nil)
        event = {
          name: name,
          timestamp: timestamp || Time.now.utc.iso8601,
          attributes: attributes
        }
        @events << event
        self
      end

      # Sets the span's status
      #
      # Status indicates whether the operation completed successfully or
      # encountered an error.
      #
      # @param status [Symbol] Status code (:ok, :error, :cancelled)
      # @param description [String, nil] Optional error description
      # @return [Span] Returns self for method chaining
      #
      # @example Success
      #   span.set_status(:ok)
      #
      # @example Error with description
      #   span.set_status(:error, description: "Connection timeout")
      def set_status(status, description: nil)
        @status = status
        @attributes["status.description"] = description if description
        self
      end

      # Marks the span as finished and records end time
      #
      # Once finished, no further modifications should be made to the span.
      # Duration is automatically calculated and stored as an attribute.
      #
      # @param end_time [Time, nil] Optional end time (defaults to current time)
      # @return [Span] Returns self for method chaining
      #
      # @example
      #   span.finish
      #
      # @example With custom end time
      #   span.finish(end_time: Time.now.utc + 0.5)
      def finish(end_time: nil)
        return self if @finished

        @end_time = end_time || Time.now.utc
        @finished = true

        # Calculate duration
        @attributes["duration_ms"] = ((@end_time - @start_time) * 1000).round(2)

        self
      end

      # Checks if the span has been finished
      #
      # @return [Boolean] true if span is finished
      def finished?
        @finished
      end

      # Returns the span's duration in seconds
      #
      # @return [Float, nil] Duration in seconds, or nil if not finished
      def duration
        return nil unless @end_time

        @end_time - @start_time
      end

      # Converts the span to a hash representation
      #
      # @return [Hash] Hash containing all span data
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

      # Converts the span to JSON
      #
      # @param args [Array] Arguments passed to JSON.generate
      # @return [String] JSON representation of the span
      def to_json(*)
        JSON.generate(to_h, *)
      end
    end

    # Manages the hierarchical context of spans within a trace
    #
    # SpanContext maintains a stack of active spans, enabling proper
    # parent-child relationships and ensuring spans are correctly
    # associated with their trace. This is used internally by SpanTracer.
    #
    # @api private
    class SpanContext
      # @return [Span, nil] The currently active span
      attr_reader :current_span

      # @return [String, nil] The current trace ID
      attr_reader :trace_id

      # Creates a new span context
      def initialize
        @span_stack = []
        @trace_id = nil
        @spans = []
      end

      def start_span(name, kind: :internal, parent: nil)
        parent_span = parent || @span_stack.last
        # Use current trace's ID if available
        current_trace = defined?(Context) ? Context.current_trace : nil
        trace_id = current_trace&.trace_id || parent_span&.trace_id || "trace_#{SecureRandom.hex(16)}"
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

    # Main tracer implementation for creating and managing spans
    #
    # SpanTracer is the primary interface for creating spans and managing
    # trace operations. It provides:
    #
    # - Span creation with automatic context management
    # - Convenience methods for common span types
    # - Event and attribute management
    # - Processor notification system
    # - Export capabilities
    #
    # ## Thread Safety
    #
    # SpanTracer uses thread-local storage for maintaining span context,
    # allowing safe concurrent usage across threads.
    #
    # ## Usage
    #
    # SpanTracer is typically accessed through the global tracer:
    #
    # @example Basic span creation
    #   tracer = RAAF::tracer
    #   tracer.span("operation") do |span|
    #     span.set_attribute("key", "value")
    #     # Your operation here
    #   end
    #
    # @example Using convenience methods
    #   tracer.agent_span("MyAgent") do |span|
    #     # Agent execution
    #   end
    #
    #   tracer.http_span("POST /v1/responses") do |span|
    #     # HTTP API call
    #   end
    class SpanTracer
      include Logger
      # @return [SpanContext] The span context manager
      attr_reader :context

      # @return [Array<Object>] Registered span processors
      attr_reader :processors

      # Creates a new SpanTracer
      #
      # @param provider [TraceProvider, nil] Optional trace provider for configuration
      def initialize(provider = nil)
        @context = SpanContext.new
        @processors = []
        @provider = provider
        @config = {
          max_spans_per_trace: 1000,
          max_events_per_span: 100,
          max_attribute_length: 4096
        }
      end

      # Adds a processor to receive span lifecycle events
      #
      # Processors are notified when spans start and end, allowing
      # custom handling of span data.
      #
      # @param processor [Object] Processor implementing on_span_start/on_span_end
      # @return [void]
      def add_processor(processor)
        @processors << processor
      end

      # Creates and manages a new span
      #
      # This is the primary method for creating spans. When called with a block,
      # the span is automatically finished after the block executes. Without a
      # block, you must manually call finish_span.
      #
      # @param name [String] Name of the operation
      # @param kind [Symbol] Span kind (:internal, :agent, :llm, :tool, etc.)
      # @param attributes [Hash] Initial attributes for the span
      # @yield [span] Block to execute within span context
      # @yieldparam span [Span] The created span
      # @return [Object, Span] Block result if block given, otherwise the span
      #
      # @example With block (automatic management)
      #   tracer.start_span("database.query", kind: :internal) do |span|
      #     span.set_attribute("db.name", "users")
      #     User.find(id)
      #   end
      #
      # @example Without block (manual management)
      #   span = tracer.start_span("long_operation")
      #   begin
      #     perform_operation()
      #   ensure
      #     tracer.finish_span(span)
      #   end
      def start_span(name, kind: :internal, **attributes)
        span = @context.start_span(name, kind: kind)
        span.attributes = attributes unless attributes.empty?

        # Notify processors
        notify_processors(:on_span_start, span)

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
            notify_processors(:on_span_end, span)
          end
        else
          span
        end
      end

      # Returns the currently active span
      #
      # @return [Span, nil] Current span or nil if none active
      def current_span
        @context.current_span
      end

      # Adds an event to the current span
      #
      # @param name [String] Event name
      # @param attributes [Hash] Event attributes
      # @return [void]
      #
      # @example
      #   tracer.add_event("cache.hit", key: "user:123", size: 1024)
      def add_event(name, **attributes)
        span = current_span
        span&.add_event(name, attributes: attributes)
      end

      # Sets an attribute on the current span
      #
      # @param key [String, Symbol] Attribute key
      # @param value [Object] Attribute value
      # @return [void]
      #
      # @example
      #   tracer.set_attribute("user.id", current_user.id)
      def set_attribute(key, value)
        span = current_span
        span&.set_attribute(key, value)
      end

      # Finishes a span and notifies processors
      #
      # @param span [Span, nil] Span to finish (defaults to current)
      # @return [Span, nil] The finished span
      def finish_span(span = nil)
        finished_span = @context.finish_span(span)

        notify_processors(:on_span_end, finished_span) if finished_span

        finished_span
      end

      # Returns a summary of the current trace
      #
      # @return [Hash] Summary including span counts, duration, and status
      def trace_summary
        @context.trace_summary
      end

      # Exports all spans in the specified format
      #
      # @param format [Symbol] Export format (:json or :hash)
      # @return [String, Hash] Exported span data
      # @raise [ArgumentError] If format is not supported
      #
      # @example Export as JSON
      #   json_data = tracer.export_spans(format: :json)
      #   File.write("trace.json", json_data)
      #
      # @example Export as hash
      #   data = tracer.export_spans(format: :hash)
      #   send_to_backend(data)
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

      # Clears all spans and resets context
      #
      # @return [void]
      def clear
        @context.clear
      end

      # Flushes all processors that support flushing
      #
      # @return [void]
      def flush
        # Flush all processors that support it
        @processors.each do |processor|
          processor.flush if processor.respond_to?(:flush)
        end
      end

      # Creates an agent execution span
      #
      # @param agent_name [String] Name of the agent
      # @param attributes [Hash] Additional span attributes
      # @yield [span] Block to execute within the span
      # @return [Object] Result of the block
      #
      # @example
      #   tracer.agent_span("CustomerSupport") do |span|
      #     span.set_attribute("agent.version", "1.0")
      #     agent.process_request(message)
      #   end
      def agent_span(agent_name, **attributes, &)
        start_span("agent.#{agent_name}", kind: :agent,
                                          "agent.name" => agent_name, **attributes, &)
      end

      # Creates a tool/function execution span
      #
      # @param tool_name [String] Name of the tool
      # @param attributes [Hash] Additional span attributes
      # @yield [span] Block to execute within the span
      # @return [Object] Result of the block
      def tool_span(tool_name, **attributes, &)
        start_span("tool.#{tool_name}", kind: :tool,
                                        "tool.name" => tool_name, **attributes, &)
      end

      # Creates an HTTP API request span (matching Python implementation)
      #
      # @param endpoint [String] API endpoint (e.g., "POST /v1/responses")
      # @param attributes [Hash] Additional span attributes
      # @yield [span] Block to execute within the span
      # @return [Object] Result of the block
      def http_span(endpoint, **attributes, &)
        start_span(endpoint, kind: :llm, **attributes, &)
      end

      # Creates an agent handoff span
      #
      # @param from_agent [String] Source agent name
      # @param to_agent [String] Target agent name
      # @param attributes [Hash] Additional span attributes
      # @yield [span] Block to execute within the span
      # @return [Object] Result of the block
      def handoff_span(from_agent, to_agent, **attributes, &)
        start_span("handoff", kind: :handoff,
                              "handoff.from" => from_agent,
                              "handoff.to" => to_agent,
                              **attributes, &)
      end

      # Creates a guardrail evaluation span
      #
      # @param guardrail_name [String] Name of the guardrail
      # @param attributes [Hash] Additional span attributes
      # @yield [span] Block to execute within the span
      # @return [Object] Result of the block
      def guardrail_span(guardrail_name, **attributes, &)
        start_span("guardrail.#{guardrail_name}", kind: :guardrail,
                                                  "guardrail.name" => guardrail_name, **attributes, &)
      end

      # Creates an MCP tool listing span
      #
      # @param server [String] MCP server name
      # @param attributes [Hash] Additional span attributes
      # @yield [span] Block to execute within the span
      # @return [Object] Result of the block
      def mcp_list_tools_span(server, **attributes, &)
        start_span("mcp.list_tools", kind: :mcp_list_tools,
                                     "mcp.server" => server, **attributes, &)
      end

      # Creates a response formatting span
      #
      # @param format [String] Response format type
      # @param attributes [Hash] Additional span attributes
      # @yield [span] Block to execute within the span
      # @return [Object] Result of the block
      def response_span(format, **attributes, &)
        start_span("response.format", kind: :response,
                                      "response.format" => format, **attributes, &)
      end

      # Creates a speech group span for grouping audio operations
      #
      # @param name [String] Group name
      # @param attributes [Hash] Additional span attributes
      # @yield [span] Block to execute within the span
      # @return [Object] Result of the block
      def speech_group_span(name, **attributes, &)
        start_span("speech_group.#{name}", kind: :speech_group,
                                           "speech_group.name" => name, **attributes, &)
      end

      # Creates a text-to-speech span
      #
      # @param model [String] TTS model name
      # @param attributes [Hash] Additional span attributes
      # @yield [span] Block to execute within the span
      # @return [Object] Result of the block
      def speech_span(model, **attributes, &)
        start_span("speech.synthesis", kind: :speech,
                                       "speech.model" => model, **attributes, &)
      end

      # Creates a speech-to-text transcription span
      #
      # @param model [String] Transcription model name
      # @param attributes [Hash] Additional span attributes
      # @yield [span] Block to execute within the span
      # @return [Object] Result of the block
      def transcription_span(model, **attributes, &)
        start_span("transcription", kind: :transcription,
                                    "transcription.model" => model, **attributes, &)
      end

      # Creates a custom span for user-defined operations
      #
      # @param name [String] Custom operation name
      # @param data [Hash] Custom data to attach
      # @param attributes [Hash] Additional span attributes
      # @yield [span] Block to execute within the span
      # @return [Object] Result of the block
      #
      # @example
      #   tracer.custom_span("data_validation", { records: 1000 }) do |span|
      #     span.set_attribute("validation.type", "schema")
      #     validate_records()
      #   end
      def custom_span(name, data = {}, **attributes, &)
        start_span("custom.#{name}", kind: :custom,
                                     "custom.name" => name,
                                     "custom.data" => data,
                                     **attributes, &)
      end

      # Generic span creation with optional type
      #
      # @param name [String] Span name
      # @param type [Symbol, nil] Optional span type
      # @param attributes [Hash] Additional span attributes
      # @yield [span] Block to execute within the span
      # @return [Object] Result of the block
      def span(name, type: nil, **attributes, &)
        kind = type || :internal
        start_span(name, kind: kind, **attributes, &)
      end

      # Sets multiple attributes on the current span
      #
      # @param attributes [Hash] Attributes to set
      # @return [void]
      def set_attributes(attributes)
        span = current_span
        attributes.each { |k, v| span&.set_attribute(k, v) }
      end

      # Records an exception in the current span
      #
      # This sets the span status to error and adds an exception event
      # with details about the error.
      #
      # @param exception [Exception] The exception to record
      # @return [void]
      #
      # @example
      #   begin
      #     risky_operation()
      #   rescue => e
      #     tracer.record_exception(e)
      #     raise
      #   end
      def record_exception(exception)
        span = current_span
        return unless span

        span.set_status(:error, description: exception.message)
        span.add_event("exception", attributes: {
                         "exception.type" => exception.class.name,
                         "exception.message" => exception.message,
                         "exception.stacktrace" => exception.backtrace&.first(10)&.join("\n")
                       })
      end

      private

      # Notifies all processors of a span event
      #
      # @param method [Symbol] Method to call on processors
      # @param span [Span] The span to pass to processors
      # @api private
      def notify_processors(method, span)
        processors = @processors.dup
        processors += @provider.processors if @provider.respond_to?(:processors)

        processors.each do |processor|
          processor.send(method, span) if processor.respond_to?(method)
        rescue StandardError => e
          log_error("Error in processor.#{method}: #{e.message}", processor_method: method, error_class: e.class.name)
        end
      end
    end

    # Console processor that prints span lifecycle events
    #
    # This processor outputs span start/end events to stdout, useful for
    # development and debugging. It includes timing information and error
    # details when spans fail.
    #
    # @example Enable console tracing
    #   tracer = RAAF::tracer
    #   tracer.add_processor(ConsoleSpanProcessor.new)
    class ConsoleSpanProcessor
      include Logger
      # Called when a span starts
      #
      # @param span [Span] The started span
      def on_span_start(span)
        log_debug_tracing("[SPAN START] #{span.name} (#{span.span_id})", span_name: span.name,
                                                                         span_id: span.span_id)
      end

      # Called when a span ends
      #
      # @param span [Span] The ended span
      def on_span_end(span)
        duration = span.duration ? "#{(span.duration * 1000).round(2)}ms" : "unknown"
        status_icon = span.status == :error ? "❌" : "✅"
        log_debug_tracing("[SPAN END] #{status_icon} #{span.name} (#{span.span_id}) - #{duration}",
                          span_name: span.name, span_id: span.span_id, duration: duration, status: span.status)

        return unless span.status == :error && span.attributes["status.description"]

        log_error("Span error: #{span.attributes["status.description"]}",
                  span_name: span.name, span_id: span.span_id, error_description: span.attributes["status.description"])
      end
    end

    # File-based processor that writes span events to a file
    #
    # Each span event is written as a JSON line to the specified file,
    # creating an append-only log of all span activity. Useful for
    # offline analysis and debugging.
    #
    # @example Log spans to file
    #   processor = FileSpanProcessor.new("traces.jsonl")
    #   tracer.add_processor(processor)
    class FileSpanProcessor
      # Creates a new file processor
      #
      # @param filename [String] Path to the output file
      def initialize(filename)
        @filename = filename
      end

      # Called when a span starts
      #
      # @param span [Span] The started span
      def on_span_start(span)
        write_span_event("start", span)
      end

      # Called when a span ends
      #
      # @param span [Span] The ended span
      def on_span_end(span)
        write_span_event("end", span)
      end

      private

      # Writes a span event to the file
      #
      # @param event_type [String] Type of event (start/end)
      # @param span [Span] The span
      # @api private
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

    # Memory-based processor that stores spans in memory
    #
    # Useful for testing and scenarios where you need programmatic
    # access to completed spans. Note that this processor only stores
    # spans when they end, not when they start.
    #
    # @example Collect spans for analysis
    #   processor = MemorySpanProcessor.new
    #   tracer.add_processor(processor)
    #
    #   # ... perform operations ...
    #
    #   spans = processor.spans
    #   failed_spans = spans.select { |s| s[:status] == :error }
    class MemorySpanProcessor
      # @return [Array<Hash>] Collected span data
      attr_reader :spans

      # Creates a new memory processor
      def initialize
        @spans = []
      end

      # Called when a span starts (no-op for this processor)
      #
      # @param span [Span] The started span
      def on_span_start(span)
        # Could track start events if needed
      end

      # Called when a span ends
      #
      # @param span [Span] The ended span
      def on_span_end(span)
        @spans << span.to_h
      end

      # Clears all collected spans
      #
      # @return [void]
      def clear
        @spans.clear
      end
    end
  end
end
