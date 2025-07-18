# frozen_string_literal: true

module RAAF

  module DSL

    module AgentDsl

      # Tool configuration methods for agent DSL
      module Tools

        extend ActiveSupport::Concern

        class_methods do
          # Configure tools
          def uses_tool(tool_name, options = {})
            _tools_config << { name: tool_name, options: options }
          end

          def uses_tools(*tool_names)
            tool_names.each { |name| uses_tool(name) }
          end

          # Configure multiple tools with a hash of options
          def configure_tools(tools_hash)
            tools_hash.each do |tool_name, options|
              uses_tool(tool_name, options || {})
            end
          end

          # Add tools with conditional logic
          def uses_tool_if(condition, tool_name, options = {})
            uses_tool(tool_name, options) if condition
          end
        end

      end

    end

  end

end
