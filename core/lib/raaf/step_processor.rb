# frozen_string_literal: true

require "async"
require_relative "step_result"
require_relative "processed_response"
require_relative "response_processor"
require_relative "tool_use_tracker"
require_relative "logging"
require_relative "step_errors"
require_relative "items"

module RAAF

  ##
  # Unified step processor for agent conversations
  #
  # This class provides atomic processing of conversation steps, eliminating
  # coordination issues between multiple services. It mirrors Python's
  # RunImpl.execute_tools_and_side_effects functionality with proper Ruby patterns.
  #
  # The processor handles:
  # - Model response processing
  # - Tool execution (parallel when possible)
  # - Handoff detection and execution
  # - Final output determination
  # - State management
  #
  # @example Basic usage
  #   processor = StepProcessor.new
  #   result = processor.execute_step(
  #     original_input: "Hello",
  #     pre_step_items: [],
  #     model_response: response,
  #     agent: agent,
  #     context_wrapper: context,
  #     runner: runner
  #   )
  #
  class StepProcessor

    include Logger

    ##
    # Initialize a new step processor
    #
    def initialize
      @response_processor = ResponseProcessor.new
      @tool_use_tracker = ToolUseTracker.new
    end

    ##
    # Execute a single conversation step atomically
    #
    # This method processes a model response and executes all necessary
    # side effects (tools, handoffs) to produce a complete step result.
    # It follows Python's single-method approach for step processing.
    #
    # @param original_input [String, Array<Hash>] Original input to the runner
    # @param pre_step_items [Array<Hash>] Items generated before current step
    # @param model_response [Hash] Raw model response to process
    # @param agent [Agent] Current agent for tool/handoff resolution
    # @param context_wrapper [RunContextWrapper] Current execution context
    # @param runner [Runner] Runner instance for hooks and provider access
    # @param config [RunConfig] Current run configuration
    # @return [StepResult] Complete step result with next action
    #
    def execute_step(original_input:, pre_step_items:, model_response:,
                     agent:, context_wrapper:, runner:, config:)
      log_debug("🔄 STEP_PROCESSOR: Executing step", agent: agent.name)

      # 1. Process model response atomically
      processed_response = process_model_response(model_response, agent)

      # 2. Execute tools and side effects
      new_step_items, next_step = execute_tools_and_side_effects(
        agent: agent,
        original_input: original_input,
        pre_step_items: pre_step_items,
        processed_response: processed_response,
        context_wrapper: context_wrapper,
        runner: runner,
        config: config
      )

      # 3. Create step result
      step_result = StepResult.new(
        original_input: original_input,
        model_response: model_response,
        pre_step_items: pre_step_items,
        new_step_items: new_step_items,
        next_step: next_step
      )

      log_debug("✅ STEP_PROCESSOR: Step completed",
                next_step: next_step.class.name, items: new_step_items.size)

      step_result
    end

    ##
    # Reset tool choice for agent if configured
    #
    # Matches Python's maybe_reset_tool_choice functionality
    #
    # @param agent [Agent] Agent to potentially reset
    # @return [void]
    #
    def maybe_reset_tool_choice(agent)
      return unless agent.reset_tool_choice && @tool_use_tracker.used_tools?(agent)

      log_debug("🔄 STEP_PROCESSOR: Resetting tool choice", agent: agent.name)
      agent.tool_choice = nil
    end

    private

    ##
    # Process model response into categorized elements
    #
    def process_model_response(model_response, agent)
      all_tools = agent.tools || []
      handoffs = agent.handoffs || []

      @response_processor.process_model_response(
        response: model_response,
        agent: agent,
        all_tools: all_tools,
        handoffs: handoffs
      )
    end

    ##
    # Execute tools and side effects from processed response
    #
    # This method handles the execution order and coordination:
    # 1. Execute function tools in parallel
    # 2. Handle handoffs (taking precedence over continuing)
    # 3. Check for final output
    # 4. Determine next step
    #
    def execute_tools_and_side_effects(agent:, original_input:, pre_step_items:,
                                       processed_response:, context_wrapper:, runner:, config:)
      new_step_items = processed_response.new_items.dup

      # Track tool usage
      @tool_use_tracker.add_tool_use(agent, processed_response.tools_used)

      # Execute function tools in parallel if any
      if processed_response.functions.any?
        tool_results = execute_function_tools_parallel(
          processed_response.functions, agent, context_wrapper, runner, config
        )
        
        new_step_items.concat(tool_results.map(&:run_item))

        # Check for final output from tools
        final_output = check_for_final_output_from_tools(tool_results, agent, context_wrapper, config)
        return [new_step_items, NextStepFinalOutput.new(final_output)] if final_output
      end

      # Execute computer actions sequentially if any
      if processed_response.computer_actions.any?
        computer_results = execute_computer_actions(
          processed_response.computer_actions, agent, context_wrapper, runner, config
        )
        new_step_items.concat(computer_results)
      end

      # Execute local shell calls sequentially if any
      if processed_response.local_shell_calls.any?
        shell_results = execute_local_shell_calls(
          processed_response.local_shell_calls, agent, context_wrapper, runner, config
        )
        new_step_items.concat(shell_results)
      end

      # Handle handoffs (take precedence over continuing)
      if processed_response.handoffs_detected?
        return execute_handoffs(
          original_input: original_input,
          pre_step_items: pre_step_items,
          new_step_items: new_step_items,
          processed_response: processed_response,
          agent: agent,
          context_wrapper: context_wrapper,
          runner: runner,
          config: config
        )
      end

      # Check for final output from message content
      final_output = check_for_final_output_from_message(new_step_items, processed_response, agent)
      return [new_step_items, NextStepFinalOutput.new(final_output)] if final_output

      # If there are no items at all, treat this as an empty final output
      if new_step_items.empty?
        return [new_step_items, NextStepFinalOutput.new("")]
      end

      # Continue conversation
      [new_step_items, NextStepRunAgain.new]
    end

    ##
    # Execute function tools in parallel using Async
    #
    def execute_function_tools_parallel(functions, agent, context_wrapper, runner, config)
      return [] if functions.empty?

      log_debug("🔧 STEP_PROCESSOR: Executing function tools", count: functions.size)

      # Execute tools in parallel
      begin
        task_results = Async do |task|
          functions.map do |func_run|
            task.async do
              result = execute_single_function_tool(func_run, agent, context_wrapper, runner, config)
              log_debug("🔧 STEP_PROCESSOR: Tool execution completed", result_class: result.class.name)
              result
            end
          end.map(&:wait)
        end
        
        results = task_results.wait
        log_debug("🔧 STEP_PROCESSOR: All tools completed", results_count: results.size)
        results
      rescue => e
        log_exception(e, message: "Error in parallel tool execution")
        raise
      end
    end

    ##
    # Execute a single function tool
    #
    def execute_single_function_tool(func_run, agent, context_wrapper, runner, _config)
      tool = func_run.function_tool
      tool_call = func_run.tool_call
      arguments = parse_tool_arguments(tool_call)

      log_debug("🔧 STEP_PROCESSOR: Executing tool", tool: tool.name, agent: agent.name)

      # Call tool start hooks
      runner.call_hook(:on_tool_start, context_wrapper, agent, tool)

      begin
        # Execute the tool with error handling
        result = ErrorHandling.safe_tool_execution(tool: tool, arguments: arguments, agent: agent) do
          tool.call(**arguments)
        end

        # Call tool end hooks
        runner.call_hook(:on_tool_end, context_wrapper, agent, tool, result)

        # Create function tool result
        run_item = create_tool_output_item(tool_call, result, agent)

        FunctionToolResult.new(
          tool: tool,
          output: result,
          run_item: run_item
        )
      rescue StandardError => e
        log_exception(e, message: "Tool execution failed", tool: tool.name, agent: agent.name)
        runner.call_hook(:on_tool_error, context_wrapper, agent, tool, e) if runner.respond_to?(:call_hook)

        # Create error result
        error_message = "Error: #{e.message}"
        run_item = create_tool_output_item(tool_call, error_message, agent)

        FunctionToolResult.new(
          tool: tool,
          output: error_message,
          run_item: run_item
        )
      end
    end

    ##
    # Execute computer actions sequentially
    #
    def execute_computer_actions(computer_actions, agent, context_wrapper, runner, config)
      return [] if computer_actions.empty?

      log_debug("💻 STEP_PROCESSOR: Executing computer actions", count: computer_actions.size)

      computer_actions.map do |action_run|
        # Computer actions must be sequential
        execute_single_computer_action(action_run, agent, context_wrapper, runner, config)
      end
    end

    ##
    # Execute local shell calls sequentially
    #
    def execute_local_shell_calls(shell_calls, agent, context_wrapper, runner, config)
      return [] if shell_calls.empty?

      log_debug("🖥️  STEP_PROCESSOR: Executing shell calls", count: shell_calls.size)

      shell_calls.map do |shell_run|
        # Shell calls must be sequential
        execute_single_shell_call(shell_run, agent, context_wrapper, runner, config)
      end
    end

    ##
    # Execute computer action (placeholder - implement based on your computer tool)
    #
    def execute_single_computer_action(_action_run, agent, _context_wrapper, _runner, _config)
      # This would integrate with your computer tool implementation
      # For now, return a placeholder result
      {
        type: "tool_output",
        content: "Computer action executed",
        agent: agent.name
      }
    end

    ##
    # Execute shell call (placeholder - implement based on your shell tool)
    #
    def execute_single_shell_call(_shell_run, agent, _context_wrapper, _runner, _config)
      # This would integrate with your shell tool implementation
      # For now, return a placeholder result
      {
        type: "tool_output",
        content: "Shell command executed",
        agent: agent.name
      }
    end

    ##
    # Execute handoffs with proper input filtering
    #
    def execute_handoffs(original_input:, pre_step_items:, new_step_items:,
                         processed_response:, agent:, context_wrapper:, runner:, config:)
      primary_handoff = processed_response.primary_handoff
      rejected_handoffs = processed_response.rejected_handoffs

      log_debug("🔄 STEP_PROCESSOR: Executing handoff",
                from: agent.name, to: get_handoff_agent_name(primary_handoff.handoff))

      # Add rejection messages for multiple handoffs
      rejected_handoffs.each do |rejected_handoff|
        new_step_items << create_tool_output_item(
          rejected_handoff.tool_call,
          "Multiple handoffs detected, ignoring this one.",
          agent
        )
      end

      # Execute the primary handoff
      target_agent = get_target_agent(primary_handoff.handoff)
      transfer_message = get_transfer_message(primary_handoff.handoff, target_agent)

      # Add handoff output item - OpenAI API expects output for every function call
      new_step_items << create_handoff_output_item(primary_handoff.tool_call, transfer_message, agent, target_agent)

      # Call handoff hooks
      runner.call_hook(:on_handoff, context_wrapper, agent, target_agent)

      # Return handoff result
      [new_step_items, NextStepHandoff.new(target_agent)]
    end

    ##
    # Check if tool results indicate final output
    #
    def check_for_final_output_from_tools(tool_results, agent, context_wrapper, _config)
      return nil if tool_results.empty?

      case agent.tool_use_behavior
      when "run_llm_again", nil, ToolUseBehavior::RunLLMAgain
        nil
      when "stop_on_first_tool", ToolUseBehavior::StopOnFirstTool
        tool_results.first.output
      when ToolUseBehavior::StopAtTools
        # Check if any tools match the stop list
        stop_tools = agent.tool_use_behavior.tool_names
        stop_result = tool_results.find { |result| stop_tools.include?(result.tool.name) }
        stop_result&.output
      when Hash
        # Legacy support for hash-based config
        stop_tools = agent.tool_use_behavior["stop_at_tool_names"] || []
        stop_result = tool_results.find { |result| stop_tools.include?(result.tool.name) }
        stop_result&.output
      when ToolUseBehavior::CustomFunction, Proc
        # Custom behavior function
        if agent.tool_use_behavior.respond_to?(:function)
          agent.tool_use_behavior.function.call(context_wrapper, tool_results)
        else
          agent.tool_use_behavior.call(context_wrapper, tool_results)
        end
      when ToolUseBehavior::ToolsToFinalOutput
        # Check if this is a final output tool
        # This would require more complex implementation
        nil
      else
        log_debug("Unhandled tool_use_behavior, defaulting to run_llm_again", behavior: agent.tool_use_behavior.class.name)
        nil
      end
    end

    ##
    # Check if message content indicates final output
    #
    def check_for_final_output_from_message(new_step_items, processed_response, _agent)
      # Only consider final output if no tools were executed
      return nil if processed_response.tools_or_actions_to_run?

      # Find the last message item
      message_items = new_step_items.select { |item| item.raw_item[:type] == "message" }
      last_message = message_items.last

      return nil unless last_message

      content = last_message.raw_item[:content]
      return content if content && !content.empty?

      ""
    end

    ##
    # Parse tool call arguments safely
    #
    def parse_tool_arguments(tool_call)
      arguments_json = tool_call[:arguments] || tool_call.dig(:function, :arguments) || "{}"

      begin
        JSON.parse(arguments_json, symbolize_names: true)
      rescue JSON::ParserError => e
        log_exception(e, message: "Failed to parse tool arguments", arguments: arguments_json)
        {}
      end
    end

    ##
    # Create tool output item
    #
    def create_tool_output_item(tool_call, result, agent)
      raw_item = {
        type: "tool_output",
        id: tool_call[:id] || tool_call[:call_id] || SecureRandom.uuid,
        content: result.to_s,
        agent: agent.name
      }
      Items::ToolCallOutputItem.new(agent: agent, raw_item: raw_item, output: result)
    end

    ##
    # Create handoff output item
    #
    def create_handoff_output_item(tool_call, transfer_message, from_agent, _to_agent)
      # Create function_call_output for OpenAI API compliance
      # Use call_id field if available, otherwise fall back to id
      call_id = tool_call[:call_id] || tool_call[:id] || tool_call.dig(:function, :id)

      # Debug the tool call structure
      log_debug("🔧 STEP_PROCESSOR: Creating handoff output",
                tool_call_keys: tool_call.keys,
                call_id: call_id,
                tool_call_id: tool_call[:id],
                function_id: tool_call.dig(:function, :id))

      raw_item = {
        type: "function_call_output",
        call_id: call_id,
        output: transfer_message
      }
      Items::FunctionCallOutputItem.new(agent: from_agent, raw_item: raw_item)
    end

    ##
    # Get agent name from handoff target (handles both Agent and Handoff objects)
    #
    def get_handoff_agent_name(handoff_target)
      case handoff_target
      when Agent
        handoff_target.name
      else
        # Handoff object - access the agent attribute
        handoff_target.agent.name
      end
    end

    ##
    # Get target agent from handoff (handles both Agent and Handoff objects)
    #
    def get_target_agent(handoff_target)
      case handoff_target
      when Agent
        # For Agent objects, the agent itself is the target
        handoff_target
      else
        # Handoff object - access the agent attribute
        handoff_target.agent
      end
    end

    ##
    # Get transfer message from handoff (handles both Agent and Handoff objects)
    #
    def get_transfer_message(_handoff_target, target_agent)
      # Return JSON format like Python implementation
      { assistant: target_agent.name }.to_json
    end

  end

end
