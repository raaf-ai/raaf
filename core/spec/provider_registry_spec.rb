# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::ProviderRegistry do
  describe ".detect" do
    it "detects OpenAI models" do
      expect(described_class.detect("gpt-4o")).to eq(:openai)
      expect(described_class.detect("gpt-3.5-turbo")).to eq(:openai)
      expect(described_class.detect("o1-preview")).to eq(:openai)
      expect(described_class.detect("o3-mini")).to eq(:openai)
    end

    it "detects Anthropic models" do
      expect(described_class.detect("claude-3-5-sonnet-20241022")).to eq(:anthropic)
      expect(described_class.detect("claude-3-opus-20240229")).to eq(:anthropic)
    end

    it "detects Cohere models" do
      expect(described_class.detect("command-r-plus")).to eq(:cohere)
      expect(described_class.detect("command-r")).to eq(:cohere)
    end

    it "detects Groq models" do
      expect(described_class.detect("mixtral-8x7b-32768")).to eq(:groq)
      expect(described_class.detect("llama-3-70b")).to eq(:groq)
      expect(described_class.detect("gemma-7b")).to eq(:groq)
    end

    it "detects Perplexity models" do
      expect(described_class.detect("sonar")).to eq(:perplexity)
      expect(described_class.detect("sonar-pro")).to eq(:perplexity)
      expect(described_class.detect("sonar-reasoning")).to eq(:perplexity)
    end

    it "returns nil for unknown models" do
      expect(described_class.detect("unknown-model-123")).to be_nil
      expect(described_class.detect(nil)).to be_nil
    end

    it "is case-insensitive" do
      expect(described_class.detect("GPT-4O")).to eq(:openai)
      expect(described_class.detect("Claude-3-Sonnet")).to eq(:anthropic)
    end
  end

  describe ".create" do
    it "creates OpenAI ResponsesProvider" do
      provider = described_class.create(:openai)
      expect(provider).to be_a(RAAF::Models::ResponsesProvider)
    end

    it "creates ResponsesProvider with 'responses' alias" do
      provider = described_class.create(:responses)
      expect(provider).to be_a(RAAF::Models::ResponsesProvider)
    end

    it "accepts provider options" do
      # Note: ResponsesProvider doesn't expose api_key in constructor
      # but we can verify it accepts options without error
      expect {
        described_class.create(:openai, api_key: "test-key")
      }.not_to raise_error
    end

    it "raises error for unknown provider" do
      expect {
        described_class.create(:unknown_provider)
      }.to raise_error(ArgumentError, /Unknown provider/)
    end

    it "accepts string provider names" do
      provider = described_class.create("openai")
      expect(provider).to be_a(RAAF::Models::ResponsesProvider)
    end
  end

  describe ".register" do
    after do
      # Clean up custom providers after each test
      described_class.instance_variable_set(:@custom_providers, nil)
    end

    it "registers custom provider class" do
      custom_class = Class.new
      described_class.register(:custom, custom_class)

      expect(described_class.registered?(:custom)).to be true
    end

    it "registers custom provider by class path string" do
      described_class.register(:custom, "MyApp::CustomProvider")

      expect(described_class.registered?(:custom)).to be true
    end

    it "allows creating custom provider after registration" do
      # Create a simple custom provider class that matches the interface
      custom_class = Class.new do
        def initialize(**_options); end
      end
      stub_const("MyApp::CustomProvider", custom_class)

      described_class.register(:custom, "MyApp::CustomProvider")

      provider = described_class.create(:custom)
      expect(provider).to be_a(custom_class)
    end
  end

  describe ".providers" do
    it "returns list of all registered providers" do
      providers = described_class.providers

      expect(providers).to include(:openai, :responses, :anthropic, :cohere, :groq, :perplexity, :together, :litellm)
    end

    it "includes custom providers" do
      described_class.register(:custom, "CustomProvider")

      providers = described_class.providers
      expect(providers).to include(:custom)

      # Clean up
      described_class.instance_variable_set(:@custom_providers, nil)
    end
  end

  describe ".registered?" do
    it "returns true for built-in providers" do
      expect(described_class.registered?(:openai)).to be true
      expect(described_class.registered?(:anthropic)).to be true
      expect(described_class.registered?(:cohere)).to be true
    end

    it "returns false for unknown providers" do
      expect(described_class.registered?(:unknown)).to be false
    end

    it "returns true for custom providers" do
      described_class.register(:custom, "CustomProvider")
      expect(described_class.registered?(:custom)).to be true

      # Clean up
      described_class.instance_variable_set(:@custom_providers, nil)
    end

    it "accepts string provider names" do
      expect(described_class.registered?("openai")).to be true
      expect(described_class.registered?("unknown")).to be false
    end
  end

  # ========== THREAD-SAFETY TESTS ==========
  #
  # These tests verify that ProviderRegistry is thread-safe when multiple threads
  # attempt to register providers simultaneously. This tests the mutex protection
  # added to .register(), .providers(), and .registered?() methods.

  describe ".thread_safety" do
    before do
      # Reset custom providers before each test
      described_class.instance_variable_set(:@custom_providers, nil)
    end

    after do
      # Clean up custom providers after each test
      described_class.instance_variable_set(:@custom_providers, nil)
    end

    it "handles concurrent registrations safely" do
      # Create 50 threads that each try to register a different custom provider
      thread_count = 50
      threads = []

      thread_count.times do |i|
        threads << Thread.new do
          provider_name = "custom_provider_#{i}".to_sym
          provider_class = "CustomProvider#{i}"

          # Register provider
          described_class.register(provider_name, provider_class)
        end
      end

      # Wait for all threads to complete
      threads.each(&:join)

      # Verify all 50 providers were registered
      expect(described_class.registered?(:custom_provider_0)).to be true
      expect(described_class.registered?(:custom_provider_25)).to be true
      expect(described_class.registered?(:custom_provider_49)).to be true

      # Verify total provider count includes all custom providers
      providers = described_class.providers
      expect(providers).to include(:custom_provider_0, :custom_provider_25, :custom_provider_49)
      expect(providers.count).to be >= (thread_count + 8) # 8 built-in providers
    end

    it "handles concurrent providers() calls safely" do
      # First register a provider from main thread
      described_class.register(:main_provider, "MainProvider")

      # Create 20 threads that read providers concurrently
      thread_count = 20
      results = []
      threads = []
      mutex = Mutex.new

      thread_count.times do |_i|
        threads << Thread.new do
          providers = described_class.providers

          # Store result in thread-safe manner
          mutex.synchronize do
            results << providers
          end
        end
      end

      # Wait for all threads
      threads.each(&:join)

      # Verify all threads got consistent results
      expect(results.count).to eq(thread_count)

      # All results should contain the registered provider and built-in providers
      results.each do |providers_list|
        expect(providers_list).to include(:main_provider)
        expect(providers_list).to include(:openai, :anthropic)
      end

      # All results should be the same (same provider count)
      provider_counts = results.map(&:count)
      expect(provider_counts.uniq.count).to eq(1), "All threads should see consistent provider list"
    end

    it "handles concurrent registered? checks safely" do
      # Register one provider from main thread
      described_class.register(:test_provider, "TestProvider")

      # Create 30 threads that check registration concurrently
      thread_count = 30
      results = []
      threads = []
      mutex = Mutex.new

      thread_count.times do |_i|
        threads << Thread.new do
          is_registered = described_class.registered?(:test_provider)

          # Store result in thread-safe manner
          mutex.synchronize do
            results << is_registered
          end
        end
      end

      # Wait for all threads
      threads.each(&:join)

      # Verify all threads got consistent results (all true)
      expect(results.count).to eq(thread_count)
      expect(results).to all(be true)
    end

    it "handles mixed concurrent operations safely" do
      # Use a barrier to coordinate thread startup
      thread_count = 15
      start_barrier = Barrier.new(thread_count)
      errors = []
      mutex = Mutex.new

      threads = thread_count.times.map do |i|
        Thread.new do
          begin
            # Wait for all threads to be created
            start_barrier.wait

            # Half the threads register new providers
            if i.even?
              provider_name = "mixed_provider_#{i}".to_sym
              described_class.register(provider_name, "MixedProvider#{i}")
            else
              # Half the threads read the provider list
              described_class.providers

              # And some check registration status
              described_class.registered?(:openai)
            end
          rescue => e
            mutex.synchronize do
              errors << { thread: i, error: e }
            end
          end
        end
      end

      # Wait for all threads to complete
      threads.each(&:join)

      # Verify no errors occurred
      expect(errors).to be_empty, "Errors in concurrent operations: #{errors.inspect}"

      # Verify mixed registrations succeeded
      expect(described_class.registered?(:mixed_provider_0)).to be true
      expect(described_class.registered?(:mixed_provider_14)).to be true
    end

    it "survives stress test with 100 rapid registrations" do
      # This stress test creates many threads attempting rapid registration
      # to ensure mutex protection handles high contention
      thread_count = 100
      registration_per_thread = 2
      threads = []

      thread_count.times do |thread_id|
        threads << Thread.new do
          registration_per_thread.times do |reg_id|
            provider_name = "stress_provider_#{thread_id}_#{reg_id}".to_sym
            provider_class = "StressProvider#{thread_id}#{reg_id}"

            # Register provider
            described_class.register(provider_name, provider_class)
          end
        end
      end

      # Wait for all threads
      threads.each(&:join)

      # Verify registrations were successful (check a sample)
      total_expected = thread_count * registration_per_thread
      providers = described_class.providers
      custom_providers = providers.select { |p| p.to_s.start_with?("stress_provider") }

      # Should have registered all stress providers
      expect(custom_providers.count).to eq(total_expected)
    end
  end
end

# Helper class for synchronizing thread startup in tests
class Barrier
  def initialize(count)
    @count = count
    @current = 0
    @mutex = Mutex.new
    @condition = ConditionVariable.new
  end

  def wait
    @mutex.synchronize do
      @current += 1
      if @current >= @count
        @condition.broadcast
      else
        @condition.wait(@mutex)
      end
    end
  end
end
