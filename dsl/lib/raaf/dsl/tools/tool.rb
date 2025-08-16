# frozen_string_literal: true

require_relative "convention_over_configuration"

# Load subclasses
Dir[File.join(__dir__, "tool", "*.rb")].each { |file| require_relative file }

# Main Tool base class for RAAF DSL framework
#
# This class provides the foundation for all executable tools in RAAF. It follows
# Ruby's callable object convention using the `call` method as the standard execution
# interface. Tools are configuration objects that define structure, parameters, and
# execution logic for AI agents.
#
# The Tool class supports Ruby's callable syntactic sugar, allowing tools to be
# invoked using the .() syntax:
#   tool = MyTool.new
#   result = tool.(params)  # equivalent to tool.call(params)
#
# @abstract Subclasses must implement {#call} method
#
# @example Creating a basic tool
#   class CalculatorTool < RAAF::DSL::Tools::Tool
#     def call(expression:)
#       eval(expression)
#     rescue => e
#       { error: e.message }
#     end
#   end
#
# @example Using convention over configuration
#   class AdvancedCalculator < RAAF::DSL::Tools::Tool
#     include ConventionOverConfiguration
#     
#     # Auto-generates name, description, and tool definition
#     def call(expression:, precision: 2)
#       result = eval(expression)
#       result.round(precision)
#     end
#   end
#
# @see RAAF::DSL::Tools::Tool::API For external API tools
# @see RAAF::DSL::Tools::Tool::Native For OpenAI native tools
# @see RAAF::DSL::Tools::ConventionOverConfiguration For auto-generation
# @since 1.0.0
#
module RAAF
  module DSL
    module Tools
      class Tool
        include ConventionOverConfiguration

        attr_reader :options

        # Initialize a tool with configuration options
        #
        # @param options [Hash] Configuration options for the tool
        # @option options [String] :name Override tool name
        # @option options [String] :description Override tool description
        # @option options [Boolean] :enabled (true) Whether tool is enabled
        #
        def initialize(options = {})
          @options = options || {}
        end

        # Execute the tool with given parameters
        #
        # This is the main execution method following Ruby's callable object
        # convention. Subclasses must implement this method to define their
        # specific functionality.
        #
        # @abstract Subclasses must implement this method
        # @param params [Hash] Parameters for tool execution
        # @return [Object] Result of tool execution
        # @raise [NotImplementedError] If not implemented by subclass
        #
        def call(**params)
          raise NotImplementedError, "Subclasses must implement #call method"
        end

        # Check if the tool is enabled
        #
        # Tools can be disabled through configuration or conditionally based
        # on environment or other factors. Disabled tools will not be included
        # in agent tool definitions.
        #
        # @return [Boolean] true if tool is enabled, false otherwise
        #
        def enabled?
          return @options[:enabled] if @options.key?(:enabled)
          true
        end

        # Returns the tool name
        #
        # Can be overridden by subclasses or set via options. If not provided,
        # the ConventionOverConfiguration module will generate one based on
        # the class name.
        #
        # @return [String] The name of the tool
        #
        def name
          @options[:name] || self.class.tool_name
        end

        # Returns the tool description
        #
        # Can be overridden by subclasses or set via options. If not provided,
        # the ConventionOverConfiguration module will generate one based on
        # the class name and method signature.
        #
        # @return [String] The description of the tool
        #
        def description
          @options[:description] || self.class.tool_description
        end

        # Returns the complete tool definition for OpenAI API
        #
        # This method generates the tool definition structure required by
        # OpenAI's function calling API. The definition includes the tool
        # name, description, and parameter schema.
        #
        # @return [Hash] Tool definition in OpenAI function format
        #
        def to_tool_definition
          self.class.tool_definition_for_instance(self)
        end

        # Process the result after tool execution
        #
        # This method can be overridden by subclasses to modify or transform
        # the result before it's returned to the agent. By default, it returns
        # the result unchanged.
        #
        # @param result [Object] The result from tool execution
        # @return [Object] The processed result
        #
        def process_result(result)
          result
        end

        # Returns tool configuration for framework integration
        #
        # Provides a complete configuration hash that includes the tool
        # definition and any additional metadata needed for framework
        # integration.
        #
        # @return [Hash] Complete tool configuration
        #
        def tool_configuration
          {
            tool: to_tool_definition,
            callable: self,
            enabled: enabled?,
            metadata: {
              class: self.class.name,
              options: @options
            }
          }
        end

        class << self
          # Define tool-level configuration
          #
          # @param name [String] Tool name
          # @param description [String] Tool description
          # @param enabled [Boolean] Whether tool is enabled by default
          #
          def configure(name: nil, description: nil, enabled: true)
            @tool_name = name if name
            @tool_description = description if description
            @tool_enabled = enabled
          end

          # Get the configured tool name
          #
          # @return [String] Tool name
          #
          def tool_name
            @tool_name || generate_tool_name
          end

          # Get the configured tool description
          #
          # @return [String] Tool description
          #
          def tool_description
            @tool_description || generate_tool_description
          end

          # Get the configured enabled status
          #
          # @return [Boolean] Whether tool is enabled
          #
          def tool_enabled
            @tool_enabled.nil? ? true : @tool_enabled
          end

          private

          # Generate tool name from class name
          #
          # @return [String] Generated tool name
          #
          def generate_tool_name
            name.split('::').last
                .gsub(/Tool$/, '')
                .gsub(/([A-Z])/, '_\1')
                .downcase
                .sub(/^_/, '')
          end

          # Generate tool description from class name
          #
          # @return [String] Generated tool description
          #
          def generate_tool_description
            class_name = name.split('::').last.gsub(/Tool$/, '')
            words = class_name.gsub(/([A-Z])/, ' \1').strip.downcase
            "Tool for #{words} operations"
          end
        end
      end
    end
  end
end