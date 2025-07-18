# frozen_string_literal: true

require_relative "handoff"
require_relative "handoff_context"

module RAAF
  ##
  # Python SDK compatible handoff system
  #
  # This module implements the handoff system that matches the Python SDK
  # behavior exactly, where handoffs are specified in the agent constructor
  # and automatically generate transfer tools.
  #
  module PythonSDKHandoff
    ##
    # Enhanced Agent class with Python SDK handoff support
    #
    class Agent < RAAF::Agent
      attr_reader :handoffs, :handoff_context

      def initialize(name:, instructions:, model: "gpt-4o", handoffs: nil, **kwargs)
        super(name: name, instructions: instructions, model: model, **kwargs)
        
        @handoffs = handoffs || []
        @handoff_context = HandoffContext.new(current_agent: name)
        
        # Generate handoff tools automatically
        generate_handoff_tools
      end

      private

      ##
      # Generate handoff tools from handoff specifications
      #
      def generate_handoff_tools
        @handoffs.each do |handoff_spec|
          tool = create_handoff_tool(handoff_spec)
          add_tool(tool)
        end
      end

      ##
      # Create a handoff tool from a handoff specification
      #
      # @param handoff_spec [Agent, Handoff] Handoff specification
      # @return [FunctionTool] Generated handoff tool
      #
      def create_handoff_tool(handoff_spec)
        if handoff_spec.is_a?(Agent)
          # Simple handoff - agent directly
          create_simple_handoff_tool(handoff_spec)
        elsif handoff_spec.is_a?(Handoff)
          # Custom handoff with overrides
          create_custom_handoff_tool(handoff_spec)
        else
          raise ArgumentError, "Invalid handoff specification: #{handoff_spec.class}"
        end
      end

      ##
      # Create a simple handoff tool
      #
      # @param target_agent [Agent] Target agent
      # @return [FunctionTool] Handoff tool
      #
      def create_simple_handoff_tool(target_agent)
        tool_name = "transfer_to_#{target_agent.name.downcase.gsub(/[^a-z0-9_]/, '_')}"
        
        description = "Transfer execution to #{target_agent.name}"
        
        # Get input schema from target agent
        parameters = if target_agent.respond_to?(:get_input_schema)
                      target_agent.get_input_schema
                    else
                      default_handoff_schema
                    end

        handoff_proc = proc do |**args|
          execute_handoff(target_agent, args, {}, nil)
        end

        FunctionTool.new(
          handoff_proc,
          name: tool_name,
          description: description,
          parameters: parameters
        )
      end

      ##
      # Create a custom handoff tool with overrides
      #
      # @param handoff_spec [Handoff] Handoff specification
      # @return [FunctionTool] Handoff tool
      #
      def create_custom_handoff_tool(handoff_spec)
        target_agent = handoff_spec.agent
        tool_name = "transfer_to_#{target_agent.name.downcase.gsub(/[^a-z0-9_]/, '_')}"
        
        description = handoff_spec.description || "Transfer execution to #{target_agent.name}"
        parameters = handoff_spec.get_input_schema

        handoff_proc = proc do |**args|
          execute_handoff(
            target_agent,
            args,
            handoff_spec.overrides,
            handoff_spec.input_filter
          )
        end

        FunctionTool.new(
          handoff_proc,
          name: tool_name,
          description: description,
          parameters: parameters
        )
      end

      ##
      # Execute handoff with filtering and overrides
      #
      # @param target_agent [Agent] Target agent
      # @param args [Hash] Handoff arguments
      # @param overrides [Hash] Agent overrides
      # @param input_filter [Proc] Input filter
      # @return [String] JSON response
      #
      def execute_handoff(target_agent, args, overrides, input_filter)
        # Apply input filter if provided
        filtered_args = input_filter ? input_filter.call(args) : args

        # Set up handoff context
        success = @handoff_context.set_handoff(
          target_agent: target_agent.name,
          data: filtered_args.merge(
            _target_agent_class: target_agent.class,
            _overrides: overrides
          ),
          reason: filtered_args[:reason] || "Agent requested handoff"
        )

        # Return structured response
        {
          success: success,
          handoff_prepared: true,
          target_agent: target_agent.name,
          overrides: overrides,
          filtered_data: filtered_args != args,
          timestamp: @handoff_context.handoff_timestamp&.iso8601
        }.to_json
      end

      ##
      # Default handoff schema
      #
      # @return [Hash] Default JSON schema
      #
      def default_handoff_schema
        {
          type: "object",
          properties: {
            data: {
              type: "object",
              description: "Data to pass to the target agent",
              additionalProperties: true
            },
            reason: {
              type: "string",
              description: "Reason for the handoff"
            }
          },
          required: [],
          additionalProperties: false
        }
      end
    end

    ##
    # Python SDK compatible runner
    #
    class Runner < RAAF::Runner
      def initialize(agent:, **kwargs)
        super(agent: agent, **kwargs)
        @handoff_context = agent.handoff_context if agent.respond_to?(:handoff_context)
      end

      ##
      # Run agent with handoff support
      #
      # @param message [String] Initial message
      # @return [RunResult] Result with handoff information
      #
      def run(message)
        result = super(message)
        
        # Check if handoff was requested
        if @handoff_context&.handoff_pending?
          # Execute handoff and continue with next agent
          execute_handoff_chain(message, result)
        else
          result
        end
      end

      private

      ##
      # Execute handoff chain
      #
      # @param initial_message [String] Initial message
      # @param current_result [RunResult] Current result
      # @return [RunResult] Final result
      #
      def execute_handoff_chain(initial_message, current_result)
        messages = current_result.messages.dup
        total_usage = current_result.usage.dup
        
        # Execute handoff
        handoff_result = @handoff_context.execute_handoff
        
        unless handoff_result[:success]
          return RunResult.new(
            messages: messages,
            last_agent: current_result.last_agent,
            usage: total_usage,
            metadata: { handoff_error: handoff_result[:error] }
          )
        end

        # Create next agent with overrides
        next_agent = create_handoff_target_agent
        
        # Create new runner for next agent
        next_runner = Runner.new(agent: next_agent, provider: @provider)
        
        # Build handoff message
        handoff_message = @handoff_context.build_handoff_message
        
        # Run next agent
        next_result = next_runner.run(handoff_message)
        
        # Combine results
        RunResult.new(
          messages: messages + next_result.messages,
          last_agent: next_result.last_agent,
          usage: combine_usage(total_usage, next_result.usage),
          metadata: current_result.metadata.merge(
            handoff_executed: true,
            handoff_target: handoff_result[:current_agent]
          )
        )
      end

      ##
      # Create target agent for handoff
      #
      # @return [Agent] Target agent instance
      #
      def create_handoff_target_agent
        handoff_data = @handoff_context.handoff_data
        target_class = handoff_data[:_target_agent_class]
        overrides = handoff_data[:_overrides] || {}
        
        # Create agent with overrides
        target_class.new(
          name: @handoff_context.target_agent,
          instructions: "Continue from handoff",
          model: overrides[:model] || "gpt-4o",
          **overrides
        )
      end

      ##
      # Combine usage statistics
      #
      # @param usage1 [Hash] First usage
      # @param usage2 [Hash] Second usage
      # @return [Hash] Combined usage
      #
      def combine_usage(usage1, usage2)
        {
          input_tokens: (usage1[:input_tokens] || 0) + (usage2[:input_tokens] || 0),
          output_tokens: (usage1[:output_tokens] || 0) + (usage2[:output_tokens] || 0),
          total_tokens: (usage1[:total_tokens] || 0) + (usage2[:total_tokens] || 0)
        }
      end
    end
  end
end