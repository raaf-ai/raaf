# frozen_string_literal: true

require "raaf-core"
require_relative "tool"

module RAAF

  # Compatibility layer for existing FunctionTool usage
  #
  # This module ensures that existing code using FunctionTool
  # continues to work while the system migrates to the unified
  # Tool architecture.
  #
  module ToolCompatibility

    # Enhance FunctionTool to work with new Tool system
    module FunctionToolExtensions

      def self.included(base)
        base.class_eval do
          # Make FunctionTool compatible with Tool registry
          def self.from_tool(tool_instance)
            return tool_instance if tool_instance.is_a?(FunctionTool)

            if tool_instance.respond_to?(:to_function_tool)
              tool_instance.to_function_tool
            else
              # Wrap the tool in a FunctionTool
              FunctionTool.new(
                tool_instance.method(:call),
                name: tool_instance.name,
                description: tool_instance.description,
                parameters: tool_instance.parameters,
                is_enabled: tool_instance.enabled?
              )
            end
          end
        end
      end

    end

    # Extensions for Tool class to ensure compatibility
    module ToolExtensions

      # Check if this tool can be used as a FunctionTool
      def function_tool_compatible?
        respond_to?(:call) && !native?
      end

      # Convert to hash format expected by agents
      def to_h
        to_tool_definition
      end

    end

    # Agent extensions for backward compatibility
    module AgentExtensions

      def self.included(base)
        base.class_eval do
          # Original add_tool method compatibility
          alias_method :add_tool_original, :add_tool if method_defined?(:add_tool)

          def add_tool(tool)
            case tool
            # A unified tool converts itself, and so does anything else that
            # answers to_function_tool. Nothing in the branches below defines
            # that method, so testing for it first changes no dispatch.
            when RAAF::Tool, ->(candidate) { candidate.respond_to?(:to_function_tool) }
              add_tool_original(tool.to_function_tool)
            when RAAF::FunctionTool
              # Existing FunctionTool - use as-is
              add_tool_original(tool)
            when Method, Proc
              # Raw callable - wrap in FunctionTool
              add_tool_original(FunctionTool.new(tool))
            else
              # Hand anything else to the original method: it accepts duck-typed
              # callables and raises ToolError for what it cannot use.
              add_tool_original(tool)
            end
          end
        end
      end

    end

    # Apply compatibility patches
    def self.apply!
      # Extend FunctionTool with compatibility methods
      RAAF::FunctionTool.include(FunctionToolExtensions) if defined?(RAAF::FunctionTool)

      # Extend Tool with compatibility methods
      RAAF::Tool.include(ToolExtensions) if defined?(RAAF::Tool)

      # Extend Agent if it exists
      RAAF::Agent.include(AgentExtensions) if defined?(RAAF::Agent)

      # Log that compatibility layer is active
      return unless defined?(RAAF::Logging)

      RAAF.logger.info("Tool compatibility layer activated")
    end

    # Migration helper to convert old-style tools to new format
    class Migrator

      def self.migrate_tool(old_tool)
        case old_tool
        when Hash
          # Old-style hash tool definition
          migrate_hash_tool(old_tool)
        when Class
          if old_tool < RAAF::FunctionTool
            # Old FunctionTool subclass
            migrate_function_tool_class(old_tool)
          else
            # Already a new Tool class
            old_tool
          end
        else
          # Instance - try to convert
          raise "Cannot migrate tool: #{old_tool.inspect}" unless old_tool.respond_to?(:to_function_tool)

          old_tool

        end
      end

      def self.migrate_hash_tool(hash_tool)
        # Create a new Tool class from hash definition
        Class.new(RAAF::Tool) do
          configure name: hash_tool[:name],
                    description: hash_tool[:description]

          define_method :call do |**_params|
            # Implement based on hash tool definition
            raise NotImplementedError, "Hash tool migration not fully implemented"
          end
        end
      end

      def self.migrate_function_tool_class(tool_class)
        # Create new Tool class that wraps the old FunctionTool
        Class.new(RAAF::Tool) do
          configure name: tool_class.name.underscore.gsub(/_tool$/, "")

          define_method :call do |**params|
            # Delegate to old tool
            old_instance = tool_class.new
            old_instance.call(**params)
          end
        end
      end

    end

  end

end

# Auto-apply compatibility layer when this file is required
RAAF::ToolCompatibility.apply!
