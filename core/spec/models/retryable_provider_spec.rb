# frozen_string_literal: true

require "spec_helper"

RSpec.describe "RAAF::Models::ModelInterface Retry Functionality" do
  # Test provider that implements the ModelInterface to test retry functionality
  let(:test_provider_class) do
    Class.new(RAAF::Models::ModelInterface) do
      def initialize
        super
        @call_count = 0
        @fail_count = 2 # Fail first 2 attempts, succeed on 3rd
      end

      attr_reader :call_count

      def perform_chat_completion(messages:, model:, tools: nil, stream: false, **_kwargs)
        @call_count += 1

        case @call_count
        when 1
          raise Errno::ECONNRESET, "Connection reset"
        when 2
          raise Net::ReadTimeout, "Read timeout"
        else
          {
            "choices" => [{
              "message" => {
                "role" => "assistant",
                "content" => "success after #{@call_count} attempts"
              }
            }],
            "usage" => { "total_tokens" => 10 },
            "model" => model
          }
        end
      end

      def supported_models
        ["test-model"]
      end

      def provider_name
        "TestRetryProvider"
      end

      # Reset call count for testing
      def reset_calls
        @call_count = 0
      end
    end
  end

  let(:test_provider) { test_provider_class.new }

  describe "built-in retry functionality" do
    it "has retry configuration by default" do
      expect(test_provider.retry_config).to be_a(Hash)
      expect(test_provider.retry_config[:max_attempts]).to eq(3)
      expect(test_provider.retry_config[:base_delay]).to eq(1.0)
      expect(test_provider.retry_config[:max_delay]).to eq(30.0)
    end

    it "allows retry configuration customization" do
      test_provider.configure_retry(max_attempts: 5, base_delay: 0.5)

      expect(test_provider.retry_config[:max_attempts]).to eq(5)
      expect(test_provider.retry_config[:base_delay]).to eq(0.5)
    end

    it "returns self for method chaining" do
      result = test_provider.configure_retry(max_attempts: 2)
      expect(result).to eq(test_provider)
    end
  end

  describe "automatic retry on chat_completion" do
    it "succeeds on first attempt when no error occurs" do
      # Create provider that succeeds immediately
      success_provider = Class.new(RAAF::Models::ModelInterface) do
        def initialize
          super
          @call_count = 0
        end

        attr_reader :call_count

        def perform_chat_completion(messages:, model:, **_kwargs)
          @call_count += 1
          {
            "choices" => [{ "message" => { "role" => "assistant", "content" => "immediate success" } }],
            "usage" => { "total_tokens" => 5 }
          }
        end

        def supported_models = ["success-model"]
        def provider_name = "SuccessProvider"
      end.new

      result = success_provider.chat_completion(messages: [], model: "success-model")

      expect(success_provider.call_count).to eq(1)
      expect(result["choices"][0]["message"]["content"]).to eq("immediate success")
    end

    it "retries on retryable exceptions and eventually succeeds" do
      # Mock sleep to speed up tests
      allow(test_provider).to receive(:sleep)

      result = test_provider.chat_completion(messages: [], model: "test-model")

      expect(test_provider.call_count).to eq(3) # Failed twice, succeeded on 3rd
      expect(result["choices"][0]["message"]["content"]).to eq("success after 3 attempts")
    end

    it "fails after max_attempts retries" do
      # Create provider that always fails
      failing_provider = Class.new(RAAF::Models::ModelInterface) do
        def initialize
          super
          @call_count = 0
        end

        attr_reader :call_count

        def perform_chat_completion(messages:, model:, **_kwargs)
          @call_count += 1
          raise Errno::ECONNRESET, "Always fails"
        end

        def supported_models = ["fail-model"]
        def provider_name = "FailProvider"
      end.new

      # Mock sleep to speed up tests
      allow(failing_provider).to receive(:sleep)

      expect do
        failing_provider.chat_completion(messages: [], model: "fail-model")
      end.to raise_error(Errno::ECONNRESET, /Always fails/)

      expect(failing_provider.call_count).to eq(3) # Default max_attempts
    end

    it "respects custom max_attempts configuration" do
      # Create provider that always fails
      failing_provider = Class.new(RAAF::Models::ModelInterface) do
        def initialize
          super
          @call_count = 0
        end

        attr_reader :call_count

        def perform_chat_completion(messages:, model:, **_kwargs)
          @call_count += 1
          raise Net::ReadTimeout, "Custom retry test"
        end

        def supported_models = ["custom-fail-model"]
        def provider_name = "CustomFailProvider"
      end.new

      failing_provider.configure_retry(max_attempts: 2)
      allow(failing_provider).to receive(:sleep)

      expect do
        failing_provider.chat_completion(messages: [], model: "custom-fail-model")
      end.to raise_error(Net::ReadTimeout, /Custom retry test/)

      expect(failing_provider.call_count).to eq(2) # Custom max_attempts
    end
  end

  describe "automatic retry on responses_completion" do
    it "retries responses_completion calls" do
      allow(test_provider).to receive(:sleep)

      result = test_provider.responses_completion(messages: [], model: "test-model")

      expect(test_provider.call_count).to eq(3)
      expect(result[:output][0][:content]).to eq("success after 3 attempts")
    end
  end

  describe "retry exception handling" do
    let(:custom_provider_class) do
      Class.new(RAAF::Models::ModelInterface) do
        def initialize(error_sequence)
          super()
          @error_sequence = error_sequence
          @call_count = 0
        end

        attr_reader :call_count

        def perform_chat_completion(messages:, model:, **_kwargs)
          @call_count += 1

          raise @error_sequence[@call_count - 1] if @call_count <= @error_sequence.length

          { "choices" => [{ "message" => { "role" => "assistant", "content" => "success" } }] }
        end

        def supported_models = ["custom-model"]
        def provider_name = "CustomProvider"
      end
    end

    it "retries on Errno::ECONNRESET" do
      provider = custom_provider_class.new([Errno::ECONNRESET.new("Connection reset")])
      allow(provider).to receive(:sleep)

      provider.chat_completion(messages: [], model: "custom-model")
      expect(provider.call_count).to eq(2) # 1 failure + 1 success
    end

    it "retries on Net::ReadTimeout" do
      provider = custom_provider_class.new([Net::ReadTimeout.new("Read timeout")])
      allow(provider).to receive(:sleep)

      provider.chat_completion(messages: [], model: "custom-model")
      expect(provider.call_count).to eq(2)
    end

    it "retries on Net::WriteTimeout" do
      provider = custom_provider_class.new([Net::WriteTimeout.new("Write timeout")])
      allow(provider).to receive(:sleep)

      provider.chat_completion(messages: [], model: "custom-model")
      expect(provider.call_count).to eq(2)
    end

    it "doesn't retry on non-retryable exceptions" do
      provider = custom_provider_class.new([ArgumentError.new("Invalid argument")])

      expect do
        provider.chat_completion(messages: [], model: "custom-model")
      end.to raise_error(ArgumentError, "Invalid argument")

      expect(provider.call_count).to eq(1) # No retry
    end
  end

  describe "retry delay calculation" do
    it "calculates exponential backoff with jitter" do
      # Test the private method via a test provider
      delays = []

      # Mock sleep to capture delay values
      allow(test_provider).to receive(:sleep) do |delay|
        delays << delay
      end

      test_provider.configure_retry(base_delay: 1.0, multiplier: 2.0, jitter: 0.0) # No jitter for predictable testing

      expect do
        test_provider.chat_completion(messages: [], model: "test-model")
      end.not_to raise_error

      # Should have 2 delays (for the 2 failed attempts)
      expect(delays.length).to eq(2)

      # First delay should be base_delay * multiplier^0 = 1.0
      expect(delays[0]).to be_within(0.1).of(1.0)

      # Second delay should be base_delay * multiplier^1 = 2.0
      expect(delays[1]).to be_within(0.1).of(2.0)
    end

    it "caps delay at max_delay" do
      delays = []

      allow(test_provider).to receive(:sleep) do |delay|
        delays << delay
      end

      test_provider.configure_retry(base_delay: 10.0, max_delay: 5.0, jitter: 0.0)

      expect do
        test_provider.chat_completion(messages: [], model: "test-model")
      end.not_to raise_error

      # All delays should be capped at max_delay
      expect(delays).to all(be <= 5.0)
    end
  end

  describe "retryable error detection" do
    let(:error_provider_class) do
      Class.new(RAAF::Models::ModelInterface) do
        def initialize(error_message)
          super()
          @error_message = error_message
          @call_count = 0
        end

        attr_reader :call_count

        def perform_chat_completion(messages:, model:, **_kwargs)
          @call_count += 1

          raise StandardError, @error_message if @call_count == 1

          { "choices" => [{ "message" => { "role" => "assistant", "content" => "success" } }] }
        end

        def supported_models = ["error-model"]
        def provider_name = "ErrorProvider"
      end
    end

    it "retries on rate limit error messages" do
      provider = error_provider_class.new("Rate limit exceeded")
      allow(provider).to receive(:sleep)

      provider.chat_completion(messages: [], model: "error-model")
      expect(provider.call_count).to eq(2) # 1 failure + 1 success
    end

    it "retries on 'too many requests' error messages" do
      provider = error_provider_class.new("Too many requests")
      allow(provider).to receive(:sleep)

      provider.chat_completion(messages: [], model: "error-model")
      expect(provider.call_count).to eq(2)
    end

    it "doesn't retry on non-retryable error messages" do
      provider = error_provider_class.new("Invalid API key")

      expect do
        provider.chat_completion(messages: [], model: "error-model")
      end.to raise_error(StandardError, "Invalid API key")

      expect(provider.call_count).to eq(1) # No retry
    end
  end

  describe "logging" do
    it "logs retry attempts" do
      allow(test_provider).to receive(:sleep)
      expect(test_provider).to receive(:log_warn).at_least(:once)

      test_provider.chat_completion(messages: [], model: "test-model")
    end

    it "logs final failure" do
      failing_provider = Class.new(RAAF::Models::ModelInterface) do
        def perform_chat_completion(messages:, model:, **_kwargs)
          raise Errno::ECONNRESET, "Always fails"
        end

        def supported_models = ["fail-model"]
        def provider_name = "FailProvider"
      end.new

      allow(failing_provider).to receive(:sleep)
      expect(failing_provider).to receive(:log_error).once

      expect do
        failing_provider.chat_completion(messages: [], model: "fail-model")
      end.to raise_error(Errno::ECONNRESET)
    end
  end
end
