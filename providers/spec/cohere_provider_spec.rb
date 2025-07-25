# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Models::CohereProvider do
  let(:api_key) { "test-cohere-key" }
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
    it "returns Cohere" do
      skip "waiting for research and fix"
      expect(provider.provider_name).to eq("Cohere")
    end
  end

  describe "#supported_models" do
    it "returns array of Cohere models" do
      skip "waiting for research and fix"
      models = provider.supported_models
      expect(models).to be_an(Array)
      expect(models).to include("command-r-plus")
      expect(models).to include("command-r")
    end
  end

  describe "#chat_completion" do
    let(:messages) { [{ role: "user", content: "Hello" }] }
    let(:model) { "command-r" }

    it "validates supported models" do
      skip "waiting for research and fix"
      expect { provider.chat_completion(messages: messages, model: "invalid-model") }
        .to raise_error(ArgumentError, /not supported/)
    end
  end
end
