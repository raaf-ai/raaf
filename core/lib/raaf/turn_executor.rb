# frozen_string_literal: true

require_relative "../logging"

module RubyAIAgentsFactory
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
      # @param handoff_detector [HandoffDetector] Handoff detection service
      # @param api_strategy [BaseApiStrategy] API call strategy
      #
      def initialize(tool_executor, handoff_detector, api_strategy)
        @tool_executor = tool_executor
        @handoff_detector = handoff_detector
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
      # 5. Check for handoffs via HandoffDetector
      # 6. Run post-turn hooks via executor
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
        runner.run_output_guardrails(context_wrapper, current_agent, message[:content]) if message[:content]
        
        # Call agent end hook
        runner.call_hook(:on_agent_end, context_wrapper, current_agent, message)
        
        # Handle tool calls if present
        if @tool_executor.has_tool_calls?(message)
          @tool_executor.execute_tool_calls(
            message["tool_calls"] || message[:tool_calls],
            conversation,
            context_wrapper,
            result[:response]
          ) do |tool_name, arguments, &tool_block|
            executor.wrap_tool_execution(tool_name, arguments, &tool_block)
          end
        end

        # Check for handoff
        handoff_result = @handoff_detector.check_for_handoff(message, current_agent)
        
        # Check tool calls for handoff patterns
        if @tool_executor.has_tool_calls?(message)
          tool_handoff_result = @handoff_detector.check_tool_calls_for_handoff(
            message["tool_calls"] || message[:tool_calls],
            current_agent
          )
          handoff_result = tool_handoff_result if tool_handoff_result[:handoff_occurred]
        end
        
        # Determine if execution should continue
        should_continue = @tool_executor.should_continue?(message)
        
        turn_result = {
          message: message,
          usage: usage,
          handoff_result: handoff_result,
          should_continue: should_continue
        }
        
        # Post-turn hook via executor
        executor.after_turn(conversation, current_agent, context_wrapper, turns, turn_result)
        
        turn_result
      end
    end
  end
end