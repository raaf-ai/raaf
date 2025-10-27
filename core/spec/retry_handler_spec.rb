# frozen_string_literal: true

require "spec_helper"
require "raaf/retry_handler"

RSpec.describe RAAF::RetryHandler do
  # Test class that includes the module
  let(:test_class) do
    Class.new do
      include RAAF::RetryHandler
      include RAAF::Logging

      def initialize
        initialize_retry_config
      end
    end
  end

  let(:handler) { test_class.new }

  describe "#with_retry" do
    it "executes block successfully without retry" do
      result = handler.with_retry(:test_operation) { "success" }
      expect(result).to eq("success")
    end

    it "retries on retryable exceptions" do
      attempts = 0
      result = handler.with_retry(:test_operation) do
        attempts += 1
        raise Net::ReadTimeout, "timeout" if attempts < 3
        "success"
      end

      expect(result).to eq("success")
      expect(attempts).to eq(3)
    end

    it "classifies rate limit errors correctly" do
      expect do
        handler.with_retry(:test_operation) do
          raise StandardError, "Rate limit exceeded"
        end
      end.to raise_error(StandardError)

      stats = handler.retry_stats
      expect(stats[:by_error_type][:rate_limit]).to be > 0
    end

    it "classifies timeout errors correctly" do
      expect do
        handler.with_retry(:test_operation) do
          raise StandardError, "Request timeout"
        end
      end.to raise_error(StandardError)

      stats = handler.retry_stats
      expect(stats[:by_error_type][:timeout]).to be > 0
    end

    it "classifies context_too_large errors correctly" do
      expect do
        handler.with_retry(:test_operation) do
          raise StandardError, "Maximum context length exceeded"
        end
      end.to raise_error(StandardError)

      stats = handler.retry_stats
      expect(stats[:by_error_type][:context_too_large]).to be > 0
    end

    it "classifies model_overloaded errors correctly" do
      expect do
        handler.with_retry(:test_operation) do
          raise StandardError, "Service unavailable (503)"
        end
      end.to raise_error(StandardError)

      stats = handler.retry_stats
      expect(stats[:by_error_type][:model_overloaded]).to be > 0
    end

    it "does not retry authentication errors" do
      attempts = 0
      expect do
        handler.with_retry(:test_operation) do
          attempts += 1
          raise StandardError, "Unauthorized (401)"
        end
      end.to raise_error(StandardError)

      expect(attempts).to eq(1) # Should not retry
    end

    it "respects max_attempts configuration" do
      handler.configure_retry(max_attempts: 2)
      attempts = 0

      expect do
        handler.with_retry(:test_operation) do
          attempts += 1
          raise Net::ReadTimeout, "timeout"
        end
      end.to raise_error(Net::ReadTimeout)

      expect(attempts).to eq(2)
    end

    it "uses exponential backoff" do
      handler.configure_retry(base_delay: 0.1, max_delay: 1.0)
      attempts = 0
      delays = []

      expect do
        handler.with_retry(:test_operation) do
          attempts += 1
          if attempts < 4
            delays << handler.send(:calculate_delay, attempts)
            raise Net::ReadTimeout, "timeout"
          end
        end
      end.not_to raise_error

      # Verify exponential growth (with jitter)
      expect(delays[1]).to be > delays[0]
      expect(delays[2]).to be > delays[1]
    end
  end

  describe "#configure_retry" do
    it "allows customizing retry configuration" do
      handler.configure_retry(
        max_attempts: 10,
        base_delay: 2.0,
        max_delay: 120.0,
        multiplier: 3.0,
        jitter: 0.2
      )

      config = handler.retry_config
      expect(config[:max_attempts]).to eq(10)
      expect(config[:base_delay]).to eq(2.0)
      expect(config[:max_delay]).to eq(120.0)
      expect(config[:multiplier]).to eq(3.0)
      expect(config[:jitter]).to eq(0.2)
    end
  end

  describe "#retry_stats" do
    it "tracks total retry attempts" do
      3.times do
        attempts = 0
        handler.with_retry(:test_operation) do
          attempts += 1
          raise Net::ReadTimeout, "timeout" if attempts < 2
          "success"
        end
      end

      stats = handler.retry_stats
      expect(stats[:total_attempts]).to eq(3) # 3 retries total (1 per operation)
      expect(stats[:successful_retries]).to eq(3)
    end

    it "tracks failures by error type" do
      # Rate limit error
      handler.with_retry(:test_operation) do
        raise StandardError, "Rate limit exceeded"
      end rescue nil

      # Timeout error
      handler.with_retry(:test_operation) do
        raise StandardError, "Connection timeout"
      end rescue nil

      stats = handler.retry_stats
      expect(stats[:by_error_type][:rate_limit]).to be > 0
      expect(stats[:by_error_type][:timeout]).to be > 0
    end

    it "calculates failure rate correctly" do
      # 2 successful operations
      2.times do
        handler.with_retry(:test_operation) { "success" }
      end

      # 1 failed operation (all retries exhausted)
      handler.with_retry(:test_operation) do
        raise Net::ReadTimeout, "timeout"
      end rescue nil

      stats = handler.retry_stats
      # Failure rate should be proportional
      expect(stats[:failure_rate]).to be_between(0.0, 1.0)
    end
  end

  describe "thread safety" do
    it "handles concurrent retry operations safely" do
      threads = 10.times.map do |i|
        Thread.new do
          attempts = 0
          handler.with_retry("operation_#{i}") do
            attempts += 1
            raise Net::ReadTimeout, "timeout" if attempts < 2
            "success"
          end
        end
      end

      threads.each(&:join)

      stats = handler.retry_stats
      expect(stats[:total_attempts]).to eq(10)
      expect(stats[:successful_retries]).to eq(10)
    end
  end

  describe "error classification" do
    {
      rate_limit: ["Rate limit exceeded", "Too many requests", "Quota exceeded (429)"],
      timeout: ["Request timeout", "Connection timed out", "Read timeout"],
      context_too_large: ["Context too large", "Maximum context length", "Token limit exceeded"],
      model_overloaded: ["Service unavailable", "Model overloaded", "Gateway error (502)"],
      network_error: ["Connection refused", "Network unreachable", "DNS error"],
      authentication_error: ["Unauthorized", "Invalid API key", "Forbidden (403)"]
    }.each do |error_type, messages|
      describe "#{error_type} classification" do
        messages.each do |message|
          it "classifies '#{message}' as #{error_type}" do
            error = StandardError.new(message)
            classified = handler.send(:classify_error, error)
            expect(classified).to eq(error_type)
          end
        end
      end
    end
  end
end
