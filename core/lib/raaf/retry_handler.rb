# frozen_string_literal: true

module RAAF
  ##
  # RetryHandler provides intelligent retry logic with AI-specific error classification
  # and comprehensive statistics tracking.
  #
  # This module consolidates retry logic from ModelInterface and AsyncRunner, adding
  # smart error classification for AI-specific failure modes like rate limits,
  # context size errors, and model overload.
  #
  # @example Include in a class
  #   class MyProvider
  #     include RAAF::RetryHandler
  #
  #     def call_api
  #       with_retry(:api_call) do
  #         # API call here
  #       end
  #     end
  #   end
  #
  module RetryHandler
    include Logger

    # AI-specific error classification patterns
    ERROR_PATTERNS = {
      rate_limit: [
        /rate limit/i, /too many requests/i, /quota exceeded/i,
        /throttl/i, /429/
      ],
      timeout: [
        /timeout/i, /timed out/i, /request timeout/i,
        /read timeout/i, /connection timeout/i
      ],
      context_too_large: [
        /context.*too large/i, /maximum context length/i,
        /context size.*exceed/i, /token limit/i,
        /input.*too long/i
      ],
      model_overloaded: [
        /model.*overloaded/i, /service unavailable/i,
        /temporarily unavailable/i, /503/, /502/,
        /gateway/i
      ],
      network_error: [
        /network/i, /connection/i, /dns/i, /socket/i,
        /unreachable/i, /connection refused/i
      ],
      authentication_error: [
        /unauthorized/i, /authentication/i, /401/,
        /invalid.*key/i, /forbidden/i, /403/
      ]
    }.freeze

    # Retry configuration constants
    DEFAULT_MAX_ATTEMPTS = 5
    DEFAULT_BASE_DELAY = 1.0 # seconds
    DEFAULT_MAX_DELAY = 60.0 # seconds
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

    def self.included(base)
      base.class_eval do
        attr_accessor :retry_config
      end
    end

    ##
    # Initialize retry configuration
    #
    def initialize_retry_config
      @retry_config = default_retry_config
      @retry_stats = {
        total_attempts: 0,
        successful_retries: 0,
        failed_operations: 0,
        by_error_type: Hash.new(0)
      }
      @retry_stats_mutex = Mutex.new
    end

    ##
    # Execute a block with retry logic
    #
    # @param method_name [Symbol, String] Name of the method being retried (for logging)
    # @yield Block to execute with retry logic
    # @return Result of the yielded block
    #
    # @example
    #   with_retry(:api_call) do
    #     perform_api_call
    #   end
    #
    def with_retry(method_name = nil)
      @retry_config ||= default_retry_config
      @retry_stats ||= initialize_retry_stats
      @retry_stats_mutex ||= Mutex.new

      attempts = 0

      loop do
        attempts += 1

        begin
          result = yield

          # Record success if this was a retry
          if attempts > 1
            record_retry_success
          end

          return result

        rescue *@retry_config[:exceptions] => e
          error_type = classify_error(e)
          record_retry_attempt(error_type)

          # Don't retry authentication errors
          raise if error_type == :authentication_error

          handle_retry_attempt(method_name, attempts, e, error_type)

        rescue StandardError => e
          # Check if this is a retryable error pattern
          error_type = classify_error(e)

          unless retryable_error?(e, error_type)
            # Non-retryable error, record failure and re-raise
            record_retry_failure
            raise
          end

          record_retry_attempt(error_type)

          # Don't retry authentication errors
          raise if error_type == :authentication_error

          handle_retry_attempt(method_name, attempts, e, error_type)
        end
      end
    end

    ##
    # Configure retry behavior
    #
    # @param max_attempts [Integer] Maximum retry attempts
    # @param base_delay [Float] Base delay between retries
    # @param max_delay [Float] Maximum delay between retries
    # @param multiplier [Float] Backoff multiplier
    # @param jitter [Float] Jitter percentage (0.0-1.0)
    # @param exceptions [Array<Class>] List of retryable exception classes
    #
    # @example
    #   configure_retry(max_attempts: 3, base_delay: 2.0)
    #
    def configure_retry(max_attempts: nil, base_delay: nil, max_delay: nil,
                       multiplier: nil, jitter: nil, exceptions: nil)
      @retry_config ||= default_retry_config

      @retry_config[:max_attempts] = max_attempts if max_attempts
      @retry_config[:base_delay] = base_delay if base_delay
      @retry_config[:max_delay] = max_delay if max_delay
      @retry_config[:multiplier] = multiplier if multiplier
      @retry_config[:jitter] = jitter if jitter
      @retry_config[:exceptions] = exceptions if exceptions
    end

    ##
    # Get retry statistics
    #
    # @return [Hash] Statistics about retry attempts and failures
    #
    # @example
    #   stats = provider.retry_stats
    #   puts "Failure rate: #{stats[:failure_rate]}"
    #   puts "Rate limit retries: #{stats[:by_error_type][:rate_limit]}"
    #
    def retry_stats
      @retry_stats_mutex.synchronize do
        total_ops = @retry_stats[:total_attempts] + @retry_stats[:successful_retries] + @retry_stats[:failed_operations]
        failure_rate = total_ops > 0 ? @retry_stats[:failed_operations].to_f / total_ops : 0.0

        {
          total_attempts: @retry_stats[:total_attempts],
          successful_retries: @retry_stats[:successful_retries],
          failed_operations: @retry_stats[:failed_operations],
          failure_rate: failure_rate.round(3),
          by_error_type: @retry_stats[:by_error_type].dup
        }
      end
    end

    private

    ##
    # Default retry configuration
    #
    def default_retry_config
      {
        max_attempts: DEFAULT_MAX_ATTEMPTS,
        base_delay: DEFAULT_BASE_DELAY,
        max_delay: DEFAULT_MAX_DELAY,
        multiplier: DEFAULT_MULTIPLIER,
        jitter: DEFAULT_JITTER,
        exceptions: RETRYABLE_EXCEPTIONS
      }
    end

    ##
    # Initialize retry statistics
    #
    def initialize_retry_stats
      {
        total_attempts: 0,
        successful_retries: 0,
        failed_operations: 0,
        by_error_type: Hash.new(0)
      }
    end

    ##
    # Classify error by type
    #
    # @param error [Exception] The error to classify
    # @return [Symbol] Error type classification
    #
    def classify_error(error)
      error_message = error.message.to_s.downcase
      error_class = error.class.name

      ERROR_PATTERNS.each do |error_type, patterns|
        patterns.each do |pattern|
          if pattern.is_a?(Regexp)
            return error_type if error_message.match?(pattern) || error_class.match?(pattern)
          else
            return error_type if error_message.include?(pattern.to_s)
          end
        end
      end

      # Fallback classification based on exception class
      case error
      when SocketError, Errno::ECONNRESET, Errno::ECONNREFUSED, Errno::ETIMEDOUT
        :network_error
      when Timeout::Error, Net::ReadTimeout, Net::WriteTimeout, Net::OpenTimeout
        :timeout
      when Net::HTTPTooManyRequests
        :rate_limit
      when Net::HTTPServiceUnavailable, Net::HTTPGatewayTimeout
        :model_overloaded
      else
        :unknown_error
      end
    end

    ##
    # Check if error should be retried
    #
    # @param error [Exception] The error to check
    # @param error_type [Symbol] Classified error type
    # @return [Boolean] Whether error should be retried
    #
    def retryable_error?(error, error_type)
      # Don't retry authentication errors
      return false if error_type == :authentication_error

      # Check if error message matches retryable patterns
      error_message = error.message.to_s.downcase

      retryable_patterns = [
        /rate limit/i,
        /too many requests/i,
        /service unavailable/i,
        /gateway timeout/i,
        /connection reset/i,
        /timeout/i,
        /temporarily unavailable/i,
        /context.*too large/i,
        /token limit/i
      ]

      retryable_patterns.any? { |pattern| error_message.match?(pattern) }
    end

    ##
    # Handle a retry attempt
    #
    # @param method_name [Symbol, String] Method being retried
    # @param attempts [Integer] Current attempt number
    # @param error [Exception] The error that triggered the retry
    # @param error_type [Symbol] Classified error type
    #
    def handle_retry_attempt(method_name, attempts, error, error_type)
      if attempts >= @retry_config[:max_attempts]
        log_retry_failure(method_name, attempts, error, error_type)
        record_retry_failure
        raise
      end

      delay = calculate_delay(attempts)
      log_retry_attempt(method_name, attempts, error, error_type, delay)
      sleep(delay)
    end

    ##
    # Calculate delay for exponential backoff with jitter
    #
    # @param attempt [Integer] Current attempt number
    # @return [Float] Delay in seconds
    #
    def calculate_delay(attempt)
      # Exponential backoff
      base = @retry_config[:base_delay] * (@retry_config[:multiplier]**(attempt - 1))

      # Cap at max delay
      delay = [base, @retry_config[:max_delay]].min

      # Add jitter (±jitter%)
      jitter_amount = delay * @retry_config[:jitter]
      delay + (rand * 2 * jitter_amount) - jitter_amount
    end

    ##
    # Record retry attempt in statistics
    #
    # @param error_type [Symbol] Type of error that triggered retry
    #
    def record_retry_attempt(error_type)
      @retry_stats_mutex.synchronize do
        @retry_stats[:total_attempts] += 1
        @retry_stats[:by_error_type][error_type] += 1
      end
    end

    ##
    # Record successful retry in statistics
    #
    def record_retry_success
      @retry_stats_mutex.synchronize do
        @retry_stats[:successful_retries] += 1
      end
    end

    ##
    # Record retry failure in statistics
    #
    def record_retry_failure
      @retry_stats_mutex.synchronize do
        @retry_stats[:failed_operations] += 1
      end
    end

    ##
    # Log retry attempt
    #
    # @param method [Symbol, String] Method being retried
    # @param attempt [Integer] Current attempt number
    # @param error [Exception] The error that triggered retry
    # @param error_type [Symbol] Classified error type
    # @param delay [Float] Delay before next attempt
    #
    def log_retry_attempt(method, attempt, error, error_type, delay)
      # Calculate next delay for informational logging (if not at max attempts)
      next_delay = if attempt < @retry_config[:max_attempts]
                     calculate_delay(attempt + 1)
                   end

      log_warn(
        "Retry attempt #{attempt}/#{@retry_config[:max_attempts]} for #{method || "operation"} (error_type: #{error_type})",
        error_class: error.class.name,
        error_message: error.message,
        error_type: error_type,
        current_delay_seconds: delay.round(2),
        next_delay_seconds: next_delay&.round(2),
        backoff_strategy: "exponential with #{(@retry_config[:jitter] * 100).to_i}% jitter",
        base_delay: @retry_config[:base_delay],
        multiplier: @retry_config[:multiplier],
        max_delay: @retry_config[:max_delay]
      )
    end

    ##
    # Log retry failure
    #
    # @param method [Symbol, String] Method that failed
    # @param attempts [Integer] Total number of attempts made
    # @param error [Exception] Final error
    # @param error_type [Symbol] Classified error type
    #
    def log_retry_failure(method, attempts, error, error_type)
      log_error(
        "All #{attempts} retry attempts failed for #{method || "operation"} (error_type: #{error_type})",
        error_class: error.class.name,
        error_message: error.message,
        error_type: error_type,
        total_attempts: attempts
      )
    end
  end
end
