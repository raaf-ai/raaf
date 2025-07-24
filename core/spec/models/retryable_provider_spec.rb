# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Models::RetryableProvider do
  let(:mock_provider) do
    Class.new do
      include RAAF::Models::RetryableProvider

      def initialize
        super
        @call_count = 0
      end

      attr_reader :call_count

      def test_method
        @call_count += 1

        case @call_count
        when 1
          raise Errno::ECONNRESET, "Connection reset"
        when 2
          raise Net::ReadTimeout, "Read timeout"
        else
          "success after #{@call_count} attempts"
        end
      end
    end.new
  end

  describe "module inclusion" do
    it "includes retry functionality in the target class" do
      expect(mock_provider).to respond_to(:with_retry)
      expect(mock_provider).to respond_to(:configure_retry)
    end

    it "sets up default retry configuration" do
      expect(mock_provider.retry_config).to be_a(Hash)
      expect(mock_provider.retry_config[:max_attempts]).to eq(3)
      expect(mock_provider.retry_config[:base_delay]).to eq(1.0)
    end
  end

  describe "#with_retry" do
    it "succeeds on first attempt when no error occurs" do
      allow(mock_provider).to receive(:test_method).and_return("immediate success")

      result = mock_provider.with_retry("test") do
        mock_provider.test_method
      end

      expect(result).to eq("immediate success")
    end

    it "retries on retryable exceptions and eventually succeeds" do
      result = mock_provider.with_retry("test") do
        mock_provider.test_method
      end

      expect(result).to eq("success after 3 attempts")
      expect(mock_provider.call_count).to eq(3)
    end

    it "respects max_attempts configuration" do
      mock_provider.configure_retry(max_attempts: 2)

      expect do
        mock_provider.with_retry("test") do
          mock_provider.test_method
        end
      end.to raise_error(Net::ReadTimeout)

      expect(mock_provider.call_count).to eq(2)
    end

    it "re-raises non-retryable exceptions immediately" do
      allow(mock_provider).to receive(:test_method).and_raise(ArgumentError.new("Invalid argument"))

      expect do
        mock_provider.with_retry("test") do
          mock_provider.test_method
        end
      end.to raise_error(ArgumentError)
    end
  end

  describe "#configure_retry" do
    it "updates retry configuration" do
      mock_provider.configure_retry(
        max_attempts: 5,
        base_delay: 2.0,
        max_delay: 60.0
      )

      expect(mock_provider.retry_config[:max_attempts]).to eq(5)
      expect(mock_provider.retry_config[:base_delay]).to eq(2.0)
      expect(mock_provider.retry_config[:max_delay]).to eq(60.0)
    end

    it "returns self for method chaining" do
      result = mock_provider.configure_retry(max_attempts: 5)
      expect(result).to eq(mock_provider)
    end
  end

  describe "RetryableProviderWrapper" do
    let(:base_provider) do
      Class.new do
        def initialize
          @call_count = 0
        end

        attr_reader :call_count

        def chat_completion(messages:, model:, **_options)
          @call_count += 1

          raise Errno::ECONNRESET, "Connection reset" if @call_count <= 2

          { "choices" => [{ "message" => { "content" => "Success!" } }] }
        end
      end.new
    end

    let(:wrapped_provider) do
      RAAF::Models::RetryableProviderWrapper.new(
        base_provider,
        max_attempts: 5,
        base_delay: 0.01 # Fast for testing
      )
    end

    it "wraps provider methods with retry logic" do
      result = wrapped_provider.chat_completion(
        messages: [{ role: "user", content: "test" }],
        model: "gpt-4o"
      )

      expect(result).to eq({ "choices" => [{ "message" => { "content" => "Success!" } }] })
      expect(base_provider.call_count).to eq(3)
    end

    it "forwards method calls to wrapped provider" do
      expect(wrapped_provider).to respond_to(:chat_completion)
      expect(wrapped_provider.respond_to?(:chat_completion)).to be(true)
    end
  end

  describe "error handling" do
    it "handles retryable exceptions" do
      exceptions = [
        Errno::ECONNRESET,
        Errno::ECONNREFUSED,
        Errno::ETIMEDOUT,
        Net::ReadTimeout,
        Net::WriteTimeout,
        Net::OpenTimeout
      ]

      exceptions.each do |exception_class|
        provider = Class.new do
          include RAAF::Models::RetryableProvider

          def test_method(exception_class)
            raise exception_class, "Test error"
          end
        end.new

        provider.configure_retry(max_attempts: 1) # Fail immediately

        expect do
          provider.with_retry do
            provider.test_method(exception_class)
          end
        end.to raise_error(exception_class)
      end
    end
  end

  describe "delay calculation" do
    it "calculates exponential backoff delays" do
      provider = mock_provider
      provider.configure_retry(
        base_delay: 1.0,
        multiplier: 2.0,
        max_delay: 10.0,
        jitter: 0.0 # No jitter for predictable testing
      )

      # Access private method for testing
      delay1 = provider.send(:calculate_delay, 1)
      delay2 = provider.send(:calculate_delay, 2)
      delay3 = provider.send(:calculate_delay, 3)

      expect(delay1).to eq(1.0)  # base_delay * 2^0
      expect(delay2).to eq(2.0)  # base_delay * 2^1
      expect(delay3).to eq(4.0)  # base_delay * 2^2
    end

    it "respects max_delay configuration" do
      provider = mock_provider
      provider.configure_retry(
        base_delay: 1.0,
        multiplier: 2.0,
        max_delay: 3.0,
        jitter: 0.0
      )

      delay4 = provider.send(:calculate_delay, 4) # Would be 8.0 without cap
      expect(delay4).to eq(3.0) # Capped at max_delay
    end
  end
end
