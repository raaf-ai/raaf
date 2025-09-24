# frozen_string_literal: true

require "raaf/function_tool"

# Require tracing integration if available
begin
  require "raaf/tracing/tool_integration"
rescue LoadError
  # Tracing not available
end

module RAAF
  module Tools
    ##
    # Example tool that demonstrates tracing integration
    #
    # This tool shows how to use the RAAF::Tracing::ToolIntegration module
    # to automatically create child spans when running within an agent context.
    #
    # @example Basic usage
    #   tool = TracedExampleTool.new
    #   result = tool.process_data(data: "sample")
    #
    # @example With agent context
    #   agent = RAAF::Agent.new(name: "TestAgent")
    #   agent.add_tool(TracedExampleTool.new)
    #   runner = RAAF::Runner.new(agent: agent)
    #   result = runner.run("Process some data")
    #
    class TracedExampleTool < FunctionTool
      # Include tracing integration if available
      if defined?(RAAF::Tracing::ToolIntegration)
        include RAAF::Tracing::ToolIntegration
      end

      ##
      # Initialize a new traced example tool
      #
      def initialize
        super(method(:process_data),
              name: "process_data",
              description: "Process data with automatic tracing integration",
              parameters: process_data_parameters)
      end

      ##
      # Process data with tracing
      #
      # @param data [String] The data to process
      # @return [Hash] Processing result
      #
      def process_data(data:)
        # Use tool tracing if integration is available
        if respond_to?(:with_tool_tracing)
          with_tool_tracing(:process_data, data_size: data.length) do
            perform_processing(data)
          end
        else
          # Fallback for when tracing is not available
          perform_processing(data)
        end
      end

      private

      ##
      # Defines the parameters schema for the process_data function
      #
      # @return [Hash] JSON Schema for parameters
      #
      def process_data_parameters
        {
          type: "object",
          properties: {
            data: {
              type: "string",
              description: "Data to process"
            }
          },
          required: ["data"]
        }
      end

      ##
      # Performs the actual data processing
      #
      # @param data [String] The data to process
      # @return [Hash] Processing result
      #
      def perform_processing(data)
        # Simulate some processing work
        processed_data = data.upcase.reverse
        
        {
          original: data,
          processed: processed_data,
          length: data.length,
          timestamp: Time.now.iso8601
        }
      end
    end
  end
end
