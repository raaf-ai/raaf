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
end
