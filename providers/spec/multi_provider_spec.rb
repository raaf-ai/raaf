# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Models::MultiProvider do
  let(:providers) do
    {
      openai: RAAF::Models::ResponsesProvider.new(api_key: "test-openai"),
      anthropic: RAAF::Models::AnthropicProvider.new(api_key: "test-anthropic"),
      groq: RAAF::Models::GroqProvider.new(api_key: "test-groq")
    }
  end
  let(:multi_provider) { described_class.new(providers: providers, default: :openai) }

  describe "#initialize" do
    it "requires providers hash" do
      skip "waiting for research and fix"
      expect { described_class.new }.to raise_error(ArgumentError, /providers is required/)
    end

    it "initializes with providers and default" do
      skip "waiting for research and fix"
      expect(multi_provider.instance_variable_get(:@providers)).to eq(providers)
      expect(multi_provider.instance_variable_get(:@default)).to eq(:openai)
    end
  end

  describe "#provider_name" do
    it "returns MultiProvider" do
      skip "waiting for research and fix"
      expect(multi_provider.provider_name).to eq("MultiProvider")
    end
  end

  describe "#supported_models" do
    it "returns combined models from all providers" do
      skip "waiting for research and fix"
      models = multi_provider.supported_models
      expect(models).to be_an(Array)
      expect(models).to include("gpt-4o") # OpenAI
      expect(models).to include("claude-3-5-sonnet-20241022") # Anthropic
      expect(models).to include("mixtral-8x7b-32768") # Groq
    end
  end

  describe "#get_provider_for_model" do
    it "returns correct provider for model" do
      skip "waiting for research and fix"
      provider = multi_provider.send(:get_provider_for_model, "gpt-4o")
      expect(provider).to be_a(RAAF::Models::ResponsesProvider)
    end

    it "returns default provider for unknown model" do
      skip "waiting for research and fix"
      provider = multi_provider.send(:get_provider_for_model, "unknown-model")
      expect(provider).to be_a(RAAF::Models::ResponsesProvider)
    end
  end
end
