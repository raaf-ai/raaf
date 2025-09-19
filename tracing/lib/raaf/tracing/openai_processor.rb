# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require "set"
require_relative "version"
require_relative "base_processor"

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
    class OpenAIProcessor < BaseProcessor
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
        # Store OpenAI-specific options for post_initialize
        @openai_options = {
          api_key: api_key,
          base_url: base_url,
          workflow_name: workflow_name,
          organization: organization,
          project: project
        }

        # Initialize base processor with OpenAI options
        super(batch_size: batch_size, **@openai_options)
      end

      # Hook for OpenAI-specific initialization after BaseProcessor setup
      #
      # @param options [Hash] Options passed to initialize
      # @return [void]
      def post_initialize(options)
        # OpenAI-specific initialization
        @api_key = options[:api_key] || ENV.fetch("OPENAI_API_KEY", nil)

        raise ArgumentError, "api_key is required (provide via parameter or OPENAI_API_KEY env var)" unless @api_key

        @organization = options[:organization] || ENV.fetch("OPENAI_ORG_ID", nil)
        @project = options[:project] || ENV.fetch("OPENAI_PROJECT_ID", nil)
        @base_url = options[:base_url] || "https://api.openai.com"
        @traces_endpoint = "#{@base_url}/v1/traces/ingest"
        @workflow_name = options[:workflow_name] || "openai-agents-ruby"
        @current_trace_id = nil

        log_debug("#{self.class.name} initialized",
                  processor: self.class.name,
                  base_url: @base_url,
                  workflow_name: @workflow_name)
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

      protected

      # Determines if a span should be processed by OpenAI
      #
      # OpenAI requires spans to have end_time to mark them as completed.
      # Unfinished spans will cause perpetual "Running" status.
      #
      # @param span [Span] The span to evaluate
      # @return [Boolean] true if span should be processed
      def should_process?(span)
        # Extract values in a way that works for both Span objects and sanitized hashes
        end_time = span.is_a?(Hash) ? span[:end_time] : span.end_time
        trace_id = span.is_a?(Hash) ? span[:trace_id] : span.trace_id
        kind = span.is_a?(Hash) ? span[:kind] : span.kind
        attributes = span.is_a?(Hash) ? (span[:attributes] || {}) : (span.attributes || {})

        return false unless end_time

        # Update trace context for this span
        @current_trace_id ||= trace_id

        # Handle trace spans specially - extract workflow name
        if kind == :trace && attributes["trace.workflow_name"]
          @workflow_name = attributes["trace.workflow_name"]
        end

        true
      end

      # Transforms a span to OpenAI format
      #
      # @param span [Span] The span to transform
      # @return [Hash, nil] Transformed span data or nil if should be skipped
      def process_span(span)
        transform_span(span)
      end

      # Exports a batch of spans to OpenAI
      #
      # @param spans [Array] Array of transformed span data
      # @return [void]
      def export_batch(spans)
        send_spans(spans)
      end

      private

      # Transforms a Ruby span object or hash into OpenAI's expected format
      #
      # @param span [Span, Hash] The span to transform (can be Span object or sanitized hash)
      # @return [Hash, nil] Transformed span data or nil if span should be skipped
      #
      # @api private
      def transform_span(span)
        # Extract values in a way that works for both Span objects and sanitized hashes
        kind = span.is_a?(Hash) ? span[:kind] : span.kind
        span_id = span.is_a?(Hash) ? span[:span_id] : span.span_id
        trace_id = span.is_a?(Hash) ? span[:trace_id] : span.trace_id
        parent_id = span.is_a?(Hash) ? span[:parent_id] : span.parent_id
        start_time = span.is_a?(Hash) ? span[:start_time] : span.start_time
        end_time = span.is_a?(Hash) ? span[:end_time] : span.end_time
        attributes = span.is_a?(Hash) ? (span[:attributes] || {}) : (span.attributes || {})

        # Skip trace spans - they're handled separately
        return nil if kind == :trace

        # Skip LLM spans without valid usage data
        if kind == :llm
          usage = extract_usage(span)
          return nil unless usage # OpenAI API requires usage data for LLM spans
        end

        # Create the span object with required fields
        span_data = create_span_data(span)
        return nil unless span_data

        {
          object: "trace.span",
          id: span_id,
          trace_id: trace_id,
          parent_id: parent_id,
          started_at: start_time&.utc&.strftime("%Y-%m-%dT%H:%M:%S.%6N+00:00"),
          ended_at: end_time&.utc&.strftime("%Y-%m-%dT%H:%M:%S.%6N+00:00"),
          span_data: span_data,
          error: attributes["error"] || nil
        }
      end

      # Creates type-specific span data based on span kind
      #
      # Each span type has specific fields required by the OpenAI API.
      # This method extracts the appropriate attributes and formats them
      # according to the API specification.
      #
      # @param span [Span, Hash] The span to process (can be Span object or sanitized hash)
      # @return [Hash, nil] Type-specific span data or nil
      #
      # @api private
      def create_span_data(span)
        # Extract values in a way that works for both Span objects and sanitized hashes
        kind = span.is_a?(Hash) ? span[:kind] : span.kind
        name = span.is_a?(Hash) ? span[:name] : span.name
        attributes = span.is_a?(Hash) ? (span[:attributes] || {}) : (span.attributes || {})

        data = case kind
               when :trace
                 # Trace spans are handled differently - they become the trace object
                 return nil
               when :agent
                 {
                   type: "agent",
                   name: attributes["agent.name"] || name,
                   handoffs: attributes["agent.handoffs"] || [],
                   tools: attributes["agent.tools"] || [],
                   output_type: attributes["agent.output_type"] || "str"
                 }.compact
               when :llm
                 # Get input messages as array for OpenAI API compatibility
                 input_messages = attributes["llm.request.messages"] || []
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
                   model: attributes["llm.request.model"],
                   model_config: extract_model_config(span)
                 }
                 # Only include usage if we have valid data
                 usage = extract_usage(span)
                 data[:usage] = usage if usage
                 data
               when :tool
                 # Ensure input is a string for OpenAI API compatibility
                 tool_input = attributes["function.input"]
                 input_string = case tool_input
                                when String then tool_input
                                when nil then nil
                                else JSON.generate(tool_input)
                                end

                 {
                   type: "function",
                   name: attributes["function.name"] || name,
                   input: input_string,
                   output: attributes["function.output"],
                   mcp_data: attributes["function.mcp_data"]
                 }
               when :handoff
                 {
                   type: "handoff",
                   from_agent: attributes["handoff.from"],
                   to_agent: attributes["handoff.to"]
                 }
               when :guardrail
                 {
                   type: "guardrail",
                   name: attributes["guardrail.name"] || name,
                   triggered: attributes["guardrail.triggered"] || false
                 }
               when :mcp_list_tools
                 {
                   type: "mcp_tools",
                   server: attributes["mcp.server"],
                   result: attributes["mcp.result"] || attributes["mcp.tools"] || []
                 }
               when :response
                 {
                   type: "response",
                   response_id: attributes["response_id"]
                 }.compact
               when :speech_group
                 {
                   type: "speech_group",
                   input: attributes["speech_group.input"]
                 }
               when :speech
                 {
                   type: "speech",
                   input: attributes["speech.input"],
                   output: attributes["speech.output"],
                   output_format: attributes["speech.output_format"] || "pcm",
                   model: attributes["speech.model"],
                   model_config: attributes["speech.model_config"],
                   first_content_at: attributes["speech.first_content_at"]
                 }
               when :transcription
                 {
                   type: "transcription",
                   input: attributes["transcription.input"],
                   input_format: attributes["transcription.input_format"] || "pcm",
                   output: attributes["transcription.output"],
                   model: attributes["transcription.model"],
                   model_config: attributes["transcription.model_config"]
                 }
               else
                 {
                   type: "custom",
                   name: name,
                   data: flatten_attributes(attributes)
                 }
               end

        # Remove nil values to match Python implementation
        data.compact
      end

      # Extracts model configuration from LLM span attributes
      #
      # @param span [Span, Hash] The LLM span (can be Span object or sanitized hash)
      # @return [Hash] Model configuration with nil values removed
      #
      # @api private
      def extract_model_config(span)
        # Extract attributes in a way that works for both Span objects and sanitized hashes
        attributes = span.is_a?(Hash) ? (span[:attributes] || {}) : (span.attributes || {})

        {
          temperature: attributes["llm.request.temperature"],
          top_p: attributes["llm.request.top_p"],
          frequency_penalty: attributes["llm.request.frequency_penalty"],
          presence_penalty: attributes["llm.request.presence_penalty"],
          tool_choice: attributes["llm.request.tool_choice"],
          parallel_tool_calls: attributes["llm.request.parallel_tool_calls"],
          truncation: attributes["llm.request.truncation"],
          max_tokens: attributes["llm.request.max_tokens"],
          reasoning: attributes["llm.request.reasoning"],
          metadata: attributes["llm.request.metadata"],
          store: attributes["llm.request.store"],
          include_usage: attributes["llm.request.include_usage"],
          extra_query: attributes["llm.request.extra_query"],
          extra_body: attributes["llm.request.extra_body"],
          extra_headers: attributes["llm.request.extra_headers"],
          extra_args: attributes["llm.request.extra_args"],
          base_url: attributes["llm.request.base_url"] || "https://api.openai.com/v1/"
        }
      end

      # Extracts token usage from LLM span attributes
      #
      # @param span [Span, Hash] The LLM span (can be Span object or sanitized hash)
      # @return [Hash] Token usage data with nil values removed
      #
      # @api private
      def extract_usage(span)
        # Extract attributes in a way that works for both Span objects and sanitized hashes
        attributes = span.is_a?(Hash) ? (span[:attributes] || {}) : (span.attributes || {})

        # Extract usage data, ensuring we have valid integers
        input_tokens = attributes["llm.usage.input_tokens"]
        output_tokens = attributes["llm.usage.output_tokens"]

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
      # @param span [Span, Hash] The LLM span (can be Span object or sanitized hash)
      # @return [Array<Hash>] Array of message objects
      #
      # @api private
      def format_llm_output(span)
        # Extract attributes in a way that works for both Span objects and sanitized hashes
        attributes = span.is_a?(Hash) ? (span[:attributes] || {}) : (span.attributes || {})

        content = attributes["llm.response.content"]
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

      # Sanitizes span data to ensure it doesn't exceed OpenAI's size limits
      #
      # @param span [Hash] The span to sanitize
      # @return [Hash, nil] Sanitized span or nil if it can't be made small enough
      #
      # @api private
      def sanitize_span_data(span)
        # Maximum size for individual span data (keeping it under 9KB to be safe)
        max_span_size = 9000

        # First, get the JSON size (with safe generation to avoid circular references)
        json_size = safe_json_generate(span).bytesize

        # If it's already small enough, return as-is
        return span if json_size <= max_span_size

        # Make a deep copy to avoid modifying the original
        sanitized = Marshal.load(Marshal.dump(span))

        # For custom spans with large data fields, truncate aggressively
        if sanitized[:span_data] && sanitized[:span_data][:type] == "custom"
          data = sanitized[:span_data][:data]
          if data.is_a?(Hash)
            # Keep only essential fields for custom spans
            essential_fields = %w[
              pipeline.name pipeline.class pipeline.agent_count
              pipeline.execution_mode pipeline.success pipeline.agents_executed
              duration_ms error
            ]

            filtered_data = {}
            data.each do |key, value|
              if essential_fields.any? { |field| key.to_s.start_with?(field) }
                # Truncate even essential field values if too large
                value_str = value.to_s
                if value_str.length > 200
                  filtered_data[key] = value_str[0...200] + "...[truncated]"
                else
                  filtered_data[key] = value_str
                end
              end
            end

            sanitized[:span_data][:data] = filtered_data
          end
        end

        # For LLM spans, truncate input/output messages
        if sanitized[:span_data] && sanitized[:span_data][:type] == "generation"
          # Truncate input messages
          if sanitized[:span_data][:input].is_a?(Array)
            sanitized[:span_data][:input] = sanitized[:span_data][:input].map do |msg|
              if msg.is_a?(Hash) && msg["content"]
                content = msg["content"].to_s
                if content.length > 500
                  msg.merge("content" => content[0...500] + "...[truncated]")
                else
                  msg
                end
              else
                msg
              end
            end
          end

          # Truncate output
          if sanitized[:span_data][:output].is_a?(Array)
            sanitized[:span_data][:output] = sanitized[:span_data][:output].map do |msg|
              if msg.is_a?(Hash) && msg[:content]
                content = msg[:content].to_s
                if content.length > 500
                  msg.merge(content: content[0...500] + "...[truncated]")
                else
                  msg
                end
              else
                msg
              end
            end
          end
        end

        # For tool/function spans, truncate input/output
        if sanitized[:span_data] && sanitized[:span_data][:type] == "function"
          if sanitized[:span_data][:input]
            input_str = sanitized[:span_data][:input].to_s
            if input_str.length > 500
              sanitized[:span_data][:input] = input_str[0...500] + "...[truncated]"
            end
          end

          if sanitized[:span_data][:output]
            output_str = sanitized[:span_data][:output].to_s
            if output_str.length > 500
              sanitized[:span_data][:output] = output_str[0...500] + "...[truncated]"
            end
          end
        end

        # Final check - if still too large, return minimal span
        final_size = safe_json_generate(sanitized).bytesize
        if final_size > max_span_size
          log_warn("Span still too large after sanitization (#{final_size} bytes), sending minimal data",
                   processor: "OpenAI",
                   span_id: span[:id],
                   original_size: json_size,
                   final_size: final_size)

          # Return absolute minimum span data
          {
            object: "trace.span",
            id: span[:id],
            trace_id: span[:trace_id],
            parent_id: span[:parent_id],
            started_at: span[:started_at],
            ended_at: span[:ended_at],
            span_data: {
              type: span[:span_data][:type] || "custom",
              name: span[:span_data][:name] || "unknown",
              data: { truncated: true, original_size: json_size }
            },
            error: span[:error]
          }
        else
          sanitized
        end
      rescue StandardError => e
        log_error("Failed to sanitize span data: #{e.message}",
                  processor: "OpenAI",
                  error_class: e.class.name)
        nil
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
        # Calculate trace end time from the latest span end time
        trace_ended_at = nil
        if spans.any?
          latest_end_time = spans.map { |span|
            # Extract end time from the span data
            if span.is_a?(Hash) && span.dig(:ended_at)
              Time.parse(span[:ended_at]) rescue nil
            end
          }.compact.max

          trace_ended_at = latest_end_time&.utc&.strftime("%Y-%m-%dT%H:%M:%S.%6N+00:00")
        end

        trace_data = {
          object: "trace",
          id: @current_trace_id,
          workflow_name: @workflow_name,
          group_id: nil,
          metadata: nil
          # Note: OpenAI API doesn't accept 'ended_at' field in trace objects
        }

        log_debug("[OpenAI Processor] Sending trace with #{spans.size} spans",
                 processor: "OpenAI", trace_id: @current_trace_id,
                 spans_count: spans.size, trace_ended_at: trace_ended_at || "not_set")
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

        request.body = safe_json_generate(payload)

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

      # Safely generates JSON with circular reference protection
      #
      # @param data [Object] Data to convert to JSON
      # @return [String] JSON string with circular references replaced
      def safe_json_generate(data)
        sanitized_data = deep_sanitize_for_json(data)
        JSON.generate(sanitized_data)
      rescue StandardError => e
        log_error("Failed to generate JSON: #{e.message}", processor: "OpenAI")
        JSON.generate({ error: "Failed to serialize data", message: e.message })
      end

      # Deep sanitization for JSON conversion with circular reference protection
      #
      # @param obj [Object] Object to sanitize
      # @param visited [Set] Set of visited object IDs
      # @return [Object] Sanitized object safe for JSON conversion
      def deep_sanitize_for_json(obj, visited = Set.new)
        # Handle circular references by tracking object IDs
        if obj.is_a?(Hash) || obj.is_a?(Array)
          object_id = obj.object_id
          return "[CIRCULAR_REFERENCE]" if visited.include?(object_id)
          visited = visited.dup.add(object_id)
        end

        case obj
        when Hash
          result = {}
          obj.each do |key, value|
            result[key.to_s] = deep_sanitize_for_json(value, visited)
          end
          result
        when Array
          obj.map { |item| deep_sanitize_for_json(item, visited) }
        when String, Integer, Float, TrueClass, FalseClass, NilClass
          obj
        else
          # Convert other objects to string to avoid serialization issues
          obj.to_s
        end
      end
    end
  end
end
