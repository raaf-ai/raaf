# frozen_string_literal: true

require "securerandom"
require_relative "function_tool"
require_relative "errors"
require_relative "lifecycle"
require_relative "agent_output"
require_relative "tool_use_behavior"
require_relative "model_settings"
require_relative "logging"
require_relative "handoffs"
require_relative "handoff"
require_relative "utils"

module RAAF

  ##
  # Agent - The core class representing an AI agent with configurable behavior, tools, and handoffs
  #
  # This is the main Agent class that provides Python SDK compatible handoff functionality
  # while maintaining all the original Agent features. It combines the best of both worlds:
  # - Full backward compatibility with existing Agent API
  # - Python SDK compatible handoff system with explicit tool generation
  # - Automatic tool generation for handoffs
  # - Context preservation during handoffs
  #
  # == Features
  #
  # * Configurable instructions and model selection
  # * Tool integration for extending capabilities
  # * Python SDK compatible agent handoffs for workflow orchestration
  # * Conversation turn limits for safety
  # * Provider-agnostic model support
  # * Automatic handoff tool generation
  # * Full context preservation during handoffs
  #
  # == Basic Usage
  #
  #   # Create a simple agent
  #   agent = RAAF::Agent.new(
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
  # == Python SDK Compatible Agent Handoffs
  #
  #   # Create agents with handoff capabilities
  #   support_agent = RAAF::Agent.new(name: "Support", instructions: "Handle support issues")
  #   sales_agent = RAAF::Agent.new(
  #     name: "Sales",
  #     instructions: "Handle sales inquiries",
  #     handoffs: [support_agent]  # Handoffs specified in constructor
  #   )
  #
  #   # Handoff tools are automatically generated
  #   # The sales agent now has a "transfer_to_support" tool
  #
  # == Dynamic Agent Handoffs (adding handoffs after creation)
  #
  #   # Create multiple agents
  #   weather_agent = RAAF::Agent.new(name: "WeatherBot")
  #   math_agent = RAAF::Agent.new(name: "MathBot")
  #
  #   # Add handoffs dynamically after agent creation
  #   weather_agent.add_handoff(math_agent)
  #   math_agent.add_handoff(weather_agent)
  #
  #   # Check handoff availability
  #   weather_agent.can_handoff_to?("MathBot") # => true
  #
  # == Advanced Configuration
  #
  #   agent = RAAF::Agent.new(
  #     name: "AdvancedAgent",
  #     instructions: "You are a specialized assistant",
  #     model: "claude-3-sonnet-20240229",  # Use Anthropic's Claude
  #     max_turns: 20,                      # Allow more conversation turns
  #     tools: [existing_tool],             # Pre-configured tools
  #     handoffs: [other_agent],            # Pre-configured handoffs (Python SDK style)
  #     handoff_description: "Transfer to me for advanced analysis"
  #   )
  #
  # @author RAAF Team
  # @since 0.1.0
  class Agent

    include Logger

    ##
    # @!attribute [rw] name
    #   @return [String] the unique name identifier for this agent
    # @!attribute [rw] instructions
    #   @return [String, nil] the system instructions that define the agent's behavior
    # @!attribute [rw] tools
    #   @return [Array<FunctionTool>] array of tools available to this agent
    # @!attribute [rw] handoffs
    #   @return [Array<Agent, Handoff>] array of agents or handoff objects this agent can hand off to
    # @!attribute [rw] model
    #   @return [String] the LLM model this agent uses (e.g., "gpt-4", "claude-3-sonnet")
    # @!attribute [rw] max_turns
    #   @return [Integer] maximum number of conversation turns before stopping
    # @!attribute [rw] output_type
    #   @return [Class, AgentOutputSchemaBase, nil] the expected output type for the agent
    # @!attribute [rw] hooks
    #   @return [AgentHooks, nil] lifecycle hooks for this specific agent
    # @!attribute [rw] prompt
    #   @return [Prompt, DynamicPromptFunction, Hash, Proc, nil] prompt configuration for Responses API
    # @!attribute [rw] input_guardrails
    #   @return [Array<InputGuardrail>] input validation guardrails
    # @!attribute [rw] output_guardrails
    #   @return [Array<OutputGuardrail>] output validation guardrails
    # @!attribute [rw] handoff_description
    #   @return [String, nil] description of when/why to handoff to this agent
    # @!attribute [rw] tool_use_behavior
    #   @return [ToolUseBehavior::Base, String, Symbol, Proc] controls how tools are handled
    # @!attribute [rw] reset_tool_choice
    #   @return [Boolean] whether to reset tool choice after tool calls
    # @!attribute [rw] response_format
    #   @return [Hash, nil] RAAF response format for structured output (e.g., JSON schema)
    # @!attribute [rw] tool_choice
    #   @return [String, Hash, nil] tool choice strategy - "auto", "none", "required", or specific tool
    # @!attribute [rw] model_settings
    #   @return [Hash, nil] model-specific settings for fine-tuning behavior (compatible with Python SDK)
    # @!attribute [rw] context
    #   @return [Object, nil] dependency injection object for agent run context (compatible with Python SDK)
    # @!attribute [rw] reset_tool_choice
    #   @return [Boolean] whether to reset tool_choice to nil after tool calls (default: true, compatible with Python SDK)
    attr_accessor :name, :instructions, :tools, :handoffs, :model, :max_turns, :output_type, :hooks, :prompt,
                  :input_guardrails, :output_guardrails, :handoff_description, :tool_use_behavior, :reset_tool_choice, :response_format, :tool_choice, :memory_store, :model_settings, :context, :on_handoff

    ##
    # Creates a new Agent instance
    #
    # @param name [String] unique identifier for the agent
    # @param instructions [String, nil] system instructions defining agent behavior
    # @param tools [Array<FunctionTool, Proc, Method>] tools available to the agent
    # @param handoffs [Array<Agent>] agents this agent can hand off to
    # @param model [String] LLM model to use (default: "gpt-4")
    # @param max_turns [Integer] maximum conversation turns (default: 10)
    # @param model_settings [Hash, nil] model-specific settings for fine-tuning behavior (compatible with Python SDK)
    # @param context [Object, nil] dependency injection object for agent run context (compatible with Python SDK)
    # @param reset_tool_choice [Boolean] whether to reset tool choice after tool calls (default: true)
    # @param tool_use_behavior [Symbol, String, Proc] controls how tools are handled (default: :run_llm_again)
    # @param block [Block] optional configuration block for Ruby-style setup
    #
    # @example Create a basic agent
    #   agent = RAAF::Agent.new(
    #     name: "Customer Support",
    #     instructions: "Help customers with their questions",
    #     model: "gpt-4"
    #   )
    #
    # @example Create an agent with tools and handoffs
    #   agent = RAAF::Agent.new(
    #     name: "Sales Agent",
    #     instructions: "Help with sales inquiries",
    #     tools: [search_tool, calculator_tool],
    #     handoffs: [support_agent],
    #     max_turns: 15
    #   )
    #
    # @example Create an agent with tool choice control
    #   agent = RAAF::Agent.new(
    #     name: "Tool Agent",
    #     instructions: "Use tools efficiently",
    #     tool_choice: "required",
    #     reset_tool_choice: false  # Keep tool_choice after tool calls
    #   )
    #
    # @example Create an agent with Python SDK compatible parameters
    #   agent = RAAF::Agent.new(
    #     name: "Advanced Agent",
    #     instructions: "You are a specialized assistant",
    #     model: "gpt-4o",
    #     model_settings: { temperature: 0.7, max_tokens: 1000 },
    #     context: { user_id: "123", session_id: "abc" },
    #     reset_tool_choice: false,
    #     tool_use_behavior: :return_direct
    #   )
    #
    # @example Create an agent with block-based configuration (Ruby-idiomatic)
    #   agent = RAAF::Agent.new(name: "Assistant") do |config|
    #     config.instructions = "You are a helpful assistant"
    #     config.model = "gpt-4o"
    #     config.max_turns = 20
    #     config.add_tool(calculator_tool)
    #     config.add_handoff(other_agent)
    #   end
    def initialize(name:, instructions: nil, **options)
      @name = name
      self.instructions = instructions # Use setter to support dynamic instructions
      @tools = (options[:tools] || []).dup
      @handoffs = (options[:handoffs] || []).dup
      @model = options[:model] || "gpt-4"
      @max_turns = options[:max_turns] || 10
      @output_type = options[:output_type]
      @hooks = options[:hooks]
      @prompt = options[:prompt]
      @input_guardrails = (options[:input_guardrails] || []).dup
      @output_guardrails = (options[:output_guardrails] || []).dup
      @handoff_description = options[:handoff_description]
      @response_format = options[:response_format]
      @tool_choice = options[:tool_choice]
      @model_settings = ModelSettings.from_hash(options[:model_settings]) if options[:model_settings]
      @context = options[:context]
      @on_handoff = options[:on_handoff]

      # Memory system integration (only use if Memory module is available)
      @memory_store = if options[:memory_store]
                        options[:memory_store]
                      elsif defined?(RAAF::Memory)
                        RAAF::Memory.default_store || RAAF::Memory::InMemoryStore.new
                      end

      # Tool use behavior configuration
      @tool_use_behavior = ToolUseBehavior.from_config(options[:tool_use_behavior] || :run_llm_again)
      @reset_tool_choice = options.fetch(:reset_tool_choice, true)

      # Handle output_type configuration
      configure_output_type

      # Auto-generate handoff tools (Python SDK compatibility)
      generate_handoff_tools if @handoffs.any?

      # Apply block-based configuration if provided (Ruby-idiomatic pattern)
      yield(self) if block_given?
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
    #   tool = RAAF::FunctionTool.new(
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
      else
        raise ToolError,
              "Tool must be a Proc, Method, or FunctionTool"
      end
    end

    ##
    # Adds a handoff target
    #
    # Handoffs allow agents to transfer control to other specialized agents during
    # a conversation, enabling complex multi-agent workflows.
    #
    # @param handoff [Agent, Handoff] the agent or handoff object to add
    # @return [void]
    # @raise [HandoffError] if the parameter is not an Agent or Handoff instance
    #
    # @example Set up agent handoffs
    #   support_agent = RAAF::Agent.new(name: "Support")
    #   sales_agent = RAAF::Agent.new(name: "Sales")
    #
    #   # Sales can hand off to support
    #   sales_agent.add_handoff(support_agent)
    #
    #   # Support can hand off back to sales
    #   support_agent.add_handoff(sales_agent)
    #
    # @example Use handoff objects for more control
    #   handoff = RAAF.handoff(
    #     support_agent,
    #     tool_description_override: "Transfer to support for technical issues"
    #   )
    #   sales_agent.add_handoff(handoff)
    def add_handoff(handoff)
      log_debug("🔗 HANDOFF FLOW: Adding handoff to agent",
                agent: @name,
                handoff_type: handoff.class.name)

      unless handoff.is_a?(Agent) || handoff.is_a?(Handoff)
        log_error("🔗 HANDOFF FLOW: Invalid handoff type",
                  agent: @name,
                  provided_type: handoff.class.name,
                  expected_types: "Agent or Handoff")
        raise HandoffError, "Handoff must be an Agent or Handoff object"
      end

      target_name = handoff.is_a?(Agent) ? handoff.name : handoff.agent_name
      log_debug_handoff("🔗 HANDOFF FLOW: Adding handoff capability",
                        from_agent: @name,
                        to_agent: target_name,
                        handoff_type: handoff.class.name)

      @handoffs << handoff

      # Auto-generate handoff tool for the new handoff (Python SDK compatibility)
      tool = create_handoff_tool(handoff)
      add_tool(tool)

      log_debug("🔗 HANDOFF FLOW: Handoff added successfully",
                agent: @name,
                target_agent: target_name,
                total_handoffs: @handoffs.count)
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
        response_format: @response_format
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
      @handoffs.any? do |handoff|
        case handoff
        when Agent
          handoff.name == agent_name
        when Handoff
          handoff.agent_name == agent_name
        end
      end
    end

    ##
    # Finds a handoff target by name
    #
    # @param agent_name [String] name of the target agent
    # @return [Agent, Handoff, nil] the target agent or handoff if found, nil otherwise
    #
    # @example
    #   target = agent.find_handoff("SupportAgent")
    #   if target
    #     puts "Found handoff target: #{target.name}"
    #   end
    def find_handoff(agent_name)
      log_debug_handoff("Looking for handoff target",
                        from_agent: @name,
                        requested_agent: agent_name,
                        available_handoffs: @handoffs.map { |h| h.is_a?(Agent) ? h.name : h.agent_name }.join(", "))

      result = @handoffs.find do |handoff|
        case handoff
        when Agent
          handoff.name == agent_name
        when Handoff
          handoff.agent_name == agent_name
        end
      end

      if result
        target_name = result.is_a?(Agent) ? result.name : result.agent_name
        log_debug_handoff("Handoff target found",
                          from_agent: @name,
                          to_agent: target_name)
      else
        log_debug_handoff("Handoff target not found",
                          from_agent: @name,
                          requested_agent: agent_name)
      end

      result
    end

    ##
    # Checks if the agent has any tools available
    #
    # @param context [RunContextWrapper, nil] current run context for dynamic tool filtering
    # @return [Boolean] true if the agent has enabled tools, false otherwise
    #
    # @example
    #   if agent.tools?
    #     puts "Agent has #{agent.tools.length} tools"
    #   else
    #     puts "Agent has no tools"
    #   end
    def tools?(context = nil)
      enabled_tools(context).any?
    end

    ##
    # Checks if the agent has any handoffs available
    #
    # @return [Boolean] true if the agent has handoffs, false otherwise
    #
    # @example
    #   if agent.handoffs?
    #     puts "Agent can handoff to #{agent.handoffs.length} other agents"
    #   end
    def handoffs?
      @handoffs.any?
    end

    ##
    # Checks if the agent has input guardrails
    #
    # @return [Boolean] true if the agent has input guardrails, false otherwise
    def input_guardrails?
      @input_guardrails.any?
    end

    ##
    # Checks if the agent has output guardrails
    #
    # @return [Boolean] true if the agent has output guardrails, false otherwise
    def output_guardrails?
      @output_guardrails.any?
    end

    ##
    # Checks if the agent has lifecycle hooks configured
    #
    # @return [Boolean] true if the agent has hooks, false otherwise
    def hooks?
      !@hooks.nil?
    end

    ##
    # Get all enabled tools for the given context
    #
    # @param context [RunContextWrapper, nil] current run context
    # @return [Array<FunctionTool>] enabled tools only (always returns array, never nil)
    def enabled_tools(context = nil)
      FunctionTool.enabled_tools(@tools || [], context)
    end

    ##
    # Get all tools (including disabled ones)
    #
    # @return [Array<FunctionTool>] all tools regardless of enabled state (always returns array)
    def all_tools
      @tools || []
    end

    ##
    # Get enabled tools for current context
    #
    # This method provides the interface expected by the Runner class
    # and delegates to enabled_tools for consistency.
    #
    # @param context [RunContextWrapper, nil] current run context
    # @return [Array<FunctionTool>] enabled tools only (always returns array)
    def tools(context = nil)
      enabled_tools(context)
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
    #   rescue RAAF::ToolError => e
    #     puts "Tool error: #{e.message}"
    #   end
    def execute_tool(tool_name, **)
      tool = @tools.find { |t| t.name == tool_name }
      raise ToolError, "Tool '#{tool_name}' not found" unless tool

      tool.call(**)
    end

    ##
    # Check if a tool exists with the given name
    #
    # @param tool_name [String, Symbol] name of the tool to check
    # @return [Boolean] true if tool exists, false otherwise
    def tool_exists?(tool_name)
      @tools.any? do |t|
        if t.is_a?(Hash)
          # Handle hosted tools (like web_search)
          t[:type] == tool_name.to_s || t["type"] == tool_name.to_s
        else
          # Handle regular tool objects
          t.respond_to?(:name) && t.name == tool_name.to_s
        end
      end
    end

    ##
    # Handle dynamic method calls for tool execution
    #
    # This Ruby-idiomatic approach allows calling tools directly as methods:
    # Instead of: agent.execute_tool("get_weather", city: "Paris")
    # You can use: agent.get_weather(city: "Paris")
    #
    # @param method_name [Symbol] the method name (should match a tool name)
    # @param args [Array] positional arguments
    # @param kwargs [Hash] keyword arguments
    # @param block [Proc] optional block (passed to tool if supported)
    # @return [Object] the result from the tool execution
    # @raise [NoMethodError] if no tool matches the method name
    #
    # @example Dynamic tool execution
    #   # If agent has a "get_weather" tool:
    #   result = agent.get_weather(city: "Tokyo")
    #
    #   # If agent has a "calculate" tool:
    #   result = agent.calculate(expression: "2 + 2")
    def method_missing(method_name, *, **, &)
      if tool_exists?(method_name)
        execute_tool(method_name.to_s, *, **)
      else
        super
      end
    end

    ##
    # Check if method responds to dynamic tool calls
    #
    # @param method_name [Symbol] method name to check
    # @param include_private [Boolean] whether to include private methods
    # @return [Boolean] true if method is supported
    def respond_to_missing?(method_name, include_private = false)
      tool_exists?(method_name) || super
    end

    ##
    # Adds an input guardrail to the agent
    #
    # @param guardrail [Guardrails::InputGuardrail] The guardrail to add
    #
    # @example Add a profanity guardrail
    #   agent.add_input_guardrail(
    #     RAAF::Guardrails.profanity_guardrail
    #   )
    def add_input_guardrail(guardrail)
      raise ArgumentError, "Expected InputGuardrail, got #{guardrail.class}" unless guardrail.is_a?(Guardrails::InputGuardrail)

      @input_guardrails << guardrail
    end

    ##
    # Adds an output guardrail to the agent
    #
    # @param guardrail [Guardrails::OutputGuardrail] The guardrail to add
    #
    # @example Add a length guardrail
    #   agent.add_output_guardrail(
    #     RAAF::Guardrails.length_guardrail(max_length: 1000)
    #   )
    def add_output_guardrail(guardrail)
      raise ArgumentError, "Expected OutputGuardrail, got #{guardrail.class}" unless guardrail.is_a?(Guardrails::OutputGuardrail)

      @output_guardrails << guardrail
    end

    ##
    # Clears all tools from the agent (destructive operation)
    #
    # @return [Agent] self for method chaining
    #
    # @example Clear all tools
    #   agent.reset_tools!
    def reset_tools!
      @tools.clear
      self
    end

    ##
    # Clears all handoffs from the agent (destructive operation)
    #
    # @return [Agent] self for method chaining
    #
    # @example Clear all handoffs
    #   agent.reset_handoffs!
    def reset_handoffs!
      @handoffs.clear
      self
    end

    ##
    # Clears all input guardrails from the agent (destructive operation)
    #
    # @return [Agent] self for method chaining
    def reset_input_guardrails!
      @input_guardrails.clear
      self
    end

    ##
    # Clears all output guardrails from the agent (destructive operation)
    #
    # @return [Agent] self for method chaining
    def reset_output_guardrails!
      @output_guardrails.clear
      self
    end

    ##
    # Resets the agent to basic configuration (destructive operation)
    #
    # @return [Agent] self for method chaining
    #
    # @example Reset agent completely
    #   agent.reset!
    def reset!
      reset_tools!
      reset_handoffs!
      reset_input_guardrails!
      reset_output_guardrails!
      @output_type = nil
      @output_type_schema = nil
      @hooks = nil
      @prompt = nil
      self
    end

    ##
    # Validates output against the agent's output type
    #
    # @param output [String, Object] the output to validate
    # @return [Object] the validated output
    # @raise [ModelBehaviorError] if validation fails
    def validate_output(output)
      return output unless @output_type_schema

      if output.is_a?(String) && !@output_type_schema.plain_text?
        # Try to parse and validate JSON
        @output_type_schema.validate_json(output)
      else
        # Direct validation
        TypeAdapter.new(@output_type || String).validate(output)
      end
    end

    ##
    # Clone the agent with optional parameter overrides
    #
    # Creates a new agent instance with the same configuration as this agent,
    # but allows overriding specific parameters. This is useful for creating
    # agent variants or for testing different configurations.
    #
    # @param kwargs [Hash] parameters to override in the clone
    # @return [Agent] new agent instance with specified overrides
    #
    # @example Clone with different instructions
    #   base_agent = Agent.new(name: "Assistant", instructions: "Be helpful")
    #   specialized_agent = base_agent.clone(
    #     name: "Code Assistant",
    #     instructions: "Help with programming questions",
    #     tools: [code_search_tool]
    #   )
    #
    # @example Clone with different model
    #   fast_agent = slow_agent.clone(model: "gpt-4o-mini")
    def clone(**kwargs)
      # Get current configuration
      current_config = {
        name: @name,
        instructions: @instructions,
        tools: @tools.dup,
        handoffs: @handoffs.dup,
        model: @model,
        max_turns: @max_turns,
        output_type: @output_type,
        hooks: @hooks,
        prompt: @prompt,
        input_guardrails: @input_guardrails.dup,
        output_guardrails: @output_guardrails.dup,
        handoff_description: @handoff_description,
        tool_use_behavior: @tool_use_behavior,
        reset_tool_choice: @reset_tool_choice,
        response_format: @response_format,
        memory_store: @memory_store, # Share memory store reference (not deep copied)
        on_handoff: @on_handoff
      }

      # Merge with overrides
      new_config = current_config.merge(kwargs)

      # Create new agent
      self.class.new(**new_config)
    end

    ##
    # Convert this agent into a tool that can be used by other agents
    #
    # This creates a FunctionTool that wraps this agent, allowing other agents
    # to delegate tasks to this agent as if it were a regular tool call.
    #
    # @param tool_name [String, nil] custom name for the tool (defaults to agent name)
    # @param tool_description [String, nil] custom description for the tool
    # @param custom_output_extractor [Proc, nil] custom function to extract final output
    # @return [FunctionTool] tool that wraps this agent
    #
    # @example Convert agent to tool
    #   specialist = Agent.new(name: "Specialist", instructions: "Expert in topic X")
    #   tool = specialist.as_tool(
    #     tool_name: "consult_specialist",
    #     tool_description: "Consult the specialist about topic X"
    #   )
    #
    #   main_agent = Agent.new(name: "Main", tools: [tool])
    #
    # @example With custom output extractor
    #   agent_tool = agent.as_tool do |run_result|
    #     # Extract just the final message content
    #     run_result.messages.last[:content]
    #   end
    def as_tool(tool_name: nil, tool_description: nil, custom_output_extractor: nil, &block)
      tool_name ||= @name.downcase.gsub(/\s+/, "_")
      tool_description ||= @handoff_description || "Delegate to #{@name}"

      # Use block if provided, otherwise use custom_output_extractor
      output_extractor = block || custom_output_extractor || default_output_extractor

      # Create a proc that runs this agent
      agent_proc = proc do |input_text = "", **kwargs|
        # Create a runner for this agent
        require_relative "runner"
        runner = Runner.new(agent: self)

        # Build input message
        input_message = if kwargs.any?
                          # Include kwargs in the input
                          formatted_input = "#{input_text}\n\nAdditional context: #{kwargs.to_json}"
                          formatted_input
                        else
                          input_text
                        end

        # Run the agent
        result = runner.run(input_message)

        # Extract output using the provided extractor
        output_extractor.call(result)
      end

      # Create FunctionTool from the proc
      FunctionTool.new(
        agent_proc,
        name: tool_name,
        description: tool_description,
        # Add parameters for input and optional kwargs
        parameters: {
          type: "object",
          properties: {
            input_text: {
              type: "string",
              description: "Input text to send to the #{@name} agent"
            }
          },
          required: ["input_text"]
        }
      )
    end

    ##
    # Memory Management Methods
    #
    # These methods provide memory capabilities for the agent, enabling it to store
    # and retrieve information across conversations. The memory system uses the
    # configured memory store (defaults to InMemoryStore).

    ##
    # Store information in the agent's memory
    #
    # @param content [String] the information to remember
    # @param metadata [Hash] optional metadata for categorization and filtering
    # @param conversation_id [String, nil] optional conversation identifier
    # @return [String] unique memory key for later retrieval
    #
    # @example Store user preferences
    #   agent.remember("User prefers Python programming", metadata: { type: "preference" })
    #
    # @example Store context for current conversation
    #   agent.remember("User is working on web scraping",
    #                  conversation_id: "conv-123",
    #                  metadata: { type: "context" })
    def remember(content, metadata: {}, conversation_id: nil)
      raise AgentError, "Memory store not configured" unless @memory_store

      # Create a unique key for this memory
      memory_key = "#{@name}_#{SecureRandom.uuid}"

      # Enhance metadata with agent context
      enhanced_metadata = metadata.merge(
        agent_name: @name,
        created_by: "#{self.class.name}#remember"
      )

      # Create memory object
      memory = Memory::Memory.new(
        content: content,
        agent_name: @name,
        conversation_id: conversation_id,
        metadata: enhanced_metadata
      )

      # Store in memory store
      @memory_store.store(memory_key, memory)

      memory_key
    end

    ##
    # Search and retrieve memories based on a query
    #
    # @param query [String] search query to match against memory content
    # @param limit [Integer] maximum number of memories to return (default: 10)
    # @param conversation_id [String, nil] filter by conversation (optional)
    # @param tags [Array<String>] filter by metadata tags (optional)
    # @return [Array<Hash>] array of matching memories
    #
    # @example Find programming-related memories
    #   memories = agent.recall("programming", limit: 5)
    #
    # @example Find memories from specific conversation
    #   memories = agent.recall("error", conversation_id: "conv-123")
    #
    # @example Find memories with specific tags
    #   memories = agent.recall("user", tags: ["preference", "setting"])
    def recall(query, limit: 10, conversation_id: nil, tags: [])
      return [] unless @memory_store

      @memory_store.search(query, {
                             limit: limit,
                             agent_name: @name,
                             conversation_id: conversation_id,
                             tags: tags
                           })
    end

    ##
    # Get the total number of memories stored for this agent
    #
    # @return [Integer] count of memories
    #
    # @example Check if agent has memories
    #   puts "Agent has #{agent.memory_count} memories"
    def memory_count
      return 0 unless @memory_store

      keys = @memory_store.list_keys(agent_name: @name)
      keys.length
    end

    ##
    # Check if the agent has any memories stored
    #
    # @return [Boolean] true if agent has memories, false otherwise
    #
    # @example Conditional logic based on memory
    #   if agent.memories?
    #     puts "Loading previous context..."
    #   end
    def memories?
      memory_count.positive?
    end

    ##
    # Remove a specific memory from storage
    #
    # @param memory_key [String] unique identifier of the memory to forget
    # @return [Boolean] true if memory was deleted, false if not found
    #
    # @example Remove outdated information
    #   key = agent.remember("Temporary info")
    #   # Later...
    #   agent.forget(key)
    def forget(memory_key)
      return false unless @memory_store

      @memory_store.delete(memory_key)
    end

    ##
    # Clear all memories for this agent
    #
    # @return [void]
    #
    # @example Reset agent memory
    #   agent.clear_memories
    #   puts "Agent memory cleared"
    def clear_memories
      return unless @memory_store

      # Get all keys for this agent and delete them
      keys = @memory_store.list_keys(agent_name: @name)
      keys.each { |key| @memory_store.delete(key) }
    end

    ##
    # Get recent memories for the agent
    #
    # @param limit [Integer] maximum number of recent memories to return (default: 10)
    # @param conversation_id [String, nil] filter by conversation (optional)
    # @return [Array<Hash>] array of recent memories, most recent first
    #
    # @example Get last 5 memories
    #   recent = agent.recent_memories(5)
    #
    # @example Get recent memories from current conversation
    #   recent = agent.recent_memories(10, conversation_id: "conv-123")
    def recent_memories(limit: 10, conversation_id: nil)
      return [] unless @memory_store

      # Search with empty query to get all memories, then sort by recency
      all_memories = @memory_store.search("", {
                                            limit: limit * 2, # Get more than needed to filter properly
                                            agent_name: @name,
                                            conversation_id: conversation_id
                                          })

      # Sort by updated_at (most recent first) and limit
      all_memories
        .sort_by { |memory| Time.parse(memory[:updated_at] || memory["updated_at"]) }
        .reverse
        .take(limit)
    end

    ##
    # Generate a formatted context string from memories for prompt inclusion
    #
    # This method searches for relevant memories and formats them as a context
    # string that can be included in prompts to provide the LLM with relevant
    # background information.
    #
    # @param query [String] search query to find relevant memories
    # @param limit [Integer] maximum number of memories to include (default: 5)
    # @param conversation_id [String, nil] filter by conversation (optional)
    # @return [String] formatted context string
    #
    # @example Generate context for a prompt
    #   context = agent.memory_context("user preferences", limit: 3)
    #   prompt = "Based on this context: #{context}\n\nPlease help the user..."
    def memory_context(query, limit: 5, conversation_id: nil)
      memories = recall(query, limit: limit, conversation_id: conversation_id)
      return "" if memories.empty?

      context_parts = ["Relevant memories:"]
      memories.each_with_index do |memory, index|
        content = memory[:content] || memory["content"]
        timestamp = memory[:updated_at] || memory["updated_at"]
        context_parts << "#{index + 1}. #{content} (#{timestamp})"
      end

      context_parts.join("\n")
    end

    ##
    # Get input schema for this agent when used as handoff target
    #
    # @return [Hash] JSON schema for handoff input
    #
    def get_input_schema
      {
        type: "object",
        properties: {
          context: {
            type: "string",
            description: "Context or reason for handoff"
          }
        },
        required: [],
        additionalProperties: false
      }
    end

    private

    # Configuration and setup methods

    def configure_output_type
      return unless @output_type

      # If output_type is already an AgentOutputSchemaBase, use it directly
      @output_type_schema = if @output_type.is_a?(AgentOutputSchemaBase)
                              @output_type
                            else
                              # Create an AgentOutputSchema from the type
                              AgentOutputSchema.new(@output_type, strict_json_schema: true)
                            end
    rescue StandardError => e
      log_warn("Could not configure output type: #{e.message}", agent: @name, error_class: e.class.name)
      @output_type_schema = nil
    end

    def default_output_extractor
      proc do |run_result|
        # Extract the final assistant message content
        if run_result.respond_to?(:messages) && run_result.messages.any?
          last_message = run_result.messages.reverse.find { |msg| msg[:role] == "assistant" }
          last_message&.dig(:content) || ""
        else
          run_result.to_s
        end
      end
    end

    # Collection processing utilities

    def safe_map_to_h(collection)
      return [] unless collection.respond_to?(:map)

      collection.filter_map do |item|
        if item.respond_to?(:to_h)
          item.to_h
        elsif item.respond_to?(:to_s)
          item.to_s
        end
      end
    rescue StandardError
      []
    end

    def safe_map_names(collection)
      return [] unless collection.respond_to?(:map)

      collection.filter_map do |item|
        case item
        when Agent
          item.name
        when Handoff
          item.agent_name
        else
          item.respond_to?(:name) ? item.name : item.to_s
        end
      end
    rescue StandardError
      []
    end

    ##
    # Generate handoff tools automatically (Python SDK compatibility)
    #
    def generate_handoff_tools
      @handoffs.each do |handoff_spec|
        tool = create_handoff_tool(handoff_spec)
        add_tool(tool)
      end
    end

    ##
    # Create handoff tool for agent or handoff object
    #
    # @param handoff_spec [Agent, Handoff] Handoff specification
    # @return [FunctionTool] Generated handoff tool
    #
    def create_handoff_tool(handoff_spec)
      case handoff_spec
      when Agent
        # Direct agent handoff
        create_agent_handoff_tool(handoff_spec)
      when Handoff
        # Custom handoff with overrides
        create_custom_handoff_tool(handoff_spec)
      else
        raise ArgumentError, "Invalid handoff specification: #{handoff_spec.class}"
      end
    end

    ##
    # Create tool for direct agent handoff
    #
    # @param target_agent [Agent] Target agent
    # @return [FunctionTool] Handoff tool
    #
    def create_agent_handoff_tool(target_agent)
      tool_name = "transfer_to_#{Utils.sanitize_identifier(target_agent.name)}"

      # Use the better description format from Handoff class
      description = "Handoff to the #{target_agent.name} agent to handle the request."
      description += " #{target_agent.handoff_description}" if target_agent.handoff_description

      parameters = target_agent.get_input_schema

      # Store the target agent reference in a closure
      stored_target_agent = target_agent

      # Create handoff procedure
      handoff_proc = proc do |**args|
        # Return a special handoff result that the runner can recognize
        # We'll return a hash (not JSON string) with a special marker
        {
          __raaf_handoff__: true,
          target_agent: stored_target_agent,
          handoff_data: args,
          handoff_reason: args[:context] || "Handoff requested"
        }
      end

      FunctionTool.new(
        handoff_proc,
        name: tool_name,
        description: description,
        parameters: parameters
      )
    end

    ##
    # Create tool for custom handoff
    #
    # @param handoff_spec [Handoff] Handoff specification
    # @return [FunctionTool] Handoff tool
    #
    def create_custom_handoff_tool(handoff_spec)
      target_agent = handoff_spec.agent
      tool_name = handoff_spec.tool_name_override || "transfer_to_#{Utils.sanitize_identifier(target_agent.name)}"

      description = handoff_spec.tool_description_override ||
                    handoff_spec.description ||
                    "Transfer to #{target_agent.name}"

      parameters = handoff_spec.get_input_schema

      # Store the target agent and spec references in a closure
      stored_target_agent = target_agent
      stored_handoff_spec = handoff_spec

      # Create handoff procedure with custom logic
      handoff_proc = proc do |**args|
        # Apply input filter if provided
        filtered_args = stored_handoff_spec.input_filter ? stored_handoff_spec.input_filter.call(args) : args

        # Call on_handoff callback if provided
        stored_handoff_spec.on_handoff&.call(filtered_args)

        # Return handoff data with stored agent reference
        {
          __raaf_handoff__: true,
          target_agent: stored_target_agent,
          handoff_data: filtered_args,
          handoff_reason: filtered_args[:context] || "Custom handoff requested",
          handoff_overrides: stored_handoff_spec.overrides || {},
          handoff_spec: stored_handoff_spec
        }
      end

      FunctionTool.new(
        handoff_proc,
        name: tool_name,
        description: description,
        parameters: parameters
      )
    end

  end

end
