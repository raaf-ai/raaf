# frozen_string_literal: true

require_relative "logging"

module RAAF

  module Execution

    ##
    # Handles execution of individual conversation turns
    #
    # This class encapsulates the logic for executing a single turn of
    # conversation, coordinating between API calls, tool execution,
    # guardrails, and handoff detection.
    #
    class TurnExecutor

      include Logger

      ##
      # Initialize turn executor
      #
      # @param tool_executor [ToolExecutor] Tool execution service
      # @param api_strategy [BaseApiStrategy] API call strategy
      #
      def initialize(tool_executor, api_strategy)
        @tool_executor = tool_executor
        @api_strategy = api_strategy
      end

      ##
      # Execute a single conversation turn
      #
      # This method coordinates the various services to handle a single turn:
      # 1. Run pre-turn hooks via executor
      # 2. Execute guardrails via runner
      # 3. Execute API call via strategy
      # 4. Handle tool calls via ToolExecutor
      # 5. Run post-turn hooks via executor
      #
      # @param turn_data [Hash] Turn data from ConversationManager
      # @param executor [RunExecutor] The executor for hook callbacks
      # @param runner [Runner] The runner for guardrails and hooks
      # @return [Hash] Turn result with message, usage, and control flags
      #
      def execute_turn(turn_data, executor, runner)
        conversation = turn_data[:conversation]
        current_agent = turn_data[:current_agent]
        context_wrapper = turn_data[:context_wrapper]
        turns = turn_data[:turns]

        # Pre-turn hook via executor
        executor.before_turn(conversation, current_agent, context_wrapper, turns)

        # Update context
        context_wrapper.context.current_agent = current_agent
        context_wrapper.context.current_turn = turns

        # Run hooks via runner
        runner.call_hook(:on_agent_start, context_wrapper, current_agent)

        # Run input guardrails
        current_input = conversation.last[:content] if conversation.last && conversation.last[:role] == "user"
        runner.run_input_guardrails(context_wrapper, current_agent, current_input) if current_input

        # Execute API call via strategy
        result = @api_strategy.execute(conversation, current_agent, runner)
        message = result[:message]
        usage = result[:usage]

        # Run output guardrails
        if message[:content]
          filtered_content = runner.run_output_guardrails(context_wrapper, current_agent, message[:content])
          message[:content] = filtered_content if filtered_content != message[:content]
        end

        # Call agent end hook
        runner.call_hook(:on_agent_end, context_wrapper, current_agent, message)

        # Handle tool calls if present
        if @tool_executor.tool_calls?(message)
          @tool_executor.execute_tool_calls(
            message["tool_calls"] || message[:tool_calls],
            conversation,
            context_wrapper,
            result[:response]
          ) do |tool_name, arguments, &tool_block|
            executor.wrap_tool_execution(tool_name, arguments, &tool_block)
          end

          # Reset tool choice after tool calls if configured
          if current_agent.reset_tool_choice
            log_debug("🔄 TURN_EXECUTOR: Resetting tool_choice after tool calls", agent: current_agent.name)
            current_agent.tool_choice = nil
          end
        end

        # Handoffs are now handled through tool calls only
        # No separate handoff detection needed

        # Determine if execution should continue
        should_continue = @tool_executor.should_continue?(message)

        turn_result = {
          message: message,
          usage: usage,
          should_continue: should_continue
        }

        # Post-turn hook via executor
        executor.after_turn(conversation, current_agent, context_wrapper, turns, turn_result)

        turn_result
      end

    end

  end

end
