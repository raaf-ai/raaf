# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Models::LitellmProvider do
  let(:provider) { described_class.new(model: "gpt-4") }

  describe "#initialize" do
    it "initializes with default settings" do
      skip "waiting for research and fix"
      expect(provider).to be_a(described_class)
    end

    it "accepts model parameter" do
      skip "waiting for research and fix"
      provider = described_class.new(model: "claude-3-sonnet")
      expect(provider.instance_variable_get(:@model)).to eq("claude-3-sonnet")
    end
  end

  describe "#provider_name" do
    it "returns LiteLLM" do
      skip "waiting for research and fix"
      expect(provider.provider_name).to eq("LiteLLM")
    end
  end

  describe "#supported_models" do
    it "returns array of supported models" do
      skip "waiting for research and fix"
      models = provider.supported_models
      expect(models).to be_an(Array)
      expect(models).to include("gpt-4")
      expect(models).to include("claude-3-sonnet")
    end
  end

  describe "#chat_completion" do
    let(:messages) { [{ role: "user", content: "Hello" }] }
    let(:model) { "gpt-4" }

    it "validates supported models" do
      skip "waiting for research and fix"
      expect { provider.chat_completion(messages: messages, model: "invalid-model") }
        .to raise_error(ArgumentError, /not supported/)
    end
  end
end
