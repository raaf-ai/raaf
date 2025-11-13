# frozen_string_literal: true

# Require RAAF core only when actually using the engine
# This allows DSL components to be tested independently
begin
  require_relative "../../raaf"
rescue LoadError
  # RAAF core not available - this is OK for testing DSL components
end

module RAAF
  module Eval
    ##
    # Core evaluation engine that re-runs agent executions with modified configurations
    #
    # This class is responsible for taking a baseline span and re-executing it with
    # different AI settings to compare results.
    class Engine
      attr_reader :span, :configuration_overrides

      ##
      # Creates a new evaluation engine
      #
      # @param span [Hash] the baseline span to re-evaluate
      # @param configuration_overrides [Hash] AI settings to override (model, temperature, etc.)
      def initialize(span:, configuration_overrides: {})
        @span = span
        @configuration_overrides = configuration_overrides
      end

      ##
      # Executes the evaluation
      #
      # @param async [Boolean] whether to run asynchronously
      # @return [Hash] evaluation result with metrics
      def execute(async: false)
        # Extract original agent configuration from span
        agent_config = extract_agent_config(span)

        # Merge with overrides
        merged_config = agent_config.merge(configuration_overrides)

        # Create agent with merged configuration
        agent = create_agent(merged_config)

        # Extract original messages from span
        messages = extract_messages(span)

        # Run the agent
        runner = RAAF::Runner.new(agent: agent)
        result = runner.run(messages.last[:content])

        # Build evaluation result
        build_result(result, span)
      rescue StandardError => e
        {
          success: false,
          error: e.message,
          error_class: e.class.name,
          backtrace: e.backtrace&.first(5)
        }
      end

      private

      def extract_agent_config(span)
        {
          name: span.dig(:agent_name) || "EvaluationAgent",
          instructions: span.dig(:metadata, :instructions) || span.dig(:metadata, :system_message) || "",
          model: span.dig(:metadata, :model) || "gpt-4o"
        }
      end

      def create_agent(config)
        RAAF::Agent.new(
          name: config[:name],
          instructions: config[:instructions],
          model: config[:model]
        )
      end

      def extract_messages(span)
        span.dig(:metadata, :messages) || [{ role: "user", content: "Test message" }]
      end

      def build_result(run_result, original_span)
        {
          success: true,
          output: run_result.messages.last[:content],
          messages: run_result.messages,
          usage: run_result.usage || {},
          latency_ms: calculate_latency(run_result),
          baseline_output: original_span.dig(:output) || original_span.dig(:metadata, :output),
          baseline_usage: original_span.dig(:usage) || original_span.dig(:metadata, :usage) || {},
          configuration: configuration_overrides
        }
      end

      def calculate_latency(result)
        # This would come from actual timing in a real implementation
        # For now, return a placeholder
        result.respond_to?(:latency_ms) ? result.latency_ms : 0
      end
    end
  end
end
