# frozen_string_literal: true

module RAAF
  module Continuation
    # Logging utilities for continuation operations
    #
    # Provides standardized logging for continuation attempts, completions,
    # and finish reasons with consistent formatting and emoji indicators.
    #
    # @example Log a continuation attempt
    #   RAAF::Continuation::Logging.log_continuation_start(1, :csv)
    #   # => "🔄 Continuation attempt 1 (format: csv)"
    #
    # @example Log completion
    #   RAAF::Continuation::Logging.log_continuation_complete(3, 4500)
    #   # => "✅ Continuation complete after 3 attempts (total tokens: 4500)"
    #
    # @example Log finish reason
    #   RAAF::Continuation::Logging.log_finish_reason("content_filter")
    #   # => "⚠️ Response filtered by content policy"
    class Logging
      # Log the start of a continuation attempt
      #
      # @param attempt [Integer] The attempt number (1-indexed)
      # @param format [Symbol] The output format (:csv, :markdown, :json, :auto)
      #
      # @example
      #   Logging.log_continuation_start(1, :csv)
      #   # => Logs: "🔄 Continuation attempt 1 (format: csv)"
      #
      def self.log_continuation_start(attempt, format)
        Rails.logger.info "🔄 Continuation attempt #{attempt} (format: #{format})"
      rescue StandardError
        # Graceful handling if Rails logger is not available
        puts "🔄 Continuation attempt #{attempt} (format: #{format})"
      end

      # Log completion of continuation process
      #
      # @param count [Integer] Number of continuation attempts performed
      # @param token_count [Integer] Total tokens consumed in continuation process
      #
      # @example
      #   Logging.log_continuation_complete(3, 4500)
      #   # => Logs: "✅ Continuation complete after 3 attempts (total tokens: 4500)"
      #
      def self.log_continuation_complete(count, token_count)
        Rails.logger.info "✅ Continuation complete after #{count} attempts (total tokens: #{token_count})"
      rescue StandardError
        # Graceful handling if Rails logger is not available
        puts "✅ Continuation complete after #{count} attempts (total tokens: #{token_count})"
      end

      # Log the finish reason from API response
      #
      # Maps finish_reason codes to human-readable messages with appropriate emoji indicators.
      # Common finish reasons: "stop", "length", "content_filter", "tool_calls", "error"
      #
      # @param reason [String] The finish_reason from the API response
      #
      # @example Handle various finish reasons
      #   Logging.log_finish_reason("stop")             # => "✅ Response completed normally"
      #   Logging.log_finish_reason("content_filter")   # => "⚠️ Response filtered by content policy"
      #   Logging.log_finish_reason("incomplete")       # => "⚠️ Response incomplete"
      #   Logging.log_finish_reason("error")            # => "❌ Response error"
      #
      def self.log_finish_reason(reason)
        message = case reason
                  when "stop"
                    "✅ Response completed normally"
                  when "length"
                    "⚠️ Response truncated due to length limit"
                  when "content_filter"
                    "⚠️ Response filtered by content policy"
                  when "tool_calls"
                    "ℹ️ Response includes tool calls"
                  when "incomplete"
                    "⚠️ Response incomplete"
                  when "error"
                    "❌ Response error"
                  else
                    "ℹ️ Finish reason: #{reason}"
                  end

        Rails.logger.info(message)
      rescue StandardError
        # Graceful handling if Rails logger is not available
        puts message
      end

      # Log continuation warning
      #
      # @param message [String] The warning message
      #
      # @example
      #   Logging.log_warning("Too many continuation attempts")
      #   # => Logs: "⚠️ Too many continuation attempts"
      #
      def self.log_warning(message)
        Rails.logger.warn "⚠️ #{message}"
      rescue StandardError
        # Graceful handling if Rails logger is not available
        puts "⚠️ #{message}"
      end

      # Log continuation error
      #
      # @param message [String] The error message
      # @param error [StandardError] The error object (optional)
      #
      # @example
      #   Logging.log_error("Continuation failed", error)
      #   # => Logs: "❌ Continuation failed: [error message]"
      #
      def self.log_error(message, error = nil)
        full_message = error ? "#{message}: #{error.message}" : message
        Rails.logger.error "❌ #{full_message}"
      rescue StandardError
        # Graceful handling if Rails logger is not available
        puts "❌ #{full_message}"
      end

      # Log continuation metadata
      #
      # @param metadata [Hash] Metadata about the continuation attempt
      #
      # @example
      #   Logging.log_metadata(
      #     attempt: 1,
      #     format: :csv,
      #     tokens: 1250,
      #     duration_ms: 45
      #   )
      #
      def self.log_metadata(metadata)
        formatted = metadata.map { |k, v| "#{k}: #{v}" }.join(", ")
        Rails.logger.debug { "📊 Continuation metadata: #{formatted}" }
      rescue StandardError
        # Graceful handling if Rails logger is not available
        puts "📊 Continuation metadata: #{formatted}"
      end
    end
  end
end
