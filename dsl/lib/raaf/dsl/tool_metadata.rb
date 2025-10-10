# frozen_string_literal: true

module RAAF
  module DSL
    # Tool execution metadata injection module
    #
    # Provides functionality to inject execution metadata into tool results,
    # including duration, tool name, timestamp, and agent name.
    #
    # @example Basic usage
    #   class MyAgent < RAAF::DSL::Agent
    #     include RAAF::DSL::ToolMetadata
    #
    #     def execute_tool(tool, arguments)
    #       start_time = Time.now
    #       result = super
    #       duration_ms = ((Time.now - start_time) * 1000).round(2)
    #       inject_metadata!(result, tool, duration_ms)
    #       result
    #     end
    #   end
    module ToolMetadata
      # Inject execution metadata into a Hash result
      #
      # Adds a :_execution_metadata key with duration, tool name, timestamp,
      # and agent name information. Only modifies Hash results; other types
      # are left unchanged.
      #
      # @param result [Hash] The tool execution result to modify
      # @param tool [Object] The tool instance that was executed
      # @param duration_ms [Float] The execution duration in milliseconds
      # @return [Hash] The modified result with metadata injected
      #
      # @example Inject metadata
      #   result = { success: true, data: "result" }
      #   inject_metadata!(result, my_tool, 42.5)
      #   # => { success: true, data: "result",
      #   #      _execution_metadata: { duration_ms: 42.5, ... } }
      def inject_metadata!(result, tool, duration_ms)
        return result unless result.is_a?(Hash)

        metadata = {
          _execution_metadata: {
            duration_ms: duration_ms,
            tool_name: extract_tool_name(tool),
            timestamp: Time.now.iso8601,
            agent_name: self.class.agent_name
          }
        }

        # Merge metadata, preserving existing _execution_metadata if present
        if result.key?(:_execution_metadata)
          result[:_execution_metadata].merge!(metadata[:_execution_metadata])
        else
          result.merge!(metadata)
        end

        result
      end

      private

      # Extract tool name from various tool types
      #
      # Tries multiple strategies to get a meaningful tool name:
      # 1. tool_name method (DSL tools)
      # 2. name method (generic tools)
      # 3. @name instance variable (FunctionTool)
      # 4. Class name parsing
      # 5. Fallback to "unknown_tool"
      #
      # @param tool [Object] The tool instance
      # @return [String] The extracted tool name
      def extract_tool_name(tool)
        if tool.respond_to?(:tool_name)
          tool.tool_name
        elsif tool.respond_to?(:name)
          tool.name
        elsif tool.is_a?(RAAF::FunctionTool)
          tool.instance_variable_get(:@name) || "unknown_tool"
        else
          # Fallback: parse class name
          class_name = tool.class.name
          return "unknown_tool" unless class_name

          # Convert "RAAF::Tools::CustomTool" -> "custom_tool"
          class_name.split("::").last.
            gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2').
            gsub(/([a-z\d])([A-Z])/, '\1_\2').
            downcase.
            gsub(/_tool$/, '')
        end
      end
    end
  end
end
