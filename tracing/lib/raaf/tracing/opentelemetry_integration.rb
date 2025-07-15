# frozen_string_literal: true

module RubyAIAgentsFactory
  module Tracing
    ##
    # OpenTelemetry integration for Ruby AI Agents Factory
    #
    # Provides seamless integration with OpenTelemetry for distributed tracing
    # and observability. Supports automatic instrumentation of agent workflows
    # and custom span creation for detailed monitoring.
    #
    # @example Basic OpenTelemetry setup
    #   otel = OpenTelemetryIntegration.new
    #   otel.setup_instrumentation
    #   
    #   agent = Agent.new(name: "Assistant")
    #   runner = Runner.new(agent: agent, tracer: otel)
    #
    # @example Custom configuration
    #   otel = OpenTelemetryIntegration.new(
    #     service_name: "ai-agents-production",
    #     service_version: "1.0.0",
    #     resource_attributes: {
    #       "service.namespace" => "ai-platform",
    #       "deployment.environment" => "production"
    #     }
    #   )
    #
    class OpenTelemetryIntegration
      # @return [String] Service name for OpenTelemetry
      attr_reader :service_name

      # @return [String] Service version
      attr_reader :service_version

      # @return [Hash] Resource attributes
      attr_reader :resource_attributes

      ##
      # Initialize OpenTelemetry integration
      #
      # @param service_name [String] Service name for tracing
      # @param service_version [String] Service version
      # @param resource_attributes [Hash] Additional resource attributes
      #
      def initialize(service_name: "ruby-ai-agents-factory",
                     service_version: "1.0.0",
                     resource_attributes: {})
        @service_name = service_name
        @service_version = service_version
        @resource_attributes = resource_attributes
        @tracer = nil
        @setup_complete = false
      end

      ##
      # Setup OpenTelemetry instrumentation
      #
      # Configures OpenTelemetry SDK with appropriate exporters and
      # instrumentation for AI agent workflows.
      #
      def setup_instrumentation
        return if @setup_complete

        require_otel_dependencies
        configure_otel_sdk
        setup_instrumentation_libraries
        
        @tracer = OpenTelemetry.tracer_provider.tracer(
          @service_name,
          version: @service_version
        )
        
        @setup_complete = true
      end

      ##
      # Create a new span
      #
      # @param name [String] Span name
      # @param attributes [Hash] Span attributes
      # @param kind [Symbol] Span kind (:internal, :server, :client, :producer, :consumer)
      # @yield [span] Block to execute within span context
      #
      def start_span(name, attributes: {}, kind: :internal, &block)
        setup_instrumentation unless @setup_complete

        span_kind = map_span_kind(kind)
        
        @tracer.in_span(name, attributes: attributes, kind: span_kind) do |span|
          if block_given?
            begin
              yield span
            rescue StandardError => e
              span.record_exception(e)
              span.status = OpenTelemetry::Trace::Status.error(e.message)
              raise
            end
          end
        end
      end

      ##
      # Process a span (compatibility with SpanTracer interface)
      #
      # @param span [Span] Span to process
      #
      def process(span)
        return unless span.finished?

        # Convert to OpenTelemetry span
        otel_span = create_otel_span(span)
        
        # The span is automatically sent to configured exporters
        # when it's finished within the OpenTelemetry context
      end

      ##
      # Add processor (compatibility interface)
      #
      # @param processor [Object] Processor to add
      #
      def add_processor(processor)
        # OpenTelemetry uses exporters instead of processors
        # This method maintains compatibility with SpanTracer interface
        warn "OpenTelemetry integration uses exporters, not processors. Configure exporters in setup_instrumentation."
      end

      ##
      # Check if OpenTelemetry is properly configured
      #
      # @return [Boolean] True if OpenTelemetry is configured
      #
      def configured?
        @setup_complete && @tracer
      end

      private

      def require_otel_dependencies
        require 'opentelemetry/api'
        require 'opentelemetry/sdk'
        require 'opentelemetry/exporter/otlp'
        require 'opentelemetry/instrumentation/net_http'
      rescue LoadError => e
        raise "OpenTelemetry gems are required. Add the following to your Gemfile:\n" \
              "gem 'opentelemetry-api'\n" \
              "gem 'opentelemetry-sdk'\n" \
              "gem 'opentelemetry-exporter-otlp'\n" \
              "gem 'opentelemetry-instrumentation-net_http'\n\n" \
              "Error: #{e.message}"
      end

      def configure_otel_sdk
        # Configure resource
        resource = OpenTelemetry::SDK::Resources::Resource.create(
          {
            "service.name" => @service_name,
            "service.version" => @service_version,
            "telemetry.sdk.language" => "ruby",
            "telemetry.sdk.name" => "opentelemetry",
            "telemetry.sdk.version" => OpenTelemetry::SDK::VERSION
          }.merge(@resource_attributes)
        )

        # Configure tracer provider
        OpenTelemetry::SDK.configure do |c|
          c.resource = resource
          c.service_name = @service_name
          c.service_version = @service_version
          
          # Add OTLP exporter (can be configured via environment variables)
          c.add_span_processor(
            OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(
              OpenTelemetry::Exporter::OTLP::Exporter.new
            )
          )
        end
      end

      def setup_instrumentation_libraries
        # Setup automatic instrumentation
        OpenTelemetry::Instrumentation::Net::HTTP.install
        
        # Additional instrumentations can be added here
        # OpenTelemetry::Instrumentation::Faraday.install
        # OpenTelemetry::Instrumentation::Redis.install
      end

      def map_span_kind(kind)
        case kind
        when :internal
          OpenTelemetry::Trace::SpanKind::INTERNAL
        when :server
          OpenTelemetry::Trace::SpanKind::SERVER
        when :client
          OpenTelemetry::Trace::SpanKind::CLIENT
        when :producer
          OpenTelemetry::Trace::SpanKind::PRODUCER
        when :consumer
          OpenTelemetry::Trace::SpanKind::CONSUMER
        else
          OpenTelemetry::Trace::SpanKind::INTERNAL
        end
      end

      def create_otel_span(span)
        attributes = build_otel_attributes(span)
        
        @tracer.in_span(
          span.name,
          attributes: attributes,
          kind: map_span_type_to_kind(span.type),
          start_timestamp: span.start_time
        ) do |otel_span|
          # Set span status
          if span.error
            otel_span.record_exception(span.error)
            otel_span.status = OpenTelemetry::Trace::Status.error(span.error.message)
          else
            otel_span.status = OpenTelemetry::Trace::Status.ok
          end

          # Finish span with end time
          otel_span.finish(timestamp: span.end_time)
        end
      end

      def build_otel_attributes(span)
        attributes = {}

        # Add span metadata as attributes
        span.metadata.each do |key, value|
          attributes["agent.#{key}"] = value.to_s if value
        end

        # Add specific attributes
        attributes["agent.type"] = span.type
        attributes["agent.name"] = span.metadata["agent_name"] if span.metadata["agent_name"]
        attributes["model.name"] = span.metadata["model"] if span.metadata["model"]
        attributes["provider.name"] = span.metadata["provider"] if span.metadata["provider"]
        attributes["run.id"] = span.metadata["run_id"] if span.metadata["run_id"]

        # Add usage metrics
        if span.metadata["usage"]
          usage = span.metadata["usage"]
          attributes["usage.input_tokens"] = usage["input_tokens"] if usage["input_tokens"]
          attributes["usage.output_tokens"] = usage["output_tokens"] if usage["output_tokens"]
          attributes["usage.total_tokens"] = usage["total_tokens"] if usage["total_tokens"]
        end

        # Add tool information
        if span.metadata["tool_name"]
          attributes["tool.name"] = span.metadata["tool_name"]
        end

        attributes
      end

      def map_span_type_to_kind(type)
        case type
        when "agent"
          OpenTelemetry::Trace::SpanKind::INTERNAL
        when "response"
          OpenTelemetry::Trace::SpanKind::CLIENT
        when "tool"
          OpenTelemetry::Trace::SpanKind::INTERNAL
        when "handoff"
          OpenTelemetry::Trace::SpanKind::INTERNAL
        else
          OpenTelemetry::Trace::SpanKind::INTERNAL
        end
      end
    end
  end
end