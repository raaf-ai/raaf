# frozen_string_literal: true

require "concurrent"

module RAAF
  # RateLimiter - Shared rate limiting across all RAAF agents and providers
  #
  # Prevents concurrent agents from exceeding provider rate limits by implementing
  # a centralized token bucket algorithm with configurable storage backends.
  #
  # Features:
  # - Thread-safe token bucket implementation
  # - Per-provider rate limit configuration
  # - Multiple storage backends (Memory, Redis, Rails.cache)
  # - Automatic window reset and jitter
  # - Status monitoring and metrics
  #
  # Usage:
  #   # Basic usage with memory storage
  #   limiter = RAAF::RateLimiter.new(provider: "gemini", requests_per_minute: 15)
  #   limiter.acquire do
  #     # Make AI API call
  #     provider.chat_completion(messages)
  #   end
  #
  #   # With custom storage backend
  #   limiter = RAAF::RateLimiter.new(
  #     provider: "openai",
  #     requests_per_minute: 60,
  #     storage: RAAF::RateLimiter::RedisStorage.new
  #   )
  #
  class RateLimiter
    include RAAF::Logger

    # Provider-specific rate limits (free tier defaults)
    # Users should override these based on their account tiers
    DEFAULT_RATE_LIMITS = {
      "gemini" => { rpm: 15, tokens_per_minute: 1_000_000 },
      "openai" => { rpm: 3, tokens_per_minute: 40_000 },
      "anthropic" => { rpm: 5, tokens_per_minute: 50_000 },
      "perplexity" => { rpm: 50, tokens_per_minute: nil },
      "groq" => { rpm: 30, tokens_per_minute: 20_000 },
      "cohere" => { rpm: 10, tokens_per_minute: 50_000 },
      "together" => { rpm: 60, tokens_per_minute: nil },
      "litellm" => { rpm: 10, tokens_per_minute: nil },
      "moonshot" => { rpm: 30, tokens_per_minute: nil },
      "xai" => { rpm: 20, tokens_per_minute: nil },
      "huggingface" => { rpm: 10, tokens_per_minute: nil }
    }.freeze

    attr_reader :provider, :requests_per_minute, :storage

    # Initialize rate limiter for a provider
    #
    # @param provider [String] Provider name (e.g., "gemini", "openai")
    # @param requests_per_minute [Integer, nil] Custom RPM limit (uses default if nil)
    # @param storage [Storage] Storage backend (defaults to MemoryStorage)
    # @param tokens_per_minute [Integer, nil] Token limit (not yet enforced)
    def initialize(provider:, requests_per_minute: nil, storage: nil, tokens_per_minute: nil)
      @provider = provider.to_s.downcase
      @requests_per_minute = requests_per_minute || DEFAULT_RATE_LIMITS.dig(@provider, :rpm) || 10
      @tokens_per_minute = tokens_per_minute || DEFAULT_RATE_LIMITS.dig(@provider, :tokens_per_minute)
      @storage = storage || MemoryStorage.new
      @cache_key = "raaf_rate_limit:#{@provider}"
    end

    # Acquire a token and execute block with rate limiting
    #
    # @param max_wait_seconds [Integer] Maximum time to wait for token (default: 60)
    # @yield Block to execute after acquiring rate limit token
    # @return Result of the block
    # @raise RuntimeError if max wait time exceeded
    def acquire(max_wait_seconds: 60)
      start_time = Time.now

      loop do
        if try_acquire
          log_debug("✅ [RateLimiter] Acquired token", provider: provider, rpm: @requests_per_minute)
          return yield
        end

        elapsed = Time.now - start_time
        remaining_time = max_wait_seconds - elapsed

        if remaining_time <= 0
          raise "Rate limit acquisition timeout after #{elapsed.round(1)}s for #{provider}"
        end

        wait_time = calculate_wait_time
        # Don't sleep longer than our remaining time budget
        actual_wait = [wait_time, remaining_time].min

        log_warn("⏱️  [RateLimiter] Rate limit reached",
                 provider: provider,
                 current: current_count,
                 limit: @requests_per_minute,
                 wait_seconds: actual_wait.round(2))
        sleep(actual_wait)
      end
    end

    # Check current rate limit status without acquiring
    #
    # @return [Hash] Status information
    def status
      bucket = fetch_bucket
      {
        provider: provider,
        current_requests: bucket[:count],
        limit: @requests_per_minute,
        window_start: bucket[:window_start],
        available: bucket[:count] < @requests_per_minute,
        tokens_per_minute: @tokens_per_minute
      }
    end

    # Reset rate limiter (useful for testing)
    def reset!
      @storage.delete(@cache_key)
    end

    private

    # Try to acquire a token from the bucket
    #
    # @return [Boolean] true if token acquired, false if rate limit reached
    def try_acquire
      bucket = fetch_bucket

      # Check if we're in a new time window
      if bucket[:window_start] < current_window_start
        # Reset bucket for new window
        store_bucket(count: 1, window_start: current_window_start)
        return true
      end

      # Check if we have capacity in current window
      if bucket[:count] < @requests_per_minute
        store_bucket(count: bucket[:count] + 1, window_start: bucket[:window_start])
        return true
      end

      false
    end

    # Fetch current bucket state from storage
    #
    # @return [Hash] Bucket state with :count and :window_start
    def fetch_bucket
      @storage.fetch(@cache_key) do
        { count: 0, window_start: current_window_start }
      end
    end

    # Store bucket state to storage
    def store_bucket(count:, window_start:)
      @storage.write(@cache_key, { count: count, window_start: window_start }, expires_in: 120)
    end

    # Calculate current time window start (minute boundary)
    #
    # @return [Time] Start of current minute window
    def current_window_start
      now = Time.now
      Time.new(now.year, now.month, now.day, now.hour, now.min, 0)
    end

    # Current request count from bucket
    def current_count
      fetch_bucket[:count]
    end

    # Calculate wait time based on current window
    #
    # @return [Float] Seconds to wait before next window
    def calculate_wait_time
      bucket = fetch_bucket
      next_window = bucket[:window_start] + 60 # Next minute
      wait = next_window - Time.now

      # Add small jitter to prevent thundering herd
      [wait + rand(0.1..0.5), 0.1].max
    end

    # Memory-based storage backend (default)
    class MemoryStorage
      def initialize
        @cache = Concurrent::Map.new
      end

      def fetch(key)
        @cache[key] || yield
      end

      def write(key, value, expires_in: nil)
        @cache[key] = value
      end

      def delete(key)
        @cache.delete(key)
      end
    end

    # Redis-based storage backend (for distributed rate limiting)
    class RedisStorage
      def initialize(redis: nil)
        require "redis"
        @redis = redis || Redis.new
      end

      def fetch(key)
        value = @redis.get(key)
        value ? JSON.parse(value, symbolize_names: true) : yield
      end

      def write(key, value, expires_in: nil)
        @redis.set(key, value.to_json)
        @redis.expire(key, expires_in) if expires_in
      end

      def delete(key)
        @redis.del(key)
      end
    end

    # Rails.cache-based storage backend
    class RailsCacheStorage
      def initialize(cache: nil)
        @cache = cache || (defined?(Rails) ? Rails.cache : raise("Rails not available"))
      end

      def fetch(key)
        @cache.fetch(key) { yield }
      end

      def write(key, value, expires_in: nil)
        @cache.write(key, value, expires_in: expires_in)
      end

      def delete(key)
        @cache.delete(key)
      end
    end
  end
end
