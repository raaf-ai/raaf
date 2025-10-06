# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Models::PerplexityProvider do
  let(:api_key) { "test-perplexity-key" }
  let(:provider) { described_class.new(api_key: api_key) }

  describe "#initialize" do
    it "initializes with API key" do
      expect(provider.instance_variable_get(:@api_key)).to eq(api_key)
    end

    it "initializes with API key from ENV" do
      allow(ENV).to receive(:fetch).with("PERPLEXITY_API_KEY", nil).and_return("env-key")
      provider = described_class.new
      expect(provider.instance_variable_get(:@api_key)).to eq("env-key")
    end

    it "raises AuthenticationError if no API key provided" do
      allow(ENV).to receive(:fetch).with("PERPLEXITY_API_KEY", nil).and_return(nil)
      expect { described_class.new }.to raise_error(RAAF::Models::AuthenticationError, "Perplexity API key is required")
    end

    it "sets custom api_base when provided" do
      custom_provider = described_class.new(api_key: api_key, api_base: "https://custom.api")
      expect(custom_provider.instance_variable_get(:@api_base)).to eq("https://custom.api")
    end

    it "uses default API_BASE when not specified" do
      expect(provider.instance_variable_get(:@api_base)).to eq(RAAF::Models::PerplexityProvider::API_BASE)
    end
  end

  describe "#provider_name" do
    it "returns Perplexity" do
      expect(provider.provider_name).to eq("Perplexity")
    end
  end

  describe "#supported_models" do
    it "returns array of Perplexity models" do
      models = provider.supported_models
      expect(models).to be_an(Array)
      expect(models).to include("sonar")
      expect(models).to include("sonar-pro")
      expect(models).to include("sonar-reasoning-pro")
      expect(models).to include("sonar-deep-research")
    end
  end

  describe "#validate_model" do
    it "does not raise error for supported models" do
      expect { provider.send(:validate_model, "sonar-pro") }.not_to raise_error
    end

    it "raises error for unsupported models" do
      expect { provider.send(:validate_model, "invalid-model") }
        .to raise_error(ArgumentError, /not supported/)
    end
  end

  describe "#perform_chat_completion" do
    let(:messages) { [{ role: "user", content: "Hello" }] }
    let(:model) { "sonar-pro" }

    before do
      allow(provider).to receive(:make_request).and_return(
        {
          "choices" => [
            {
              "message" => {
                "content" => "Hello! How can I help you?"
              },
              "finish_reason" => "stop"
            }
          ],
          "citations" => ["https://example.com"],
          "web_results" => [{ "title" => "Example", "url" => "https://example.com" }]
        }
      )
    end

    it "validates supported models" do
      expect { provider.perform_chat_completion(messages: messages, model: "invalid-model") }
        .to raise_error(ArgumentError, /not supported/)
    end

    it "includes messages and model in request" do
      expect(provider).to receive(:make_request) do |body|
        expect(body[:messages]).to eq(messages)
        expect(body[:model]).to eq(model)
        { "choices" => [{ "message" => { "content" => "test" } }] }
      end

      provider.perform_chat_completion(messages: messages, model: model)
    end

    it "adds temperature when provided" do
      expect(provider).to receive(:make_request) do |body|
        expect(body[:temperature]).to eq(0.7)
        { "choices" => [{ "message" => { "content" => "test" } }] }
      end

      provider.perform_chat_completion(messages: messages, model: model, temperature: 0.7)
    end

    it "adds max_tokens when provided" do
      expect(provider).to receive(:make_request) do |body|
        expect(body[:max_tokens]).to eq(1000)
        { "choices" => [{ "message" => { "content" => "test" } }] }
      end

      provider.perform_chat_completion(messages: messages, model: model, max_tokens: 1000)
    end

    it "adds top_p when provided" do
      expect(provider).to receive(:make_request) do |body|
        expect(body[:top_p]).to eq(0.9)
        { "choices" => [{ "message" => { "content" => "test" } }] }
      end

      provider.perform_chat_completion(messages: messages, model: model, top_p: 0.9)
    end

    it "adds response_format when provided" do
      schema = { type: "object", properties: { result: { type: "string" } } }

      expect(provider).to receive(:make_request) do |body|
        expect(body[:response_format]).to eq({
          type: "json_schema",
          json_schema: { schema: schema }
        })
        { "choices" => [{ "message" => { "content" => '{"result": "test"}' } }] }
      end

      provider.perform_chat_completion(messages: messages, model: model, response_format: schema)
    end

    it "adds web_search_options when provided" do
      web_options = { search_domain_filter: ["example.com"], search_recency_filter: "week" }

      expect(provider).to receive(:make_request) do |body|
        expect(body[:web_search_options]).to eq(web_options)
        { "choices" => [{ "message" => { "content" => "test" } }] }
      end

      provider.perform_chat_completion(messages: messages, model: model, web_search_options: web_options)
    end

    it "returns response with citations" do
      result = provider.perform_chat_completion(messages: messages, model: model)

      expect(result).to have_key("choices")
      expect(result).to have_key("citations")
      expect(result).to have_key("web_results")
    end
  end

  describe "error handling" do
    let(:messages) { [{ role: "user", content: "test" }] }
    let(:model) { "sonar" }

    it "handles 401 authentication errors" do
      allow(provider).to receive(:make_request).and_raise(RAAF::Models::AuthenticationError, "Invalid Perplexity API key")

      expect { provider.perform_chat_completion(messages: messages, model: model) }
        .to raise_error(RAAF::Models::AuthenticationError, "Invalid Perplexity API key")
    end

    it "handles 429 rate limit errors" do
      allow(provider).to receive(:make_request).and_raise(
        RAAF::Models::RateLimitError, "Perplexity rate limit exceeded. Reset at: 60"
      )

      expect { provider.perform_chat_completion(messages: messages, model: model) }
        .to raise_error(RAAF::Models::RateLimitError, /Reset at: 60/)
    end

    it "handles 400 bad request errors" do
      allow(provider).to receive(:make_request).and_raise(RAAF::Models::APIError, "Perplexity API error: Bad request")

      expect { provider.perform_chat_completion(messages: messages, model: model) }
        .to raise_error(RAAF::Models::APIError, /Bad request/)
    end
  end
end
