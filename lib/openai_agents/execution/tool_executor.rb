# frozen_string_literal: true

require_relative "../logging"

module OpenAIAgents
  module Execution
    ##
    # Handles tool execution during agent conversations
    #
    # This class encapsulates all tool-related logic including execution,
    # error handling, and result processing.
    #
    class ToolExecutor
      include Logger

      ##
      # Initialize tool executor
      #
      # @param agent [Agent] The agent that owns the tools
      # @param runner [Runner] The runner for callback access
      #
      def initialize(agent, runner)
        @agent = agent
        @runner = runner
      end

      ##
      # Process and execute tool calls
      #
      # @param tool_calls [Array<Hash>] Tool calls from assistant
      # @param conversation [Array<Hash>] Conversation to append results to
      # @param context_wrapper [RunContextWrapper] Execution context
      # @param response [Hash] Full API response
      # @param tool_wrapper [Proc] Optional block to wrap tool execution
      # @return [Boolean] true if execution should continue, false to stop
      #
      def execute_tool_calls(tool_calls, conversation, context_wrapper, response, &tool_wrapper)
        tool_calls.each do |tool_call|
          execute_single_tool_call(tool_call, conversation, context_wrapper, &tool_wrapper)
        end

        # Check if any tool requested stopping
        # This could be enhanced to return more specific control flow instructions
        true
      end

      ##
      # Check if a message contains tool calls
      #
      # @param message [Hash] Assistant message to check
      # @return [Boolean] true if message has tool calls
      #
      def has_tool_calls?(message)
        message["tool_calls"] || message[:tool_calls]
      end

      ##
      # Determine if conversation should continue based on message content
      #
      # @param message [Hash] The last assistant message
      # @return [Boolean] true to continue, false to stop
      #
      def should_continue?(message)
        # Continue if there are tool calls
        return true if has_tool_calls?(message)
        
        # Stop if no content
        return false unless message[:content]
        
        # Stop if content indicates termination
        !message[:content].match?(/\b(STOP|TERMINATE|DONE|FINISHED)\b/i)
      end

      private

      def execute_single_tool_call(tool_call, conversation, context_wrapper, &tool_wrapper)
        function_name = extract_function_name(tool_call)
        arguments_str = extract_arguments(tool_call)
        tool_call_id = extract_tool_call_id(tool_call)

        # Call tool start hook
        @runner.call_hook(:on_tool_start, context_wrapper, function_name)

        begin
          # Parse arguments
          arguments = JSON.parse(arguments_str, symbolize_names: true)

          # Execute the tool with optional wrapper
          result = if tool_wrapper
                     tool_wrapper.call(function_name, arguments) do
                       execute_tool(function_name, arguments, context_wrapper)
                     end
                   else
                     execute_tool(function_name, arguments, context_wrapper)
                   end

          # Add tool result to conversation
          add_tool_result(conversation, result, tool_call_id)

          # Call tool end hook
          @runner.call_hook(:on_tool_end, context_wrapper, function_name, result)

        rescue JSON::ParserError => e
          handle_tool_error(conversation, context_wrapper, function_name, tool_call_id, 
                           "Failed to parse tool arguments: #{e.message}", e, arguments_str)
        rescue StandardError => e
          handle_tool_error(conversation, context_wrapper, function_name, tool_call_id,
                           "Tool execution failed: #{e.message}", e)
        end
      end

      def extract_function_name(tool_call)
        tool_call.dig("function", "name") || tool_call[:function][:name]
      end

      def extract_arguments(tool_call)
        tool_call.dig("function", "arguments") || tool_call[:function][:arguments]
      end

      def extract_tool_call_id(tool_call)
        tool_call["id"] || tool_call[:id]
      end

      def execute_tool(function_name, arguments, context_wrapper)
        @runner.execute_tool(function_name, arguments, @agent, context_wrapper)
      end

      def add_tool_result(conversation, result, tool_call_id)
        conversation << {
          role: "tool",
          content: result.to_s,
          tool_call_id: tool_call_id
        }
      end

      def handle_tool_error(conversation, context_wrapper, function_name, tool_call_id, error_msg, error, extra_context = nil)
        log_error(error_msg, tool: function_name, error_class: error.class.name, extra: extra_context)
        
        conversation << {
          role: "tool",
          content: error_msg,
          tool_call_id: tool_call_id
        }
        
        @runner.call_hook(:on_tool_error, context_wrapper, function_name, error)
      end
    end
  end
end