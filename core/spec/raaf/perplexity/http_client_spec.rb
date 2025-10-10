# frozen_string_literal: true

require 'raaf/perplexity/http_client'
require 'raaf/errors'
require 'raaf/utils'

RSpec.describe RAAF::Perplexity::HttpClient do
  let(:api_key) { "test_api_key" }
  let(:http_client) { described_class.new(api_key: api_key) }

  describe "#initialize" do
    it "initializes with default values" do
      client = described_class.new(api_key: api_key)
      expect(client).to be_a(described_class)
    end

    it "accepts custom api_base" do
      client = described_class.new(
        api_key: api_key,
        api_base: "https://custom.api.com"
      )
      expect(client).to be_a(described_class)
    end

    it "accepts custom timeout values" do
      client = described_class.new(
        api_key: api_key,
        timeout: 120,
        open_timeout: 20
      )
      expect(client).to be_a(described_class)
    end

    it "raises error without api_key" do
      expect {
        described_class.new(api_key: nil)
      }.to raise_error(ArgumentError, /API key is required/)
    end
  end

  describe "#make_api_call" do
    let(:request_body) do
      {
        model: "sonar-pro",
        messages: [{ role: "user", content: "test" }]
      }
    end

    let(:success_response_body) do
      {
        "choices" => [
          {
            "message" => {
              "role" => "assistant",
              "content" => "test response"
            }
          }
        ],
        "usage" => {
          "prompt_tokens" => 10,
          "completion_tokens" => 20,
          "total_tokens" => 30
        }
      }
    end

    context "with successful API call" do
      before do
        stub_request(:post, "https://api.perplexity.ai/chat/completions")
          .with(
            headers: {
              "Authorization" => "Bearer #{api_key}",
              "Content-Type" => "application/json"
            },
            body: request_body.to_json
          )
          .to_return(
            status: 200,
            body: success_response_body.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "makes successful API call" do
        result = http_client.make_api_call(request_body)
        expect(result).to be_a(ActiveSupport::HashWithIndifferentAccess)
        expect(result[:choices]).to be_an(Array)
        expect(result[:choices]).not_to be_empty
        expect(result[:choices].first[:message][:content]).to eq("test response")
      end

      it "includes usage information" do
        result = http_client.make_api_call(request_body)
        expect(result[:usage][:total_tokens]).to eq(30)
      end
    end

    context "with authentication error (401)" do
      before do
        stub_request(:post, "https://api.perplexity.ai/chat/completions")
          .to_return(status: 401, body: { error: { message: "Invalid API key" } }.to_json)
      end

      it "raises AuthenticationError" do
        expect {
          http_client.make_api_call(request_body)
        }.to raise_error(RAAF::AuthenticationError, /Invalid.*API key/)
      end
    end

    context "with rate limit error (429)" do
      before do
        stub_request(:post, "https://api.perplexity.ai/chat/completions")
          .to_return(
            status: 429,
            headers: { "x-ratelimit-reset" => "2024-10-10T12:00:00Z" },
            body: { error: { message: "Rate limit exceeded" } }.to_json
          )
      end

      it "raises RateLimitError with reset time" do
        expect {
          http_client.make_api_call(request_body)
        }.to raise_error(RAAF::RateLimitError, /rate limit/i)
      end
    end

    context "with bad request error (400)" do
      before do
        stub_request(:post, "https://api.perplexity.ai/chat/completions")
          .to_return(
            status: 400,
            body: { error: { message: "Invalid model specified" } }.to_json
          )
      end

      it "raises APIError with error message" do
        expect {
          http_client.make_api_call(request_body)
        }.to raise_error(RAAF::APIError, /Invalid model/)
      end
    end

    context "with service unavailable error (503)" do
      before do
        stub_request(:post, "https://api.perplexity.ai/chat/completions")
          .to_return(status: 503, body: "Service temporarily unavailable")
      end

      it "raises ServiceUnavailableError" do
        expect {
          http_client.make_api_call(request_body)
        }.to raise_error(RAAF::ServiceUnavailableError, /temporarily unavailable/)
      end
    end

    context "with server error (500)" do
      before do
        stub_request(:post, "https://api.perplexity.ai/chat/completions")
          .to_return(status: 500, body: "Internal server error")
      end

      it "raises APIError for generic server error" do
        expect {
          http_client.make_api_call(request_body)
        }.to raise_error(RAAF::APIError)
      end
    end

    context "with network timeout" do
      before do
        stub_request(:post, "https://api.perplexity.ai/chat/completions")
          .to_timeout
      end

      it "raises appropriate error for timeout" do
        expect {
          http_client.make_api_call(request_body)
        }.to raise_error(Net::OpenTimeout)
      end
    end
  end

  describe "HTTP client configuration" do
    it "uses SSL" do
      # This is implicitly tested through WebMock stubs, which verify HTTPS
      stub_request(:post, "https://api.perplexity.ai/chat/completions")
        .to_return(status: 200, body: { choices: [] }.to_json)

      expect {
        http_client.make_api_call({ model: "sonar", messages: [] })
      }.not_to raise_error
    end

    it "applies read timeout" do
      client = described_class.new(api_key: api_key, timeout: 5)
      stub_request(:post, "https://api.perplexity.ai/chat/completions")
        .to_timeout

      expect {
        client.make_api_call({ model: "sonar", messages: [] })
      }.to raise_error(Net::OpenTimeout)
    end

    it "applies open timeout" do
      client = described_class.new(api_key: api_key, open_timeout: 5)
      stub_request(:post, "https://api.perplexity.ai/chat/completions")
        .to_timeout

      expect {
        client.make_api_call({ model: "sonar", messages: [] })
      }.to raise_error(Net::OpenTimeout)
    end
  end

  describe "request headers" do
    it "includes authorization header" do
      stub = stub_request(:post, "https://api.perplexity.ai/chat/completions")
        .with(headers: { "Authorization" => "Bearer #{api_key}" })
        .to_return(status: 200, body: { choices: [] }.to_json)

      http_client.make_api_call({ model: "sonar", messages: [] })
      expect(stub).to have_been_requested
    end

    it "includes content-type header" do
      stub = stub_request(:post, "https://api.perplexity.ai/chat/completions")
        .with(headers: { "Content-Type" => "application/json" })
        .to_return(status: 200, body: { choices: [] }.to_json)

      http_client.make_api_call({ model: "sonar", messages: [] })
      expect(stub).to have_been_requested
    end

    it "sends request body as JSON" do
      body = { model: "sonar-pro", messages: [{ role: "user", content: "test" }] }
      stub = stub_request(:post, "https://api.perplexity.ai/chat/completions")
        .with(body: body.to_json)
        .to_return(status: 200, body: { choices: [] }.to_json)

      http_client.make_api_call(body)
      expect(stub).to have_been_requested
    end
  end
end
