# frozen_string_literal: true

require "monitor"

module RAAF
  # Thread-safe token bucket implementation for rate limiting
  class TokenBucket
    attr_reader :rate, :burst, :timeout

    def initialize(rate:, burst:, timeout: 30)
      @rate = rate.to_f # Requests per minute
      @burst = burst.to_i # Maximum burst capacity
      @timeout = timeout.to_f # Maximum wait time in seconds
      
      @tokens = @burst.to_f
      @last_refill = Time.now
      @lock = Monitor.new
    end

    # Attempt to acquire a token, waiting up to timeout seconds
    # Returns true if token acquired, false if timeout exceeded
    def acquire
      deadline = Time.now + @timeout
      
      loop do
        if try_acquire
          return true
        end
        
        remaining = deadline - Time.now
        if remaining <= 0
          return false
        end
        
        # Wait for a short period before trying again
        sleep [0.01, remaining].min
      end
    end

    private

    def try_acquire
      @lock.synchronize do
        refill_tokens
        
        if @tokens >= 1.0
          @tokens -= 1.0
          return true
        end
        
        false
      end
    end

    def refill_tokens
      now = Time.now
      elapsed = now - @last_refill
      
      # Calculate tokens to add based on elapsed time
      tokens_to_add = elapsed * (@rate / 60.0) # Convert RPM to per-second rate
      
      if tokens_to_add > 0
        @tokens = [@tokens + tokens_to_add, @burst.to_f].min
        @last_refill = now
      end
    end
  end

  # Throttler module that can be included in classes to add rate limiting
  module Throttler
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      def inherited(subclass)
        super
        subclass.instance_variable_set(:@throttle_config, @throttle_config&.dup)
      end
    end

    def initialize_throttle_config
      @throttle_enabled = false
      @throttle_buckets = {}
      @throttle_config = {
        rpm: nil,
        burst: nil,
        timeout: 30
      }
      @throttle_stats = {
        requests_throttled: 0,
        total_wait_time: 0.0,
        timeout_failures: 0
      }
      @throttle_stats_lock = Mutex.new
    end

    # Configure throttling for this instance
    # @param rpm [Integer] Requests per minute limit
    # @param burst [Integer] Burst capacity (defaults to rpm/10)
    # @param timeout [Float] Maximum wait time in seconds
    # @param enabled [Boolean] Enable/disable throttling
    # @return [self]
    def configure_throttle(rpm: nil, burst: nil, timeout: nil, enabled: nil)
      initialize_throttle_config unless defined?(@throttle_config)
      
      @throttle_config[:rpm] = rpm if rpm
      @throttle_config[:burst] = burst || (rpm ? rpm / 10 : nil) if rpm || burst
      @throttle_config[:timeout] = timeout if timeout
      @throttle_enabled = enabled unless enabled.nil?
      
      # Enable throttling if RPM is configured
      @throttle_enabled = true if rpm && enabled.nil?
      
      self
    end

    # Get current throttle statistics
    # @return [Hash] Statistics hash with counts and timings
    def throttle_stats
      @throttle_stats_lock.synchronize { @throttle_stats.dup }
    end

    # Reset throttle statistics
    def reset_throttle_stats
      @throttle_stats_lock.synchronize do
        @throttle_stats = {
          requests_throttled: 0,
          total_wait_time: 0.0,
          timeout_failures: 0
        }
      end
    end

    protected

    # Wrap a block with throttling
    # @param method_name [Symbol] Name of the method being throttled (for bucket isolation)
    # @yield Block to execute after acquiring throttle token
    # @return Result of the block
    # @raise [ThrottleTimeoutError] If token cannot be acquired within timeout
    def with_throttle(method_name = :default)
      initialize_throttle_config unless defined?(@throttle_config)
      
      # Skip throttling if not enabled or not configured
      return yield unless @throttle_enabled && @throttle_config[:rpm]
      
      bucket = get_or_create_bucket(method_name)
      start_time = Time.now
      
      unless bucket.acquire
        record_throttle_timeout
        raise ThrottleTimeoutError, 
              "Throttle timeout exceeded (#{@throttle_config[:timeout]}s) for #{self.class.name}##{method_name}"
      end
      
      wait_time = Time.now - start_time
      record_throttle_wait(wait_time) if wait_time > 0.001 # Only record significant waits
      
      yield
    end

    private

    def get_or_create_bucket(method_name)
      @throttle_buckets[method_name] ||= TokenBucket.new(
        rate: @throttle_config[:rpm],
        burst: @throttle_config[:burst] || @throttle_config[:rpm] / 10,
        timeout: @throttle_config[:timeout]
      )
    end

    def record_throttle_wait(wait_time)
      @throttle_stats_lock.synchronize do
        @throttle_stats[:requests_throttled] += 1
        @throttle_stats[:total_wait_time] += wait_time
      end
    end

    def record_throttle_timeout
      @throttle_stats_lock.synchronize do
        @throttle_stats[:timeout_failures] += 1
      end
    end
  end

  # Error raised when throttle timeout is exceeded
  class ThrottleTimeoutError < StandardError; end
end
