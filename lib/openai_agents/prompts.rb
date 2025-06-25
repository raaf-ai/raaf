# frozen_string_literal: true

module OpenAIAgents
  # Prompt configuration for interacting with OpenAI models
  # Supports both static prompts and dynamic prompt generation
  class Prompt
    attr_reader :id, :version, :variables

    # @param id [String] The unique ID of the prompt
    # @param version [String, nil] Optional version of the prompt
    # @param variables [Hash, nil] Optional variables to substitute into the prompt
    def initialize(id:, version: nil, variables: nil)
      @id = id
      @version = version
      @variables = variables || {}
    end

    # Convert to hash for API calls
    def to_h
      {
        id: @id,
        version: @version,
        variables: @variables
      }.compact
    end

    # Create from hash
    def self.from_hash(hash)
      new(
        id: hash[:id] || hash["id"],
        version: hash[:version] || hash["version"],
        variables: hash[:variables] || hash["variables"]
      )
    end
  end

  # Data provided to dynamic prompt functions
  class DynamicPromptData
    attr_reader :context, :agent

    # @param context [RunContextWrapper] The run context
    # @param agent [Agent] The agent for which the prompt is being generated
    def initialize(context:, agent:)
      @context = context
      @agent = agent
    end
  end

  # A callable that dynamically generates prompts
  # Can be a Proc, lambda, or any object responding to :call
  class DynamicPromptFunction
    attr_reader :function

    def initialize(function)
      raise ArgumentError, "Dynamic prompt function must respond to :call" unless function.respond_to?(:call)

      @function = function
    end

    # Call the function with prompt data
    # @param data [DynamicPromptData] The prompt generation data
    # @return [Prompt] The generated prompt
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

  # Utilities for working with prompts
  module PromptUtil
    # Convert a prompt to model input format
    # @param prompt [Prompt, DynamicPromptFunction, Proc, Hash, nil] The prompt
    # @param context [RunContextWrapper] The run context
    # @param agent [Agent] The agent
    # @return [Hash, nil] The prompt in API format
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

  # Extension to Agent to support dynamic instructions
  class Agent
    # Dynamic instructions can be a callable that returns instructions based on context
    # This allows instructions to change during execution
    class DynamicInstructions
      attr_reader :function

      def initialize(function)
        raise ArgumentError, "Dynamic instructions must respond to :call" unless function.respond_to?(:call)

        @function = function
      end

      # Generate instructions for the given context
      # @param context [RunContextWrapper] The current run context
      # @param agent [Agent] The agent
      # @return [String] The generated instructions
      def generate(context, agent)
        result = @function.call(context, agent)
        raise TypeError, "Dynamic instructions must return a String, got #{result.class}" unless result.is_a?(String)

        result
      end
    end

    # Override instructions getter to support dynamic instructions
    def instructions
      return @instructions unless @instructions.is_a?(DynamicInstructions)

      # Return static placeholder for dynamic instructions
      "[Dynamic Instructions]"
    end

    # Alias to access original instructions method if needed
    def static_instructions
      @instructions
    end

    # Get actual instructions (static or dynamically generated)
    # @param context [RunContextWrapper, nil] The run context (required for dynamic)
    # @return [String] The instructions
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

    # Set instructions (can be string or callable)
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
