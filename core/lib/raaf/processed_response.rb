# frozen_string_literal: true

module RAAF

  ##
  # Immutable processed response from model with categorized elements
  #
  # This structure mirrors Python's ProcessedResponse and provides atomic processing
  # of model responses, eliminating the coordination issues between services.
  # All response elements are categorized once and processed together.
  #
  # @example Creating a processed response
  #   processed = ProcessedResponse.new(
  #     new_items: [message_item, tool_call_item],
  #     handoffs: [handoff_data],
  #     functions: [function_data],
  #     tools_used: ["get_weather", "transfer_to_agent"],
  #     computer_actions: [],
  #     local_shell_calls: []
  #   )
  #
  ProcessedResponse = Data.define(
    :new_items,           # Array<Hash> - Message and tool call items from response
    :handoffs,            # Array<ToolRunHandoff> - Handoffs to execute
    :functions,           # Array<ToolRunFunction> - Function tools to execute
    :computer_actions,    # Array<ToolRunComputerAction> - Computer actions to execute
    :local_shell_calls,   # Array<ToolRunLocalShellCall> - Local shell calls to execute
    :tools_used           # Array<String> - Names of all tools used
  ) do
    ##
    # Check if there are tools or actions that need local processing
    #
    # Handoffs, functions, and computer actions need local processing.
    # Hosted tools have already run, so there's nothing to do for them.
    #
    # @return [Boolean] true if tools need processing
    def tools_or_actions_to_run?
      handoffs.any? || functions.any? || computer_actions.any? || local_shell_calls.any?
    end

    ##
    # Check if any tools were used in this response
    #
    # @return [Boolean] true if tools were used
    def tool_usage?
      tools_used.any?
    end

    ##
    # Check if any handoffs were detected
    #
    # @return [Boolean] true if handoffs occurred
    def handoffs_detected?
      handoffs.any?
    end

    ##
    # Get the primary handoff (first one if multiple)
    #
    # Following Python's pattern of only processing the first handoff
    # when multiple handoffs are detected in a single response.
    #
    # @return [ToolRunHandoff, nil] The primary handoff or nil
    def primary_handoff
      handoffs.first
    end

    ##
    # Get rejected handoffs (all but first if multiple)
    #
    # @return [Array<ToolRunHandoff>] Handoffs to reject
    def rejected_handoffs
      handoffs[1..] || []
    end
  end

  ##
  # Data structure for handoff tool execution
  #
  ToolRunHandoff = Data.define(:handoff, :tool_call) do
    def to_s
      agent_name = if handoff.class.name == "RAAF::Agent"
                     handoff.name
                   else
                     # Handoff object - access the agent attribute
                     handoff.agent.name
                   end
      "ToolRunHandoff(#{agent_name})"
    end
  end

  ##
  # Data structure for function tool execution
  #
  ToolRunFunction = Data.define(:tool_call, :function_tool) do
    def to_s
      "ToolRunFunction(#{function_tool.name})"
    end
  end

  ##
  # Data structure for computer action execution
  #
  ToolRunComputerAction = Data.define(:tool_call, :computer_tool) do
    def to_s
      "ToolRunComputerAction(#{tool_call["action"]&.dig("type")})"
    end
  end

  ##
  # Data structure for local shell call execution
  #
  ToolRunLocalShellCall = Data.define(:tool_call, :local_shell_tool) do
    def to_s
      "ToolRunLocalShellCall(#{tool_call["command"]})"
    end
  end

  ##
  # Result of function tool execution
  #
  FunctionToolResult = Data.define(:tool, :output, :run_item) do
    def success?
      !output.nil?
    end

    def to_s
      tool_name = tool.respond_to?(:name) ? tool.name : tool.to_s
      "FunctionToolResult(#{tool_name}: #{output&.class&.name})"
    end
  end

end
