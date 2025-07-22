# frozen_string_literal: true

module RAAF

  ##
  # Centralized tracker for agent tool usage
  #
  # This class provides a single source of truth for tracking which tools
  # each agent has used during execution. This eliminates scattered tool
  # tracking across multiple services and prevents state inconsistencies.
  #
  # Mirrors Python's AgentToolUseTracker functionality.
  #
  class ToolUseTracker

    ##
    # Initialize a new tool use tracker
    #
    def initialize
      @agent_to_tools = {}
    end

    ##
    # Add tool usage for an agent
    #
    # Records that an agent has used the specified tools. If the agent
    # already has recorded tool usage, the new tools are added to the
    # existing list.
    #
    # @param agent [Agent] The agent that used the tools
    # @param tool_names [Array<String>] Names of tools used
    # @return [void]
    #
    # @example Recording tool usage
    #   tracker.add_tool_use(agent, ["get_weather", "send_email"])
    #   tracker.add_tool_use(agent, ["search_web"])  # Adds to existing
    #
    def add_tool_use(agent, tool_names)
      return if tool_names.empty?

      @agent_to_tools[agent] ||= []
      @agent_to_tools[agent].concat(tool_names)

      # Remove duplicates while preserving order
      @agent_to_tools[agent].uniq!
    end

    ##
    # Check if an agent has used any tools
    #
    # @param agent [Agent] The agent to check
    # @return [Boolean] true if agent has used tools, false otherwise
    #
    # @example Checking tool usage
    #   if tracker.used_tools?(agent)
    #     puts "Agent has used tools"
    #   end
    #
    def used_tools?(agent)
      tools = @agent_to_tools[agent]
      !tools.nil? && !tools.empty?
    end

    ##
    # Get tools used by an agent
    #
    # @param agent [Agent] The agent to get tools for
    # @return [Array<String>] Names of tools used by agent (empty if none)
    #
    def tools_used_by(agent)
      @agent_to_tools[agent] || []
    end

    ##
    # Get all agents that have used tools
    #
    # @return [Array<Agent>] Agents that have used at least one tool
    #
    def agents_with_tool_usage
      @agent_to_tools.keys.select { |agent| used_tools?(agent) }
    end

    ##
    # Get total number of tools used across all agents
    #
    # @return [Integer] Total unique tool usage count
    #
    def total_tool_usage_count
      @agent_to_tools.values.map(&:size).sum
    end

    ##
    # Check if a specific tool has been used by any agent
    #
    # @param tool_name [String] Name of tool to check
    # @return [Boolean] true if any agent used the tool
    #
    def tool_used?(tool_name)
      @agent_to_tools.values.any? { |tools| tools.include?(tool_name) }
    end

    ##
    # Clear all tool usage data
    #
    # @return [void]
    #
    def clear
      @agent_to_tools.clear
    end

    ##
    # Get summary of tool usage across all agents
    #
    # @return [Hash] Summary with agent names as keys and tool lists as values
    #
    def usage_summary
      @agent_to_tools.transform_keys(&:name)
    end

    ##
    # Debug representation of tracker state
    #
    # @return [String] Human-readable tracker state
    #
    def to_s
      if @agent_to_tools.empty?
        "ToolUseTracker(no usage)"
      else
        agent_summaries = @agent_to_tools.map do |agent, tools|
          "#{agent.name}:#{tools.size}"
        end.join(", ")
        "ToolUseTracker(#{agent_summaries})"
      end
    end

    ##
    # Inspect representation for debugging
    #
    def inspect
      "#<ToolUseTracker agents=#{@agent_to_tools.size} " \
        "total_tools=#{total_tool_usage_count}>"
    end

  end

end
