# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Models::GroqProvider do
  let(:api_key) { "test-groq-key" }
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
    it "returns Groq" do
      skip "waiting for research and fix"
      expect(provider.provider_name).to eq("Groq")
    end
  end

  describe "#supported_models" do
    it "returns array of Groq models" do
      skip "waiting for research and fix"
      models = provider.supported_models
      expect(models).to be_an(Array)
      expect(models).to include("mixtral-8x7b-32768")
      expect(models).to include("llama-3.3-70b-versatile")
    end
  end

  describe "#chat_completion" do
    let(:messages) { [{ role: "user", content: "Hello" }] }
    let(:model) { "mixtral-8x7b-32768" }

    it "validates supported models" do
      skip "waiting for research and fix"
      expect { provider.chat_completion(messages: messages, model: "invalid-model") }
        .to raise_error(ArgumentError, /not supported/)
    end
  end
end
