# frozen_string_literal: true

module RubyAIAgentsFactory
  module Execution
    ##
    # Template method hooks for executor lifecycle events
    #
    # This module provides the template method pattern hooks that allow
    # subclasses to inject behavior at specific points in the execution
    # lifecycle without modifying the core execution flow.
    #
    # @example Custom executor with hooks
    #   class CustomExecutor < RunExecutor
    #     include ExecutorHooks
    #     
    #     def before_turn(conversation, agent, context, turns)
    #       log_info("Starting turn #{turns + 1} with #{agent.name}")
    #     end
    #     
    #     def after_turn(conversation, agent, context, turns, result)
    #       log_info("Completed turn", tokens: result[:usage][:total_tokens])
    #     end
    #     
    #     def wrap_tool_execution(tool_name, arguments)
    #       start_time = Time.now
    #       result = yield
    #       duration = Time.now - start_time
    #       log_debug_tools("Tool executed", tool: tool_name, duration: duration)
    #       result
    #     end
    #   end
    #
    # @example TracedRunExecutor usage
    #   class TracedRunExecutor < RunExecutor
    #     def before_turn(conversation, agent, context, turns)
    #       @span = tracer.start_span("agent.turn", parent_id: @run_span.span_id)
    #     end
    #     
    #     def after_turn(conversation, agent, context, turns, result)
    #       @span.end_with_metadata(usage: result[:usage])
    #     end
    #   end
    #
    module ExecutorHooks
      ##
      # Hook called before each conversation turn
      #
      # Subclasses can override this to add behavior before each turn,
      # such as starting a trace span or logging.
      #
      # @param conversation [Array<Hash>] Current conversation state
      # @param current_agent [Agent] The active agent
      # @param context_wrapper [RunContextWrapper] Execution context
      # @param turns [Integer] Current turn number
      #
      def before_turn(conversation, current_agent, context_wrapper, turns)
        # Template method - subclasses should override if needed
        # Default implementation does nothing
      end

      ##
      # Hook called after each conversation turn
      #
      # Subclasses can override this to add behavior after each turn,
      # such as ending a trace span or processing results.
      #
      # @param conversation [Array<Hash>] Current conversation state
      # @param current_agent [Agent] The active agent
      # @param context_wrapper [RunContextWrapper] Execution context
      # @param turns [Integer] Current turn number
      # @param result [Hash] Turn result with :message, :usage, :response
      #
      def after_turn(conversation, current_agent, context_wrapper, turns, result)
        # Template method - subclasses should override if needed
        # Default implementation does nothing
      end

      ##
      # Hook called before API calls
      #
      # Subclasses can override this to add behavior before API calls,
      # such as logging request details or starting API timing.
      #
      # @param messages [Array<Hash>] Messages being sent to API
      # @param model [String] Model being used
      # @param params [Hash] Parameters for the API call
      #
      def before_api_call(messages, model, params)
        # Template method - subclasses should override if needed
        # Default implementation does nothing
      end

      ##
      # Hook called after API calls
      #
      # Subclasses can override this to add behavior after API calls,
      # such as logging response details or recording timing.
      #
      # @param response [Hash] API response
      # @param usage [Hash] Token usage data
      #
      def after_api_call(response, usage)
        # Template method - subclasses should override if needed
        # Default implementation does nothing
      end

      ##
      # Wrap tool execution with custom behavior
      #
      # Subclasses can override this to add tracing, logging, or
      # other behavior around tool execution.
      #
      # @param tool_name [String] Name of the tool being executed
      # @param arguments [Hash] Tool arguments
      # @yield The tool execution block
      # @return [Object] The tool execution result
      #
      def wrap_tool_execution(tool_name, arguments, &block)
        # Default implementation just yields
        yield
      end
    end
  end
end