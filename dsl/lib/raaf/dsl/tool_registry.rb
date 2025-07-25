# frozen_string_literal: true

# Registry for mapping tool names to their implementations
#
# This registry allows tools to be referenced by symbol names in agent DSL
# and resolved to their actual implementation classes at runtime.
#
module RAAF
  module DSL
    class ToolRegistry
      class << self
        def registry
          @registry ||= {}
        end

        # Register a tool class with a name
        #
        # @param name [Symbol, String] The name to register the tool under
        # @param tool_class [Class] The tool class to register
        # @param options [Hash] Additional options for tool registration
        def register(name, tool_class, **options)
          registry[name.to_sym] = {
            class: tool_class,
            options: options
          }
        end

        # Get a tool class by name
        #
        # @param name [Symbol, String] The name of the tool to retrieve
        # @return [Class, nil] The tool class if found
        def get(name)
          entry = registry[name.to_sym]
          entry ? entry[:class] : nil
        end

        # Check if a tool is registered
        #
        # @param name [Symbol, String] The name to check
        # @return [Boolean] True if the tool is registered
        def registered?(name)
          registry.key?(name.to_sym)
        end

        # Clear all registered tools (mainly for testing)
        def clear!
          @registry = {}
        end

        # Get all registered tool names
        #
        # @return [Array<Symbol>] Array of registered tool names
        def names
          registry.keys
        end
      end
    end
  end
end
