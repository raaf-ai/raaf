# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require_relative "version"

module RAAF
  module Tracing
    # Processor that sends spans to OpenAI's traces ingestion endpoint
    #
    # OpenAIProcessor is responsible for:
    # - Transforming span data into OpenAI's expected format
    # - Batching spans for efficient network usage
    # - Sending traces to the OpenAI platform dashboard
    # - Handling authentication and API communication
    #
    # ## Configuration
    #
    # The processor can be configured via initialization parameters or
    # environment variables:
    #
    # - `OPENAI_API_KEY` - Required for authentication
    # - `OPENAI_ORG_ID` - Optional organization ID
    # - `OPENAI_PROJECT_ID` - Optional project ID
    # - `RAAF_DEBUG_CATEGORIES=http` - Enable detailed HTTP debug output
    #
    # ## Span Format
    #
    # The processor transforms Ruby span objects into the OpenAI traces
    # API format, which includes:
    # - Trace object with workflow metadata
    # - Individual span objects with type-specific data
    #
    # @see https://platform.openai.com/traces OpenAI Traces Dashboard
    #
    # @example Direct usage (usually not needed)
    #   processor = OpenAIProcessor.new(
    #     api_key: "sk-...",
    #     batch_size: 100
    #   )
    #   tracer.add_processor(processor)
    #
    # @example Typical usage via TraceProvider
    #   # Automatically configured when OPENAI_API_KEY is set
    #   runner = RAAF::Runner.new(agent: agent)
    #   runner.run(messages)  # Traces sent automatically
    class OpenAIProcessor
      include Logger
      # Creates a new OpenAI processor
      #
      # @param api_key [String, nil] OpenAI API key. Defaults to OPENAI_API_KEY env var
      # @param base_url [String, nil] Base URL for OpenAI API. Defaults to https://api.openai.com
      # @param batch_size [Integer] Number of spans to buffer before sending. Default: 50
      # @param workflow_name [String, nil] Default workflow name. Default: "openai-agents-ruby"
      # @param organization [String, nil] Organization ID. Defaults to OPENAI_ORG_ID env var
      # @param project [String, nil] Project ID. Defaults to OPENAI_PROJECT_ID env var
      #
      # @raise [ArgumentError] If api_key is not provided and OPENAI_API_KEY is not set
      def initialize(api_key: nil, base_url: nil, batch_size: 50, workflow_name: nil, organization: nil, project: nil)
        @api_key = api_key || ENV.fetch("OPENAI_API_KEY", nil)
        @organization = organization || ENV.fetch("OPENAI_ORG_ID", nil)
        @project = project || ENV.fetch("OPENAI_PROJECT_ID", nil)
        @base_url = base_url || "https://api.openai.com"
        @traces_endpoint = "#{@base_url}/v1/traces/ingest"
        @batch_size = batch_size
        @span_buffer = []
        @mutex = Mutex.new
        @workflow_name = workflow_name || "openai-agents-ruby"
        @current_trace_id = nil
      end

      # Called when a span starts
      #
      # OpenAI's traces API only processes completed spans, so this method
      # is a no-op. Span data is collected when the span ends.
      #
      # @param span [Span] The span that started
      # @return [void]
      def on_span_start(span)
        # OpenAI processes spans on completion, not on start
      end

      # Called when a span ends
      #
      # Transforms the span to OpenAI format and adds it to the buffer.
      # If the buffer reaches the batch size, automatically flushes.
      #
      # @param span [Span] The span that ended
      # @return [void]
      def on_span_end(span)
        @mutex.synchronize do
          @current_trace_id ||= span.trace_id

          # Handle trace spans specially
          if span.kind == :trace && span.attributes["trace.workflow_name"]
            @workflow_name = span.attributes["trace.workflow_name"]
          end

          transformed = transform_span(span)
          @span_buffer << transformed if transformed

          flush_spans if @span_buffer.size >= @batch_size
        end
      end

      # Exports a batch of spans to OpenAI
      #
      # This method is typically called by BatchTraceProcessor with accumulated
      # spans. It groups spans by trace ID and sends them to the OpenAI API.
      #
      # @param spans [Array<Span>] Array of spans to export
      # @return [void]
      #
      # @api private
      def export(spans)
        return if spans.empty?

        unless @api_key
          log_warn("OPENAI_API_KEY is not set, skipping trace export", processor: "OpenAI")
          return
        end

        # Group spans by trace_id
        spans_by_trace = spans.group_by(&:trace_id)

        spans_by_trace.each do |trace_id, trace_spans|
          @current_trace_id = trace_id

          # Find trace span if any
          trace_span = trace_spans.find { |s| s.kind == :trace }

          # Extract workflow name from trace span or use default
          @workflow_name = trace_span.attributes["trace.workflow_name"] || @workflow_name if trace_span

          # Transform spans, filtering out nils
          transformed_spans = trace_spans.map { |span| transform_span(span) }.compact
          send_spans(transformed_spans) unless transformed_spans.empty?
        end
      rescue StandardError => e
        log_error("Failed to export spans to OpenAI: #{e.message}", processor: "OpenAI", error_class: e.class.name)
        log_debug_tracing("Export error backtrace: #{e.backtrace.first(5).join("\n")}",
                          processor: "OpenAI")
      end

      # Forces immediate export of any buffered spans
      #
      # Call this method to ensure all pending span data is sent to OpenAI,
      # typically before application shutdown or at critical checkpoints.
      #
      # @return [void]
      #
      # @example
      #   processor.force_flush
      #   sleep(1)  # Allow time for network request
      def force_flush
        @mutex.synchronize do
          flush_spans if @span_buffer.any?
        end
      end

      # Shuts down the processor
      #
      # Flushes any remaining spans and releases resources.
      # After shutdown, the processor should not be used.
      #
      # @return [void]
      def shutdown
        force_flush
      end

      private

      # Transforms a Ruby span object into OpenAI's expected format
      #
      # @param span [Span] The span to transform
      # @return [Hash, nil] Transformed span data or nil if span should be skipped
      #
      # @api private
      def transform_span(span)
        # Skip trace spans - they're handled separately
        return nil if span.kind == :trace

        # Skip LLM spans without valid usage data
        if span.kind == :llm
          usage = extract_usage(span)
          return nil unless usage # OpenAI API requires usage data for LLM spans
        end

        # Create the span object with required fields
        span_data = create_span_data(span)
        return nil unless span_data

        {
          object: "trace.span",
          id: span.span_id,
          trace_id: span.trace_id,
          parent_id: span.parent_id,
          started_at: span.start_time.utc.strftime("%Y-%m-%dT%H:%M:%S.%6N+00:00"),
          ended_at: span.end_time&.utc&.strftime("%Y-%m-%dT%H:%M:%S.%6N+00:00"),
          span_data: span_data,
          error: span.attributes["error"] || nil
        }
      end

      # Creates type-specific span data based on span kind
      #
      # Each span type has specific fields required by the OpenAI API.
      # This method extracts the appropriate attributes and formats them
      # according to the API specification.
      #
      # @param span [Span] The span to process
      # @return [Hash, nil] Type-specific span data or nil
      #
      # @api private
      def create_span_data(span)
        data = case span.kind
               when :trace
                 # Trace spans are handled differently - they become the trace object
                 return nil
               when :agent
                 {
                   type: "agent",
                   name: span.attributes["agent.name"] || span.name,
                   handoffs: span.attributes["agent.handoffs"] || [],
                   tools: span.attributes["agent.tools"] || [],
                   output_type: span.attributes["agent.output_type"] || "str"
                 }.compact
               when :llm
                 # Get input messages as array for OpenAI API compatibility
                 input_messages = span.attributes["llm.request.messages"] || []
                 # If it's a string, try to parse it, otherwise use as-is
                 parsed_input = if input_messages.is_a?(String)
                                  begin
                                    JSON.parse(input_messages)
                                  rescue JSON::ParserError
                                    []
                                  end
                                else
                                  input_messages
                                end

                 data = {
                   type: "generation",
                   input: parsed_input,
                   output: format_llm_output(span),
                   model: span.attributes["llm.request.model"],
                   model_config: extract_model_config(span)
                 }
                 # Only include usage if we have valid data
                 usage = extract_usage(span)
                 data[:usage] = usage if usage
                 data
               when :tool
                 # Ensure input is a string for OpenAI API compatibility
                 tool_input = span.attributes["function.input"]
                 input_string = case tool_input
                                when String then tool_input
                                when nil then nil
                                else JSON.generate(tool_input)
                                end

                 {
                   type: "function",
                   name: span.attributes["function.name"] || span.name,
                   input: input_string,
                   output: span.attributes["function.output"],
                   mcp_data: span.attributes["function.mcp_data"]
                 }
               when :handoff
                 {
                   type: "handoff",
                   from_agent: span.attributes["handoff.from"],
                   to_agent: span.attributes["handoff.to"]
                 }
               when :guardrail
                 {
                   type: "guardrail",
                   name: span.attributes["guardrail.name"] || span.name,
                   triggered: span.attributes["guardrail.triggered"] || false
                 }
               when :mcp_list_tools
                 {
                   type: "mcp_tools",
                   server: span.attributes["mcp.server"],
                   result: span.attributes["mcp.result"] || span.attributes["mcp.tools"] || []
                 }
               when :response
                 {
                   type: "response",
                   response_id: span.attributes["response_id"]
                 }.compact
               when :speech_group
                 {
                   type: "speech_group",
                   input: span.attributes["speech_group.input"]
                 }
               when :speech
                 {
                   type: "speech",
                   input: span.attributes["speech.input"],
                   output: span.attributes["speech.output"],
                   output_format: span.attributes["speech.output_format"] || "pcm",
                   model: span.attributes["speech.model"],
                   model_config: span.attributes["speech.model_config"],
                   first_content_at: span.attributes["speech.first_content_at"]
                 }
               when :transcription
                 {
                   type: "transcription",
                   input: span.attributes["transcription.input"],
                   input_format: span.attributes["transcription.input_format"] || "pcm",
                   output: span.attributes["transcription.output"],
                   model: span.attributes["transcription.model"],
                   model_config: span.attributes["transcription.model_config"]
                 }
               else
                 {
                   type: "custom",
                   name: span.name,
                   data: flatten_attributes(span.attributes)
                 }
               end

        # Remove nil values to match Python implementation
        data.compact
      end

      # Extracts model configuration from LLM span attributes
      #
      # @param span [Span] The LLM span
      # @return [Hash] Model configuration with nil values removed
      #
      # @api private
      def extract_model_config(span)
        {
          temperature: span.attributes["llm.request.temperature"],
          top_p: span.attributes["llm.request.top_p"],
          frequency_penalty: span.attributes["llm.request.frequency_penalty"],
          presence_penalty: span.attributes["llm.request.presence_penalty"],
          tool_choice: span.attributes["llm.request.tool_choice"],
          parallel_tool_calls: span.attributes["llm.request.parallel_tool_calls"],
          truncation: span.attributes["llm.request.truncation"],
          max_tokens: span.attributes["llm.request.max_tokens"],
          reasoning: span.attributes["llm.request.reasoning"],
          metadata: span.attributes["llm.request.metadata"],
          store: span.attributes["llm.request.store"],
          include_usage: span.attributes["llm.request.include_usage"],
          extra_query: span.attributes["llm.request.extra_query"],
          extra_body: span.attributes["llm.request.extra_body"],
          extra_headers: span.attributes["llm.request.extra_headers"],
          extra_args: span.attributes["llm.request.extra_args"],
          base_url: span.attributes["llm.request.base_url"] || "https://api.openai.com/v1/"
        }
      end

      # Extracts token usage from LLM span attributes
      #
      # @param span [Span] The LLM span
      # @return [Hash] Token usage data with nil values removed
      #
      # @api private
      def extract_usage(span)
        # Extract usage data, ensuring we have valid integers
        input_tokens = span.attributes["llm.usage.input_tokens"]
        output_tokens = span.attributes["llm.usage.output_tokens"]

        # Skip if we don't have valid token counts
        return nil if input_tokens.nil? || output_tokens.nil?
        return nil if input_tokens == 0 && output_tokens == 0

        {
          input_tokens: input_tokens.to_i,
          output_tokens: output_tokens.to_i
        }
      end

      # Formats LLM output as expected by OpenAI traces API
      #
      # @param span [Span] The LLM span
      # @return [Array<Hash>] Array of message objects
      #
      # @api private
      def format_llm_output(span)
        content = span.attributes["llm.response.content"]
        return [] unless content

        # The API expects an array of message objects for output (matching Python format)
        [{
          content: content,
          refusal: nil,
          role: "assistant",
          annotations: [],
          audio: nil,
          function_call: nil,
          tool_calls: nil
        }]
      end

      # Flattens nested attributes for custom span data
      #
      # Converts nested hashes into dot-notation keys and ensures
      # all values are strings for JSON serialization.
      # Limits the size of values to prevent exceeding OpenAI's 10KB limit.
      #
      # @param attributes [Hash] Span attributes to flatten
      # @return [Hash] Flattened attributes with string values
      #
      # @api private
      def flatten_attributes(attributes)
        result = {}
        max_value_size = 500 # Limit individual value size

        # Fields to exclude entirely to reduce payload size
        excluded_prefixes = [
          'pipeline.initial_context',
          'pipeline.final_result',
          'pipeline.result_keys',
          'agent.dialogue',
          'tool.large_output'
        ]

        attributes.each do |key, value|
          key_str = key.to_s

          # Skip excluded fields
          next if excluded_prefixes.any? { |prefix| key_str.start_with?(prefix) }

          case value
          when Hash
            value.each do |k, v|
              nested_key = "#{key}.#{k}"
              next if excluded_prefixes.any? { |prefix| nested_key.start_with?(prefix) }

              str_value = v.to_s
              # Truncate large values
              if str_value.length > max_value_size
                result[nested_key] = str_value[0...max_value_size] + "...[truncated]"
              else
                result[nested_key] = str_value
              end
            end
          when Array
            arr_str = value.inspect
            if arr_str.length > max_value_size
              result[key] = arr_str[0...max_value_size] + "...[truncated]"
            else
              result[key] = arr_str
            end
          else
            str_value = value.to_s
            if str_value.length > max_value_size
              result[key] = str_value[0...max_value_size] + "...[truncated]"
            else
              result[key] = str_value
            end
          end
        end
        result
      end

      # Flushes buffered spans to the OpenAI API
      #
      # @api private
      def flush_spans
        return if @span_buffer.empty?

        unless @api_key
          log_warn("OPENAI_API_KEY is not set, skipping trace export", processor: "OpenAI")
          return
        end

        spans_to_send = @span_buffer.dup
        @span_buffer.clear

        send_spans(spans_to_send)
      rescue StandardError => e
        if $DEBUG
          log_debug("Failed to send spans to OpenAI: #{e.message}", processor: "OpenAI",
                                                                    error_class: e.class.name)
        end
      end

      # Sends spans to the OpenAI traces API
      #
      # Constructs the HTTP request with proper authentication and formatting,
      # sends the trace data, and handles the response. Debug output can be
      # enabled via RAAF_DEBUG_CATEGORIES=http environment variable.
      #
      # @param spans [Array<Hash>] Transformed span data to send
      # @return [void]
      #
      # @api private
      def send_spans(spans)
        log_debug_api("[OpenAI Processor] Sending #{spans.size} spans to #{@traces_endpoint}", processor: "OpenAI",
                                                                                               span_count: spans.size)

        uri = URI(@traces_endpoint)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.set_debug_output($stdout) if http_debug_enabled?

        request = Net::HTTP::Post.new(uri)
        # Important: Clear any default User-Agent that Net::HTTP might set
        request.delete("User-Agent")
        request["Authorization"] = "Bearer #{@api_key}"
        request["Content-Type"] = "application/json"
        # DO NOT set User-Agent - Python SDK doesn't set it either
        request["OpenAI-Beta"] = "traces=v1"

        # Add optional headers if set (matching Python SDK)
        request["OpenAI-Organization"] = @organization if @organization
        request["OpenAI-Project"] = @project if @project

        # Based on the error, it seems the API expects a flatter structure
        # where each span is a separate item in the data array, not nested
        payload_items = []

        # First add the trace object (without spans)
        trace_data = {
          object: "trace",
          id: @current_trace_id,
          workflow_name: @workflow_name,
          group_id: nil,
          metadata: nil
        }
        payload_items << trace_data

        # Then add each span as a separate item, but ensure they don't exceed size limits
        spans.each do |span|
          # Ensure individual span data doesn't exceed limits
          sanitized_span = sanitize_span_data(span)
          payload_items << sanitized_span if sanitized_span
        end

        payload = {
          data: payload_items
        }

        request.body = JSON.generate(payload)

        log_debug_http("HTTP request details", processor: "OpenAI", url: uri.to_s)
        log_debug_http("HTTP request headers", processor: "OpenAI")
        request.each_header do |key, value|
          if key.downcase == "authorization" && value.start_with?("Bearer ")
            log_debug_http("Request header", key: key, value: "Bearer #{value[7..17]}...")
          else
            log_debug_http("Request header", key: key, value: value)
          end
        end
        log_debug_http("Payload structure", processor: "OpenAI")
        log_debug_http("Payload items", processor: "OpenAI", item_count: payload_items.size)
        log_debug_http("Trace object", trace_id: trace_data[:id], workflow: trace_data[:workflow_name])
        spans.each_with_index do |span, i|
          span_type = begin
            span[:span_data][:type]
          rescue StandardError
            "unknown"
          end
          span_name = begin
            span[:span_data][:name]
          rescue StandardError
            span[:id]
          end
          log_debug_http("Span info", processor: "OpenAI", index: i + 1, type: span_type, name: span_name)
        end
        log_debug_http("Full payload preview", payload: JSON.pretty_generate(payload)[0..1000])
        log_debug_http("End HTTP request debug", processor: "OpenAI")

        log_debug("Sending request to OpenAI traces API", processor: "OpenAI")
        start_time = Time.now
        response = http.request(request)
        duration = Time.now - start_time

        log_debug_http("HTTP response summary",
                       processor: "OpenAI",
                       code: response.code,
                       message: response.message,
                       duration_ms: (duration * 1000).round(2))

        log_debug_http("HTTP response details", processor: "OpenAI")
        log_debug_http("Response status", code: response.code, message: response.message)
        log_debug_http("HTTP response headers", processor: "OpenAI")
        response.each_header { |key, value| log_debug_http("Response header", key: key, value: value) }
        log_debug_http("Response body preview", body: response.body ? response.body[0..500] : "(empty)")
        log_debug_http("End HTTP response debug", processor: "OpenAI")

        if response.code.start_with?("2")
          log_debug("Successfully sent traces to OpenAI", processor: "OpenAI")
          if response.body && !response.body.empty?
            begin
              result = JSON.parse(response.body)
              log_debug_http("OpenAI response data", processor: "OpenAI", data: result.inspect)
            rescue JSON::ParserError
              # Response might be empty for 204 No Content
            end
          end
        else
          log_debug_http("OpenAI error response body", processor: "OpenAI", body: response.body)
          log_warn("OpenAI traces API error", processor: "OpenAI", code: response.code, body: response.body)
        end
      end
    end
  end
end
