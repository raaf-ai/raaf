# frozen_string_literal: true

require_relative "logging"

module RAAF

  module Execution

    ##
    # Centralized error handling with recovery strategies
    #
    # This class provides a unified approach to handling errors during
    # agent execution, with configurable recovery strategies.
    #
    class ErrorHandler

      include Logger

      ##
      # Error recovery strategies
      #
      module RecoveryStrategy

        FAIL_FAST = :fail_fast # Re-raise immediately
        LOG_AND_CONTINUE = :log_and_continue # Log error but continue execution
        RETRY_ONCE = :retry_once # Retry the operation once
        GRACEFUL_DEGRADATION = :graceful_degradation # Continue with reduced functionality

      end

      attr_reader :strategy

      ##
      # Initialize error handler
      #
      # @param strategy [Symbol] Recovery strategy to use
      # @param max_retries [Integer] Maximum number of retries for RETRY_ONCE strategy
      #
      def initialize(strategy: RecoveryStrategy::FAIL_FAST, max_retries: 1)
        @strategy = strategy
        @max_retries = max_retries
        @retry_count = 0
      end

      ##
      # Execute block with error handling
      #
      # @param context [Hash] Context information for error reporting
      # @yield Block to execute with error protection
      # @return [Object] Result of the block or recovery value
      #
      def with_error_handling(context = {})
        yield
      rescue MaxTurnsError => e
        handle_max_turns_error(e, context)
      rescue ExecutionStoppedError => e
        handle_stopped_execution_error(e, context)
      rescue StandardError => e
        # Check if this is a guardrails error when guardrails gem is loaded
        raise unless defined?(Guardrails)

        case e
        when Guardrails::InputGuardrailTripwireTriggered
          handle_guardrail_error(e, context, :input)
        when Guardrails::OutputGuardrailTripwireTriggered
          handle_guardrail_error(e, context, :output)
        else
          raise # Re-raise if not a guardrails error
        end

      # Re-raise if guardrails not available
      rescue JSON::ParserError => e
        handle_parsing_error(e, context)
      rescue StandardError => e
        handle_general_error(e, context)
      ensure
        @retry_count = 0 # Reset retry count after successful execution
      end

      ##
      # Handle API-related errors with specific recovery strategies
      #
      # @param context [Hash] Context information
      # @yield Block to execute with API error protection
      # @return [Object] Result or recovery value
      #
      def with_api_error_handling(context = {})
        yield
      rescue Net::TimeoutError => e
        handle_timeout_error(e, context)
      rescue Net::HTTPError => e
        handle_http_error(e, context)
      rescue StandardError => e
        handle_general_error(e, context)
      end

      ##
      # Handle tool execution errors
      #
      # @param tool_name [String] Name of the tool that failed
      # @param error [StandardError] The error that occurred
      # @param context [Hash] Additional context
      # @return [String] Error message to return as tool result
      #
      def handle_tool_error(tool_name, error, context = {})
        error_context = context.merge(tool: tool_name, error_class: error.class.name)

        case error
        when JSON::ParserError
          log_error("Tool argument parsing failed", **error_context, message: error.message)
          "Error: Invalid tool arguments format"
        when ArgumentError
          log_error("Tool argument error", **error_context, message: error.message)
          "Error: Invalid arguments provided to tool"
        when StandardError
          log_error("Tool execution failed", **error_context, message: error.message)
          "Error: Tool execution failed - #{error.message}"
        end
      end

      private

      ##
      # Handle max turns exceeded errors
      #
      # Applies the configured recovery strategy when the maximum
      # number of conversation turns is exceeded.
      #
      # @param error [MaxTurnsError] The max turns error
      # @param context [Hash] Error context information
      # @return [Hash] Recovery result or re-raises error
      # @private
      #
      def handle_max_turns_error(error, context)
        log_error("Maximum turns exceeded", **context, message: error.message)

        case strategy
        when RecoveryStrategy::LOG_AND_CONTINUE
          log_warn("Continuing despite max turns exceeded")
          { error: :max_turns_exceeded, handled: true }
        when RecoveryStrategy::GRACEFUL_DEGRADATION
          { error: :max_turns_exceeded, message: "Conversation truncated due to length" }
        else
          # RecoveryStrategy::FAIL_FAST and any other strategy
          raise error
        end
      end

      ##
      # Handle execution stopped errors
      #
      # Handles cases where execution is intentionally stopped,
      # typically by user request.
      #
      # @param error [ExecutionStoppedError] The execution stopped error
      # @param context [Hash] Error context information
      # @return [Hash] Recovery result indicating graceful stop
      # @private
      #
      def handle_stopped_execution_error(error, context)
        log_info("Execution stopped by request", **context, message: error.message)

        # Execution stopped errors are usually intentional, so we handle them gracefully
        { error: :execution_stopped, message: error.message, handled: true }
      end

      ##
      # Handle guardrail tripwire errors
      #
      # Processes errors from input or output guardrails being triggered,
      # applying the configured recovery strategy.
      #
      # @param error [Guardrails::GuardrailTripwireTriggered] The guardrail error
      # @param context [Hash] Error context information
      # @param guardrail_type [Symbol] Type of guardrail (:input or :output)
      # @return [Hash] Recovery result or re-raises error
      # @private
      #
      def handle_guardrail_error(error, context, guardrail_type)
        log_warn("#{guardrail_type.capitalize} guardrail triggered",
                 **context, guardrail: error.triggered_by, message: error.message)

        case strategy
        when RecoveryStrategy::LOG_AND_CONTINUE, RecoveryStrategy::GRACEFUL_DEGRADATION
          {
            error: :"#{guardrail_type}_guardrail_triggered",
            guardrail: error.triggered_by,
            message: "Content blocked by #{guardrail_type} guardrail",
            handled: true
          }
        else
          # RecoveryStrategy::FAIL_FAST and any other strategy
          raise error
        end
      end

      ##
      # Handle JSON parsing errors
      #
      # Processes JSON parsing failures with optional retry logic
      # based on the configured recovery strategy.
      #
      # @param error [JSON::ParserError] The parsing error
      # @param context [Hash] Error context information
      # @return [Hash] Recovery result or re-raises error
      # @private
      #
      def handle_parsing_error(error, context)
        log_error("JSON parsing failed", **context, message: error.message)

        case strategy
        when RecoveryStrategy::FAIL_FAST
          raise error
        when RecoveryStrategy::LOG_AND_CONTINUE
          { error: :parsing_failed, message: "Failed to parse response", handled: true }
        when RecoveryStrategy::RETRY_ONCE
          if @retry_count < @max_retries
            @retry_count += 1
            log_info("Retrying after parsing error", attempt: @retry_count)
            raise error # Let the caller retry
          else
            log_error("Max retries exceeded for parsing error")
            { error: :parsing_failed, message: "Failed to parse after retries", handled: true }
          end
        else
          raise error
        end
      end

      ##
      # Handle network timeout errors
      #
      # Processes API timeout errors with retry logic and
      # graceful degradation options.
      #
      # @param error [Net::TimeoutError] The timeout error
      # @param context [Hash] Error context information
      # @return [Hash] Recovery result or re-raises error
      # @private
      #
      def handle_timeout_error(error, context)
        log_error("API request timed out", **context, message: error.message)

        case strategy
        when RecoveryStrategy::RETRY_ONCE
          if @retry_count < @max_retries
            @retry_count += 1
            log_info("Retrying after timeout", attempt: @retry_count)
            raise error # Let the caller retry
          else
            { error: :timeout, message: "Request timed out after retries", handled: true }
          end
        when RecoveryStrategy::GRACEFUL_DEGRADATION
          { error: :timeout, message: "Request timed out, please try again", handled: true }
        else
          raise error
        end
      end

      ##
      # Handle HTTP errors
      #
      # Processes HTTP-related errors from API calls with
      # appropriate recovery strategies.
      #
      # @param error [Net::HTTPError] The HTTP error
      # @param context [Hash] Error context information
      # @return [Hash] Recovery result or re-raises error
      # @private
      #
      def handle_http_error(error, context)
        log_error("HTTP error occurred", **context, message: error.message)

        case strategy
        when RecoveryStrategy::GRACEFUL_DEGRADATION
          { error: :http_error, message: "Service temporarily unavailable", handled: true }
        else
          raise error
        end
      end

      ##
      # Handle general unexpected errors
      #
      # Catches and processes any unexpected errors that don't
      # match specific error types.
      #
      # @param error [StandardError] The unexpected error
      # @param context [Hash] Error context information
      # @return [Hash] Recovery result or re-raises error
      # @private
      #
      def handle_general_error(error, context)
        log_error("Unexpected error occurred",
                  **context, error_class: error.class.name, message: error.message)

        case strategy
        when RecoveryStrategy::FAIL_FAST
          raise error
        when RecoveryStrategy::LOG_AND_CONTINUE
          { error: :general_error, message: error.message, handled: true }
        when RecoveryStrategy::GRACEFUL_DEGRADATION
          { error: :general_error, message: "An unexpected error occurred", handled: true }
        else
          raise error
        end
      end

    end

  end

end
