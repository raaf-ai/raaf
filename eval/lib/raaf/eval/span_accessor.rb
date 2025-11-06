require "ostruct"
# frozen_string_literal: true

module RAAF
  module Eval
    ##
    # SpanAccessor provides query interface for RAAF tracing spans
    class SpanAccessor
      ##
      # Find span by ID
      # @param span_id [String] Span ID to find
      # @return [Object, nil] Span object or nil
      def find_by_id(span_id)
        # Mock implementation - would query raaf-tracing in real use
        stored_span = Models::EvaluationSpan.find_by(span_id: span_id)
        return nil unless stored_span

        # Return span-like object
        OpenStruct.new(stored_span.span_data.merge(span_id: span_id))
      end

      ##
      # Query spans by criteria
      # @param agent_name [String, nil] Filter by agent name
      # @param model [String, nil] Filter by model
      # @param time_range [Range, nil] Filter by time range
      # @param status [String, nil] Filter by status
      # @return [Array<Object>] Matching spans
      def query(agent_name: nil, model: nil, time_range: nil, status: nil)
        spans = Models::EvaluationSpan.all

        if agent_name
          spans = spans.where("span_data ->> 'agent_name' = ?", agent_name)
        end

        if model
          spans = spans.where("span_data ->> 'model' = ?", model)
        end

        if time_range
          spans = spans.where(created_at: time_range)
        end

        spans.map do |s|
          OpenStruct.new(s.span_data.merge(span_id: s.span_id))
        end
      end

      ##
      # Find spans by trace ID
      # @param trace_id [String] Trace ID
      # @return [Array<Object>] Spans in trace
      def find_by_trace(trace_id)
        Models::EvaluationSpan.by_trace(trace_id).map do |s|
          OpenStruct.new(s.span_data.merge(span_id: s.span_id))
        end
      end
    end
  end
end

require "ostruct"
