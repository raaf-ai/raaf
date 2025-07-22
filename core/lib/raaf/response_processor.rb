# frozen_string_literal: true

require "securerandom"
require_relative "processed_response"
require_relative "logging"
require_relative "step_errors"
require_relative "items"

module RAAF

  ##
  # Unified processor for model responses
  #
  # This class provides atomic processing of model responses, categorizing all
  # response elements (messages, tool calls, handoffs) in a single pass.
  # This eliminates coordination issues between multiple services and ensures
  # consistent state processing.
  #
  # Mirrors Python's process_model_response functionality with Ruby patterns.
  #
  class ResponseProcessor

    include Logger

    ##
    # Process a model response into categorized elements
    #
    # Takes a raw model response and categorizes all elements into appropriate
    # buckets for execution. This is the single source of truth for response
    # processing, eliminating the need for coordination between services.
    #
    # @param response [Hash] Raw model response from provider
    # @param agent [Agent] Current agent for tool/handoff resolution
    # @param all_tools [Array<Tool>] Available tools for the agent
    # @param handoffs [Array<Handoff>] Available handoffs for the agent
    # @return [ProcessedResponse] Categorized response elements
    #
    def process_model_response(response:, agent:, all_tools:, handoffs:)
      log_debug("🔄 RESPONSE_PROCESSOR: Processing model response",
                agent: agent.name, tools_count: all_tools.size, handoffs_count: handoffs.size)

      items = []
      run_handoffs = []
      functions = []
      computer_actions = []
      local_shell_calls = []
      tools_used = []

      # Create lookup maps for performance
      handoff_map = build_handoff_map(handoffs)
      function_map = build_function_map(all_tools)
      computer_tool = find_computer_tool(all_tools)
      local_shell_tool = find_local_shell_tool(all_tools)

      # Process response based on format
      response_items = extract_response_items(response)

      response_items.each do |item|
        process_response_item(
          item: item,
          agent: agent,
          items: items,
          run_handoffs: run_handoffs,
          functions: functions,
          computer_actions: computer_actions,
          local_shell_calls: local_shell_calls,
          tools_used: tools_used,
          handoff_map: handoff_map,
          function_map: function_map,
          computer_tool: computer_tool,
          local_shell_tool: local_shell_tool
        )
      end

      log_debug("✅ RESPONSE_PROCESSOR: Processed response",
                items: items.size, handoffs: run_handoffs.size,
                functions: functions.size, tools_used: tools_used)

      ProcessedResponse.new(
        new_items: items,
        handoffs: run_handoffs,
        functions: functions,
        computer_actions: computer_actions,
        local_shell_calls: local_shell_calls,
        tools_used: tools_used
      )
    end

    private

    ##
    # Extract response items from various response formats
    #
    # Handles both traditional message format and Responses API format
    #
    # @param response [Hash] Raw model response
    # @return [Array<Hash>] Normalized response items
    #
    def extract_response_items(response)
      if response[:choices]&.first&.dig(:message)
        # Traditional Chat Completions format
        message = response[:choices].first[:message]
        items = [message]

        # Add tool calls as separate items if present
        items.concat(message[:tool_calls]) if message[:tool_calls]

        items
      elsif response[:output]
        # Responses API format
        response[:output]
      else
        # Direct message format
        [response]
      end
    end

    ##
    # Process a single response item and categorize it
    #
    def process_response_item(item:, agent:, items:, run_handoffs:, functions:,
                              computer_actions:, local_shell_calls:, tools_used:,
                              handoff_map:, function_map:, computer_tool:, local_shell_tool:)
      case item[:type] || infer_item_type(item)
      when "message", nil
        items << create_message_item(item, agent)

      when "function", "tool_call", "function_call"
        process_tool_call(
          item: item,
          agent: agent,
          items: items,
          run_handoffs: run_handoffs,
          functions: functions,
          tools_used: tools_used,
          handoff_map: handoff_map,
          function_map: function_map
        )

      when "computer_use"
        process_computer_action(
          item: item,
          agent: agent,
          items: items,
          computer_actions: computer_actions,
          tools_used: tools_used,
          computer_tool: computer_tool
        )

      when "local_shell"
        process_local_shell_call(
          item: item,
          agent: agent,
          items: items,
          local_shell_calls: local_shell_calls,
          tools_used: tools_used,
          local_shell_tool: local_shell_tool
        )

      when "file_search"
        items << create_tool_call_item(item, agent)
        tools_used << "file_search"

      when "web_search"
        items << create_tool_call_item(item, agent)
        tools_used << "web_search"

      else
        log_warn("Unknown response item type", type: item[:type], item_keys: item.keys)
        items << create_message_item(item, agent) # Treat unknown items as messages
      end
    end

    ##
    # Process a function/tool call
    #
    def process_tool_call(item:, agent:, items:, run_handoffs:, functions:,
                          tools_used:, handoff_map:, function_map:)
      tool_name = item[:name] || item.dig(:function, :name)
      return unless tool_name

      tools_used << tool_name

      if handoff_map[tool_name]
        # This is a handoff
        items << create_handoff_call_item(item, agent)
        run_handoffs << ToolRunHandoff.new(
          tool_call: item,
          handoff: handoff_map[tool_name]
        )
      elsif function_map[tool_name]
        # Regular function tool
        items << create_tool_call_item(item, agent)
        functions << ToolRunFunction.new(
          tool_call: item,
          function_tool: function_map[tool_name]
        )
      else
        error = Errors::ModelBehaviorError.new("Tool #{tool_name} not found in agent #{agent.name}", agent: agent)
        log_exception(error, message: "Tool not found", tool_name: tool_name, agent: agent.name)
        raise error
      end
    end

    ##
    # Process a computer action
    #
    def process_computer_action(item:, agent:, items:, computer_actions:,
                                tools_used:, computer_tool:)
      unless computer_tool
        error = Errors::ModelBehaviorError.new("Computer tool not available for agent #{agent.name}", agent: agent)
        log_exception(error, message: "Computer tool not available", agent: agent.name)
        raise error
      end

      items << create_tool_call_item(item, agent)
      tools_used << "computer_use"
      computer_actions << ToolRunComputerAction.new(
        tool_call: item,
        computer_tool: computer_tool
      )
    end

    ##
    # Process a local shell call
    #
    def process_local_shell_call(item:, agent:, items:, local_shell_calls:,
                                 tools_used:, local_shell_tool:)
      unless local_shell_tool
        error = Errors::ModelBehaviorError.new("Local shell tool not available for agent #{agent.name}", agent: agent)
        log_exception(error, message: "Local shell tool not available", agent: agent.name)
        raise error
      end

      items << create_tool_call_item(item, agent)
      tools_used << "local_shell"
      local_shell_calls << ToolRunLocalShellCall.new(
        tool_call: item,
        local_shell_tool: local_shell_tool
      )
    end

    ##
    # Build lookup map for handoffs by tool name
    #
    def build_handoff_map(handoffs)
      handoffs.to_h do |handoff|
        tool_name = case handoff
                    when Agent
                      # For Agent objects, generate the default tool name
                      "transfer_to_#{snake_case(handoff.name)}"
                    else
                      # For Handoff objects, use the tool_name attribute
                      handoff.tool_name
                    end
        [tool_name, handoff]
      end
    end

    ##
    # Build lookup map for function tools by name
    #
    def build_function_map(all_tools)
      all_tools.select { |tool| tool.is_a?(FunctionTool) }
               .to_h { |tool| [tool.name, tool] }
    end

    ##
    # Find computer tool in available tools
    #
    def find_computer_tool(all_tools)
      all_tools.find { |tool| tool.class.name.include?("Computer") }
    end

    ##
    # Find local shell tool in available tools
    #
    def find_local_shell_tool(all_tools)
      all_tools.find { |tool| tool.class.name.include?("LocalShell") }
    end

    ##
    # Infer item type from item structure
    #
    def infer_item_type(item)
      if item[:role] && item[:content]
        "message"
      elsif item[:name] || item[:function]
        "function"
      elsif item[:action]
        "computer_use"
      elsif item[:command]
        "local_shell"
      end
    end

    ##
    # Create message item from response
    #
    def create_message_item(item, agent)
      raw_item = {
        type: "message",
        role: item[:role] || "assistant",
        content: item[:content] || "",
        agent: agent.name
      }
      Items::MessageOutputItem.new(agent: agent, raw_item: raw_item)
    end

    ##
    # Create tool call item from response
    #
    def create_tool_call_item(item, agent)
      raw_item = {
        type: "tool_call",
        id: item[:id] || item[:call_id] || SecureRandom.uuid,
        name: item[:name] || item.dig(:function, :name),
        arguments: item[:arguments] || item.dig(:function, :arguments) || "{}",
        agent: agent.name
      }
      Items::ToolCallItem.new(agent: agent, raw_item: raw_item)
    end

    ##
    # Create handoff call item from response
    #
    def create_handoff_call_item(item, agent)
      raw_item = {
        type: "function_call",
        id: item[:id] || item[:call_id] || SecureRandom.uuid,
        name: item[:name] || item.dig(:function, :name),
        arguments: item[:arguments] || item.dig(:function, :arguments) || "{}",
        agent: agent.name
      }
      Items::HandoffCallItem.new(agent: agent, raw_item: raw_item)
    end

    ##
    # Convert string to snake_case
    #
    def snake_case(str)
      str.to_s
         .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
         .gsub(/([a-z\d])([A-Z])/, '\1_\2')
         .gsub(/\s+/, "_")
         .downcase
    end

  end

end
