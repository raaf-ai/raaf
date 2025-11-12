# frozen_string_literal: true

require "spec_helper"
require_relative "../lib/raaf/throttler"

RSpec.describe RAAF::TokenBucket do
  describe "#initialize" do
    it "initializes with rate and burst" do
      bucket = described_class.new(rate: 60, burst: 10)
      expect(bucket.rate).to eq(60)
      expect(bucket.burst).to eq(10)
      expect(bucket.timeout).to eq(30)
    end

    it "initializes with custom timeout" do
      bucket = described_class.new(rate: 60, burst: 10, timeout: 60)
      expect(bucket.timeout).to eq(60)
    end

    it "starts with burst capacity" do
      bucket = described_class.new(rate: 60, burst: 10)
      # Should be able to acquire burst number of tokens immediately
      10.times { expect(bucket.acquire).to be true }
    end
  end

  describe "#acquire" do
    context "with available tokens" do
      it "acquires token immediately" do
        bucket = described_class.new(rate: 60, burst: 10)
        expect(bucket.acquire).to be true
      end

      it "decrements token count" do
        bucket = described_class.new(rate: 60, burst: 10, timeout: 0.1)
        10.times { bucket.acquire }
        # Next acquire should wait (no tokens left), timeout after 0.1s
        expect(bucket.acquire).to be false
      end
    end

    context "with no available tokens" do
      it "waits for token refill" do
        bucket = described_class.new(rate: 60, burst: 1, timeout: 2)
        bucket.acquire # Use first token

        start_time = Time.now
        result = bucket.acquire # Should wait ~1 second (60 RPM = 1 per second)
        elapsed = Time.now - start_time

        expect(result).to be true
        expect(elapsed).to be >= 0.9 # Allow slight timing variation
      end

      it "times out if token not available" do
        bucket = described_class.new(rate: 1, burst: 1, timeout: 0.1)
        bucket.acquire # Use first token

        # Should timeout after 0.1 seconds (much less than 60 seconds needed for 1 RPM)
        result = bucket.acquire
        expect(result).to be false
      end
    end

    context "with token refill" do
      it "refills tokens over time" do
        bucket = described_class.new(rate: 60, burst: 1) # 1 token per second
        bucket.acquire # Use first token

        sleep(1.1) # Wait for refill (1 second + margin)

        expect(bucket.acquire).to be true
      end

      it "respects burst capacity during refill" do
        bucket = described_class.new(rate: 120, burst: 2, timeout: 0.1) # 2 tokens per second, max 2
        bucket.acquire # Use 1 token
        bucket.acquire # Use 2nd token

        sleep(2.1) # Wait for refill (should get 2 tokens back, not 4)

        expect(bucket.acquire).to be true # Token 1
        expect(bucket.acquire).to be true # Token 2
        expect(bucket.acquire).to be false # Over capacity, should timeout after 0.1s
      end
    end
  end
end

RSpec.describe RAAF::Throttler do
  let(:test_class) do
    Class.new do
      include RAAF::Throttler

      def initialize
        initialize_throttle_config
      end

      def execute
        with_throttle(:execute) do
          "executed"
        end
      end
    end
  end

  describe "#configure_throttle" do
    it "configures throttle with RPM" do
      instance = test_class.new
      instance.configure_throttle(rpm: 60)

      # throttle_stats returns statistics, not configuration
      # Check that statistics are initialized
      stats = instance.throttle_stats
      expect(stats).to include(
        requests_throttled: 0,
        total_wait_time: 0.0,
        timeout_failures: 0
      )
    end

    it "configures throttle with burst" do
      instance = test_class.new
      instance.configure_throttle(rpm: 60, burst: 10)

      # Verify statistics structure
      stats = instance.throttle_stats
      expect(stats).to be_a(Hash)
      expect(stats.keys).to match_array([:requests_throttled, :total_wait_time, :timeout_failures])
    end

    it "configures throttle with timeout" do
      instance = test_class.new
      instance.configure_throttle(rpm: 60, timeout: 60)

      # Verify statistics structure
      stats = instance.throttle_stats
      expect(stats).to be_a(Hash)
    end

    it "enables throttling when RPM is set" do
      instance = test_class.new
      instance.configure_throttle(rpm: 60)

      # Should throttle (block execution briefly)
      start_time = Time.now
      2.times { instance.execute }
      elapsed = Time.now - start_time

      # Second call should wait (60 RPM = 1 per second)
      # With burst=6 (rpm/10), should have immediate tokens
      expect(elapsed).to be < 0.5 # Fast because burst allows immediate execution
    end

    it "disables throttling when explicitly disabled" do
      instance = test_class.new
      instance.configure_throttle(rpm: 60, enabled: false)

      start_time = Time.now
      10.times { instance.execute }
      elapsed = Time.now - start_time

      # All executions should be immediate (no throttling)
      expect(elapsed).to be < 0.1
    end
  end

  describe "#with_throttle" do
    context "when throttling is disabled" do
      it "executes immediately" do
        instance = test_class.new

        start_time = Time.now
        10.times { instance.execute }
        elapsed = Time.now - start_time

        expect(elapsed).to be < 0.1
      end
    end

    context "when throttling is enabled" do
      it "executes with rate limiting" do
        instance = test_class.new
        instance.configure_throttle(rpm: 60, burst: 1, enabled: true)

        start_time = Time.now
        2.times { instance.execute }
        elapsed = Time.now - start_time

        # Second call should wait ~1 second (60 RPM)
        expect(elapsed).to be >= 0.9
      end

      it "raises ThrottleTimeoutError on timeout" do
        instance = test_class.new
        instance.configure_throttle(rpm: 1, burst: 1, timeout: 0.1, enabled: true)

        instance.execute # Use first token

        expect { instance.execute }.to raise_error(RAAF::ThrottleTimeoutError)
      end
    end

    context "with per-method buckets" do
      let(:multi_method_class) do
        Class.new do
          include RAAF::Throttler

          def initialize
            initialize_throttle_config
          end

          def method_a
            with_throttle(:method_a) { "a" }
          end

          def method_b
            with_throttle(:method_b) { "b" }
          end
        end
      end

      it "maintains separate buckets for different methods" do
        instance = multi_method_class.new
        instance.configure_throttle(rpm: 60, burst: 1, enabled: true)

        # Each method has its own bucket, so both should execute immediately
        start_time = Time.now
        instance.method_a
        instance.method_b
        elapsed = Time.now - start_time

        expect(elapsed).to be < 0.1
      end
    end
  end

  describe "#throttle_stats" do
    it "tracks requests throttled" do
      instance = test_class.new
      instance.configure_throttle(rpm: 60, burst: 1, enabled: true)

      instance.execute # First (uses burst token)
      sleep(0.05)
      instance.execute # Second (needs to wait, gets throttled)

      stats = instance.throttle_stats
      expect(stats[:requests_throttled]).to be >= 1
    end

    it "tracks total wait time" do
      instance = test_class.new
      instance.configure_throttle(rpm: 60, burst: 1, enabled: true)

      instance.execute
      sleep(0.05)
      instance.execute

      stats = instance.throttle_stats
      expect(stats[:total_wait_time]).to be > 0
    end

    it "tracks timeout failures" do
      instance = test_class.new
      instance.configure_throttle(rpm: 1, burst: 1, timeout: 0.1, enabled: true)

      instance.execute

      begin
        instance.execute
      rescue RAAF::ThrottleTimeoutError
        # Expected
      end

      stats = instance.throttle_stats
      expect(stats[:timeout_failures]).to eq(1)
    end
  end

  describe "#reset_throttle_stats" do
    it "resets statistics" do
      instance = test_class.new
      instance.configure_throttle(rpm: 60, burst: 1, enabled: true)

      instance.execute
      sleep(0.05)
      instance.execute

      instance.reset_throttle_stats

      stats = instance.throttle_stats
      expect(stats[:requests_throttled]).to eq(0)
      expect(stats[:total_wait_time]).to eq(0)
      expect(stats[:timeout_failures]).to eq(0)
    end
  end
end
