# frozen_string_literal: true

module RAAF
  module DSL
    # ToolLogging provides comprehensive logging for tool executions
    #
    # This module is included in RAAF::DSL::Agent to add logging capabilities
    # to tool executions. It handles:
    # - Tool execution start logging
    # - Tool execution completion logging with duration
    # - Tool execution error logging with stack traces
    # - Argument formatting with truncation
    #
    # @example Basic usage
    #   class MyAgent < RAAF::DSL::Agent
    #     tool_execution do
    #       enable_logging true
    #       log_arguments true
    #       truncate_logs 100
    #     end
    #   end
    #
    module ToolLogging
      # Log the start of tool execution
      #
      # @param tool [Object] The tool being executed
      # @param arguments [Hash] Arguments passed to the tool
      def log_tool_start(tool, arguments)
        tool_name = extract_tool_name(tool)

        RAAF.logger.debug("[TOOL EXECUTION] Starting #{tool_name}")

        if log_arguments?
          args_str = format_arguments(arguments)
          RAAF.logger.debug("[TOOL EXECUTION] Arguments: #{args_str}")
        end
      end

      # Log the completion of tool execution
      #
      # @param tool [Object] The tool that was executed
      # @param result [Hash] The tool execution result
      # @param duration_ms [Float] Execution duration in milliseconds
      def log_tool_end(tool, result, duration_ms)
        tool_name = extract_tool_name(tool)
        formatted_duration = format_duration(duration_ms)

        if result.is_a?(Hash) && result[:success] == false
          RAAF.logger.debug("[TOOL EXECUTION] Failed #{tool_name} (#{formatted_duration}ms): #{result[:error]}")
        else
          RAAF.logger.debug("[TOOL EXECUTION] Completed #{tool_name} (#{formatted_duration}ms)")
        end
      end

      # Log tool execution errors
      #
      # @param tool [Object] The tool that raised an error
      # @param error [StandardError] The error that occurred
      def log_tool_error(tool, error)
        tool_name = extract_tool_name(tool)

        RAAF.logger.error("[TOOL EXECUTION] Error in #{tool_name}: #{error.message}")
        RAAF.logger.error("[TOOL EXECUTION] Stack trace: #{format_stack_trace(error)}")
      end

      private

      # Format arguments for logging with truncation
      #
      # @param arguments [Hash] Arguments to format
      # @return [String] Formatted arguments string
      def format_arguments(arguments)
        truncate_length = truncate_logs_at || 100

        arguments.map do |key, value|
          value_str = value.to_s
          value_str = truncate_string(value_str, truncate_length) if value_str.length > truncate_length
          "#{key}: #{value_str}"
        end.join(", ")
      end

      # Truncate a string with ellipsis
      #
      # @param str [String] String to truncate
      # @param length [Integer] Maximum length
      # @return [String] Truncated string
      def truncate_string(str, length)
        return str if str.length <= length
        "#{str[0...length]}..."
      end

      # Format duration to 2 decimal places
      #
      # @param duration_ms [Float] Duration in milliseconds
      # @return [String] Formatted duration
      def format_duration(duration_ms)
        duration_ms.round(2)
      end

      # Format stack trace (first 5 lines)
      #
      # @param error [StandardError] The error with backtrace
      # @return [String] Formatted stack trace
      def format_stack_trace(error)
        return "No backtrace available" unless error.backtrace

        error.backtrace.first(5).join("\n")
      end
    end
  end
end
