# frozen_string_literal: true

require "logger"

module RubyAIAgentsFactory
  module Models
    # Mixin for adding retry logic to model providers
    #
    # This module provides configurable retry behavior with exponential backoff
    # for handling transient API failures.
    #
    # @example Basic usage
    #   class MyProvider < ModelInterface
    #     include RetryableProvider
    #
    #     def chat_completion(**kwargs)
    #       with_retry { api_call(**kwargs) }
    #     end
    #   end
    #
    # @example Custom configuration
    #   provider.configure_retry(
    #     max_attempts: 5,
    #     base_delay: 2.0,
    #     max_delay: 60.0,
    #     exceptions: [Net::HTTPError, Timeout::Error]
    #   )
    module RetryableProvider
      # Default configuration
      DEFAULT_MAX_ATTEMPTS = 3
      DEFAULT_BASE_DELAY = 1.0 # seconds
      DEFAULT_MAX_DELAY = 30.0 # seconds
      DEFAULT_MULTIPLIER = 2.0
      DEFAULT_JITTER = 0.1 # 10% jitter

      # Common retryable exceptions
      RETRYABLE_EXCEPTIONS = [
        Errno::ECONNRESET,
        Errno::ECONNREFUSED,
        Errno::ETIMEDOUT,
        Net::ReadTimeout,
        Net::WriteTimeout,
        Net::OpenTimeout,
        Net::HTTPTooManyRequests,
        Net::HTTPServiceUnavailable,
        Net::HTTPGatewayTimeout
      ].freeze

      # HTTP status codes that should trigger retry
      RETRYABLE_STATUS_CODES = [408, 429, 500, 502, 503, 504].freeze

      def self.included(base)
        base.extend(ClassMethods)
        base.class_eval do
          attr_accessor :retry_config
        end
      end

      module ClassMethods
        def default_retry_config
          {
            max_attempts: DEFAULT_MAX_ATTEMPTS,
            base_delay: DEFAULT_BASE_DELAY,
            max_delay: DEFAULT_MAX_DELAY,
            multiplier: DEFAULT_MULTIPLIER,
            jitter: DEFAULT_JITTER,
            exceptions: RETRYABLE_EXCEPTIONS.dup,
            status_codes: RETRYABLE_STATUS_CODES.dup,
            logger: ::Logger.new($stdout)
          }
        end
      end

      def initialize(*, **)
        super if defined?(super)
        @retry_config = self.class.default_retry_config
      end

      def configure_retry(**options)
        @retry_config ||= self.class.default_retry_config
        @retry_config.merge!(options)
        self
      end

      # Execute a block with retry logic
      def with_retry(method_name = nil)
        @retry_config ||= self.class.default_retry_config
        attempts = 0
        last_error = nil

        loop do
          attempts += 1

          begin
            result = yield

            # Check for HTTP responses that need retry
            raise RetryableError.new("HTTP #{result.code}", result) if should_retry_response?(result)

            return result
          rescue *@retry_config[:exceptions] => e
            last_error = e

            if attempts >= @retry_config[:max_attempts]
              log_retry_failure(method_name, attempts, e)
              raise
            end

            delay = calculate_delay(attempts)
            log_retry_attempt(method_name, attempts, e, delay)
            sleep(delay)
          rescue StandardError => e
            # Check if this is a wrapped HTTP error we should retry
            raise unless retryable_error?(e)

            last_error = e

            if attempts >= @retry_config[:max_attempts]
              log_retry_failure(method_name, attempts, e)
              raise
            end

            delay = calculate_delay(attempts)
            log_retry_attempt(method_name, attempts, e, delay)
            sleep(delay)

            # Non-retryable error, re-raise immediately
          end
        end
      end

      private

      def calculate_delay(attempt)
        # Exponential backoff with jitter
        base = @retry_config[:base_delay] * (@retry_config[:multiplier]**(attempt - 1))

        # Cap at max delay
        delay = [base, @retry_config[:max_delay]].min

        # Add jitter (±jitter%)
        jitter_amount = delay * @retry_config[:jitter]
        delay + (rand * 2 * jitter_amount) - jitter_amount
      end

      def should_retry_response?(response)
        return false unless response.respond_to?(:code)

        @retry_config[:status_codes].include?(response.code.to_i)
      end

      def retryable_error?(error)
        # Check if error message indicates a retryable condition
        error_message = error.message.to_s.downcase

        retryable_patterns = [
          /rate limit/i,
          /too many requests/i,
          /service unavailable/i,
          /gateway timeout/i,
          /connection reset/i,
          /timeout/i,
          /temporarily unavailable/i
        ]

        retryable_patterns.any? { |pattern| error_message.match?(pattern) }
      end

      def log_retry_attempt(method, attempt, error, delay)
        return unless @retry_config[:logger]

        @retry_config[:logger].warn(
          "[RetryableProvider] Attempt #{attempt}/#{@retry_config[:max_attempts]} " \
          "for #{method || "operation"} failed: #{error.class} - #{error.message}. " \
          "Retrying in #{delay.round(2)}s..."
        )
      end

      def log_retry_failure(method, attempts, error)
        return unless @retry_config[:logger]

        @retry_config[:logger].error(
          "[RetryableProvider] All #{attempts} attempts failed " \
          "for #{method || "operation"}: #{error.class} - #{error.message}"
        )
      end

      # Custom error class for retryable HTTP responses
      class RetryableError < StandardError
        attr_reader :response

        def initialize(message, response = nil)
          super(message)
          @response = response
        end
      end
    end

    # Convenience wrapper for adding retry to any provider
    class RetryableProviderWrapper
      include RetryableProvider

      def initialize(provider, **retry_options)
        @provider = provider
        @retry_config = self.class.default_retry_config.merge(retry_options)
      end

      def method_missing(method, ...)
        if @provider.respond_to?(method)
          with_retry(method) do
            @provider.send(method, ...)
          end
        else
          super
        end
      end

      def respond_to_missing?(method, include_private = false)
        @provider.respond_to?(method, include_private) || super
      end
    end
  end
end
