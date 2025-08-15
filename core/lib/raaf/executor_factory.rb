# frozen_string_literal: true

require_relative "logging"
require_relative "conversation_manager"
require_relative "tool_executor"
require_relative "api_strategies"
require_relative "error_handler"
require_relative "turn_executor"

module RAAF

  module Execution

    ##
    # Factory for creating executor instances with proper service dependencies
    #
    # This class handles the complexity of wiring together all the service
    # objects that an executor needs, providing a clean interface for
    # executor creation.
    #
    # @example Creating a service bundle
    #   services = ExecutorFactory.create_service_bundle(
    #     runner: runner,
    #     provider: provider,
    #     agent: agent,
    #     config: config
    #   )
    #   # Returns hash with all service dependencies wired together
    #
    # @example Creating executors directly
    #   basic_executor = ExecutorFactory.create_basic_executor(
    #     runner: runner, provider: provider, agent: agent, config: config
    #   )
    #
    #   traced_executor = ExecutorFactory.create_traced_executor(
    #     runner: runner, provider: provider, agent: agent,
    #     config: config, tracer: tracer
    #   )
    #
    # @example Service bundle contents
    #   services = ExecutorFactory.create_service_bundle(...)
    #   services[:conversation_manager] # Manages conversation flow
    #   services[:tool_executor]        # Handles tool execution
    #   services[:api_strategy]         # API calling strategy
    #   services[:error_handler]        # Error handling and recovery
    #   services[:turn_executor]        # Coordinates single turns
    #
    class ExecutorFactory

      include Logger

      ##
      # Create service bundle for an executor
      #
      # Creates all the service objects that an executor needs and
      # wires them together with proper dependencies.
      #
      # @param runner [Runner] The runner instance for callbacks
      # @param provider [Models::Interface] The AI provider
      # @param agent [Agent] The agent to execute
      # @param config [RunConfig] Execution configuration
      # @return [Hash] Service bundle with all dependencies
      #
      def self.create_service_bundle(runner:, provider:, agent:, config:)
        agent_name = agent.respond_to?(:name) ? agent.name : agent.class.name
        log_debug_general("Creating service bundle", provider: provider.class.name, agent: agent_name)

        # Create core services
        conversation_manager = ConversationManager.new(config)
        tool_executor = ToolExecutor.new(agent, runner)
        api_strategy = ApiStrategyFactory.create(provider, config)
        error_handler = ErrorHandler.new

        # Create turn executor that coordinates other services
        turn_executor = TurnExecutor.new(tool_executor, api_strategy)

        {
          conversation_manager: conversation_manager,
          tool_executor: tool_executor,
          api_strategy: api_strategy,
          error_handler: error_handler,
          turn_executor: turn_executor
        }
      end

      ##
      # Create a basic executor
      #
      # @param runner [Runner] The runner instance
      # @param provider [Models::Interface] The AI provider
      # @param agent [Agent] The agent to execute
      # @param config [RunConfig] Execution configuration
      # @return [BasicRunExecutor] Configured executor
      #
      def self.create_basic_executor(runner:, provider:, agent:, config:)
        require_relative "run_executor"
        BasicRunExecutor.new(runner: runner, provider: provider, agent: agent, config: config)
      end

      ##
      # Create a traced executor
      #
      # @param runner [Runner] The runner instance
      # @param provider [Models::Interface] The AI provider
      # @param agent [Agent] The agent to execute
      # @param config [RunConfig] Execution configuration
      # @param tracer [Tracing::SpanTracer] The tracer for spans
      # @return [TracedRunExecutor] Configured traced executor
      #
      def self.create_traced_executor(runner:, provider:, agent:, config:, tracer:)
        require_relative "run_executor"
        TracedRunExecutor.new(
          runner: runner,
          provider: provider,
          agent: agent,
          config: config,
          tracer: tracer
        )
      end

      def self.log_debug_general(message, context = {})
        # Simple logging fallback if Logger module isn't available
        return unless defined?(RAAF::Logging)

        RAAF.logger.debug(message, category: :general, **context)
      end

    end

  end

end
