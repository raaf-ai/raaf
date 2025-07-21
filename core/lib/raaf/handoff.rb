# frozen_string_literal: true

require_relative "handoff_context"

module RAAF
  ##
  # Handoff specification class (matches Python SDK exactly)
  #
  # This class represents a handoff configuration that can be passed
  # to an agent's handoffs parameter, matching the Python SDK API.
  #
  class Handoff
    attr_reader :agent, :overrides, :input_filter, :description
    attr_reader :tool_name_override, :tool_description_override, :on_handoff, :input_type

    def initialize(agent, overrides: {}, input_filter: nil, description: nil, 
                   tool_name_override: nil, tool_description_override: nil, 
                   on_handoff: nil, input_type: nil)
      @agent = agent
      @overrides = overrides
      @input_filter = input_filter
      @description = description
      @tool_name_override = tool_name_override
      @tool_description_override = tool_description_override
      @on_handoff = on_handoff
      @input_type = input_type
    end

    ##
    # Get the input schema for this handoff
    #
    # @return [Hash] JSON schema for handoff parameters
    #
    def get_input_schema
      # If target agent has a schema, use it
      if @agent.respond_to?(:get_input_schema)
        @agent.get_input_schema
      else
        # Default schema
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
    # Apply input filter if configured
    #
    # @param data [Hash] Raw handoff data
    # @return [Hash] Filtered handoff data
    #
    def filter_input(data)
      if @input_filter
        @input_filter.call(data)
      else
        data
      end
    end

    ##
    # Create target agent instance with overrides
    #
    # @param base_config [Hash] Base configuration
    # @return [Agent] Agent instance with overrides applied
    #
    def create_agent_instance(base_config = {})
      config = base_config.merge(@overrides)
      
      if @agent.is_a?(Class)
        @agent.new(**config)
      else
        # Clone existing agent with overrides
        @agent.clone.tap do |cloned_agent|
          config.each { |key, value| cloned_agent.send("#{key}=", value) }
        end
      end
    end
  end

  ##
  # Handoff factory function (matches Python SDK exactly)
  #
  # Creates a Handoff object that can be passed to an agent's handoffs parameter.
  # This function matches the Python SDK handoff() function signature.
  #
  # @param agent [Agent, Class] Target agent or agent class
  # @param overrides [Hash] Configuration overrides for the target agent
  # @param input_filter [Proc] Function to filter/transform handoff data
  # @param description [String] Description of the handoff
  # @param tool_name_override [String] Override the default tool name
  # @param tool_description_override [String] Override the default tool description
  # @param on_handoff [Proc] Callback function executed when handoff is invoked
  # @param input_type [Class] The type of input expected by the handoff
  # @return [Handoff] Handoff specification
  #
  # @example Simple handoff
  #   RAAF.handoff(CompanyDiscoveryAgent)
  #
  # @example Custom handoff with all options
  #   RAAF.handoff(
  #     SpecialistAgent,
  #     overrides: { model: "gpt-4", temperature: 0.7 },
  #     input_filter: proc { |data| filter_sensitive_data(data) },
  #     tool_name_override: "escalate_to_specialist",
  #     tool_description_override: "Escalate to specialist agent",
  #     on_handoff: proc { |data| puts "Handoff executed: #{data}" },
  #     input_type: EscalationData
  #   )
  #
  def self.handoff(agent, overrides: {}, input_filter: nil, description: nil,
                   tool_name_override: nil, tool_description_override: nil, 
                   on_handoff: nil, input_type: nil)
    Handoff.new(
      agent, 
      overrides: overrides, 
      input_filter: input_filter, 
      description: description,
      tool_name_override: tool_name_override,
      tool_description_override: tool_description_override,
      on_handoff: on_handoff,
      input_type: input_type
    )
  end

end