# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Models::XAIProvider do
  let(:api_key) { "test-xai-key" }
  let(:provider) { described_class.new(api_key: api_key) }

  describe "#initialize" do
    it "requires an API key" do
      expect { described_class.new }.to raise_error(RAAF::Models::AuthenticationError, /xAI API key is required/)
    end

    it "initializes with API key" do
      expect(provider.instance_variable_get(:@api_key)).to eq(api_key)
    end

    it "uses XAI_API_KEY environment variable by default" do
      ENV["XAI_API_KEY"] = "env-xai-key"
      provider = described_class.new
      expect(provider.instance_variable_get(:@api_key)).to eq("env-xai-key")
    ensure
      ENV.delete("XAI_API_KEY")
    end

    it "uses correct API base URL" do
      expect(provider.instance_variable_get(:@api_base)).to eq("https://api.x.ai/v1")
    end
  end

  describe "#provider_name" do
    it "returns xAI" do
      expect(provider.provider_name).to eq("xAI")
    end
  end

  describe "#supported_models" do
    it "returns array of Grok models" do
      models = provider.supported_models
      expect(models).to be_an(Array)
      expect(models).to include("grok-4")
      expect(models).to include("grok-3")
      expect(models).to include("grok-3-mini")
      expect(models).to include("grok-code-fast-1")
    end

    it "includes all defined models" do
      expect(provider.supported_models).to eq(RAAF::Models::XAIProvider::SUPPORTED_MODELS)
    end
  end

  describe "#vision_model?" do
    it "returns true for grok-4" do
      expect(provider.vision_model?("grok-4")).to be true
    end

    it "returns false for non-vision models" do
      expect(provider.vision_model?("grok-3")).to be false
      expect(provider.vision_model?("grok-3-mini")).to be false
    end
  end

  describe "#coding_model?" do
    it "returns true for coding-optimized models" do
      expect(provider.coding_model?("grok-code-fast-1")).to be true
      expect(provider.coding_model?("grok-4")).to be true
    end

    it "returns false for non-coding models" do
      expect(provider.coding_model?("grok-3-mini")).to be false
    end
  end

  describe "#chat_completion" do
    let(:messages) { [{ role: "user", content: "Hello" }] }
    let(:model) { "grok-4" }

    it "validates supported models" do
      expect { provider.chat_completion(messages: messages, model: "invalid-model") }
        .to raise_error(ArgumentError, /not supported/)
    end

    it "accepts all supported models" do
      RAAF::Models::XAIProvider::SUPPORTED_MODELS.each do |model|
        # We expect the method to NOT raise an error during validation
        # (It will fail later when trying to make actual API call, but that's fine for this test)
        expect do
          # Mock the actual HTTP request to avoid real API calls
          allow(provider).to receive(:make_request).and_return({
            "id" => "test-id",
            "choices" => [{ "message" => { "content" => "Test response" } }]
          })
          provider.chat_completion(messages: messages, model: model)
        end.not_to raise_error
      end
    end
  end

  describe "API integration", skip: "requires real API key" do
    let(:real_provider) { described_class.new(api_key: ENV["XAI_API_KEY"]) }

    before do
      skip "No XAI_API_KEY found" unless ENV["XAI_API_KEY"]
    end

    it "makes a real API call" do
      response = real_provider.chat_completion(
        messages: [{ role: "user", content: "Say 'Hello, World!' and nothing else." }],
        model: "grok-3-mini",
        max_tokens: 20
      )

      expect(response).to be_a(Hash)
      expect(response["choices"]).to be_an(Array)
      expect(response["choices"].first["message"]["content"]).to include("Hello")
    end

    it "supports streaming" do
      chunks = []
      real_provider.stream_completion(
        messages: [{ role: "user", content: "Count to 3" }],
        model: "grok-3-mini"
      ) do |chunk|
        chunks << chunk
      end

      expect(chunks).not_to be_empty
    end

    it "supports tool calling" do
      tools = [{
        type: "function",
        function: {
          name: "get_weather",
          description: "Get weather for a location",
          parameters: {
            type: "object",
            properties: {
              location: { type: "string" }
            },
            required: ["location"]
          }
        }
      }]

      response = real_provider.chat_completion(
        messages: [{ role: "user", content: "What's the weather in Tokyo?" }],
        model: "grok-4",
        tools: tools
      )

      expect(response).to be_a(Hash)
      # Tool calling should work (may or may not be invoked depending on LLM decision)
    end
  end
end
