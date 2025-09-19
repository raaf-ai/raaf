# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::DSL::Resilience::SmartRetry do
  # Test class that includes SmartRetry
  class TestRetryableAgent
    include RAAF::DSL::Resilience::SmartRetry

    def initialize
      @attempt_count = 0
      @failure_mode = nil
    end

    attr_accessor :failure_mode
    attr_reader :attempt_count

    def risky_operation
      @attempt_count += 1

      case @failure_mode
      when :rate_limit
        raise StandardError, "rate limit exceeded"
      when :network
        raise SocketError, "connection failed"
      when :timeout
        raise Timeout::Error, "operation timed out"
      when :success_after_retries
        raise StandardError, "temporary failure" if @attempt_count < 3
        "success"
      else
        "immediate success"
      end
    end

    # Configuration methods for testing
    def self.retry_on(error_type, options = {})
      @retry_config ||= {}
      @retry_config[error_type] = options
    end

    def self._retry_config
      @retry_config || {}
    end

    def self.circuit_breaker(options = {})
      @circuit_breaker_config = options
    end

    def self._circuit_breaker_config
      @circuit_breaker_config || {}
    end
  end

  let(:agent) { TestRetryableAgent.new }

  describe "error classification" do
    it "classifies rate limit errors" do
      agent.failure_mode = :rate_limit
      error_type = agent.classify_error(StandardError.new("rate limit exceeded"))
      expect(error_type).to eq(:rate_limit)
    end

    it "classifies network errors" do
      agent.failure_mode = :network
      error_type = agent.classify_error(SocketError.new("connection failed"))
      expect(error_type).to eq(:network_error)
    end

    it "classifies timeout errors" do
      agent.failure_mode = :timeout
      error_type = agent.classify_error(Timeout::Error.new("operation timed out"))
      expect(error_type).to eq(:timeout)
    end

    it "classifies JSON errors" do
      error_type = agent.classify_error(JSON::ParserError.new("unexpected token"))
      expect(error_type).to eq(:json_error)
    end

    it "classifies unknown errors as general" do
      error_type = agent.classify_error(RuntimeError.new("unknown error"))
      expect(error_type).to eq(:general)
    end

    it "handles error message patterns" do
      # Test various error message patterns
      rate_limit_error = StandardError.new("Too Many Requests")
      expect(agent.classify_error(rate_limit_error)).to eq(:rate_limit)

      network_error = StandardError.new("connection timeout")
      expect(agent.classify_error(network_error)).to eq(:network_error)

      json_error = StandardError.new("Invalid JSON response")
      expect(agent.classify_error(json_error)).to eq(:json_error)
    end
  end

  describe "retry configuration" do
    before do
      TestRetryableAgent.retry_on :rate_limit, max_attempts: 3, backoff: :exponential
      TestRetryableAgent.retry_on :network_error, max_attempts: 2, backoff: :linear
      TestRetryableAgent.retry_on Timeout::Error, max_attempts: 1
    end

    it "stores retry configuration by error type" do
      config = TestRetryableAgent._retry_config
      expect(config[:rate_limit]).to include(max_attempts: 3, backoff: :exponential)
      expect(config[:network_error]).to include(max_attempts: 2, backoff: :linear)
      expect(config[Timeout::Error]).to include(max_attempts: 1)
    end

    it "finds retry configuration for classified errors" do
      agent.failure_mode = :rate_limit
      error = StandardError.new("rate limit exceeded")
      config = agent.find_retry_config_for_error(error)

      expect(config).to include(max_attempts: 3, backoff: :exponential)
    end

    it "returns nil for unconfigured error types" do
      error = RuntimeError.new("unconfigured error")
      config = agent.find_retry_config_for_error(error)
      expect(config).to be_nil
    end

    it "matches error classes directly" do
      timeout_error = Timeout::Error.new("timeout")
      config = agent.find_retry_config_for_error(timeout_error)
      expect(config).to include(max_attempts: 1)
    end
  end

  describe "circuit breaker" do
    before do
      TestRetryableAgent.circuit_breaker threshold: 3, timeout: 60, reset_timeout: 300
    end

    it "stores circuit breaker configuration" do
      config = TestRetryableAgent._circuit_breaker_config
      expect(config).to include(threshold: 3, timeout: 60, reset_timeout: 300)
    end

    it "tracks consecutive failures" do
      agent.failure_mode = :rate_limit

      3.times do
        begin
          agent.execute_with_circuit_breaker { agent.risky_operation }
        rescue StandardError
          # Expected failures
        end
      end

      # Fourth attempt should trigger circuit breaker
      expect { agent.execute_with_circuit_breaker { agent.risky_operation } }
        .to raise_error(RAAF::DSL::Resilience::SmartRetry::CircuitBreakerOpenError)
    end

    it "resets after successful operations" do
      agent.failure_mode = :rate_limit

      # Cause some failures
      2.times do
        begin
          agent.execute_with_circuit_breaker { agent.risky_operation }
        rescue StandardError
          # Expected
        end
      end

      # Success should reset counter
      agent.failure_mode = nil
      result = agent.execute_with_circuit_breaker { agent.risky_operation }
      expect(result).to eq("immediate success")

      # Should be able to handle more failures without immediate circuit break
      agent.failure_mode = :rate_limit
      expect { agent.execute_with_circuit_breaker { agent.risky_operation } }
        .to raise_error(StandardError, /rate limit/)
    end
  end

  describe "retry execution" do
    before do
      TestRetryableAgent.retry_on :rate_limit, max_attempts: 3, backoff: :exponential, base_delay: 0.1
    end

    it "retries operations based on configuration" do
      agent.failure_mode = :success_after_retries

      result = agent.execute_with_retry { agent.risky_operation }

      expect(result).to eq("success")
      expect(agent.attempt_count).to eq(3)
    end

    it "respects maximum attempts" do
      agent.failure_mode = :rate_limit

      expect { agent.execute_with_retry { agent.risky_operation } }
        .to raise_error(StandardError, /rate limit/)

      # Should have attempted the configured number of times
      expect(agent.attempt_count).to eq(3)
    end

    it "implements exponential backoff" do
      agent.failure_mode = :rate_limit

      start_time = Time.now

      expect { agent.execute_with_retry { agent.risky_operation } }
        .to raise_error(StandardError)

      end_time = Time.now
      elapsed = end_time - start_time

      # Should have taken some time due to backoff (even with small base_delay)
      expect(elapsed).to be > 0.1
    end

    it "implements linear backoff" do
      TestRetryableAgent.retry_on :network_error, max_attempts: 3, backoff: :linear, base_delay: 0.1
      agent.failure_mode = :network

      start_time = Time.now

      expect { agent.execute_with_retry { agent.risky_operation } }
        .to raise_error(SocketError)

      end_time = Time.now
      elapsed = end_time - start_time

      # Should have taken time for linear backoff
      expect(elapsed).to be > 0.1
    end

    it "implements custom backoff strategies" do
      TestRetryableAgent.retry_on :rate_limit,
        max_attempts: 2,
        backoff: :custom,
        backoff_strategy: ->(attempt) { 0.1 * attempt }

      agent.failure_mode = :rate_limit

      start_time = Time.now

      expect { agent.execute_with_retry { agent.risky_operation } }
        .to raise_error(StandardError)

      end_time = Time.now
      elapsed = end_time - start_time

      expect(elapsed).to be > 0.1
    end
  end

  describe "fallback strategies" do
    it "executes fallback operations on failure" do
      fallback_executed = false
      fallback_result = "fallback result"

      TestRetryableAgent.fallback_on :rate_limit do
        fallback_executed = true
        fallback_result
      end

      agent.failure_mode = :rate_limit

      result = agent.execute_with_fallback { agent.risky_operation }

      expect(fallback_executed).to be true
      expect(result).to eq(fallback_result)
    end

    it "returns original result when no failure occurs" do
      TestRetryableAgent.fallback_on :rate_limit do
        "fallback"
      end

      agent.failure_mode = nil

      result = agent.execute_with_fallback { agent.risky_operation }
      expect(result).to eq("immediate success")
    end

    it "raises error when no fallback is configured" do
      agent.failure_mode = :rate_limit

      expect { agent.execute_with_fallback { agent.risky_operation } }
        .to raise_error(StandardError, /rate limit/)
    end
  end

  describe "combined retry and circuit breaker" do
    before do
      TestRetryableAgent.retry_on :rate_limit, max_attempts: 2, base_delay: 0.01
      TestRetryableAgent.circuit_breaker threshold: 3, timeout: 1
    end

    it "applies both retry and circuit breaker logic" do
      agent.failure_mode = :rate_limit

      # First few operations should retry
      2.times do
        expect { agent.execute_with_retry { agent.risky_operation } }
          .to raise_error(StandardError, /rate limit/)
      end

      # Circuit breaker should eventually trigger
      expect { agent.execute_with_circuit_breaker { agent.risky_operation } }
        .to raise_error(RAAF::DSL::Resilience::SmartRetry::CircuitBreakerOpenError)
    end
  end

  describe "error context and logging" do
    it "provides detailed error context" do
      agent.failure_mode = :rate_limit

      expect { agent.execute_with_retry { agent.risky_operation } }
        .to raise_error(StandardError) do |error|
          expect(error.message).to include("rate limit")
        end
    end

    it "logs retry attempts when logging is available" do
      # Mock logger if available
      if defined?(RAAF::Logger)
        expect(RAAF::Logger).to receive(:debug).at_least(:once)
      end

      agent.failure_mode = :success_after_retries
      agent.execute_with_retry { agent.risky_operation }
    end
  end

  describe "configuration validation" do
    it "validates retry configuration parameters" do
      expect { TestRetryableAgent.retry_on :test, max_attempts: -1 }
        .to raise_error(ArgumentError, /max_attempts must be positive/)

      expect { TestRetryableAgent.retry_on :test, backoff: :invalid }
        .to raise_error(ArgumentError, /invalid backoff strategy/)
    end

    it "validates circuit breaker configuration" do
      expect { TestRetryableAgent.circuit_breaker threshold: 0 }
        .to raise_error(ArgumentError, /threshold must be positive/)

      expect { TestRetryableAgent.circuit_breaker timeout: -1 }
        .to raise_error(ArgumentError, /timeout must be non-negative/)
    end
  end

  describe "thread safety" do
    it "handles concurrent operations safely" do
      TestRetryableAgent.retry_on :rate_limit, max_attempts: 2, base_delay: 0.01

      threads = 5.times.map do
        Thread.new do
          local_agent = TestRetryableAgent.new
          local_agent.failure_mode = :rate_limit
          begin
            local_agent.execute_with_retry { local_agent.risky_operation }
          rescue StandardError
            # Expected
          end
          local_agent.attempt_count
        end
      end

      results = threads.map(&:value)
      expect(results).to all(eq(2))
    end
  end

  describe "edge cases" do
    it "handles zero retry attempts" do
      TestRetryableAgent.retry_on :rate_limit, max_attempts: 0

      agent.failure_mode = :rate_limit

      expect { agent.execute_with_retry { agent.risky_operation } }
        .to raise_error(StandardError, /rate limit/)

      expect(agent.attempt_count).to eq(0)
    end

    it "handles nil backoff strategy" do
      TestRetryableAgent.retry_on :rate_limit, max_attempts: 2, backoff: nil, base_delay: 0

      agent.failure_mode = :rate_limit

      start_time = Time.now
      expect { agent.execute_with_retry { agent.risky_operation } }
        .to raise_error(StandardError)
      end_time = Time.now

      # Should be very fast with no backoff
      expect(end_time - start_time).to be < 0.1
    end

    it "handles exceptions during backoff calculation" do
      TestRetryableAgent.retry_on :rate_limit,
        max_attempts: 2,
        backoff: :custom,
        backoff_strategy: ->(_) { raise "backoff error" }

      agent.failure_mode = :rate_limit

      # Should still attempt retries even if backoff calculation fails
      expect { agent.execute_with_retry { agent.risky_operation } }
        .to raise_error(StandardError, /rate limit/)
    end
  end
end