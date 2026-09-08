# frozen_string_literal: true

module RAAF
  module DSL
    ##
    # Builds a single tool definition for {AgentBuilder#tool}
    #
    # The builder collects a description, a JSON-schema parameter list and the
    # block that runs when the tool is called, and hands them back as the
    # configuration hash the agent builder turns into a
    # {RAAF::FunctionTool}.
    #
    # @example
    #   config = RAAF::DSL::ToolBuilder.build(:web_search) do
    #     description "Search the web for information"
    #     parameter :query, type: :string, required: true
    #
    #     execute do |query:|
    #       { results: search(query) }
    #     end
    #   end
    #
    class ToolBuilder
      # @return [Symbol, String] Tool name
      attr_reader :tool_name

      # @return [Hash] Tool configuration collected so far
      attr_reader :config

      ##
      # Build a tool from a block
      #
      # @param name [Symbol, String] Tool name
      # @param block [Proc] Tool definition block
      # @return [RAAF::FunctionTool] The tool, ready to add to an agent
      #
      def self.build(name = nil, &block)
        builder = new(name)
        builder.instance_eval(&block) if block
        config = builder.build_config
        to_function_tool(config[:name], config)
      end

      ##
      # Turn a built configuration into a core tool
      #
      # @param name [Symbol, String] Tool name
      # @param config [Hash] Configuration from {#build_config}
      # @return [RAAF::FunctionTool]
      #
      def self.to_function_tool(name, config)
        RAAF::FunctionTool.new(
          config[:execution_block],
          name: name.to_s,
          description: config[:description],
          parameters: config[:parameters]
        )
      end

      ##
      # Initialize tool builder
      #
      # @param name [Symbol, String] Tool name
      #
      def initialize(name = nil)
        @tool_name = name
        @config = {
          parameters: {
            type: "object",
            properties: {},
            required: []
          }
        }
        @execution_block = nil
      end

      ##
      # Set the tool name
      #
      # @param name [Symbol, String] Tool name
      #
      def name(name)
        @tool_name = name
      end

      ##
      # Set the tool description shown to the model
      #
      # @param description [String] Tool description
      #
      def description(description)
        @config[:description] = description
      end

      ##
      # Declare a parameter
      #
      # @param name [Symbol] Parameter name
      # @param type [Symbol] JSON schema type
      # @param required [Boolean] Whether the model must supply the parameter
      # @param options [Hash] Extra JSON schema attributes (enum, items, ...)
      #
      def parameter(name, type: :string, required: false, **options)
        @config[:parameters][:properties][name] = { type: type.to_s, **options }
        @config[:parameters][:required] << name if required
      end

      ##
      # Define the block executed when the model calls the tool
      #
      # @param block [Proc] Execution block, called with keyword arguments
      #
      def execute(&block)
        @execution_block = block
      end

      ##
      # Build the configuration hash
      #
      # @return [Hash] Tool configuration including the execution block
      #
      def build_config
        @config.merge(name: @tool_name, execution_block: @execution_block)
      end
    end
  end
end
