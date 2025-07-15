# frozen_string_literal: true

require_relative "raaf/tracing/version"
require_relative "raaf/tracing/span_tracer"
require_relative "raaf/tracing/openai_processor"
require_relative "raaf/tracing/console_processor"
require_relative "raaf/tracing/file_processor"
require_relative "raaf/tracing/datadog_processor"
require_relative "raaf/tracing/spans"
require_relative "raaf/tracing/opentelemetry_integration"

module RubyAIAgentsFactory
  ##
  # Distributed tracing and monitoring for Ruby AI Agents Factory
  #
  # The Tracing module provides comprehensive monitoring and observability
  # for AI agent workflows. It includes span-based tracking that maintains
  # structural alignment with the Python OpenAI Agents SDK, enabling
  # consistent monitoring across language implementations.
  #
  # Key features:
  # - Span-based distributed tracing
  # - Performance metrics and timing
  # - Integration with popular monitoring platforms
  # - Python SDK-compatible trace format
  # - OpenTelemetry integration
  # - Custom processor support
  #
  # @example Basic tracing setup
  #   tracer = RubyAIAgentsFactory::Tracing::SpanTracer.new
  #   tracer.add_processor(RubyAIAgentsFactory::Tracing::OpenAIProcessor.new)
  #   
  #   agent = RubyAIAgentsFactory::Agent.new(
  #     name: "Assistant",
  #     instructions: "You are helpful"
  #   )
  #   
  #   runner = RubyAIAgentsFactory::Runner.new(agent: agent, tracer: tracer)
  #   result = runner.run("Hello")
  #
  # @example Multiple processors
  #   tracer = RubyAIAgentsFactory::Tracing::SpanTracer.new
  #   tracer.add_processor(RubyAIAgentsFactory::Tracing::OpenAIProcessor.new)
  #   tracer.add_processor(RubyAIAgentsFactory::Tracing::DatadogProcessor.new)
  #   tracer.add_processor(RubyAIAgentsFactory::Tracing::ConsoleProcessor.new)
  #
  # @example OpenTelemetry integration
  #   otel_tracer = RubyAIAgentsFactory::Tracing::OpenTelemetryIntegration.new
  #   otel_tracer.setup_instrumentation
  #   
  #   # Traces will be sent to configured OpenTelemetry exporters
  #   agent = RubyAIAgentsFactory::Agent.new(name: "Assistant")
  #   runner = RubyAIAgentsFactory::Runner.new(agent: agent, tracer: otel_tracer)
  #
  # @since 1.0.0
  module Tracing
    # Default configuration
    DEFAULT_CONFIG = {
      enabled: true,
      processors: [],
      sample_rate: 1.0,
      max_spans_per_trace: 1000,
      span_timeout: 30.0
    }.freeze

    class << self
      # @return [Hash] Current tracing configuration
      attr_accessor :config

      ##
      # Configure tracing settings
      #
      # @param options [Hash] Configuration options
      # @option options [Boolean] :enabled (true) Enable/disable tracing
      # @option options [Array] :processors ([]) Default processors
      # @option options [Float] :sample_rate (1.0) Sampling rate (0.0-1.0)
      # @option options [Integer] :max_spans_per_trace (1000) Maximum spans per trace
      # @option options [Float] :span_timeout (30.0) Span timeout in seconds
      #
      # @example Configure tracing
      #   RubyAIAgentsFactory::Tracing.configure do |config|
      #     config.enabled = true
      #     config.sample_rate = 0.1
      #     config.processors = [OpenAIProcessor.new, ConsoleProcessor.new]
      #   end
      #
      def configure
        @config ||= DEFAULT_CONFIG.dup
        yield @config if block_given?
        @config
      end

      ##
      # Get current configuration
      #
      # @return [Hash] Current configuration
      def config
        @config ||= DEFAULT_CONFIG.dup
      end

      ##
      # Create a new tracer with default configuration
      #
      # @return [SpanTracer] New tracer instance
      def create_tracer
        tracer = SpanTracer.new
        config[:processors].each { |processor| tracer.add_processor(processor) }
        tracer
      end

      ##
      # Check if tracing is enabled
      #
      # @return [Boolean] True if tracing is enabled
      def enabled?
        config[:enabled]
      end

      ##
      # Disable tracing globally
      def disable!
        config[:enabled] = false
      end

      ##
      # Enable tracing globally
      def enable!
        config[:enabled] = true
      end
    end
  end
end