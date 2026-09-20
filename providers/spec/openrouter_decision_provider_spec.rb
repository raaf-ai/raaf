# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Models::OpenRouterDecisionProvider do
  subject(:provider) { described_class.new(api_key: "test-key") }

  let(:endpoint) { "https://openrouter.ai/api/alpha/decisions" }
  let(:ticket) { "Help! My payouts have been failing for 3 days." }
  let(:urgency) { RAAF::Models::Decision::Noul.new(instructions: "The message conveys urgency") }

  def stub_decisions(body, status: 200, headers: {})
    stub_request(:post, endpoint).to_return(
      status: status,
      body: body.is_a?(String) ? body : body.to_json,
      headers: { "Content-Type" => "application/json" }.merge(headers)
    )
  end

  def answers(body)
    { "model" => "~typesafe/jev-latest", "answers" => body }
  end

  describe "#initialize" do
    it "reads the API key from OPENROUTER_API_KEY" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("OPENROUTER_API_KEY", nil).and_return("from-env")

      expect(described_class.new.instance_variable_get(:@api_key)).to eq("from-env")
    end

    it "raises without an API key" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("OPENROUTER_API_KEY", nil).and_return(nil)

      expect { described_class.new }.to raise_error(RAAF::Models::AuthenticationError, /OpenRouter API key/)
    end

    it "defaults to the tilde-prefixed Jev slug" do
      expect(provider.model).to eq("~typesafe/jev-latest")
    end
  end

  describe "#decide" do
    it "posts the same body to OpenRouter's decisions path" do
      stub_decisions(answers("is_urgent" => { "type" => "noul", "noul" => 0.98 }))

      provider.decide(state: ticket, questions: { is_urgent: urgency })

      expect(a_request(:post, endpoint).with do |request|
        body = JSON.parse(request.body)
        body["model"] == "~typesafe/jev-latest" &&
          body["state"] == ticket &&
          body["questions"] == {
            "is_urgent" => { "type" => "noul", "instructions" => "The message conveys urgency" }
          }
      end).to have_been_made
    end

    it "authenticates with a bearer token" do
      stub_decisions(answers("is_urgent" => { "type" => "noul", "noul" => 0.98 }))

      provider.decide(state: ticket, questions: { is_urgent: urgency })

      expect(a_request(:post, endpoint).with(headers: { "Authorization" => "Bearer test-key" }))
        .to have_been_made
    end

    it "reads the answers back" do
      stub_decisions(answers("is_urgent" => { "type" => "noul", "noul" => 0.98 }))

      result = provider.decide(state: ticket, questions: { is_urgent: urgency })

      expect(result[:is_urgent].probability).to eq(0.98)
      expect(result.provider).to eq("OpenRouter")
      expect(result.model).to eq("~typesafe/jev-latest")
    end

    it "routes any decision model OpenRouter carries" do
      stub_decisions(answers("is_urgent" => { "type" => "noul", "noul" => 0.5 }))

      provider.decide(state: ticket, questions: { is_urgent: urgency }, model: "~other/model")

      expect(a_request(:post, endpoint).with do |request|
        JSON.parse(request.body)["model"] == "~other/model"
      end).to have_been_made
    end
  end

  describe "attribution headers" do
    it "sends the ranking headers when a site is configured" do
      stub_decisions(answers("answer" => { "type" => "noul", "noul" => 0.5 }))

      described_class.new(api_key: "test-key", site_url: "https://example.com", site_name: "Example")
                     .noul(state: ticket, instructions: "x")

      expect(a_request(:post, endpoint)
        .with(headers: { "HTTP-Referer" => "https://example.com", "X-Title" => "Example" }))
        .to have_been_made
    end

    it "omits them when no site is configured" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("OPENROUTER_SITE_URL", nil).and_return(nil)
      allow(ENV).to receive(:fetch).with("OPENROUTER_SITE_NAME", nil).and_return(nil)
      stub_decisions(answers("answer" => { "type" => "noul", "noul" => 0.5 }))

      provider.noul(state: ticket, instructions: "x")

      expect(a_request(:post, endpoint)).to have_been_made
      expect(a_request(:post, endpoint).with(headers: { "HTTP-Referer" => "https://example.com" }))
        .not_to have_been_made
    end
  end

  describe "error handling" do
    it "raises AuthenticationError on 401" do
      stub_decisions({ "error" => { "message" => "no credits" } }, status: 401)

      expect { provider.noul(state: ticket, instructions: "x") }
        .to raise_error(RAAF::Models::AuthenticationError, /Invalid OpenRouter API key/)
    end

    it "surfaces the API's message on a 400" do
      stub_decisions({ "error" => { "message" => "unknown model" } }, status: 400)

      expect { provider.noul(state: ticket, instructions: "x") }
        .to raise_error(RAAF::Models::APIError, /unknown model/)
    end
  end

  # OpenRouterProvider waves through any slug containing a slash, so a decision
  # model passes its validation and reaches /chat/completions, where it has no
  # business being. Routing by model name has to send these here instead.
  describe "telling it apart from the chat provider" do
    it "is what the decision registry routes a tilde slug to" do
      expect(RAAF::DecisionRegistry.detect("~typesafe/jev-latest")).to eq(:openrouter)
      expect(RAAF::DecisionRegistry.for_model("~typesafe/jev-latest", api_key: "k")).to be_a(described_class)
    end

    it "is not reachable through the chat provider's model list" do
      expect(RAAF::Models::OpenRouterProvider::SUPPORTED_MODELS).not_to include("~typesafe/jev-latest")
    end
  end
end
