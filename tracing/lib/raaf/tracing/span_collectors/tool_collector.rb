# frozen_string_literal: true

require_relative "base_collector"

module RAAF
  module Tracing
    module SpanCollectors
      # Specialized collector for Tool components that captures tool execution details,
      # method information, agent context, and results. This collector provides visibility
      # into individual tool calls and their outcomes within agent workflows.
      #
      # @example Basic usage with RAAF tool
      #   tool = MySearchTool.new
      #   collector = ToolCollector.new
      #   attributes = collector.collect_attributes(tool)
      #   result_attrs = collector.collect_result(tool, execution_result)
      #
      # @example Captured tool information
      #   # Tool identification
      #   attributes["tool.name"]  # => "MySearchTool"
      #   attributes["tool.method"]  # => "search_web"
      #
      #   # Agent context
      #   attributes["tool.agent_context"]  # => "RAAF::Agent"
      #
      #   # Tool execution results
      #   result_attrs["result.execution_result"]  # => "Search completed: 5 results found"
      #   result_attrs["result.tool_result"]  # => {full_result_object}
      #
      # @example Integration with agent tracing
      #   agent = RAAF::Agent.new(name: "Assistant")
      #   agent.add_tool(MySearchTool.new)
      #   tracer = RAAF::Tracing::SpanTracer.new
      #   runner = RAAF::Runner.new(agent: agent, tracer: tracer)
      #   result = runner.run("Search for Ruby tutorials")
      #   # Tool execution automatically traced with full context
      #
      # @note Tool names are extracted from class names when available
      # @note Method names come from internal @method_name instance variable
      # @note Agent context detection helps correlate tool calls with parent agents
      # @note Tool results are serialized safely for span storage
      #
      # @see BaseCollector For DSL methods and common attribute handling
      # @see AgentCollector For parent agent tracing that includes tool calls
      # @see RAAF::Tool The component type this collector specializes in tracing
      #
      # @since 1.0.0
      # @author RAAF Team
      class ToolCollector < BaseCollector
        # Tool identification and method extraction
        span name: ->(comp) { comp.class.name }
        span method: ->(comp) { comp.instance_variable_get(:@method_name)&.to_s || "unknown" }

        # Agent context detection - identifies which agent is executing this tool
        # @return [String] Class name of the parent agent or nil if not detectable
        span agent_context: ->(comp) do
          if comp.respond_to?(:detect_agent_context)
            comp.detect_agent_context&.class&.name
          end
        end

        # ============================================================================
        # TOOL RESULT COLLECTION
        # These attributes capture tool execution outcomes and full result data
        # for analysis and debugging purposes.
        # ============================================================================

        # Truncated execution result for quick overview (first 100 characters)
        # @return [String] Truncated string representation of the tool result
        result execution_result: ->(result, comp) { result.to_s[0..100] }

        # Complete tool result for detailed analysis and UI display
        # The safe_value method from BaseCollector handles complex object serialization
        # @return [Object] Full tool result with automatic serialization safety
        result tool_result: ->(result, comp) { result }
      end
    end
  end
end
