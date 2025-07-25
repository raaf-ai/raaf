# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Models::AnthropicProvider do
  let(:api_key) { "test-anthropic-key" }
  let(:provider) { described_class.new(api_key: api_key) }

  describe "#initialize" do
    it "requires an API key" do
      expect { described_class.new }.to raise_error(RAAF::AuthenticationError)
    end

    it "initializes with API key" do
      expect(provider.instance_variable_get(:@api_key)).to eq(api_key)
    end
  end

  describe "#provider_name" do
    it "returns Anthropic" do
      expect(provider.provider_name).to eq("Anthropic")
    end
  end

  describe "#supported_models" do
    it "returns array of Claude models" do
      models = provider.supported_models
      expect(models).to be_an(Array)
      expect(models).to include("claude-3-5-sonnet-20241022")
      expect(models).to include("claude-3-opus-20240229")
    end
  end

  describe "#chat_completion" do
    let(:messages) { [{ role: "user", content: "Hello" }] }
    let(:model) { "claude-3-5-sonnet-20241022" }

    it "validates supported models" do
      expect { provider.chat_completion(messages: messages, model: "invalid-model") }
        .to raise_error(ArgumentError, /not supported/)
    end
  end
end
