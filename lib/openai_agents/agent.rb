# frozen_string_literal: true

require_relative "function_tool"
require_relative "errors"

module OpenAIAgents
  ##
  # Agent - The core class representing an AI agent with configurable behavior, tools, and handoffs
  #
  # An Agent represents a single AI assistant with specific instructions, tools, and the ability
  # to hand off control to other agents. Agents are the building blocks of multi-agent workflows.
  #
  # == Features
  #
  # * Configurable instructions and model selection
  # * Tool integration for extending capabilities
  # * Agent handoffs for workflow orchestration
  # * Conversation turn limits for safety
  # * Provider-agnostic model support
  #
  # == Basic Usage
  #
  #   # Create a simple agent
  #   agent = OpenAIAgents::Agent.new(
  #     name: "MyAgent",
  #     instructions: "You are a helpful assistant",
  #     model: "gpt-4"
  #   )
  #
  # == Adding Tools
  #
  #   # Define a tool function
  #   def get_weather(city)
  #     "The weather in #{city} is sunny with 22°C"
  #   end
  #
  #   # Add the tool to the agent
  #   agent.add_tool(method(:get_weather))
  #
  #   # Or add a proc
  #   calculator = proc { |expression| eval(expression) }
  #   agent.add_tool(calculator)
  #
  # == Agent Handoffs
  #
  #   # Create multiple agents
  #   weather_agent = OpenAIAgents::Agent.new(name: "WeatherBot")
  #   math_agent = OpenAIAgents::Agent.new(name: "MathBot")
  #
  #   # Set up handoffs
  #   weather_agent.add_handoff(math_agent)
  #   math_agent.add_handoff(weather_agent)
  #
  #   # Check handoff availability
  #   weather_agent.can_handoff_to?("MathBot") # => true
  #
  # == Advanced Configuration
  #
  #   agent = OpenAIAgents::Agent.new(
  #     name: "AdvancedAgent",
  #     instructions: "You are a specialized assistant",
  #     model: "claude-3-sonnet-20240229",  # Use Anthropic's Claude
  #     max_turns: 20,                      # Allow more conversation turns
  #     tools: [existing_tool],             # Pre-configured tools
  #     handoffs: [other_agent]             # Pre-configured handoffs
  #   )
  #
  # @author OpenAI Agents Ruby Team
  # @since 0.1.0
  class Agent
    ##
    # @!attribute [rw] name
    #   @return [String] the unique name identifier for this agent
    # @!attribute [rw] instructions
    #   @return [String, nil] the system instructions that define the agent's behavior
    # @!attribute [rw] tools
    #   @return [Array<FunctionTool>] array of tools available to this agent
    # @!attribute [rw] handoffs
    #   @return [Array<Agent>] array of agents this agent can hand off to
    # @!attribute [rw] model
    #   @return [String] the LLM model this agent uses (e.g., "gpt-4", "claude-3-sonnet")
    # @!attribute [rw] max_turns
    #   @return [Integer] maximum number of conversation turns before stopping
    # @!attribute [rw] output_schema
    #   @return [Hash, nil] JSON schema for structured output validation
    attr_accessor :name, :instructions, :tools, :handoffs, :model, :max_turns, :output_schema

    ##
    # Creates a new Agent instance
    #
    # @param name [String] unique identifier for the agent
    # @param instructions [String, nil] system instructions defining agent behavior
    # @param tools [Array<FunctionTool, Proc, Method>] tools available to the agent
    # @param handoffs [Array<Agent>] agents this agent can hand off to
    # @param model [String] LLM model to use (default: "gpt-4")
    # @param max_turns [Integer] maximum conversation turns (default: 10)
    #
    # @example Create a basic agent
    #   agent = OpenAIAgents::Agent.new(
    #     name: "Customer Support",
    #     instructions: "Help customers with their questions",
    #     model: "gpt-4"
    #   )
    #
    # @example Create an agent with tools and handoffs
    #   agent = OpenAIAgents::Agent.new(
    #     name: "Sales Agent",
    #     instructions: "Help with sales inquiries",
    #     tools: [search_tool, calculator_tool],
    #     handoffs: [support_agent],
    #     max_turns: 15
    #   )
    def initialize(name:, instructions: nil, **options)
      @name = name
      @instructions = instructions
      @tools = (options[:tools] || []).dup
      @handoffs = (options[:handoffs] || []).dup
      @model = options[:model] || "gpt-4"
      @max_turns = options[:max_turns] || 10
      @output_schema = options[:output_schema]
    end

    ##
    # Adds a tool to the agent's available tools
    #
    # Tools can be Ruby methods, procs, or FunctionTool objects. They extend the agent's
    # capabilities by allowing it to perform specific actions or retrieve information.
    #
    # @param tool [Proc, Method, FunctionTool] the tool to add
    # @return [void]
    # @raise [ToolError] if the tool type is not supported
    #
    # @example Add a method as a tool
    #   def get_weather(city)
    #     "Weather in #{city}: sunny, 22°C"
    #   end
    #   agent.add_tool(method(:get_weather))
    #
    # @example Add a proc as a tool
    #   calculator = proc { |expression| eval(expression) }
    #   agent.add_tool(calculator)
    #
    # @example Add a FunctionTool
    #   tool = OpenAIAgents::FunctionTool.new(
    #     proc { |query| search_database(query) },
    #     name: "search",
    #     description: "Search the database"
    #   )
    #   agent.add_tool(tool)
    def add_tool(tool)
      case tool
      when Proc, Method
        @tools << FunctionTool.new(tool)
      when FunctionTool
        @tools << tool
      when OpenAIAgents::Tools::WebSearchTool, OpenAIAgents::Tools::HostedFileSearchTool, OpenAIAgents::Tools::HostedComputerTool
        @tools << tool
      else
        raise ToolError,
              "Tool must be a Proc, Method, FunctionTool, or hosted tool (WebSearchTool, HostedFileSearchTool, HostedComputerTool)"
      end
    end

    ##
    # Adds another agent as a handoff target
    #
    # Handoffs allow agents to transfer control to other specialized agents during
    # a conversation, enabling complex multi-agent workflows.
    #
    # @param agent [Agent] the agent to add as a handoff target
    # @return [void]
    # @raise [HandoffError] if the parameter is not an Agent instance
    #
    # @example Set up agent handoffs
    #   support_agent = OpenAIAgents::Agent.new(name: "Support")
    #   sales_agent = OpenAIAgents::Agent.new(name: "Sales")
    #
    #   # Sales can hand off to support
    #   sales_agent.add_handoff(support_agent)
    #
    #   # Support can hand off back to sales
    #   support_agent.add_handoff(sales_agent)
    def add_handoff(agent)
      raise HandoffError, "Handoff must be an Agent" unless agent.is_a?(Agent)

      @handoffs << agent
    end

    ##
    # Converts the agent to a hash representation
    #
    # Useful for serialization, debugging, or API interactions that require
    # hash-based data structures.
    #
    # @return [Hash] hash representation of the agent
    #
    # @example
    #   agent_hash = agent.to_h
    #   # => {
    #   #   name: "MyAgent",
    #   #   instructions: "You are helpful",
    #   #   tools: [...],
    #   #   handoffs: ["OtherAgent"],
    #   #   model: "gpt-4",
    #   #   max_turns: 10
    #   # }
    def to_h
      {
        name: @name,
        instructions: @instructions,
        tools: safe_map_to_h(@tools),
        handoffs: safe_map_names(@handoffs),
        model: @model,
        max_turns: @max_turns,
        output_schema: @output_schema
      }
    end

    ##
    # Checks if the agent can hand off to another agent
    #
    # @param agent_name [String] name of the target agent
    # @return [Boolean] true if handoff is possible, false otherwise
    #
    # @example
    #   agent.add_handoff(other_agent)
    #   agent.can_handoff_to?("OtherAgent") # => true
    #   agent.can_handoff_to?("UnknownAgent") # => false
    def can_handoff_to?(agent_name)
      @handoffs.any? { |agent| agent.name == agent_name }
    end

    ##
    # Finds a handoff target agent by name
    #
    # @param agent_name [String] name of the target agent
    # @return [Agent, nil] the target agent if found, nil otherwise
    #
    # @example
    #   target = agent.find_handoff("SupportAgent")
    #   if target
    #     puts "Found handoff target: #{target.name}"
    #   end
    def find_handoff(agent_name)
      @handoffs.find { |agent| agent.name == agent_name }
    end

    ##
    # Checks if the agent has any tools available
    #
    # @return [Boolean] true if the agent has tools, false otherwise
    #
    # @example
    #   if agent.tools?
    #     puts "Agent has #{agent.tools.length} tools"
    #   else
    #     puts "Agent has no tools"
    #   end
    def tools?
      !@tools.empty?
    end

    ##
    # Executes a specific tool by name
    #
    # This method allows direct execution of agent tools, useful for testing
    # or programmatic tool invocation.
    #
    # @param tool_name [String] name of the tool to execute
    # @param kwargs [Hash] keyword arguments to pass to the tool
    # @return [Object] the result returned by the tool
    # @raise [ToolError] if the tool is not found or execution fails
    #
    # @example Execute a tool directly
    #   result = agent.execute_tool("get_weather", city: "Paris")
    #   puts result # => "Weather in Paris: sunny, 22°C"
    #
    # @example Handle tool execution errors
    #   begin
    #     result = agent.execute_tool("unknown_tool")
    #   rescue OpenAIAgents::ToolError => e
    #     puts "Tool error: #{e.message}"
    #   end
    def execute_tool(tool_name, **)
      tool = @tools.find { |t| t.name == tool_name }
      raise ToolError, "Tool '#{tool_name}' not found" unless tool

      tool.call(**)
    end

    private

    def safe_map_to_h(collection)
      return [] unless collection.respond_to?(:map)

      collection.map do |item|
        if item.respond_to?(:to_h)
          item.to_h
        else
          item.to_s
        end
      end
    rescue StandardError
      []
    end

    def safe_map_names(collection)
      return [] unless collection.respond_to?(:map)

      collection.map do |item|
        if item.respond_to?(:name)
          item.name
        else
          item.to_s
        end
      end
    rescue StandardError
      []
    end
  end
end
