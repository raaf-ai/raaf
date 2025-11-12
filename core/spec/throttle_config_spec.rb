# frozen_string_literal: true

require "spec_helper"
require_relative "../lib/raaf/throttle_config"

RSpec.describe RAAF::ThrottleConfig do
  describe "::DEFAULT_RPM_LIMITS" do
    it "includes limits for all major providers" do
      expect(described_class::DEFAULT_RPM_LIMITS).to include(
        gemini: 10,
        perplexity: 20,
        openai: 500,
        responses: 500,
        anthropic: 1000,
        groq: 30,
        cohere: 100,
        xai: 60,
        moonshot: 60
      )
    end

    it "includes nil for providers without defaults" do
      expect(described_class::DEFAULT_RPM_LIMITS[:litellm]).to be_nil
      expect(described_class::DEFAULT_RPM_LIMITS[:openrouter]).to be_nil
    end

    it "is frozen" do
      expect(described_class::DEFAULT_RPM_LIMITS).to be_frozen
    end
  end

  describe ".default_rpm_for" do
    context "with symbol key" do
      it "returns default RPM for known provider" do
        expect(described_class.default_rpm_for(:gemini)).to eq(10)
        expect(described_class.default_rpm_for(:openai)).to eq(500)
        expect(described_class.default_rpm_for(:anthropic)).to eq(1000)
      end

      it "returns nil for provider with no default" do
        expect(described_class.default_rpm_for(:litellm)).to be_nil
        expect(described_class.default_rpm_for(:openrouter)).to be_nil
      end

      it "returns nil for unknown provider" do
        expect(described_class.default_rpm_for(:unknown)).to be_nil
      end
    end

    context "with string key" do
      it "returns default RPM for known provider" do
        expect(described_class.default_rpm_for("gemini")).to eq(10)
        expect(described_class.default_rpm_for("openai")).to eq(500)
      end
    end

    context "with environment variable override" do
      around do |example|
        original_value = ENV["RAAF_THROTTLE_GEMINI_RPM"]
        ENV["RAAF_THROTTLE_GEMINI_RPM"] = "60"
        example.run
        if original_value
          ENV["RAAF_THROTTLE_GEMINI_RPM"] = original_value
        else
          ENV.delete("RAAF_THROTTLE_GEMINI_RPM")
        end
      end

      it "uses environment variable over default" do
        expect(described_class.default_rpm_for(:gemini)).to eq(60)
      end
    end

    context "with empty environment variable" do
      around do |example|
        original_value = ENV["RAAF_THROTTLE_GEMINI_RPM"]
        ENV["RAAF_THROTTLE_GEMINI_RPM"] = ""
        example.run
        if original_value
          ENV["RAAF_THROTTLE_GEMINI_RPM"] = original_value
        else
          ENV.delete("RAAF_THROTTLE_GEMINI_RPM")
        end
      end

      it "uses default when env var is empty" do
        expect(described_class.default_rpm_for(:gemini)).to eq(10)
      end
    end
  end

  describe ".rpm_for_provider" do
    context "with provider instance" do
      let(:mock_provider_class) do
        Class.new do
          def self.name
            "TestApp::GeminiProvider"
          end
        end
      end

      it "extracts provider name from class" do
        provider = mock_provider_class.new
        expect(described_class.rpm_for_provider(provider)).to eq(10)
      end
    end

    context "with provider class" do
      let(:openai_provider_class) do
        Class.new do
          def self.name
            "RAAF::Models::OpenAIProvider"
          end
        end
      end

      it "extracts provider name from class" do
        expect(described_class.rpm_for_provider(openai_provider_class)).to eq(500)
      end
    end

    context "with ResponsesProvider" do
      let(:responses_provider_class) do
        Class.new do
          def self.name
            "RAAF::Models::ResponsesProvider"
          end
        end
      end

      it "detects ResponsesProvider specifically" do
        expect(described_class.rpm_for_provider(responses_provider_class)).to eq(500)
      end
    end

    context "with unknown provider" do
      let(:unknown_provider_class) do
        Class.new do
          def self.name
            "MyApp::CustomProvider"
          end
        end
      end

      it "returns nil for unknown provider" do
        expect(described_class.rpm_for_provider(unknown_provider_class)).to be_nil
      end
    end

    context "with invalid input" do
      it "returns nil for class without Provider suffix" do
        non_provider_class = Class.new do
          def self.name
            "MyApp::NotAProvider"
          end
        end

        expect(described_class.rpm_for_provider(non_provider_class)).to be_nil
      end
    end
  end

  describe ".all_limits" do
    it "returns all default limits" do
      limits = described_class.all_limits
      expect(limits).to include(
        gemini: 10,
        openai: 500,
        anthropic: 1000
      )
    end

    it "includes environment variable overrides" do
      original_value = ENV["RAAF_THROTTLE_GEMINI_RPM"]
      ENV["RAAF_THROTTLE_GEMINI_RPM"] = "100"

      limits = described_class.all_limits
      expect(limits[:gemini]).to eq(100)

      if original_value
        ENV["RAAF_THROTTLE_GEMINI_RPM"] = original_value
      else
        ENV.delete("RAAF_THROTTLE_GEMINI_RPM")
      end
    end
  end

  describe ".configured?" do
    it "returns true for providers with default limits" do
      expect(described_class.configured?(:gemini)).to be true
      expect(described_class.configured?(:openai)).to be true
    end

    it "returns false for providers without default limits" do
      expect(described_class.configured?(:litellm)).to be false
      expect(described_class.configured?(:openrouter)).to be false
    end

    it "returns false for unknown providers" do
      expect(described_class.configured?(:unknown)).to be false
    end

    it "returns true with environment variable override" do
      original_value = ENV["RAAF_THROTTLE_UNKNOWN_RPM"]
      ENV["RAAF_THROTTLE_UNKNOWN_RPM"] = "50"

      expect(described_class.configured?(:unknown)).to be true

      if original_value
        ENV["RAAF_THROTTLE_UNKNOWN_RPM"] = original_value
      else
        ENV.delete("RAAF_THROTTLE_UNKNOWN_RPM")
      end
    end
  end
end
