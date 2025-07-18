# frozen_string_literal: true

# Base class for AI tool configurations used by agents in the AI Agent DSL framework
#
# This class provides a configuration-only approach for defining AI tools that can be
# used by agents. It only handles tool definition and configuration - all execution
# is delegated to the RAAF framework.
#
# Tools are configuration objects that define the structure, parameters, and metadata
# for tools that will be executed by the RAAF framework. The DSL is purely
# configurational and does not execute tools directly.
#
# @abstract Subclasses must implement {#tool_name} and {#build_tool_definition}
#
# @example Creating a basic tool configuration
#   class CalculatorTool < RAAF::DSL::Tools::Base
#     def tool_name
#       "calculator"
#     end
#
#     def build_tool_definition
#       {
#         type: "function",
#         function: {
#           name: tool_name,
#           description: "Performs basic mathematical calculations",
#           parameters: {
#             type: "object",
#             properties: {
#               expression: { type: "string", description: "Mathematical expression to evaluate" }
#             },
#             required: ["expression"],
#             additionalProperties: false
#           }
#         }
#       }
#     end
#   end
#
# @example Using with DSL
#   class AdvancedTool < RAAF::DSL::Tools::Base
#     include RAAF::DSL::ToolDsl
#
#     tool_name "advanced_search"
#     description "Advanced search with filtering"
#     parameter :query, type: :string, required: true
#     parameter :limit, type: :integer, default: 10
#   end
#
# @see RAAF::DSL::ToolDsl For DSL-based tool configuration
# @see RAAF::DSL::AgentDsl#uses_tool For using tools in agents
# @since 0.1.0
#
module RAAF

  module DSL

    module Tools

      class Base

        attr_reader :options

        # Initialize a tool configuration
        #
        # @param options [Hash] Configuration options for the tool
        #
        def initialize(options = {})
          @options = options || {}
        end

        # Returns the complete tool configuration for RAAF framework
        #
        # This method combines the base tool definition with any additional metadata
        # to create a complete tool configuration that can be passed to the OpenAI
        # Agents framework for execution.
        #
        # @return [Hash] Complete tool configuration
        #
        def tool_configuration
          base_definition = build_tool_definition

          # Add common metadata if available
          if respond_to?(:application_metadata, true)
            base_definition.merge(application_metadata)
          else
            base_definition
          end
        end

        # Returns the tool definition for OpenAI API compatibility
        #
        # @deprecated Use {#tool_configuration} instead
        # @return [Hash] Tool definition
        #
        def tool_definition
          tool_configuration
        end

        # Returns the tool name
        #
        # @abstract Subclasses must implement this method
        # @return [String] The name of the tool
        # @raise [NotImplementedError] If not implemented by subclass
        #
        def tool_name
          raise NotImplementedError, "Subclasses must implement #tool_name"
        end

        # Builds the tool definition structure
        #
        # @abstract Subclasses must implement this method
        # @return [Hash] Tool definition in OpenAI function format
        # @raise [NotImplementedError] If not implemented by subclass
        #
        def build_tool_definition
          raise NotImplementedError, "Subclasses must implement #build_tool_definition"
        end

        private

        # Override in subclasses to provide application-specific metadata
        #
        # @return [Hash] Additional metadata to merge with tool definition
        #
        def application_metadata
          {}
        end

      end

    end

  end

end
