# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require_relative "../version"

module OpenAIAgents
  module Tracing
    # OpenAI Platform Processor - Sends spans to OpenAI's traces ingestion endpoint
    #
    # This processor sends span data to OpenAI's tracing backend for visualization
    # in the OpenAI platform dashboard at https://platform.openai.com/traces
    class OpenAIProcessor
      def initialize(api_key: nil, base_url: nil, batch_size: 50, workflow_name: nil, organization: nil, project: nil)
        @api_key = api_key || ENV["OPENAI_API_KEY"]
        @organization = organization || ENV["OPENAI_ORG_ID"]
        @project = project || ENV["OPENAI_PROJECT_ID"]
        @base_url = base_url || "https://api.openai.com"
        @traces_endpoint = "#{@base_url}/v1/traces/ingest"
        @batch_size = batch_size
        @span_buffer = []
        @mutex = Mutex.new
        @workflow_name = workflow_name || "openai-agents-ruby"
        @current_trace_id = nil
      end

      def on_span_start(span)
        # OpenAI processes spans on completion, not on start
      end

      def on_span_end(span)
        @mutex.synchronize do
          @current_trace_id ||= span.trace_id
          @span_buffer << transform_span(span)
          
          if @span_buffer.size >= @batch_size
            flush_spans
          end
        end
      end

      # Export a batch of spans (called by BatchTraceProcessor)
      def export(spans)
        return if spans.empty?
        
        unless @api_key
          warn "OPENAI_API_KEY is not set, skipping trace export"
          return
        end
        
        # Group spans by trace_id
        spans_by_trace = spans.group_by(&:trace_id)
        
        spans_by_trace.each do |trace_id, trace_spans|
          @current_trace_id = trace_id
          transformed_spans = trace_spans.map { |span| transform_span(span) }
          send_spans(transformed_spans)
        end
      rescue StandardError => e
        warn "Failed to export spans to OpenAI: #{e.message}" 
        warn e.backtrace.first(5).join("\n") if ENV["OPENAI_AGENTS_TRACE_DEBUG"] == "true"
      end

      # Force flush any remaining spans
      def force_flush
        @mutex.synchronize do
          flush_spans if @span_buffer.any?
        end
      end
      
      def shutdown
        force_flush
      end

      private

      def transform_span(span)
        # Create the span object with required fields
        {
          object: "trace.span",
          id: span.span_id,
          trace_id: span.trace_id,
          started_at: span.start_time.utc.strftime('%Y-%m-%dT%H:%M:%S.%3NZ'),
          ended_at: span.end_time&.utc&.strftime('%Y-%m-%dT%H:%M:%S.%3NZ'),
          span_data: create_span_data(span)
        }
      end

      def create_span_data(span)
        data = case span.kind
        when :agent
          {
            type: "agent",
            name: span.attributes["agent.name"] || span.name,
            handoffs: span.attributes["agent.handoffs"] || [],
            tools: span.attributes["agent.tools"] || [],
            output_type: span.attributes["agent.output_type"] || "text"
          }
        when :llm
          {
            type: "generation",
            input: span.attributes["llm.request.messages"] || [],
            output: format_llm_output(span),
            model: span.attributes["llm.request.model"] || span.attributes["llm.model"],
            model_config: extract_model_config(span),
            usage: extract_usage(span)
          }
        when :tool
          {
            type: "function",
            name: span.attributes["function.name"] || span.attributes["tool.name"] || span.name,
            input: span.attributes["function.input"] || span.attributes["tool.arguments"],
            output: span.attributes["function.output"] || span.attributes["tool.result"]
          }
        when :handoff
          {
            type: "handoff",
            from_agent: span.attributes["handoff.from"],
            to_agent: span.attributes["handoff.to"]
          }
        else
          {
            type: "custom",
            name: span.name,
            data: flatten_attributes(span.attributes)
          }
        end
        
        # Don't include parent_span_id in span_data - the API doesn't accept it there
        data
      end


      def extract_model_config(span)
        {
          max_tokens: span.attributes["llm.request.max_tokens"],
          temperature: span.attributes["llm.request.temperature"]
        }.compact
      end

      def extract_usage(span)
        {
          input_tokens: span.attributes["llm.usage.prompt_tokens"],
          output_tokens: span.attributes["llm.usage.completion_tokens"]
        }.compact
      end

      def format_llm_output(span)
        content = span.attributes["llm.response.content"]
        return [] unless content
        
        # The API expects an array of message objects for output
        [{
          role: "assistant",
          content: content
        }]
      end

      def flatten_attributes(attributes)
        result = {}
        attributes.each do |key, value|
          case value
          when Hash
            value.each { |k, v| result["#{key}.#{k}"] = v.to_s }
          when Array
            result[key] = value.inspect
          else
            result[key] = value.to_s
          end
        end
        result
      end

      def flush_spans
        return if @span_buffer.empty?
        
        unless @api_key
          warn "OPENAI_API_KEY is not set, skipping trace export"
          return
        end

        spans_to_send = @span_buffer.dup
        @span_buffer.clear

        send_spans(spans_to_send)
      rescue StandardError => e
        warn "Failed to send spans to OpenAI: #{e.message}" if $DEBUG
      end

      def send_spans(spans)
        debug = ENV["OPENAI_AGENTS_TRACE_DEBUG"] == "true"
        
        puts "[OpenAI Processor] Sending #{spans.size} spans to #{@traces_endpoint}"
        
        uri = URI(@traces_endpoint)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.set_debug_output($stdout) if debug

        request = Net::HTTP::Post.new(uri)
        # Important: Clear any default User-Agent that Net::HTTP might set
        request.delete('User-Agent')
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
          metadata: {
            "sdk.language" => "ruby",
            "sdk.version" => OpenAIAgents::VERSION
          }
        }
        payload_items << trace_data
        
        # Then add each span as a separate item
        spans.each do |span|
          payload_items << span
        end

        payload = {
          data: payload_items
        }
        
        request.body = JSON.generate(payload)

        if debug
          puts "\n[OpenAI Processor] === DEBUG: HTTP Request Details ==="
          puts "URL: #{uri}"
          puts "Headers:"
          request.each_header { |key, value| 
            if key.downcase == 'authorization' && value.start_with?('Bearer ')
              puts "  #{key}: Bearer #{value[7..17]}..."
            else
              puts "  #{key}: #{value}"
            end
          }
          puts "\nPayload Structure:"
          puts "  - Data array contains #{payload_items.size} items:"
          puts "    [0] Trace object - ID: #{trace_data[:id]}, Workflow: #{trace_data[:workflow_name]}"
          spans.each_with_index do |span, i|
            span_type = span[:span_data][:type] rescue "unknown"
            span_name = span[:span_data][:name] rescue span[:id]
            puts "    [#{i+1}] Span - #{span_type} - #{span_name}"
          end
          puts "\nFull Payload (first 1000 chars):"
          puts JSON.pretty_generate(payload)[0..1000]
          puts "=== End DEBUG ===" 
        end

        puts "[OpenAI Processor] Sending request to OpenAI traces API..."
        start_time = Time.now
        response = http.request(request)
        duration = Time.now - start_time
        
        puts "[OpenAI Processor] Response: #{response.code} - #{response.message} (#{(duration * 1000).round(2)}ms)"
        
        if debug
          puts "\n[OpenAI Processor] === DEBUG: HTTP Response Details ==="
          puts "Status: #{response.code} #{response.message}"
          puts "Headers:"
          response.each_header { |key, value| puts "  #{key}: #{value}" }
          puts "\nBody (first 500 chars):"
          puts response.body ? response.body[0..500] : "(empty)"
          puts "=== End DEBUG ===" 
        end
        
        unless response.code.start_with?("2")
          puts "[OpenAI Processor] Error body: #{response.body}"
          warn "OpenAI traces API returned #{response.code}: #{response.body}"
        else
          puts "[OpenAI Processor] ✅ Successfully sent traces to OpenAI"
          if debug && response.body && !response.body.empty?
            begin
              result = JSON.parse(response.body)
              puts "[OpenAI Processor] Response data: #{result.inspect}"
            rescue JSON::ParserError
              # Response might be empty for 204 No Content
            end
          end
        end
      end
    end
  end
end