# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::DecisionRegistry do
  describe ".detect" do
    it "detects Jev models" do
      expect(described_class.detect("jev-latest")).to eq(:jev)
      expect(described_class.detect("jev-1")).to eq(:jev)
    end

    it "detects OpenRouter's tilde-prefixed decision slugs" do
      expect(described_class.detect("~typesafe/jev-latest")).to eq(:openrouter)
      expect(described_class.detect("~other/model")).to eq(:openrouter)
    end

    it "returns nil for a chat model" do
      expect(described_class.detect("gpt-4o")).to be_nil
      expect(described_class.detect("claude-3-5-sonnet-20241022")).to be_nil
      expect(described_class.detect("openai/gpt-4o")).to be_nil
    end

    it "returns nil without a model name" do
      expect(described_class.detect(nil)).to be_nil
    end
  end

  describe "separation from ProviderRegistry" do
    it "keeps decision models out of the chat provider registry" do
      expect(RAAF::ProviderRegistry.detect("jev-latest")).to be_nil
      expect(RAAF::ProviderRegistry.registered?(:jev)).to be(false)
    end

    it "keeps chat providers out of the decision registry" do
      expect(described_class.registered?(:anthropic)).to be(false)
      expect(described_class.registered?(:openai)).to be(false)
    end
  end

  describe ".create" do
    it "builds the LLM-backed provider" do
      expect(described_class.create(:llm)).to be_a(RAAF::Models::Decision::LLMBackedProvider)
    end

    it "passes options to the provider" do
      expect(described_class.create(:llm, model: "gpt-4o-mini").model).to eq("gpt-4o-mini")
    end

    it "accepts a String name" do
      expect(described_class.create("llm")).to be_a(RAAF::Models::Decision::LLMBackedProvider)
    end

    it "raises for an unknown provider" do
      expect { described_class.create(:nope) }
        .to raise_error(ArgumentError, /Unknown decision provider: nope/)
    end
  end

  describe ".for_model" do
    it "raises when no provider matches" do
      expect { described_class.for_model("gpt-4o") }
        .to raise_error(ArgumentError, /No decision provider matches/)
    end
  end

  describe ".default" do
    around do |example|
      original = ENV.fetch("RAAF_DECISION_PROVIDER", nil)
      example.run
    ensure
      ENV["RAAF_DECISION_PROVIDER"] = original
    end

    def without_decision_keys
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("TYPESAFE_API_KEY").and_return(nil)
      allow(ENV).to receive(:[]).with("OPENROUTER_API_KEY").and_return(nil)
    end

    it "falls back to the LLM-backed provider with nothing configured" do
      ENV.delete("RAAF_DECISION_PROVIDER")
      without_decision_keys

      expect(described_class.default).to be_a(RAAF::Models::Decision::LLMBackedProvider)
    end

    it "honours RAAF_DECISION_PROVIDER" do
      ENV["RAAF_DECISION_PROVIDER"] = "llm"

      expect(described_class.default).to be_a(RAAF::Models::Decision::LLMBackedProvider)
    end

    it "ignores a blank RAAF_DECISION_PROVIDER" do
      ENV["RAAF_DECISION_PROVIDER"] = "  "
      without_decision_keys

      expect(described_class.default).to be_a(RAAF::Models::Decision::LLMBackedProvider)
    end
  end

  describe ".register" do
    let(:custom_provider) do
      Class.new(RAAF::Models::DecisionInterface) do
        def self.name = "SpecCustomDecisionProvider"

        def provider_name = "SpecCustom"
      end
    end

    before { stub_const("SpecCustomDecisionProvider", custom_provider) }

    it "registers a provider class" do
      described_class.register(:spec_custom, custom_provider)

      expect(described_class.registered?(:spec_custom)).to be(true)
      expect(described_class.create(:spec_custom)).to be_a(custom_provider)
      expect(described_class.providers).to include(:spec_custom)
    end

    it "registers a provider by class path" do
      described_class.register(:spec_custom_path, "SpecCustomDecisionProvider")

      expect(described_class.create(:spec_custom_path)).to be_a(custom_provider)
    end
  end

  describe ".providers" do
    it "lists the built-in decision providers" do
      expect(described_class.providers).to include(:jev, :typesafe, :openrouter, :llm)
    end
  end
end
