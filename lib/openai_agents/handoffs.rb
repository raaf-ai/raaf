# frozen_string_literal: true

require "json"
require_relative "strict_schema"
require_relative "errors"

module OpenAIAgents
  # Represents handoff input data passed between agents
  class HandoffInputData
    attr_reader :input_history, :pre_handoff_items, :new_items

    def initialize(input_history:, pre_handoff_items:, new_items:)
      @input_history = input_history
      @pre_handoff_items = pre_handoff_items
      @new_items = new_items
    end

    # Get all items (pre-handoff + new)
    def all_items
      @pre_handoff_items + @new_items
    end
  end

  # A handoff represents delegation from one agent to another
  class Handoff
    attr_reader :tool_name, :tool_description, :input_json_schema, :agent_name,
                :input_filter, :strict_json_schema

    def initialize(
      tool_name:,
      tool_description:,
      input_json_schema:,
      on_invoke_handoff:,
      agent_name:,
      input_filter: nil,
      strict_json_schema: true
    )
      @tool_name = tool_name
      @tool_description = tool_description
      @input_json_schema = input_json_schema
      @on_invoke_handoff = on_invoke_handoff
      @agent_name = agent_name
      @input_filter = input_filter
      @strict_json_schema = strict_json_schema
    end

    # Invoke the handoff
    def invoke(context_wrapper, input_json = nil)
      @on_invoke_handoff.call(context_wrapper, input_json)
    end

    # Get the transfer message for this handoff
    def get_transfer_message(agent)
      JSON.generate({ assistant: agent.name })
    end

    # Default tool name for an agent
    def self.default_tool_name(agent)
      "transfer_to_#{agent.name.downcase.gsub(/[^a-z0-9]+/, '_')}"
    end

    # Default tool description for an agent
    def self.default_tool_description(agent)
      desc = "Handoff to the #{agent.name} agent to handle the request."
      desc += " #{agent.handoff_description}" if agent.respond_to?(:handoff_description) && agent.handoff_description
      desc
    end

    # Convert to tool definition for API
    def to_tool_definition
      {
        type: "function",
        function: {
          name: @tool_name,
          description: @tool_description,
          parameters: @input_json_schema
        }
      }
    end
  end

  # Module for creating handoffs
  module Handoffs
    class << self
      # Create a handoff from an agent
      # 
      # @param agent [Agent] The agent to handoff to
      # @param tool_name_override [String, nil] Override for tool name
      # @param tool_description_override [String, nil] Override for tool description
      # @param on_handoff [Proc, nil] Function to run when handoff is invoked
      # @param input_type [Class, nil] Type for input validation
      # @param input_filter [Proc, nil] Function to filter inputs passed to next agent
      # @return [Handoff] The created handoff
      def handoff(
        agent,
        tool_name_override: nil,
        tool_description_override: nil,
        on_handoff: nil,
        input_type: nil,
        input_filter: nil
      )
        # Validate parameters
        if (on_handoff && input_type.nil?) || (on_handoff.nil? && input_type)
          raise ArgumentError, "You must provide either both on_handoff and input_type, or neither"
        end

        # Determine input schema
        input_json_schema = if input_type
          # Create schema from input type
          case input_type.name
          when "String"
            {
              type: "object",
              properties: {
                input: { type: "string" }
              },
              required: ["input"]
            }
          when "Integer"
            {
              type: "object",
              properties: {
                input: { type: "integer" }
              },
              required: ["input"]
            }
          when "Hash"
            # For Hash types, we need more specific schema
            {
              type: "object",
              properties: {},
              additionalProperties: true
            }
          else
            # For custom classes, attempt to infer schema
            infer_schema_from_type(input_type)
          end
        else
          {} # Empty schema if no input type
        end

        # Ensure strict JSON schema
        input_json_schema = StrictSchema.ensure_strict_json_schema(input_json_schema) if input_json_schema.any?

        # Create the invoke handler
        on_invoke_handoff = lambda do |context_wrapper, input_json|
          if input_type && on_handoff
            # Validate and parse input
            if input_json.nil? || input_json.empty?
              raise ModelBehaviorError, "Handoff function expected non-null input, but got None"
            end

            begin
              parsed_input = JSON.parse(input_json)
              validated_input = validate_input(parsed_input, input_type)
              
              # Call the on_handoff function
              if on_handoff.arity == 2
                on_handoff.call(context_wrapper, validated_input)
              else
                raise ArgumentError, "on_handoff must take two arguments: context and input"
              end
            rescue JSON::ParserError => e
              raise ModelBehaviorError, "Invalid JSON input for handoff: #{e.message}"
            end
          elsif on_handoff
            # No input type, just call with context
            if on_handoff.arity == 1
              on_handoff.call(context_wrapper)
            else
              raise ArgumentError, "on_handoff must take one argument: context"
            end
          end

          # Return the agent
          agent
        end

        # Create and return the handoff
        Handoff.new(
          tool_name: tool_name_override || Handoff.default_tool_name(agent),
          tool_description: tool_description_override || Handoff.default_tool_description(agent),
          input_json_schema: input_json_schema,
          on_invoke_handoff: on_invoke_handoff,
          agent_name: agent.name,
          input_filter: input_filter,
          strict_json_schema: true
        )
      end

      # Create a simple handoff without custom logic
      def simple_handoff(agent, description: nil)
        handoff(
          agent,
          tool_description_override: description
        )
      end

      # Create a conditional handoff
      def conditional_handoff(agent, condition:, description: nil)
        handoff(
          agent,
          tool_description_override: description,
          on_handoff: ->(context) {
            # Only proceed if condition is met
            if condition.call(context)
              true
            else
              raise HandoffError, "Handoff condition not met"
            end
          }
        )
      end

      # Create a handoff with input validation
      def validated_handoff(agent, input_schema:, description: nil)
        handoff(
          agent,
          tool_description_override: description,
          input_type: Hash,
          on_handoff: ->(context, input) {
            # Validate input against schema
            validator = StructuredOutput::ResponseFormatter.new(input_schema)
            result = validator.format_response(input)
            
            unless result[:valid]
              raise HandoffError, "Invalid handoff input: #{result[:error]}"
            end
            
            true
          }
        )
      end

      private

      # Infer JSON schema from Ruby type
      def infer_schema_from_type(type)
        # Basic implementation - can be extended
        if type.respond_to?(:json_schema)
          type.json_schema
        elsif type.respond_to?(:schema)
          type.schema
        else
          # Default object schema
          {
            type: "object",
            properties: {},
            additionalProperties: true
          }
        end
      end

      # Validate input against expected type
      def validate_input(input, expected_type)
        case expected_type.name
        when "String"
          input["input"].to_s
        when "Integer"
          input["input"].to_i
        when "Hash"
          input
        else
          # For custom types, attempt instantiation
          if expected_type.respond_to?(:new)
            expected_type.new(input)
          else
            input
          end
        end
      end
    end
  end

  # Convenience method at module level
  def self.handoff(agent, **kwargs)
    Handoffs.handoff(agent, **kwargs)
  end
end