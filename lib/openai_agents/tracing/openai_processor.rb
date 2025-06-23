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
      def initialize(api_key: nil, base_url: nil, batch_size: 50, workflow_name: nil)
        @api_key = api_key || ENV["OPENAI_API_KEY"]
        @base_url = base_url || "https://api.openai.com/v1"
        @traces_endpoint = "#{@base_url}/v1/traces/ingest"
        @batch_size = batch_size
        @span_buffer = []
        @mutex = Mutex.new
        @workflow_name = workflow_name || "openai-agents-ruby"
        @current_trace_id = nil
      end

      def on_start(span)
        # OpenAI processes spans on completion, not on start
      end

      def on_end(span)
        @mutex.synchronize do
          @current_trace_id ||= span.trace_id
          @span_buffer << transform_span(span)
          
          if @span_buffer.size >= @batch_size
            flush_spans
          end
        end
      end

      # Force flush any remaining spans
      def flush
        @mutex.synchronize do
          flush_spans if @span_buffer.any?
        end
      end

      private

      def transform_span(span)
        {
          object: "span",
          id: span.span_id,
          trace_id: span.trace_id,
          parent_id: span.parent_id,
          name: span.name,
          started_at: span.start_time.utc.iso8601,
          ended_at: span.end_time&.utc&.iso8601,
          span_data: create_span_data(span)
        }
      end

      def create_span_data(span)
        case span.kind
        when :agent
          {
            type: "agent",
            name: span.attributes["agent.name"] || span.name,
            handoffs: extract_handoffs(span),
            tools: extract_tools(span),
            output_type: "text"
          }
        when :llm
          {
            type: "generation",
            input: extract_llm_input(span),
            output: extract_llm_output(span),
            model: span.attributes["llm.model"],
            model_config: extract_model_config(span),
            usage: extract_usage(span)
          }
        when :tool
          {
            type: "function",
            name: span.attributes["tool.name"] || span.name,
            input: span.attributes["tool.arguments"],
            output: span.attributes["tool.result"]
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
      end

      def extract_handoffs(span)
        # Extract handoff information from span attributes
        []
      end

      def extract_tools(span)
        # Extract tool information from span attributes
        []
      end

      def extract_llm_input(span)
        span.attributes["llm.request.messages"] || []
      end

      def extract_llm_output(span)
        span.attributes["llm.response.content"] || ""
      end

      def extract_model_config(span)
        {
          max_tokens: span.attributes["llm.request.max_tokens"],
          temperature: span.attributes["llm.request.temperature"]
        }.compact
      end

      def extract_usage(span)
        {
          prompt_tokens: span.attributes["llm.usage.prompt_tokens"],
          completion_tokens: span.attributes["llm.usage.completion_tokens"],
          total_tokens: span.attributes["llm.usage.total_tokens"]
        }.compact
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
        return if @span_buffer.empty? || !@api_key

        spans_to_send = @span_buffer.dup
        @span_buffer.clear

        send_spans(spans_to_send)
      rescue StandardError => e
        warn "Failed to send spans to OpenAI: #{e.message}" if $DEBUG
      end

      def send_spans(spans)
        uri = URI(@traces_endpoint)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{@api_key}"
        request["Content-Type"] = "application/json"
        request["User-Agent"] = "openai-agents-ruby/#{OpenAIAgents::VERSION}"
        request["OpenAI-Beta"] = "traces=v1"

        # Create trace data according to Python implementation
        trace_data = {
          object: "trace",
          id: @current_trace_id,
          workflow_name: @workflow_name,
          metadata: {
            "sdk.language" => "ruby",
            "sdk.version" => OpenAIAgents::VERSION
          }
        }

        request.body = JSON.generate({
          data: [trace_data] + spans
        })

        response = http.request(request)
        
        unless response.code.start_with?("2")
          warn "OpenAI traces API returned #{response.code}: #{response.body}" if $DEBUG
        end
      end
    end
  end
end