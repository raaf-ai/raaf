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
        # ============================================================================
        # TOOL IDENTIFICATION
        # These attributes identify and locate the tool in the system
        # ============================================================================

        # Tool class name for identification
        span name: ->(comp) { comp.class.name }

        # Tool method name (how the tool is called)
        span method: ->(comp) { comp.instance_variable_get(:@method_name)&.to_s || "unknown" }

        # Agent context detection - identifies which agent is executing this tool
        # @return [String] Class name of the parent agent or nil if not detectable
        span agent_context: ->(comp) do
          if comp.respond_to?(:detect_agent_context)
            comp.detect_agent_context&.class&.name
          end
        end

        # ============================================================================
        # TOOL EXECUTION METRICS
        # These attributes track execution performance and status
        # ============================================================================

        # Execution duration in milliseconds
        # Stored as: tool.duration_ms
        # @return [String] Duration in milliseconds or "N/A"
        span "duration.ms": ->(comp) do
          if comp.respond_to?(:execution_duration_ms)
            comp.execution_duration_ms.to_s
          else
            "N/A"
          end
        end

        # Execution status - success or failure
        # Stored as: tool.status
        # @return [String] "success" or "failure"
        span status: ->(comp) do
          # Status will be set from result in collect_result
          "N/A"
        end

        # Number of retry attempts made
        # Stored as: tool.retry_count
        # @return [String] Number of retries or "0"
        span "retry.count": ->(comp) do
          if comp.respond_to?(:retry_count)
            comp.retry_count.to_s
          else
            "0"
          end
        end

        # Total backoff delay in milliseconds across all retries
        # Stored as: tool.retry.total_backoff_ms
        # @return [String] Total backoff time or "0"
        span "retry.total_backoff_ms": ->(comp) do
          if comp.respond_to?(:total_backoff_ms)
            comp.total_backoff_ms.to_s
          else
            "0"
          end
        end

        # ============================================================================
        # TOOL RESULT COLLECTION
        # These attributes capture tool execution outcomes and full result data
        # for analysis and debugging purposes.
        # ============================================================================

        # Execution status from result
        # Stored as: result.status
        # @return [String] "success" or "error"
        result status: ->(result, comp) do
          if result.is_a?(Exception) || (result.respond_to?(:failure?) && result.failure?)
            "error"
          else
            "success"
          end
        end

        # Execution duration in milliseconds
        # Stored as: result.duration_ms
        # @return [String] Duration in milliseconds or empty
        result "duration.ms": ->(result, comp) do
          if comp.respond_to?(:execution_duration_ms)
            comp.execution_duration_ms.to_s
          end
        end

        # Result size in bytes (for large result handling)
        # Stored as: result.size_bytes
        # @return [String] Size in bytes or empty
        result "size.bytes": ->(result, comp) do
          if result.is_a?(String)
            result.bytesize.to_s
          elsif result.respond_to?(:to_s)
            result.to_s.bytesize.to_s
          end
        end

        # Error type if execution failed
        # Stored as: result.error_type
        # @return [String] Error class name or empty
        result "error.type": ->(result, comp) do
          if result.is_a?(Exception)
            result.class.name
          elsif result.respond_to?(:error) && result.error
            result.error.class.name
          end
        end

        # Error message if execution failed
        # Stored as: result.error_message
        # @return [String] Error message or empty
        result "error.message": ->(result, comp) do
          if result.is_a?(Exception)
            result.message
          elsif result.respond_to?(:error) && result.error
            result.error.message
          end
        end

        # Truncated execution result for quick overview (first 100 characters)
        # @return [String] Truncated string representation of the tool result
        result execution_result: ->(result, comp) do
          if result.is_a?(Exception)
            "ERROR: #{result.message}"
          else
            result.to_s[0..100]
          end
        end

        # Complete tool result for detailed analysis and UI display
        # The safe_value method from BaseCollector handles complex object serialization
        # @return [Object] Full tool result with automatic serialization safety
        result tool_result: ->(result, comp) do
          if result.is_a?(Exception)
            { error: result.message, class: result.class.name }
          else
            result
          end
        end
      end
    end
  end
end
