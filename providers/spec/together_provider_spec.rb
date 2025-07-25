# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Models::TogetherProvider do
  let(:api_key) { "test-together-key" }
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
  end

  describe "#provider_name" do
    it "returns Together" do
      skip "waiting for research and fix"
      expect(provider.provider_name).to eq("Together")
    end
  end

  describe "#supported_models" do
    it "returns array of Together models" do
      skip "waiting for research and fix"
      models = provider.supported_models
      expect(models).to be_an(Array)
      expect(models).to include("meta-llama/Llama-3.3-70B-Instruct-Turbo")
      expect(models).to include("meta-llama/Llama-2-70b-chat-hf")
    end
  end

  describe "#chat_completion" do
    let(:messages) { [{ role: "user", content: "Hello" }] }
    let(:model) { "meta-llama/Llama-3.3-70B-Instruct-Turbo" }

    it "validates supported models" do
      skip "waiting for research and fix"
      expect { provider.chat_completion(messages: messages, model: "invalid-model") }
        .to raise_error(ArgumentError, /not supported/)
    end
  end
end
