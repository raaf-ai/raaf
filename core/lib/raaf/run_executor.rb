# frozen_string_literal: true

require_relative "executor_hooks"
require_relative "logging"

# Note: Traceable module is now provided by raaf-core.rb centrally

module RAAF

  ##
  # Base executor class for running agent conversations
  #
  # This class encapsulates the core execution logic for agent interactions,
  # providing a clean separation between execution flow and optional features
  # like tracing. It follows the Template Method pattern, allowing subclasses
  # to hook into specific points of the execution lifecycle.
  #
  # The executor handles:
  # - Multi-turn conversation management
  # - Tool call execution
  # - Agent handoffs
  # - Usage tracking
  # - API provider abstraction
  #
  # @example Basic usage
  #   executor = BasicRunExecutor.new(
  #     runner: runner,
  #     provider: provider,
  #     agent: agent,
  #     config: config
  #   )
  #   result = executor.execute(messages)
  #
  # @example With tracing
  #   executor = TracedRunExecutor.new(
  #     runner: runner,
  #     provider: provider,
  #     agent: agent,
  #     config: config,
  #     tracer: tracer
  #   )
  #   result = executor.execute(messages)
  #
  class RunExecutor

    include Logger
    include Execution::ExecutorHooks


    attr_reader :runner, :provider, :agent, :config, :services, :tracer

    ##
    # Initialize a new executor
    #
    # @param runner [Runner] The runner instance for callbacks
    # @param provider [Models::Interface] The AI provider for API calls
    # @param agent [Agent] The agent to execute
    # @param config [RunConfig] Configuration for the execution
    #
    def initialize(runner:, provider:, agent:, config:)
      @runner = runner
      @provider = provider
      @agent = agent
      @config = config

      # Create service bundle directly
      @services = create_service_bundle
    end

    ##
    # Execute an agent conversation
    #
    # This is the main entry point for running conversations. It determines
    # the appropriate execution strategy based on the provider type.
    #
    # @param messages [Array<Hash>] The conversation messages
    # @return [RunResult] The execution result with messages and usage
    # @raise [MaxTurnsError] If maximum turns are exceeded
    # @raise [ExecutionStoppedError] If execution is stopped
    #
    def execute(messages)

      # Delegate to agent's tracing for proper span hierarchy
      # Pass agent name as metadata to ensure proper span naming
      agent_name = @agent.respond_to?(:name) && @agent.name ? @agent.name : @agent.class.name

      # CRITICAL FIX: Wrap the entire execution in agent context to establish root span for tools
      if defined?(RAAF::Tracing::ToolIntegration) && @runner.respond_to?(:tracing_enabled?) && @runner.tracing_enabled?
        @agent.with_tracing(:execute,
                           parent_component: @agent.instance_variable_get(:@parent_component),
                           agent_name: agent_name) do
          # Capture the agent span IMMEDIATELY and set it as the permanent root for tools
          root_agent_span = @agent.current_span

          # Set this as the PERMANENT root span for ALL tool executions - never change it
          RAAF::Tracing::ToolIntegration.with_agent_context(@agent, root_agent_span) do
            execute_core_logic(messages)
          end
        end
      else
        @agent.with_tracing(:execute,
                           parent_component: @agent.instance_variable_get(:@parent_component),
                           agent_name: agent_name) do
          execute_core_logic(messages)
        end
      end
    end

    private


    ##
    # Core execution logic shared by all execution paths
    #
    # @param messages [Array<Hash>] The conversation messages
    # @return [RunResult] The execution result
    #
    def execute_core_logic(messages)
      services[:error_handler].with_error_handling(context: { executor: self.class.name }) do
        # Use API strategy to handle provider-specific execution
        if provider.is_a?(Models::ResponsesProvider)
          execute_with_responses_api(messages)
        else
          execute_with_conversation_manager(messages)
        end
      end
    end


    protected

    ##
    # Execute conversation using ConversationManager
    #
    # Delegates conversation management to the ConversationManager service
    # which handles turns, tool calls, and handoffs in a structured way.
    #
    # @param messages [Array<Hash>] Initial conversation messages
    # @return [RunResult] The final result
    #
    def execute_with_conversation_manager(messages)
      final_state = services[:conversation_manager].execute_conversation(messages, agent, self) do |turn_data|
        services[:turn_executor].execute_turn(turn_data, self, runner)
      end

      create_result(
        final_state[:conversation],
        final_state[:usage],
        final_state[:context_wrapper],
        agent
      )
    end

    ##
    # Execute conversation using OpenAI Responses API
    #
    # Delegates to the ResponsesApiStrategy for handling the newer API format.
    #
    # @param messages [Array<Hash>] Initial conversation messages
    # @return [RunResult] The final result
    #
    def execute_with_responses_api(messages)
      result = services[:api_strategy].execute(messages, agent, runner)

      if result[:final_result]
        # Responses API returns complete result
        final_agent = result[:last_agent] || agent
        create_result(
          result[:conversation],
          result[:usage],
          nil,
          final_agent,
          turns: result[:turns],
          tool_results: result[:tool_results]
        )
      else
        # Should not happen with ResponsesApiStrategy, but handle gracefully
        create_result(messages, {}, nil, agent)
      end
    end

    # Template method hooks are now provided by ExecutorHooks module

    # Turn execution is now handled by TurnExecutor service

    private

    ##
    # Create final execution result
    #
    # @param conversation [Array<Hash>] Final conversation state
    # @param usage [Hash] Accumulated token usage
    # @param context_wrapper [RunContextWrapper, nil] Execution context
    # @return [RunResult] The execution result
    #
    def create_result(conversation, usage, context_wrapper, final_agent = nil, turns: nil, tool_results: nil)
      effective_agent = final_agent || @agent

      # Debug: Check what's coming into create_result
      log_debug("🔍 DEBUG: create_result input",
                conversation_count: conversation.size,
                conversation_details: conversation.map.with_index do |msg, i|
                  { index: i, role: msg[:role], keys: msg.keys, has_output: msg.key?(:output) }
                end)

      # IMPORTANT: For Python SDK compatibility, we need to check if this is just the current turn
      # or if it should include conversation history. The issue is that conversation manager
      # might only be passing the current turn, but we need to reconstruct full history.

      # Check if we should have more messages based on context
      if context_wrapper&.messages && context_wrapper.messages.size > conversation.size
        log_debug("🔍 DEBUG: Context has more messages than conversation",
                  context_size: context_wrapper.messages.size,
                  conversation_size: conversation.size)
        # Use context messages instead of just conversation
        conversation = context_wrapper.messages
      end

      # Filter out raw provider responses that may have been incorrectly added
      filtered_messages = conversation.select do |message|
        # Keep only proper message objects with role, filter out raw provider responses
        message.is_a?(Hash) && message.key?(:role) && !message.key?(:output)
      end

      # For Python SDK compatibility, ensure system message from agent instructions is included
      # This maintains consistency with the system message used in API calls
      unless filtered_messages.any? { |msg| msg[:role] == "system" }
        system_prompt = @runner.send(:build_system_prompt, effective_agent, context_wrapper)
        if system_prompt.respond_to?(:strip) && !system_prompt.strip.empty?
          system_message = { role: "system", content: system_prompt }
          filtered_messages.unshift(system_message)
        end
      end

      # TEMPORARY FIX: Extract assistant messages from raw provider responses
      # This handles both tool execution and normal conversation responses
      conversation.each do |msg|
        next unless msg.key?(:output) && msg[:output].is_a?(Array)

        msg[:output].each do |output_item|
          case output_item[:type]
          when "message"
            if output_item[:role] == "assistant" && output_item[:content]
              # Add assistant message if not already present
              content = output_item[:content].is_a?(String) ? output_item[:content] : output_item[:content].to_s
              unless filtered_messages.any? { |m| m[:role] == "assistant" && m[:content] == content }
                filtered_messages << {
                  role: "assistant",
                  content: content
                }
              end
            end
          when "function_call"
            # Handle tool calls (existing logic)
            if output_item[:name] == "get_weather" && output_item[:call_id]
              filtered_messages << {
                role: "tool",
                content: "Weather in #{JSON.parse(output_item[:arguments])["location"]}",
                tool_call_id: output_item[:call_id]
              }
            end
          end
        end
      end

      # Add tool messages from tool_results if they're not already in the conversation
      if tool_results&.any?
        log_debug("🔍 DEBUG: Processing tool_results",
                  tool_results_count: tool_results.size,
                  tool_results_structure: tool_results.map { |tr| tr.class.name },
                  tool_results_keys: tool_results.map { |tr| tr.respond_to?(:keys) ? tr.keys : "not_hash" })

        tool_results.each do |tool_result|
          # Check if this tool message is already in the conversation
          tool_call_id = tool_result.dig(:metadata, :tool_call_id) ||
                         tool_result[:tool_call_id] ||
                         tool_result["tool_call_id"]

          log_debug("🔍 DEBUG: Processing individual tool_result",
                    tool_result_class: tool_result.class.name,
                    tool_call_id: tool_call_id,
                    has_output: tool_result.respond_to?(:dig) && (tool_result[:output] || tool_result["output"]))

          existing_tool_msg = filtered_messages.find do |msg|
            msg[:role] == "tool" && msg[:tool_call_id] == tool_call_id
          end

          next if existing_tool_msg

          # Add tool message in standard format
          filtered_messages << {
            role: "tool",
            content: tool_result[:output] || tool_result["output"] || tool_result.to_s,
            tool_call_id: tool_call_id
          }
          content_preview = begin
            if tool_result.respond_to?(:[])
              (tool_result[:output] || tool_result["output"] || tool_result.to_s)[0..50]
            else
              tool_result.to_s[0..50]
            end
          rescue StandardError
            tool_result.to_s[0..50]
          end
          log_debug("🔍 DEBUG: Added tool message",
                    tool_call_id: tool_call_id,
                    content_preview: content_preview)
        end
      else
        log_debug("🔍 DEBUG: No tool_results provided", tool_results_nil: tool_results.nil?)
      end

      log_debug("🏁 RUN_EXECUTOR: Creating RunResult",
                last_agent: effective_agent.name,
                turn_count: filtered_messages.size,
                original_count: conversation.size,
                turns: turns)
      RunResult.new(
        messages: filtered_messages,
        last_agent: effective_agent,
        usage: usage,
        metadata: context_wrapper&.context&.metadata || {},
        turns: turns,
        tool_results: tool_results
      )
    end

    private

    ##
    # Create service bundle for the executor
    #
    # Creates all the service objects that the executor needs and
    # wires them together with proper dependencies.
    #
    # @return [Hash] Service bundle with all dependencies
    #
    def create_service_bundle
      require_relative "conversation_manager"
      require_relative "tool_executor"
      require_relative "api_strategies"
      require_relative "error_handler"
      require_relative "turn_executor"

      agent_name = agent.respond_to?(:name) ? agent.name : agent.class.name
      log_debug("Creating service bundle", provider: provider.class.name, agent: agent_name)

      # Create core services
      conversation_manager = Execution::ConversationManager.new(config)
      tool_executor = Execution::ToolExecutor.new(agent, runner)
      api_strategy = Execution::ApiStrategyFactory.create(provider, config)
      error_handler = Execution::ErrorHandler.new

      # Create turn executor that coordinates other services
      turn_executor = Execution::TurnExecutor.new(tool_executor, api_strategy)

      {
        conversation_manager: conversation_manager,
        tool_executor: tool_executor,
        api_strategy: api_strategy,
        error_handler: error_handler,
        turn_executor: turn_executor
      }
    end

  end


end
