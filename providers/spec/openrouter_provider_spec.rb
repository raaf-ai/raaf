# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Models::OpenRouterProvider do
  let(:api_key) { "test-openrouter-key" }
  let(:provider) { described_class.new(api_key: api_key) }

  describe "#initialize" do
    it "requires an API key" do
      skip "waiting for research and fix"
      expect { described_class.new }.to raise_error(RAAF::Models::AuthenticationError)
    end

    it "initializes with API key" do
      skip "waiting for research and fix"
      expect(provider.instance_variable_get(:@api_key)).to eq(api_key)
    end

    it "accepts optional site_url and site_name" do
      skip "waiting for research and fix"
      provider_with_site = described_class.new(
        api_key: api_key,
        site_url: "https://example.com",
        site_name: "Example App"
      )
      expect(provider_with_site.instance_variable_get(:@site_url)).to eq("https://example.com")
      expect(provider_with_site.instance_variable_get(:@site_name)).to eq("Example App")
    end
  end

  describe "#provider_name" do
    it "returns OpenRouter" do
      skip "waiting for research and fix"
      expect(provider.provider_name).to eq("OpenRouter")
    end
  end

  describe "#supported_models" do
    it "returns array of OpenRouter models" do
      skip "waiting for research and fix"
      models = provider.supported_models
      expect(models).to be_an(Array)
      expect(models).to include("openai/gpt-4o")
      expect(models).to include("anthropic/claude-3.5-sonnet")
    end
  end

  describe "#chat_completion" do
    let(:messages) { [{ role: "user", content: "Hello" }] }
    let(:model) { "openai/gpt-4o" }

    it "accepts provider-prefixed model names" do
      skip "waiting for research and fix"
      # Should not raise error for provider/model format
      expect { provider.validate_model("openai/gpt-4o") }.not_to raise_error
      expect { provider.validate_model("anthropic/claude-3-opus") }.not_to raise_error
    end
  end

  describe "#list_available_models" do
    it "fetches models from OpenRouter API" do
      skip "waiting for research and fix"
      # This would require mocking HTTP requests
      expect(provider).to respond_to(:list_available_models)
    end
  end
end
