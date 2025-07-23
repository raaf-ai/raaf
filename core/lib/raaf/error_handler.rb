# frozen_string_literal: true

require "net/http"
require "timeout"
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
        begin
          yield
        rescue StandardError => e
          # Handle retries for RETRY_ONCE strategy
          if strategy == RecoveryStrategy::RETRY_ONCE && @retry_count < @max_retries
            @retry_count += 1
            log_info("Retrying operation", attempt: @retry_count, **context)
            retry
          end
          
          # Now handle specific error types after retry logic
          case e
          when MaxTurnsError
            handle_max_turns_error(e, context)
          when ExecutionStoppedError
            handle_stopped_execution_error(e, context)
          when JSON::ParserError
            handle_parsing_error(e, context)
          else
            # Check if this is a guardrails error when guardrails gem is loaded
            if defined?(Guardrails)
              case e
              when Guardrails::InputGuardrailTripwireTriggered
                handle_guardrail_error(e, context, :input)
              when Guardrails::OutputGuardrailTripwireTriggered
                handle_guardrail_error(e, context, :output)
              else
                handle_general_error(e, context)
              end
            else
              handle_general_error(e, context)
            end
          end
        ensure
          @retry_count = 0
        end
      end

      ##
      # Handle API-related errors with specific recovery strategies
      #
      # @param context [Hash] Context information
      # @yield Block to execute with API error protection
      # @return [Object] Result or recovery value
      #
      def with_api_error_handling(context = {})
        begin
          yield
        rescue StandardError => e
          # Handle retries for RETRY_ONCE strategy
          if strategy == RecoveryStrategy::RETRY_ONCE && @retry_count < @max_retries
            @retry_count += 1
            log_info("Retrying API operation", attempt: @retry_count, **context)
            retry
          end
          
          # Now handle specific error types
          case e
          when Timeout::Error
            handle_timeout_error(e, context)
          when Net::HTTPError
            handle_http_error(e, context)
          else
            handle_general_error(e, context)
          end
        ensure
          @retry_count = 0
        end
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

        case strategy
        when RecoveryStrategy::LOG_AND_CONTINUE
          { error: :execution_stopped, message: error.message, handled: true }
        when RecoveryStrategy::GRACEFUL_DEGRADATION
          { error: :execution_stopped, message: "Execution was halted", handled: true }
        when RecoveryStrategy::RETRY_ONCE
          # Retries have already been exhausted in main method
          log_error("Max retries exceeded for execution stopped error")
          { error: :execution_stopped, message: "Failed after retries", handled: true }
        else
          # FAIL_FAST and unknown strategies
          raise error
        end
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
        when RecoveryStrategy::LOG_AND_CONTINUE, RecoveryStrategy::GRACEFUL_DEGRADATION
          { error: :parsing_failed, message: "Failed to parse response", handled: true }
        when RecoveryStrategy::RETRY_ONCE
          # Retries have already been exhausted in main method
          log_error("Max retries exceeded for parsing error")
          { error: :parsing_failed, message: "Failed to parse after retries", handled: true }
        else
          # FAIL_FAST and unknown strategies
          raise error
        end
      end

      ##
      # Handle network timeout errors
      #
      # Processes API timeout errors with retry logic and
      # graceful degradation options.
      #
      # @param error [Timeout::Error] The timeout error
      # @param context [Hash] Error context information
      # @return [Hash] Recovery result or re-raises error
      # @private
      #
      def handle_timeout_error(error, context)
        log_error("API request timed out", **context, message: error.message)

        case strategy
        when RecoveryStrategy::RETRY_ONCE
          # Retries have already been exhausted in main method
          { error: :timeout, message: "Request timed out after retries", handled: true }
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
        when RecoveryStrategy::LOG_AND_CONTINUE
          # LOG_AND_CONTINUE only applies to specific errors, not general errors
          raise error
        when RecoveryStrategy::GRACEFUL_DEGRADATION
          { error: :general_error, message: "An unexpected error occurred", handled: true }
        when RecoveryStrategy::RETRY_ONCE
          # Retries have already been exhausted in main method
          log_error("Max retries exceeded for general error")
          raise error
        else
          # FAIL_FAST and unknown strategies
          raise error
        end
      end

    end

  end

end
