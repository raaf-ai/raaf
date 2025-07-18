# frozen_string_literal: true

module RAAF
  module Tracing
    ##
    # Datadog processor for sending traces to Datadog APM
    #
    # Integrates with Datadog's distributed tracing platform to provide
    # comprehensive monitoring of AI agent workflows. Supports custom
    # metrics, service mapping, and performance analysis.
    #
    # @example Basic Datadog integration
    #   processor = DatadogProcessor.new
    #   tracer = SpanTracer.new
    #   tracer.add_processor(processor)
    #
    # @example With custom configuration
    #   processor = DatadogProcessor.new(
    #     service_name: "ai-agents-production",
    #     env: "production",
    #     version: "1.0.0",
    #     tags: { team: "ai", component: "agents" }
    #   )
    #
    class DatadogProcessor
      # @return [String] Service name for Datadog
      attr_reader :service_name

      # @return [String] Environment name
      attr_reader :env

      # @return [String] Service version
      attr_reader :version

      # @return [Hash] Default tags
      attr_reader :tags

      ##
      # Initialize Datadog processor
      #
      # @param service_name [String] Service name for Datadog
      # @param env [String] Environment (development, staging, production)
      # @param version [String] Service version
      # @param tags [Hash] Default tags to apply to all spans
      # @param agent_host [String] Datadog agent host
      # @param agent_port [Integer] Datadog agent port
      #
      def initialize(service_name: "ruby-ai-agents-factory", 
                     env: "development", 
                     version: "1.0.0",
                     tags: {},
                     agent_host: "localhost",
                     agent_port: 8126)
        @service_name = service_name
        @env = env
        @version = version
        @tags = tags
        @agent_host = agent_host
        @agent_port = agent_port

        setup_datadog
      end

      ##
      # Process a span and send to Datadog
      #
      # @param span [Span] Span to process
      #
      def process(span)
        return unless span.finished?

        dd_span = create_datadog_span(span)
        send_to_datadog(dd_span)
      rescue StandardError => e
        warn "Failed to send span to Datadog: #{e.message}"
      end

      private

      def setup_datadog
        begin
          require 'datadog'
          
          Datadog.configure do |c|
            c.service = @service_name
            c.env = @env
            c.version = @version
            c.agent.host = @agent_host
            c.agent.port = @agent_port
            
            # Configure tracing
            c.tracing.enabled = true
            c.tracing.analytics.enabled = true
            
            # Set default tags
            @tags.each { |k, v| c.tags[k.to_s] = v.to_s }
          end
        rescue LoadError
          raise "ddtrace gem is required for DatadogProcessor. Add 'gem \"ddtrace\"' to your Gemfile."
        end
      end

      def create_datadog_span(span)
        tracer = Datadog::Tracing.tracer
        
        # Create span
        dd_span = tracer.trace(
          span.name,
          service: @service_name,
          resource: span.metadata["resource"] || span.name,
          span_type: map_span_type(span.type),
          start_time: span.start_time,
          tags: build_tags(span)
        )

        # Set timing
        dd_span.finish(span.end_time)

        # Set error if present
        if span.error
          dd_span.set_error(span.error)
        end

        # Set metadata as tags
        span.metadata.each do |key, value|
          dd_span.set_tag(key.to_s, value.to_s) if value
        end

        dd_span
      end

      def map_span_type(agent_span_type)
        case agent_span_type
        when "agent"
          "custom"
        when "response"
          "llm"
        when "tool"
          "custom"
        when "handoff"
          "custom"
        else
          "custom"
        end
      end

      def build_tags(span)
        tags = @tags.dup

        # Add span-specific tags
        tags["span.kind"] = "internal"
        tags["span.type"] = span.type
        tags["agent.name"] = span.metadata["agent_name"] if span.metadata["agent_name"]
        tags["model.name"] = span.metadata["model"] if span.metadata["model"]
        tags["provider.name"] = span.metadata["provider"] if span.metadata["provider"]
        tags["run.id"] = span.metadata["run_id"] if span.metadata["run_id"]

        # Add usage metrics as tags
        if span.metadata["usage"]
          usage = span.metadata["usage"]
          tags["usage.input_tokens"] = usage["input_tokens"].to_s if usage["input_tokens"]
          tags["usage.output_tokens"] = usage["output_tokens"].to_s if usage["output_tokens"]
          tags["usage.total_tokens"] = usage["total_tokens"].to_s if usage["total_tokens"]
        end

        # Add tool information
        if span.metadata["tool_name"]
          tags["tool.name"] = span.metadata["tool_name"]
        end

        tags
      end

      def send_to_datadog(dd_span)
        # Span is automatically sent to Datadog when finished
        # Additional custom metrics can be sent here
        
        # Send custom metrics
        if dd_span.get_tag("usage.total_tokens")
          Datadog::Statsd.histogram(
            "ai_agents.tokens.total",
            dd_span.get_tag("usage.total_tokens").to_i,
            tags: ["service:#{@service_name}", "env:#{@env}"]
          )
        end

        # Send duration metric
        Datadog::Statsd.histogram(
          "ai_agents.span.duration",
          dd_span.duration * 1000, # Convert to milliseconds
          tags: [
            "service:#{@service_name}",
            "env:#{@env}",
            "span_type:#{dd_span.get_tag('span.type')}"
          ]
        )
      end
    end
  end
end