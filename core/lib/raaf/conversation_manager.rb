# frozen_string_literal: true

require_relative "logging"

module RAAF

  module Execution

    ##
    # Manages conversation flow and state during agent execution
    #
    # This class encapsulates the logic for managing multi-turn conversations,
    # tracking usage statistics, and coordinating the overall execution flow.
    #
    class ConversationManager

      include Logger

      attr_reader :config, :accumulated_usage

      ##
      # Initialize conversation manager
      #
      # @param config [RunConfig] Execution configuration
      #
      def initialize(config)
        @config = config
        @accumulated_usage = initialize_usage_tracking
      end

      ##
      # Execute a multi-turn conversation
      #
      # @param messages [Array<Hash>] Initial conversation messages
      # @param agent [Agent] The agent to execute
      # @param executor [RunExecutor] The executor instance for callbacks
      # @yield [turn_data] Yields turn data for each conversation turn
      # @return [Hash] Final conversation state
      #
      def execute_conversation(messages, agent, executor)
        conversation = messages.dup
        current_agent = agent
        turns = 0

        max_turns = config.max_turns || current_agent.max_turns
        context_wrapper = create_context_wrapper(conversation)

        while turns < max_turns
          # Check if execution should stop
          check_execution_stop(conversation, executor)

          # Execute single turn
          turn_data = {
            conversation: conversation,
            current_agent: current_agent,
            context_wrapper: context_wrapper,
            turns: turns
          }

          result = yield(turn_data)

          # Process turn result
          process_turn_result(result, conversation, current_agent)

          # Check for handoff
          handoff_result = result[:handoff_result]
          if handoff_result && handoff_result[:handoff_occurred]
            current_agent = handoff_result[:new_agent]
            turns = 0 # Reset turns for new agent
            next
          end

          # Check if we should continue
          break unless result[:should_continue]

          turns += 1
        end

        # Check if we exceeded max turns
        handle_max_turns_exceeded(conversation, max_turns) if turns >= max_turns

        {
          conversation: conversation,
          usage: accumulated_usage,
          context_wrapper: context_wrapper
        }
      end

      ##
      # Accumulate usage statistics
      #
      # @param usage [Hash, nil] Usage data to accumulate
      #
      def accumulate_usage(usage)
        return unless usage

        accumulated_usage[:input_tokens] += usage[:input_tokens] || usage[:prompt_tokens] || 0
        accumulated_usage[:output_tokens] += usage[:output_tokens] || usage[:completion_tokens] || 0
        accumulated_usage[:total_tokens] += usage[:total_tokens] || 0
      end

      private

      ##
      # Initialize usage tracking hash
      #
      # Creates the initial structure for accumulating token usage
      # across multiple conversation turns.
      #
      # @return [Hash] Initial usage tracking structure
      # @private
      #
      def initialize_usage_tracking
        {
          input_tokens: 0,
          output_tokens: 0,
          total_tokens: 0
        }
      end

      ##
      # Create a context wrapper for the conversation
      #
      # Builds a RunContextWrapper containing the conversation state
      # and metadata for use throughout the execution.
      #
      # @param conversation [Array<Hash>] Current conversation messages
      # @return [RunContextWrapper] Wrapped execution context
      # @private
      #
      def create_context_wrapper(conversation)
        context = RunContext.new(
          messages: conversation,
          metadata: config.metadata || {},
          trace_id: config.trace_id,
          group_id: config.group_id
        )
        RunContextWrapper.new(context)
      end

      ##
      # Check if execution should be stopped
      #
      # Checks the runner's stop flag and handles graceful shutdown
      # if execution has been requested to stop.
      #
      # @param conversation [Array<Hash>] Current conversation
      # @param executor [RunExecutor] Executor instance
      # @raise [ExecutionStoppedError] If execution should stop
      # @private
      #
      def check_execution_stop(conversation, executor)
        return unless executor.runner.should_stop?

        conversation << { role: "assistant", content: "Execution stopped by user request." }
        raise ExecutionStoppedError, "Execution stopped by user request"
      end

      ##
      # Process the result of a conversation turn
      #
      # Extracts the message and usage data from a turn result,
      # accumulates usage statistics, and adds the message to
      # the conversation history.
      #
      # @param result [Hash] Turn execution result
      # @param conversation [Array<Hash>] Current conversation
      # @param current_agent [Agent] The agent that produced the result
      # @private
      #
      def process_turn_result(result, conversation, _current_agent)
        message = result[:message]
        usage = result[:usage]

        # Accumulate usage
        accumulate_usage(usage) if usage

        # Add message to conversation
        conversation << message if message
      end

      ##
      # Handle exceeding maximum turn limit
      #
      # Adds an error message to the conversation and raises an exception
      # when the maximum number of turns has been exceeded.
      #
      # @param conversation [Array<Hash>] Current conversation
      # @param max_turns [Integer] Maximum allowed turns
      # @raise [MaxTurnsError] Always raised to indicate limit exceeded
      # @private
      #
      def handle_max_turns_exceeded(conversation, max_turns)
        error_msg = "Maximum turns (#{max_turns}) exceeded"
        conversation << { role: "assistant", content: error_msg }
        raise MaxTurnsError, error_msg
      end

    end

  end

end
