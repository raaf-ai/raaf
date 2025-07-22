# frozen_string_literal: true

require "json"
require_relative "strict_schema"
require_relative "errors"
require_relative "logging"
require_relative "utils"

module RAAF

  ##
  # RECOMMENDED_PROMPT_PREFIX - Standard handoff instructions for multi-agent systems
  #
  # This constant contains the recommended prompt prefix for agents that use handoffs,
  # matching the OpenAI Agents SDK specification. It provides essential context about
  # the multi-agent system and handoff behavior to ensure proper LLM understanding.
  #
  # == Usage
  #
  # Use this prefix when creating agents that need to understand the handoff system:
  #
  #   instructions = RAAF::RECOMMENDED_PROMPT_PREFIX + "\n\n" + custom_instructions
  #
  # Or use the convenience method:
  #
  #   instructions = RAAF.prompt_with_handoff_instructions(custom_instructions)
  #
  # == Content
  #
  # The prefix explains:
  # - The agent is part of a multi-agent system
  # - Handoffs are achieved by calling transfer_to_<agent_name> functions
  # - Transfers should be handled seamlessly without drawing attention
  # - The system abstracts handoff complexity from the user
  #
  # @since 0.1.0
  # @see #prompt_with_handoff_instructions
  RECOMMENDED_PROMPT_PREFIX = <<~INSTRUCTIONS.strip
    # System context
    You are part of a multi-agent system called the Agents SDK, designed to make agent coordination and execution easy. Agents uses two primary abstraction: **Agents** and **Handoffs**. An agent encompasses instructions and tools and can hand off a conversation to another agent when appropriate. Handoffs are achieved by calling a handoff function, generally named `transfer_to_<agent_name>`. Transfers between agents are handled seamlessly in the background; do not mention or draw attention to these transfers in your conversation with the user.
  INSTRUCTIONS

  ##
  # HandoffInputData - Container for handoff context and message history
  #
  # This class encapsulates all the data that needs to be passed when one agent
  # hands off control to another agent. It maintains the conversation history,
  # messages that existed before the handoff, and any new messages created
  # during the handoff process.
  #
  # == Purpose
  #
  # When agents collaborate in a multi-agent workflow, they need to share context
  # about the conversation, user requests, and any intermediate results. This class
  # provides a structured way to package that information.
  #
  # == Usage
  #
  #   # Create handoff input data
  #   handoff_data = RAAF::HandoffInputData.new(
  #     input_history: conversation_messages,
  #     pre_handoff_items: existing_items,
  #     new_items: generated_items
  #   )
  #
  #   # Access all items together
  #   all_context = handoff_data.all_items
  #
  # @author RAAF Development Team
  # @since 0.1.0
  # @see Handoff
  # @see Handoffs
  class HandoffInputData

    # @!attribute [r] input_history
    #   @return [Array<Hash>] Complete conversation history leading up to handoff
    # @!attribute [r] pre_handoff_items
    #   @return [Array<Object>] Items that existed before the handoff occurred
    # @!attribute [r] new_items
    #   @return [Array<Object>] Items created during the handoff process
    attr_reader :input_history, :pre_handoff_items, :new_items

    ##
    # Initialize handoff input data
    #
    # @param input_history [Array<Hash>] conversation messages leading to handoff
    # @param pre_handoff_items [Array<Object>] items that existed before handoff
    # @param new_items [Array<Object>] items created during handoff process
    #
    # @example Create handoff data
    #   data = HandoffInputData.new(
    #     input_history: [
    #       { role: "user", content: "I need help with billing" },
    #       { role: "assistant", content: "I'll transfer you to billing support" }
    #     ],
    #     pre_handoff_items: [customer_record, previous_tickets],
    #     new_items: [analysis_result, recommendations]
    #   )
    def initialize(input_history:, pre_handoff_items:, new_items:)
      @input_history = input_history
      @pre_handoff_items = pre_handoff_items
      @new_items = new_items
    end

    ##
    # Get all items combined
    #
    # Merges pre-handoff items with newly created items to provide
    # a complete view of all available context for the receiving agent.
    #
    # @return [Array<Object>] combined array of all items
    #
    # @example Access all context
    #   data = HandoffInputData.new(
    #     input_history: messages,
    #     pre_handoff_items: [user_profile, order_history],
    #     new_items: [analysis, recommendations]
    #   )
    #
    #   # Get everything together
    #   full_context = data.all_items
    #   # => [user_profile, order_history, analysis, recommendations]
    def all_items
      @pre_handoff_items + @new_items
    end

  end

  ##
  # CallbackHandoffTool - Internal tool implementation for agent handoffs
  #
  # A CallbackHandoffTool encapsulates the logic for transferring control between agents in a
  # multi-agent workflow. It defines the tool interface that allows one agent to
  # invoke another agent, including input validation, context passing, and execution.
  #
  # Note: This is the internal implementation class for callback-based handoffs. For the
  # public API, use the Handoff class in handoff.rb which matches the Python SDK interface.
  # For structured handoffs with data contracts, see HandoffTool in handoff_tool.rb.
  #
  # == Core Concepts
  #
  # * **Tool Interface**: Handoffs appear as tools to the invoking agent
  # * **Input Validation**: Optional JSON schema validation for handoff parameters
  # * **Context Preservation**: Maintains conversation context across agent transitions
  # * **Filtering**: Optional input filtering to control what data is passed
  # * **Execution Hook**: Custom logic that runs when handoff is invoked
  #
  # == Basic Handoff
  #
  #   # Simple handoff without custom logic
  #   handoff = CallbackHandoffTool.new(
  #     tool_name: "transfer_to_support",
  #     tool_description: "Transfer to customer support agent",
  #     input_json_schema: {},
  #     on_invoke_handoff: ->(context, input) { support_agent },
  #     agent_name: "SupportAgent"
  #   )
  #
  # == Advanced Handoff with Validation
  #
  #   # Handoff with input validation and filtering
  #   schema = {
  #     type: "object",
  #     properties: {
  #       issue_type: { type: "string", enum: ["billing", "technical"] },
  #       priority: { type: "string", enum: ["low", "medium", "high"] }
  #     },
  #     required: ["issue_type"]
  #   }
  #
  #   handoff = CallbackHandoffTool.new(
  #     tool_name: "escalate_to_specialist",
  #     tool_description: "Escalate to specialist based on issue type",
  #     input_json_schema: schema,
  #     on_invoke_handoff: ->(context, input) {
  #       # Custom logic to select appropriate specialist
  #       case input[:issue_type]
  #       when "billing" then billing_specialist
  #       when "technical" then tech_specialist
  #       end
  #     },
  #     agent_name: "SpecialistRouter",
  #     input_filter: ->(input) { input.except(:sensitive_data) }
  #   )
  #
  # @author RAAF Development Team
  # @since 0.1.0
  # @see Handoffs
  # @see HandoffInputData
  class CallbackHandoffTool

    include Logger

    # @!attribute [r] tool_name
    #   @return [String] Name of the tool as it appears to the invoking agent
    # @!attribute [r] tool_description
    #   @return [String] Description shown to the agent about this handoff tool
    # @!attribute [r] input_json_schema
    #   @return [Hash] JSON schema for validating handoff input parameters
    # @!attribute [r] agent_name
    #   @return [String] Name of the target agent this handoff delegates to
    # @!attribute [r] input_filter
    #   @return [Proc, nil] Optional filter function for handoff input data
    # @!attribute [r] strict_json_schema
    #   @return [Boolean] Whether to enforce strict JSON schema validation
    attr_reader :tool_name, :tool_description, :input_json_schema, :agent_name,
                :input_filter, :strict_json_schema

    ##
    # Initialize a new handoff
    #
    # Creates a handoff mechanism that allows one agent to delegate control to another.
    # The handoff appears as a tool to the invoking agent and handles the transition
    # of context and execution control.
    #
    # @param tool_name [String] unique name for the handoff tool
    # @param tool_description [String] description of what this handoff does
    # @param input_json_schema [Hash] JSON schema for validating input (can be empty)
    # @param on_invoke_handoff [Proc] function called when handoff is invoked
    # @param agent_name [String] name of the target agent
    # @param input_filter [Proc, nil] optional function to filter/transform input
    # @param strict_json_schema [Boolean] whether to enforce strict schema validation
    #
    # @example Basic handoff creation
    #   handoff = Handoff.new(
    #     tool_name: "transfer_to_billing",
    #     tool_description: "Transfer customer to billing department",
    #     input_json_schema: {},
    #     on_invoke_handoff: ->(context, input) { billing_agent },
    #     agent_name: "BillingAgent"
    #   )
    #
    # @example Handoff with input validation
    #   schema = {
    #     type: "object",
    #     properties: {
    #       customer_id: { type: "string" },
    #       issue_summary: { type: "string" }
    #     },
    #     required: ["customer_id"]
    #   }
    #
    #   handoff = Handoff.new(
    #     tool_name: "escalate_with_context",
    #     tool_description: "Escalate with customer context",
    #     input_json_schema: schema,
    #     on_invoke_handoff: ->(context, input) {
    #       # Load customer data and pass to specialist
    #       customer = Customer.find(input[:customer_id])
    #       specialist_agent.with_context(customer: customer)
    #     },
    #     agent_name: "SpecialistAgent"
    #   )
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

    ##
    # Invoke the handoff
    #
    # Executes the handoff process, transferring control from the current agent
    # to the target agent. This includes validating any input, applying filters,
    # running custom handoff logic, and returning the target agent.
    #
    # @param context_wrapper [Object] wrapper containing conversation context
    # @param input_json [String, nil] JSON string with handoff parameters
    # @return [Agent] the target agent that should handle the conversation
    #
    # @example Simple handoff invocation
    #   target_agent = handoff.invoke(context_wrapper)
    #
    # @example Handoff with input parameters
    #   input = '{"issue_type": "billing", "priority": "high"}'
    #   target_agent = handoff.invoke(context_wrapper, input)
    #
    # @raise [ModelBehaviorError] if input validation fails
    # @raise [ArgumentError] if handoff function has incorrect arity
    def invoke(context_wrapper, input_json = nil)
      log_debug_handoff("Invoking handoff function",
                        to_agent: @agent_name,
                        tool_name: @tool_name,
                        has_input: !input_json.nil?)

      result = @on_invoke_handoff.call(context_wrapper, input_json)

      log_debug_handoff("Handoff function completed",
                        to_agent: @agent_name,
                        result_type: result.class.name)

      result
    end

    ##
    # Get the transfer message for this handoff
    #
    # Generates a JSON message that indicates the handoff to the specified agent.
    # This message is used internally by the system to track agent transitions.
    #
    # @param agent [Agent] the agent being handed off to
    # @return [String] JSON string indicating the transfer
    #
    # @example Get transfer message
    #   message = handoff.get_transfer_message(support_agent)
    #   # => '{"assistant":"SupportAgent"}'
    def get_transfer_message(agent)
      JSON.generate({ assistant: agent.name })
    end

    ##
    # Generate default tool name for an agent
    #
    # Creates a standardized tool name based on the agent's name, following
    # the pattern "transfer_to_{sanitized_agent_name}". The agent name is
    # converted to lowercase and sanitized for use as a tool identifier.
    #
    # @param agent [Agent] agent to generate tool name for
    # @return [String] default tool name
    #
    # @example Generate tool name
    #   tool_name = CallbackHandoffTool.default_tool_name(billing_support_agent)
    #   # => "transfer_to_billing_support_agent"
    #
    # @example More examples
    #   CompanyDiscoveryAgent -> "transfer_to_company_discovery_agent"
    #   XMLParserAgent -> "transfer_to_xml_parser_agent"
    #   Customer Service Agent -> "transfer_to_customer_service_agent"
    def self.default_tool_name(agent)
      "transfer_to_#{Utils.snake_case(agent.name)}"
    end

    ##
    # Generate default tool description for an agent
    #
    # Creates a standardized description for the handoff tool, optionally
    # incorporating the agent's handoff_description if available.
    #
    # @param agent [Agent] agent to generate description for
    # @return [String] default tool description
    #
    # @example Generate description
    #   desc = CallbackHandoffTool.default_tool_description(support_agent)
    #   # => "Handoff to the SupportAgent agent to handle the request."
    def self.default_tool_description(agent)
      desc = "Handoff to the #{agent.name} agent to handle the request."
      desc += " #{agent.handoff_description}" if agent.respond_to?(:handoff_description) && agent.handoff_description
      desc
    end

    ##
    # Convert to tool definition for API
    #
    # Converts the handoff into a tool definition that can be used by AI models.
    # The resulting structure follows the OpenAI function calling format.
    #
    # @return [Hash] tool definition with type, name, and function details
    #
    # @example Convert to tool definition
    #   tool_def = handoff.to_tool_definition
    #   # => {
    #   #   type: "function",
    #   #   name: "transfer_to_support",
    #   #   function: {
    #   #     name: "transfer_to_support",
    #   #     description: "Transfer to customer support agent",
    #   #     parameters: { type: "object", properties: {} }
    #   #   }
    #   # }
    def to_tool_definition
      {
        type: "function",
        name: @tool_name,
        function: {
          name: @tool_name,
          description: @tool_description,
          parameters: @input_json_schema
        }
      }
    end

  end

  ##
  # Handoffs - Factory module for creating agent handoff mechanisms
  #
  # This module provides a comprehensive set of tools for creating different types
  # of agent handoffs in multi-agent workflows. It supports simple handoffs,
  # conditional handoffs, input validation, and custom handoff logic.
  #
  # == Handoff Types
  #
  # * **Simple Handoffs**: Basic agent-to-agent transfers
  # * **Conditional Handoffs**: Transfers based on runtime conditions
  # * **Validated Handoffs**: Transfers with input schema validation
  # * **Custom Handoffs**: Transfers with custom execution logic
  #
  # == Basic Usage
  #
  #   # Create a simple handoff
  #   handoff = RAAF::Handoffs.handoff(support_agent)
  #
  #   # Create handoff with custom description
  #   handoff = RAAF::Handoffs.simple_handoff(
  #     billing_agent,
  #     description: "Transfer billing inquiries to specialist"
  #   )
  #
  # == Advanced Usage
  #
  #   # Conditional handoff
  #   handoff = RAAF::Handoffs.conditional_handoff(
  #     escalation_agent,
  #     condition: ->(context) { context.priority == "urgent" },
  #     description: "Escalate urgent issues"
  #   )
  #
  #   # Handoff with input validation
  #   schema = {
  #     type: "object",
  #     properties: {
  #       customer_id: { type: "string" },
  #       issue_type: { type: "string" }
  #     },
  #     required: ["customer_id"]
  #   }
  #
  #   handoff = RAAF::Handoffs.validated_handoff(
  #     specialist_agent,
  #     input_schema: schema,
  #     description: "Transfer with customer context"
  #   )
  #
  # == Custom Handoff Logic
  #
  #   # Handoff with custom processing
  #   handoff = RAAF::Handoffs.handoff(
  #     target_agent,
  #     input_type: Hash,
  #     on_handoff: ->(context, input) {
  #       # Custom logic here
  #       customer = Customer.find(input[:customer_id])
  #       context.add_data(:customer, customer)
  #       log_handoff_event(context, customer)
  #     }
  #   )
  #
  # @author RAAF Development Team
  # @since 0.1.0
  # @see Handoff
  # @see HandoffInputData
  module Handoffs

    extend Logger

    class << self

      ##
      # Create a handoff from an agent
      #
      # This is the primary method for creating handoffs between agents. It provides
      # extensive customization options including custom tool names, descriptions,
      # input validation, filtering, and execution hooks.
      #
      # == Input Type Validation
      #
      # When `input_type` is specified, the handoff will validate input against that type:
      # * `String` - expects `{"input": "string_value"}`
      # * `Integer` - expects `{"input": 123}`
      # * `Hash` - expects any object structure
      # * Custom classes - attempts to instantiate with input data
      #
      # == Execution Hooks
      #
      # The `on_handoff` proc can have different signatures:
      # * With input_type: `proc { |context, validated_input| ... }`
      # * Without input_type: `proc { |context| ... }`
      #
      # @param agent [Agent] target agent to handoff to
      # @param tool_name_override [String, nil] custom tool name (auto-generated if nil)
      # @param tool_description_override [String, nil] custom tool description (auto-generated if nil)
      # @param on_handoff [Proc, nil] function to execute when handoff is invoked
      # @param input_type [Class, nil] expected type for input validation
      # @param input_filter [Proc, nil] function to filter/transform input data
      # @return [Handoff] configured handoff object
      #
      # @raise [ArgumentError] if input_type is specified without on_handoff
      # @raise [ArgumentError] if on_handoff has incorrect arity
      #
      # @example Basic handoff
      #   handoff = handoff(support_agent)
      #
      # @example Handoff with custom name and description
      #   handoff = handoff(
      #     billing_agent,
      #     tool_name_override: "escalate_billing",
      #     tool_description_override: "Escalate complex billing issues"
      #   )
      #
      # @example Handoff with input validation
      #   handoff = handoff(
      #     specialist_agent,
      #     input_type: Hash,
      #     on_handoff: ->(context, input) {
      #       # Validate customer_id is present
      #       raise "Missing customer_id" unless input[:customer_id]
      #
      #       # Load customer context
      #       customer = Customer.find(input[:customer_id])
      #       context.add_customer_data(customer)
      #     }
      #   )
      #
      # @example Handoff with input filtering
      #   handoff = handoff(
      #     public_agent,
      #     input_filter: ->(input) {
      #       # Remove sensitive data before handoff
      #       input.except(:credit_card, :ssn, :internal_notes)
      #     }
      #   )
      def handoff(
        agent,
        tool_name_override: nil,
        tool_description_override: nil,
        on_handoff: nil,
        input_type: nil,
        input_filter: nil
      )
        # Validate parameters - input_type requires on_handoff, but on_handoff can be used alone
        raise ArgumentError, "You must provide on_handoff when using input_type" if input_type && on_handoff.nil?

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
                                  additionalProperties: false
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
          log_debug_handoff("Creating handoff to agent",
                            to_agent: agent.name,
                            has_input_type: !input_type.nil?,
                            has_on_handoff: !on_handoff.nil?,
                            input_provided: !input_json.nil?)

          if input_type && on_handoff
            # Validate and parse input
            if input_json.nil? || input_json.empty?
              log_debug_handoff("Handoff input validation failed",
                                to_agent: agent.name,
                                error: "Expected non-null input but got None")
              raise ModelBehaviorError, "Handoff function expected non-null input, but got None"
            end

            begin
              parsed_input = JSON.parse(input_json)
              validated_input = validate_input(parsed_input, input_type)

              log_debug_handoff("Handoff input validated successfully",
                                to_agent: agent.name,
                                input_type: input_type.name)

              # Call the on_handoff function
              raise ArgumentError, "on_handoff must take two arguments: context and input" unless on_handoff.arity == 2

              on_handoff.call(context_wrapper, validated_input)
            rescue JSON::ParserError => e
              log_debug_handoff("Handoff JSON parsing failed",
                                to_agent: agent.name,
                                error: e.message)
              raise ModelBehaviorError, "Invalid JSON input for handoff: #{e.message}"
            end
          elsif on_handoff
            # No input type, just call with context
            log_debug_handoff("Executing context-only handoff",
                              to_agent: agent.name)

            raise ArgumentError, "on_handoff must take one argument: context" unless on_handoff.arity == 1

            on_handoff.call(context_wrapper)

          else
            log_debug_handoff("Simple handoff without custom logic",
                              to_agent: agent.name)
          end

          # Return the agent
          agent
        end

        # Create and return the handoff
        CallbackHandoffTool.new(
          tool_name: tool_name_override || CallbackHandoffTool.default_tool_name(agent),
          tool_description: tool_description_override || CallbackHandoffTool.default_tool_description(agent),
          input_json_schema: input_json_schema,
          on_invoke_handoff: on_invoke_handoff,
          agent_name: agent.name,
          input_filter: input_filter,
          strict_json_schema: true
        )
      end

      ##
      # Create a simple handoff without custom logic
      #
      # A convenience method for creating basic handoffs that simply transfer
      # control to another agent without any input validation, filtering, or
      # custom execution logic.
      #
      # @param agent [Agent] target agent to handoff to
      # @param description [String, nil] optional custom description
      # @return [Handoff] simple handoff object
      #
      # @example Simple handoff
      #   handoff = simple_handoff(support_agent)
      #
      # @example Simple handoff with custom description
      #   handoff = simple_handoff(
      #     billing_agent,
      #     description: "Transfer customer to billing department"
      #   )
      def simple_handoff(agent, description: nil)
        handoff(
          agent,
          tool_description_override: description
        )
      end

      ##
      # Create a conditional handoff
      #
      # Creates a handoff that only proceeds if the specified condition is met.
      # The condition is evaluated at handoff time with access to the conversation context.
      #
      # @param agent [Agent] target agent to handoff to
      # @param condition [Proc] condition that must return true for handoff to proceed
      # @param description [String, nil] optional custom description
      # @return [Handoff] conditional handoff object
      #
      # @raise [HandoffError] if condition returns false when handoff is attempted
      #
      # @example Business hours handoff
      #   handoff = conditional_handoff(
      #     human_agent,
      #     condition: ->(context) {
      #       current_hour = Time.now.hour
      #       current_hour.between?(9, 17)
      #     },
      #     description: "Transfer to human during business hours"
      #   )
      #
      # @example Priority-based handoff
      #   handoff = conditional_handoff(
      #     escalation_agent,
      #     condition: ->(context) {
      #       context.user_tier == "premium" || context.issue_priority == "urgent"
      #     },
      #     description: "Escalate for premium users or urgent issues"
      #   )
      def conditional_handoff(agent, condition:, description: nil)
        handoff(
          agent,
          tool_description_override: description,
          on_handoff: lambda { |context|
            # Evaluate the condition with the current context
            # This allows for dynamic handoff decisions based on conversation state
            raise HandoffError, "Handoff condition not met" unless condition.call(context)

            # Return true to indicate successful condition evaluation
            # The actual agent return happens in the main handoff logic
            true
          }
        )
      end

      ##
      # Create a handoff with input validation
      #
      # Creates a handoff that validates input against a JSON schema before proceeding.
      # This ensures that the receiving agent gets properly structured and validated data.
      #
      # @param agent [Agent] target agent to handoff to
      # @param input_schema [Hash] JSON schema for input validation
      # @param description [String, nil] optional custom description
      # @return [Handoff] validated handoff object
      #
      # @raise [HandoffError] if input validation fails
      #
      # @example Customer handoff with validation
      #   schema = {
      #     type: "object",
      #     properties: {
      #       customer_id: { type: "string", pattern: "^[A-Z0-9]+$" },
      #       issue_type: {
      #         type: "string",
      #         enum: ["billing", "technical", "account"]
      #       },
      #       priority: {
      #         type: "string",
      #         enum: ["low", "medium", "high", "urgent"]
      #       }
      #     },
      #     required: ["customer_id", "issue_type"]
      #   }
      #
      #   handoff = validated_handoff(
      #     specialist_agent,
      #     input_schema: schema,
      #     description: "Transfer with validated customer context"
      #   )
      def validated_handoff(agent, input_schema:, description: nil)
        handoff(
          agent,
          tool_description_override: description,
          input_type: Hash,
          on_handoff: lambda { |_context, input|
            # Use the structured output validator to ensure input matches the schema
            # This provides more detailed validation than basic type checking
            validator = StructuredOutput::ResponseFormatter.new(input_schema)
            result = validator.format_response(input)

            # Raise an error if validation fails, providing the specific error details
            raise HandoffError, "Invalid handoff input: #{result[:error]}" unless result[:valid]

            # Return true to indicate successful validation
            true
          }
        )
      end

      private

      ##
      # Infer JSON schema from Ruby type
      #
      # Attempts to generate a JSON schema for a given Ruby type. This is used
      # internally when creating handoffs with input_type validation.
      #
      # @param type [Class] Ruby class to generate schema for
      # @return [Hash] JSON schema object
      #
      # @example Schema inference
      #   schema = infer_schema_from_type(String)
      #   # => { type: "object", properties: { input: { type: "string" } } }
      #
      # @note Custom classes can implement #json_schema or #schema methods
      #       to provide their own schema definitions
      # @private
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
            additionalProperties: false
          }
        end
      end

      ##
      # Validate input against expected type
      #
      # Validates and converts input data to match the expected Ruby type.
      # This is used internally during handoff execution when input_type
      # validation is enabled.
      #
      # @param input [Hash] parsed JSON input data
      # @param expected_type [Class] expected Ruby type
      # @return [Object] validated and converted input
      #
      # @example Input validation
      #   validated = validate_input({"input" => "123"}, Integer)
      #   # => 123
      #
      # @raise [TypeError] if input cannot be converted to expected type
      # @private
      def validate_input(input, expected_type)
        case expected_type.name
        when "String"
          # Extract string value from the wrapper object and ensure it's a string
          input["input"].to_s
        when "Integer"
          # Extract integer value from the wrapper object and convert to integer
          input["input"].to_i
        when "Hash"
          # For Hash types, return the input directly (it's already a hash from JSON parsing)
          input
        else
          # For custom types, attempt to instantiate them with the input data
          # This allows users to define custom data classes for handoff input
          if expected_type.respond_to?(:new)
            expected_type.new(input)
          else
            # Fallback: return input as-is if we can't instantiate the type
            input
          end
        end
      end

    end

  end

  ##
  # Convenience method for creating handoffs at module level
  #
  # This is a convenience method that delegates to Handoffs.handoff, allowing
  # you to create handoffs using the shorter RAAF.handoff syntax instead of
  # RAAF::Handoffs.handoff.
  #
  # @param agent [Agent] target agent to handoff to
  # @param options [Hash] all options supported by Handoffs.handoff
  # @return [Handoff] configured handoff object
  #
  # @example Use convenience method
  #   # Instead of:
  #   handoff = RAAF::Handoffs.handoff(support_agent)
  #
  #   # You can use:
  #   handoff = RAAF.handoff(support_agent)
  #
  # @see Handoffs.handoff
  def self.handoff(agent, **)
    Handoffs.handoff(agent, **)
  end

  ##
  # Add recommended handoff instructions to a custom prompt
  #
  # This function prepends the RECOMMENDED_PROMPT_PREFIX to your custom prompt,
  # providing the essential context about the multi-agent system and handoff
  # behavior. This matches the OpenAI Agents SDK's prompt_with_handoff_instructions
  # function for compatibility.
  #
  # == Usage
  #
  # Use this function when creating agents that need to understand handoffs:
  #
  #   instructions = RAAF.prompt_with_handoff_instructions(
  #     "You are a helpful customer service agent. Be polite and professional."
  #   )
  #
  # == Benefits
  #
  # - Ensures consistent handoff behavior across agents
  # - Provides LLM with proper context about multi-agent system
  # - Maintains compatibility with OpenAI Agents SDK patterns
  # - Reduces boilerplate in agent configuration
  #
  # @param prompt [String] your custom agent instructions
  # @return [String] complete instructions with handoff context
  #
  # @example Basic usage
  #   agent = RAAF::Agent.new(
  #     name: "SupportAgent",
  #     instructions: RAAF.prompt_with_handoff_instructions(
  #       "You are a customer support specialist. Help users with their questions."
  #     ),
  #     model: "gpt-4o"
  #   )
  #
  # @example With detailed instructions
  #   custom_instructions = <<~INSTRUCTIONS
  #     You are a technical support agent specializing in API integration issues.
  #
  #     Your responsibilities:
  #     - Diagnose API connectivity problems
  #     - Provide code examples for common integration patterns
  #     - Escalate complex issues to senior engineers when needed
  #
  #     Always be clear and provide actionable solutions.
  #   INSTRUCTIONS
  #
  #   agent = RAAF::Agent.new(
  #     name: "TechSupport",
  #     instructions: RAAF.prompt_with_handoff_instructions(custom_instructions),
  #     model: "gpt-4o"
  #   )
  #
  # @since 0.1.0
  # @see RECOMMENDED_PROMPT_PREFIX
  def self.prompt_with_handoff_instructions(prompt)
    return RECOMMENDED_PROMPT_PREFIX if prompt.nil? || prompt.empty?

    "#{RECOMMENDED_PROMPT_PREFIX}\n\n#{prompt}"
  end

end
