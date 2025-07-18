# frozen_string_literal: true

module RAAF
  ##
  # Prompt configuration for interacting with OpenAI models
  #
  # The Prompt class provides a structured way to define and manage prompts
  # for AI interactions. It supports both static prompts with variables and
  # dynamic prompt generation based on runtime context.
  #
  # == Static Prompts
  #
  # Static prompts are defined with an ID, optional version, and variables
  # that can be substituted during execution. This approach enables prompt
  # management and versioning.
  #
  # == Variable Substitution
  #
  # Prompts can include variables that are resolved at runtime, allowing
  # for context-specific customization while maintaining a consistent
  # prompt structure.
  #
  # @example Basic static prompt
  #   prompt = RAAF::Prompt.new(
  #     id: "customer_service",
  #     version: "v2.1",
  #     variables: { company_name: "ACME Corp", tone: "friendly" }
  #   )
  #
  # @example Prompt with dynamic variables
  #   variables = {
  #     user_name: current_user.name,
  #     date: Date.today.strftime("%B %d, %Y"),
  #     context: previous_conversation.summary
  #   }
  #   prompt = RAAF::Prompt.new(
  #     id: "personalized_assistant",
  #     variables: variables
  #   )
  #
  # @example Converting to API format
  #   api_format = prompt.to_h
  #   # => { id: "customer_service", version: "v2.1", variables: {...} }
  #
  # @author RAAF (Ruby AI Agents Factory) Team
  # @since 0.1.0
  # @see DynamicPromptFunction For dynamic prompt generation
  # @see PromptUtil For prompt conversion utilities
  class Prompt
    # @return [String] unique identifier for the prompt
    attr_reader :id
    
    # @return [String, nil] version identifier for prompt management
    attr_reader :version
    
    # @return [Hash] variables for prompt substitution
    attr_reader :variables

    ##
    # Initialize a new prompt configuration
    #
    # @param id [String] The unique ID of the prompt
    # @param version [String, nil] Optional version of the prompt for management
    # @param variables [Hash, nil] Optional variables to substitute into the prompt
    #
    # @example Basic prompt
    #   prompt = Prompt.new(id: "greeting")
    #
    # @example Versioned prompt with variables
    #   prompt = Prompt.new(
    #     id: "support_ticket",
    #     version: "2.0",
    #     variables: { priority: "high", department: "billing" }
    #   )
    def initialize(id:, version: nil, variables: nil)
      @id = id
      @version = version
      @variables = variables || {}
    end

    ##
    # Convert prompt to hash format suitable for API calls
    #
    # Creates a hash representation of the prompt that can be sent to
    # OpenAI APIs. Nil values are omitted to keep the payload clean.
    #
    # @return [Hash] prompt data formatted for API consumption
    #
    # @example API format output
    #   prompt.to_h
    #   # => { id: "customer_service", version: "v1.2", variables: { tone: "professional" } }
    def to_h
      {
        id: @id,
        version: @version,
        variables: @variables
      }.compact
    end

    ##
    # Create prompt instance from hash data
    #
    # Factory method that creates a Prompt instance from hash data,
    # supporting both string and symbol keys for flexibility.
    #
    # @param hash [Hash] hash containing prompt configuration
    # @option hash [String] :id/:"id" unique prompt identifier
    # @option hash [String] :version/:"version" prompt version
    # @option hash [Hash] :variables/:"variables" substitution variables
    # @return [Prompt] new prompt instance
    #
    # @example From API response
    #   data = { "id" => "greeting", "version" => "1.0", "variables" => { "name" => "Alice" } }
    #   prompt = Prompt.from_hash(data)
    #
    # @example From symbol hash
    #   prompt = Prompt.from_hash(id: "farewell", variables: { time: "evening" })
    def self.from_hash(hash)
      new(
        id: hash[:id] || hash["id"],
        version: hash[:version] || hash["version"],
        variables: hash[:variables] || hash["variables"]
      )
    end
  end

  ##
  # Data provided to dynamic prompt functions
  #
  # This class encapsulates the runtime context and agent information
  # that dynamic prompt functions need to generate context-appropriate
  # prompts. It provides a clean interface for accessing execution state.
  #
  # == Available Data
  #
  # * **Context**: Current execution context with conversation state
  # * **Agent**: The agent instance that will use the generated prompt
  # * **Metadata**: Additional context like trace IDs and group information
  #
  # @example Accessing context data
  #   def generate_prompt(data)
  #     conversation_length = data.context.messages.length
  #     agent_name = data.agent.name
  #     
  #     Prompt.new(
  #       id: "context_aware",
  #       variables: {
  #         message_count: conversation_length,
  #         agent: agent_name
  #       }
  #     )
  #   end
  #
  # @author RAAF (Ruby AI Agents Factory) Team
  # @since 0.1.0
  # @see DynamicPromptFunction For usage in dynamic prompts
  class DynamicPromptData
    # @return [RunContextWrapper] execution context with conversation state
    attr_reader :context
    
    # @return [Agent] agent that will use the generated prompt
    attr_reader :agent

    ##
    # Initialize dynamic prompt data container
    #
    # @param context [RunContextWrapper] The run context containing conversation state
    # @param agent [Agent] The agent for which the prompt is being generated
    #
    # @example Creating prompt data
    #   data = DynamicPromptData.new(context: context_wrapper, agent: my_agent)
    def initialize(context:, agent:)
      @context = context
      @agent = agent
    end
  end

  ##
  # A callable that dynamically generates prompts
  #
  # This class wraps functions that generate prompts based on runtime context.
  # It provides a consistent interface for dynamic prompt generation while
  # supporting various callable types (Proc, lambda, methods, or custom objects).
  #
  # == Dynamic Generation Benefits
  #
  # * **Context Awareness**: Prompts adapt to current conversation state
  # * **Personalization**: Prompts can include user-specific information
  # * **Conditional Logic**: Different prompts based on execution conditions
  # * **Real-time Data**: Incorporate live data like timestamps or external state
  #
  # == Function Requirements
  #
  # Dynamic prompt functions must:
  # - Accept a DynamicPromptData parameter
  # - Return a Prompt instance or Hash that can be converted to a Prompt
  # - Be deterministic for consistent behavior
  #
  # @example Basic dynamic function
  #   function = proc do |data|
  #     time_of_day = Time.now.hour < 12 ? "morning" : "afternoon"
  #     
  #     Prompt.new(
  #       id: "time_aware_greeting",
  #       variables: {
  #         time: time_of_day,
  #         user: data.context.metadata[:user_name]
  #       }
  #     )
  #   end
  #   
  #   dynamic_prompt = DynamicPromptFunction.new(function)
  #
  # @example Conditional prompt generation
  #   function = lambda do |data|
  #     if data.context.messages.length > 10
  #       Prompt.new(id: "long_conversation", variables: { style: "concise" })
  #     else
  #       Prompt.new(id: "short_conversation", variables: { style: "detailed" })
  #     end
  #   end
  #
  # @author RAAF (Ruby AI Agents Factory) Team
  # @since 0.1.0
  # @see DynamicPromptData For available context data
  class DynamicPromptFunction
    # @return [#call] the wrapped function that generates prompts
    attr_reader :function

    ##
    # Initialize dynamic prompt function wrapper
    #
    # @param function [#call] callable that generates prompts
    # @raise [ArgumentError] if function doesn't respond to :call
    #
    # @example With proc
    #   function = DynamicPromptFunction.new(proc { |data| ... })
    #
    # @example With lambda
    #   function = DynamicPromptFunction.new(->(data) { ... })
    #
    # @example With method
    #   function = DynamicPromptFunction.new(method(:generate_custom_prompt))
    def initialize(function)
      raise ArgumentError, "Dynamic prompt function must respond to :call" unless function.respond_to?(:call)

      @function = function
    end

    ##
    # Call the function to generate a prompt
    #
    # Executes the wrapped function with the provided context data and
    # ensures the result is a valid Prompt instance. Handles different
    # return types for flexibility.
    #
    # @param data [DynamicPromptData] The prompt generation data
    # @return [Prompt] The generated prompt instance
    # @raise [TypeError] if function returns invalid type
    #
    # @example Generating a prompt
    #   data = DynamicPromptData.new(context: context, agent: agent)
    #   prompt = dynamic_function.call(data)
    def call(data)
      result = @function.call(data)

      # Handle different return types
      case result
      when Prompt
        result
      when Hash
        Prompt.from_hash(result)
      else
        raise TypeError, "Dynamic prompt function must return a Prompt or Hash, got #{result.class}"
      end
    end
  end

  ##
  # Utilities for working with prompts
  #
  # This module provides helper methods for converting and processing
  # prompts in various formats. It handles the complexity of different
  # prompt types and provides a unified interface for prompt processing.
  #
  # == Supported Prompt Types
  #
  # * **Prompt instances**: Direct Prompt objects
  # * **Hash format**: Prompt data as hash (converted to Prompt)
  # * **Dynamic functions**: DynamicPromptFunction instances
  # * **Proc/Lambda**: Raw callables (wrapped in DynamicPromptFunction)
  # * **Methods**: Method objects (wrapped in DynamicPromptFunction)
  #
  # == Conversion Process
  #
  # 1. Identify prompt type
  # 2. Apply appropriate conversion strategy
  # 3. Resolve dynamic prompts with context
  # 4. Format for API consumption
  #
  # @example Converting various prompt types
  #   # Static prompt
  #   api_format = PromptUtil.to_model_input(prompt, context, agent)
  #   
  #   # Dynamic prompt function
  #   api_format = PromptUtil.to_model_input(dynamic_function, context, agent)
  #   
  #   # Raw proc
  #   api_format = PromptUtil.to_model_input(proc { |data| ... }, context, agent)
  #
  # @author RAAF (Ruby AI Agents Factory) Team
  # @since 0.1.0
  module PromptUtil
    ##
    # Convert a prompt to model input format
    #
    # Transforms various prompt types into the standardized format expected
    # by AI model APIs. Handles static prompts, dynamic generation, and
    # different input formats with consistent output.
    #
    # @param prompt [Prompt, DynamicPromptFunction, Proc, Hash, nil] The prompt to convert
    # @param context [RunContextWrapper] The run context for dynamic prompts
    # @param agent [Agent] The agent that will use the prompt
    # @return [Hash, nil] The prompt in API format, or nil if no prompt provided
    # @raise [TypeError] if prompt type is not supported
    #
    # @example Static prompt conversion
    #   prompt = Prompt.new(id: "greeting", variables: { name: "Alice" })
    #   api_format = PromptUtil.to_model_input(prompt, context, agent)
    #   # => { id: "greeting", variables: { name: "Alice" } }
    #
    # @example Dynamic prompt conversion
    #   dynamic_func = proc { |data| Prompt.new(id: "custom", variables: { user: data.context.user }) }
    #   api_format = PromptUtil.to_model_input(dynamic_func, context, agent)
    #   # => { id: "custom", variables: { user: "current_user" } }
    #
    # @example Hash format conversion
    #   hash_prompt = { id: "support", version: "1.0", variables: { priority: "high" } }
    #   api_format = PromptUtil.to_model_input(hash_prompt, context, agent)
    def self.to_model_input(prompt, context, agent)
      return nil if prompt.nil?

      resolved_prompt = case prompt
                        when Prompt
                          prompt
                        when Hash
                          Prompt.from_hash(prompt)
                        when DynamicPromptFunction
                          prompt.call(DynamicPromptData.new(context: context, agent: agent))
                        when Proc, Method
                          # Wrap in DynamicPromptFunction for consistent behavior
                          DynamicPromptFunction.new(prompt).call(
                            DynamicPromptData.new(context: context, agent: agent)
                          )
                        else
                          raise TypeError, "Invalid prompt type: #{prompt.class}"
                        end

      # Return in API format
      {
        id: resolved_prompt.id,
        version: resolved_prompt.version,
        variables: resolved_prompt.variables
      }.compact
    end
  end

  ##
  # Extension to Agent to support dynamic instructions
  #
  # This extension enhances the Agent class with dynamic instruction capabilities,
  # allowing instructions to be generated at runtime based on current context.
  # This enables more adaptive and context-aware agent behavior.
  #
  # == Dynamic Instructions
  #
  # Dynamic instructions are functions that generate instruction text based on:
  # - Current conversation state
  # - Agent configuration
  # - Runtime metadata
  # - External context (time, user data, etc.)
  #
  # @example Using dynamic instructions
  #   agent = Agent.new(name: "Support")
  #   agent.instructions = proc do |context, agent|
  #     user_tier = context.metadata[:user_tier] || "basic"
  #     "You are a #{user_tier} support agent. Provide #{user_tier}-level assistance."
  #   end
  #
  # @see DynamicInstructions For the wrapper class implementation
  class Agent
    ##
    # Dynamic instructions generator
    #
    # This class wraps functions that generate agent instructions based on runtime
    # context. It enables adaptive agent behavior where instructions can change
    # based on conversation state, user context, or other dynamic factors.
    #
    # == Function Requirements
    #
    # Dynamic instruction functions must:
    # - Accept context and agent parameters
    # - Return a String containing the generated instructions
    # - Be deterministic for consistent agent behavior
    # - Handle missing context gracefully
    #
    # @example Time-based instructions
    #   function = proc do |context, agent|
    #     hour = Time.now.hour
    #     if hour < 9 || hour > 17
    #       "You are an after-hours support agent. Direct urgent issues to emergency support."
    #     else
    #       "You are a business-hours support agent. Provide full assistance."
    #     end
    #   end
    #   
    #   dynamic_instructions = DynamicInstructions.new(function)
    #
    # @example Context-aware instructions
    #   function = lambda do |context, agent|
    #     conversation_length = context.messages.length
    #     if conversation_length > 20
    #       "Be concise. This is a long conversation - focus on resolution."
    #     else
    #       "Be helpful and detailed. Take time to understand the user's needs."
    #     end
    #   end
    #
    # @author RAAF (Ruby AI Agents Factory) Team
    # @since 0.1.0
    class DynamicInstructions
      # @return [#call] the function that generates instructions
      attr_reader :function

      ##
      # Initialize dynamic instructions wrapper
      #
      # @param function [#call] callable that generates instruction strings
      # @raise [ArgumentError] if function doesn't respond to :call
      #
      # @example With proc
      #   instructions = DynamicInstructions.new(proc { |context, agent| ... })
      #
      # @example With lambda
      #   instructions = DynamicInstructions.new(->(context, agent) { ... })
      def initialize(function)
        raise ArgumentError, "Dynamic instructions must respond to :call" unless function.respond_to?(:call)

        @function = function
      end

      ##
      # Generate instructions for the given context
      #
      # Calls the wrapped function to generate contextual instructions and
      # validates the result to ensure it's a string.
      #
      # @param context [RunContextWrapper] The current run context
      # @param agent [Agent] The agent requiring instructions
      # @return [String] The generated instructions
      # @raise [TypeError] if function doesn't return a String
      #
      # @example Generating instructions
      #   instructions_text = dynamic_instructions.generate(context, agent)
      def generate(context, agent)
        result = @function.call(context, agent)
        raise TypeError, "Dynamic instructions must return a String, got #{result.class}" unless result.is_a?(String)

        result
      end
    end

    ##
    # Override instructions getter to support dynamic instructions
    #
    # When instructions are dynamic, this returns a placeholder string
    # to indicate that instructions are generated at runtime. Use
    # get_instructions(context) to retrieve actual instructions.
    #
    # @return [String] static instructions or placeholder for dynamic ones
    #
    # @example Checking instruction type
    #   if agent.instructions == "[Dynamic Instructions]"
    #     # Instructions are dynamic, need context to resolve
    #     actual_instructions = agent.get_instructions(context)
    #   end
    def instructions
      return @instructions unless @instructions.is_a?(DynamicInstructions)

      # Return static placeholder for dynamic instructions
      "[Dynamic Instructions]"
    end

    ##
    # Access the raw instructions value without processing
    #
    # Returns the actual stored instructions value, whether it's a string
    # or a DynamicInstructions instance. Useful for inspection and debugging.
    #
    # @return [String, DynamicInstructions, nil] raw instructions value
    #
    # @example Checking instruction type
    #   case agent.static_instructions
    #   when String
    #     # Static instructions
    #   when DynamicInstructions
    #     # Dynamic instructions
    #   end
    def static_instructions
      @instructions
    end

    ##
    # Get actual instructions (static or dynamically generated)
    #
    # Retrieves the effective instructions for the agent, generating them
    # dynamically if necessary. This is the primary method for getting
    # instructions that will be used during agent execution.
    #
    # @param context [RunContextWrapper, nil] The run context (required for dynamic instructions)
    # @return [String, nil] The effective instructions
    # @raise [ArgumentError] if context is required but not provided
    #
    # @example Getting static instructions
    #   instructions = agent.get_instructions  # context not required
    #
    # @example Getting dynamic instructions
    #   instructions = agent.get_instructions(context)  # context required
    def get_instructions(context = nil)
      case @instructions
      when DynamicInstructions
        raise ArgumentError, "Context required for dynamic instructions" unless context

        @instructions.generate(context, self)
      when String, nil
        @instructions
      else
        @instructions.to_s
      end
    end

    ##
    # Set instructions (can be string or callable)
    #
    # Accepts various instruction types and automatically wraps callables
    # in DynamicInstructions instances. Provides flexible instruction
    # configuration while maintaining type safety.
    #
    # @param value [String, DynamicInstructions, #call, nil] instructions to set
    #
    # @example Static instructions
    #   agent.instructions = "You are a helpful assistant."
    #
    # @example Dynamic instructions with proc
    #   agent.instructions = proc { |context, agent| generate_instructions(context) }
    #
    # @example Dynamic instructions with lambda
    #   agent.instructions = ->(context, agent) { "Context-aware: #{context.messages.length} messages" }
    #
    # @example Pre-wrapped dynamic instructions
    #   function = proc { |context, agent| ... }
    #   agent.instructions = DynamicInstructions.new(function)
    def instructions=(value)
      @instructions = case value
                      when String, nil
                        value
                      when DynamicInstructions
                        value
                      when Proc, Method
                        DynamicInstructions.new(value)
                      else
                        if value.respond_to?(:call)
                          DynamicInstructions.new(value)
                        else
                          value.to_s
                        end
                      end
    end
  end
end
