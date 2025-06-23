# frozen_string_literal: true

module OpenAIAgents
  module Tracing
    # OpenTelemetry adapter for OpenAI Agents tracing
    # This provides compatibility with OpenTelemetry exporters and conventions
    class OTelAdapter
      # Maps OpenAI Agents span kinds to OpenTelemetry span kinds
      SPAN_KIND_MAP = {
        agent: :internal,
        llm: :client,
        tool: :internal,
        handoff: :internal,
        internal: :internal
      }.freeze

      # Convert OpenAI Agents span to OpenTelemetry-compatible format
      def self.to_otel_span(span)
        {
          trace_id: normalize_trace_id(span.trace_id),
          span_id: normalize_span_id(span.span_id),
          parent_span_id: span.parent_id ? normalize_span_id(span.parent_id) : nil,
          name: span.name,
          kind: SPAN_KIND_MAP[span.kind] || :internal,
          start_time: span.start_time.to_i * 1_000_000_000, # Convert to nanoseconds
          end_time: span.end_time ? span.end_time.to_i * 1_000_000_000 : nil,
          attributes: transform_attributes(span.attributes),
          events: transform_events(span.events),
          status: transform_status(span.status),
          resource: {
            "service.name" => "openai-agents-ruby",
            "service.version" => OpenAIAgents::VERSION,
            "telemetry.sdk.name" => "openai-agents-ruby",
            "telemetry.sdk.language" => "ruby",
            "telemetry.sdk.version" => OpenAIAgents::VERSION
          }
        }
      end

      # Convert batch of spans to OTLP format
      def self.to_otlp_batch(spans)
        resource_spans = spans.group_by(&:trace_id).map do |trace_id, trace_spans|
          {
            resource: {
              attributes: [
                { key: "service.name", value: { string_value: "openai-agents-ruby" } },
                { key: "service.version", value: { string_value: OpenAIAgents::VERSION } },
                { key: "telemetry.sdk.name", value: { string_value: "openai-agents-ruby" } },
                { key: "telemetry.sdk.language", value: { string_value: "ruby" } },
                { key: "telemetry.sdk.version", value: { string_value: OpenAIAgents::VERSION } }
              ]
            },
            scope_spans: [
              {
                scope: {
                  name: "openai-agents",
                  version: OpenAIAgents::VERSION
                },
                spans: trace_spans.map { |span| to_otlp_span(span) }
              }
            ]
          }
        end

        {
          resource_spans: resource_spans
        }
      end

      private

      def self.normalize_trace_id(trace_id)
        # OpenTelemetry expects 32 hex chars (128 bits)
        trace_id.gsub(/[^a-f0-9]/i, "").rjust(32, "0")[0..31]
      end

      def self.normalize_span_id(span_id)
        # OpenTelemetry expects 16 hex chars (64 bits)
        span_id.gsub(/[^a-f0-9]/i, "").rjust(16, "0")[0..15]
      end

      def self.transform_attributes(attributes)
        attributes.map do |key, value|
          {
            key: key.to_s,
            value: attribute_value(value)
          }
        end
      end

      def self.attribute_value(value)
        case value
        when String
          { string_value: value }
        when Integer
          { int_value: value }
        when Float
          { double_value: value }
        when TrueClass, FalseClass
          { bool_value: value }
        when Array
          { array_value: { values: value.map { |v| attribute_value(v) } } }
        when Hash
          { kvlist_value: { values: value.map { |k, v| { key: k.to_s, value: attribute_value(v) } } } }
        else
          { string_value: value.to_s }
        end
      end

      def self.transform_events(events)
        events.map do |event|
          {
            time_unix_nano: Time.parse(event[:timestamp]).to_i * 1_000_000_000,
            name: event[:name],
            attributes: transform_attributes(event[:attributes] || {})
          }
        end
      end

      def self.transform_status(status)
        case status
        when :ok
          { code: 1 } # OK
        when :error
          { code: 2 } # ERROR
        else
          { code: 0 } # UNSET
        end
      end

      def self.to_otlp_span(span)
        otel_span = to_otel_span(span)
        {
          trace_id: hex_to_bytes(otel_span[:trace_id]),
          span_id: hex_to_bytes(otel_span[:span_id]),
          parent_span_id: otel_span[:parent_span_id] ? hex_to_bytes(otel_span[:parent_span_id]) : nil,
          name: otel_span[:name],
          kind: span_kind_to_otlp(otel_span[:kind]),
          start_time_unix_nano: otel_span[:start_time],
          end_time_unix_nano: otel_span[:end_time],
          attributes: otel_span[:attributes],
          events: otel_span[:events],
          status: otel_span[:status]
        }.compact
      end

      def self.hex_to_bytes(hex_string)
        [hex_string].pack("H*")
      end

      def self.span_kind_to_otlp(kind)
        case kind
        when :internal
          1 # SPAN_KIND_INTERNAL
        when :server
          2 # SPAN_KIND_SERVER
        when :client
          3 # SPAN_KIND_CLIENT
        when :producer
          4 # SPAN_KIND_PRODUCER
        when :consumer
          5 # SPAN_KIND_CONSUMER
        else
          0 # SPAN_KIND_UNSPECIFIED
        end
      end
    end

    # OpenTelemetry-compatible span processor
    class OTelProcessor
      def initialize(exporter)
        @exporter = exporter
      end

      def on_span_start(span)
        # Most OTEL exporters don't need start notification
      end

      def on_span_end(span)
        otel_span = OTelAdapter.to_otel_span(span)
        @exporter.export([otel_span])
      rescue StandardError => e
        warn "[OTelProcessor] Failed to export span: #{e.message}"
      end

      def force_flush
        @exporter.force_flush if @exporter.respond_to?(:force_flush)
      end

      def shutdown
        @exporter.shutdown if @exporter.respond_to?(:shutdown)
      end
    end

    # Bridge to use OpenTelemetry gem exporters with OpenAI Agents tracing
    class OTelBridge
      def self.use_otel_exporter(exporter)
        processor = OTelProcessor.new(exporter)
        TraceProvider.instance.add_processor(processor)
      end

      # Convenience method to set up OTLP exporter
      def self.configure_otlp(endpoint: nil, headers: nil)
        begin
          require "opentelemetry/exporter/otlp"
          
          exporter = OpenTelemetry::Exporter::OTLP::Exporter.new(
            endpoint: endpoint || ENV["OTEL_EXPORTER_OTLP_ENDPOINT"] || "http://localhost:4318/v1/traces",
            headers: headers || ENV["OTEL_EXPORTER_OTLP_HEADERS"] || {}
          )
          
          use_otel_exporter(exporter)
        rescue LoadError
          warn "OpenTelemetry OTLP exporter not available. Install 'opentelemetry-exporter-otlp' gem."
        end
      end

      # Convenience method to set up Jaeger exporter
      def self.configure_jaeger(endpoint: nil)
        begin
          require "opentelemetry/exporter/jaeger"
          
          exporter = OpenTelemetry::Exporter::Jaeger::AgentExporter.new(
            host: endpoint&.split(":")&.first || ENV["JAEGER_HOST"] || "localhost",
            port: endpoint&.split(":")&.last&.to_i || ENV["JAEGER_PORT"]&.to_i || 6831
          )
          
          use_otel_exporter(exporter)
        rescue LoadError
          warn "OpenTelemetry Jaeger exporter not available. Install 'opentelemetry-exporter-jaeger' gem."
        end
      end
    end
  end
end