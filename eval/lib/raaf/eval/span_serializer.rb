# frozen_string_literal: true

module RAAF
  module Eval
    ##
    # SpanSerializer converts RAAF span objects into complete serialized form
    # for storage and reproduction.
    class SpanSerializer
      class << self
        ##
        # Serialize a RAAF span to storable format
        # @param span [Object] RAAF span object
        # @return [Hash] Serialized span data
        def serialize(span)
          {
            span_id: span.span_id,
            trace_id: span.trace_id,
            parent_span_id: span.parent_span_id,
            span_type: determine_span_type(span),
            agent_name: span.respond_to?(:agent_name) ? span.agent_name : nil,
            model: span.respond_to?(:model) ? span.model : nil,
            instructions: span.respond_to?(:instructions) ? span.instructions : nil,
            parameters: extract_parameters(span),
            input_messages: extract_messages(span, :input),
            output_messages: extract_messages(span, :output),
            tool_calls: extract_tool_calls(span),
            handoffs: extract_handoffs(span),
            context_variables: extract_context(span),
            provider_details: extract_provider_details(span),
            metadata: extract_metadata(span),
            error_info: extract_error_info(span),
            timestamps: extract_timestamps(span)
          }
        end

        private

        def determine_span_type(span)
          return "agent" if span.respond_to?(:agent_name)
          return "tool" if span.respond_to?(:tool_name)
          return "handoff" if span.respond_to?(:target_agent)
          "response"
        end

        def extract_parameters(span)
          return {} unless span.respond_to?(:parameters)
          span.parameters || {}
        end

        def extract_messages(span, direction)
          method_name = "#{direction}_messages"
          return [] unless span.respond_to?(method_name)
          
          messages = span.send(method_name) || []
          messages.map do |msg|
            {
              role: msg[:role] || msg["role"],
              content: msg[:content] || msg["content"],
              tool_calls: msg[:tool_calls] || msg["tool_calls"],
              tool_call_id: msg[:tool_call_id] || msg["tool_call_id"],
              name: msg[:name] || msg["name"]
            }.compact
          end
        end

        def extract_tool_calls(span)
          return [] unless span.respond_to?(:tool_calls)
          
          tool_calls = span.tool_calls || []
          tool_calls.map do |tc|
            {
              tool_name: tc[:tool_name] || tc["tool_name"],
              arguments: tc[:arguments] || tc["arguments"],
              result: tc[:result] || tc["result"],
              error: tc[:error] || tc["error"],
              duration_ms: tc[:duration_ms] || tc["duration_ms"]
            }.compact
          end
        end

        def extract_handoffs(span)
          return [] unless span.respond_to?(:handoffs)
          
          handoffs = span.handoffs || []
          handoffs.map do |h|
            {
              target_agent: h[:target_agent] || h["target_agent"],
              context_passed: h[:context_passed] || h["context_passed"],
              reason: h[:reason] || h["reason"]
            }.compact
          end
        end

        def extract_context(span)
          return {} unless span.respond_to?(:context_variables)
          span.context_variables || {}
        end

        def extract_provider_details(span)
          return {} unless span.respond_to?(:provider_details)
          span.provider_details || {}
        end

        def extract_metadata(span)
          metadata = {}
          metadata[:tokens] = span.total_tokens if span.respond_to?(:total_tokens)
          metadata[:input_tokens] = span.input_tokens if span.respond_to?(:input_tokens)
          metadata[:output_tokens] = span.output_tokens if span.respond_to?(:output_tokens)
          metadata[:reasoning_tokens] = span.reasoning_tokens if span.respond_to?(:reasoning_tokens)
          metadata[:latency_ms] = span.latency_ms if span.respond_to?(:latency_ms)
          metadata[:cost] = span.cost if span.respond_to?(:cost)
          metadata
        end

        def extract_error_info(span)
          return nil unless span.respond_to?(:error) && span.error
          {
            message: span.error[:message] || span.error["message"],
            type: span.error[:type] || span.error["type"],
            backtrace: span.error[:backtrace] || span.error["backtrace"]
          }.compact
        end

        def extract_timestamps(span)
          {
            start_time: span.respond_to?(:start_time) ? span.start_time : nil,
            end_time: span.respond_to?(:end_time) ? span.end_time : nil
          }.compact
        end
      end
    end
  end
end
