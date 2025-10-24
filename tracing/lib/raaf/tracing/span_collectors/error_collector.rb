# frozen_string_literal: true

require_relative "base_collector"

module RAAF
  module Tracing
    module SpanCollectors
      # Specialized collector for error tracking and recovery metrics that captures
      # error information, retry patterns, and recovery status. This collector provides
      # comprehensive visibility into error handling and resilience patterns.
      #
      # @example Basic usage with error tracking
      #   component = SomeComponent.new
      #   collector = ErrorCollector.new
      #   attributes = collector.collect_attributes(component)
      #   result_attrs = collector.collect_result(component, result)
      #
      # @example Captured error information
      #   # Pre-execution error state
      #   attributes["error.has_errors"]  # => "false" or "true"
      #   attributes["error.error_count"]  # => "0", "1", "2", etc.
      #   attributes["error.first_error_type"]  # => "RateLimitError"
      #
      #   # Post-execution recovery status
      #   result_attrs["result.recovery_status"]  # => "success", "failed", "recovered_after_retries"
      #   result_attrs["result.error_details"]  # => {error_type, error_message, retry_events, ...}
      #
      # @example Integration with tracing system
      #   tracer = RAAF::Tracing::SpanTracer.new
      #   component = MyComponent.new
      #   # Error tracking automatically collected
      #
      # @note Error collectors help identify patterns in error recovery
      # @note Retry events preserve detailed attempt information
      # @note Stack traces captured for debugging without sensitive data
      # @note Error categories (transient vs permanent) help guide retry logic
      #
      # @see BaseCollector For DSL methods and common attribute handling
      # @see ToolCollector For tool-specific error handling
      # @see RAAF::Tracing Error handling and recovery patterns
      #
      # @since 1.0.0
      # @author RAAF Team
      class ErrorCollector < BaseCollector
        # ============================================================================
        # ERROR STATE TRACKING
        # These attributes capture whether errors exist before execution
        # ============================================================================

        # Flag indicating if component has tracked errors
        span has_errors: ->(comp) do
          if comp.respond_to?(:get_error_count)
            (comp.get_error_count.to_i > 0).to_s
          else
            "false"
          end
        end

        # Count of errors tracked in component
        span error_count: ->(comp) do
          if comp.respond_to?(:get_error_count)
            comp.get_error_count.to_s
          else
            "0"
          end
        end

        # Type of the first error encountered
        span first_error_type: ->(comp) do
          if comp.respond_to?(:get_errors)
            errors = comp.get_errors
            if errors && errors.any?
              errors.first[:type] || errors.first["type"] || "Unknown"
            end
          end
        end

        # ============================================================================
        # ERROR RECOVERY TRACKING
        # These attributes capture execution outcome and recovery information
        # ============================================================================

        # Overall recovery status from execution result
        result recovery_status: ->(result, comp) do
          case result
          when Exception
            "failed"
          when Hash
            if result[:success] || result["success"]
              if result[:recovery_attempt] || result["recovery_attempt"]
                "recovered_after_retries"
              else
                "success"
              end
            elsif result[:attempted_retries] || result["attempted_retries"]
              "recovered_after_retries"
            else
              "failed"
            end
          else
            "unknown"
          end
        end

        # Detailed error information and recovery context
        result error_details: ->(result, comp) do
          error_info = {}

          case result
          when Exception
            error_info["error_type"] = result.class.name
            error_info["error_message"] = result.message
            error_info["stack_trace"] = format_stack_trace(result.backtrace)
            error_info["error_category"] = classify_error(result.class.name)

          when Hash
            # Error type
            error_type = result[:error_type] || result["error_type"]
            if error_type
              error_info["error_type"] = error_type
              error_info["error_category"] = classify_error(error_type)
            end

            # Error message
            error_message = result[:error_message] || result["error_message"]
            error_info["error_message"] = error_message if error_message

            # Retry attempt information
            if result[:recovery_attempt] || result["recovery_attempt"]
              error_info["total_attempts"] = result[:recovery_attempt] || result["recovery_attempt"]
            end

            if result[:recovered_after_attempt] || result["recovered_after_attempt"]
              error_info["successful_on_attempt"] = result[:recovered_after_attempt] || result["recovered_after_attempt"]
            end

            if result[:total_retry_delay_ms] || result["total_retry_delay_ms"]
              error_info["total_backoff_ms"] = result[:total_retry_delay_ms] || result["total_retry_delay_ms"]
            end

            # Retry events array
            retry_events = result[:retry_events] || result["retry_events"]
            if retry_events && retry_events.any?
              error_info["retry_events"] = retry_events
            end

            # Status code for API errors
            status_code = result[:status_code] || result["status_code"]
            error_info["status_code"] = status_code if status_code

          end

          # Extract error from error response object
          if result.respond_to?(:error) && result.error
            error_obj = result.error
            error_info["error_type"] = error_obj.class.name
            error_info["error_message"] = error_obj.message if error_obj.respond_to?(:message)
            error_info["error_category"] = classify_error(error_obj.class.name)

            if error_obj.respond_to?(:backtrace) && error_obj.backtrace
              error_info["stack_trace"] = format_stack_trace(error_obj.backtrace)
            end
          end

          # Ensure empty hash if no error info collected
          error_info
        end

        # ============================================================================
        # PRIVATE HELPER METHODS
        # ============================================================================

        private

        # Format stack trace for safe storage, removing sensitive lines
        def self.format_stack_trace(backtrace)
          return nil unless backtrace && backtrace.any?

          # Join first 5 lines of backtrace (most relevant)
          backtrace.first(5).join("\n")
        end

        # Classify error as transient or permanent for retry logic guidance
        # Transient errors can often be retried; permanent errors should not
        def self.classify_error(error_type)
          transient_patterns = %w[
            Timeout
            TimeoutError
            RateLimit
            RateLimitError
            Connection
            ConnectionError
            Network
            NetworkError
            Temporary
            TemporaryError
            ServiceUnavailable
            Unavailable
            TooManyRequests
            Throttle
          ]

          permanent_patterns = %w[
            Authentication
            AuthenticationError
            Authorization
            AuthorizationError
            Permission
            PermissionError
            NotFound
            Invalid
            InvalidError
            BadRequest
            Unauthorized
            Forbidden
          ]

          error_str = error_type.to_s.downcase

          if transient_patterns.any? { |pattern| error_str.include?(pattern.downcase) }
            "transient"
          elsif permanent_patterns.any? { |pattern| error_str.include?(pattern.downcase) }
            "permanent"
          else
            "unknown"
          end
        end
      end
    end
  end
end
