# frozen_string_literal: true

require "spec_helper"
require "webmock/rspec"

RSpec.describe RAAF::Models::ResponsesProvider, "Basic Coverage Tests" do
  let(:api_key) { "sk-test-key" }
  let(:provider) { described_class.new(api_key: api_key) }

  before do
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  after do
    WebMock.reset!
  end

  describe "#responses_completion - basic functionality" do
    let(:messages) { [{ role: "user", content: "Hello" }] }
    let(:model) { "gpt-4o" }

    let(:mock_response) do
      {
        id: "resp_test_123",
        output: [
          {
            type: "message",
            role: "assistant",
            content: [{ type: "text", text: "Hello! How can I help you?" }]
          }
        ],
        usage: { input_tokens: 15, output_tokens: 25, total_tokens: 40 }
      }
    end

    it "processes basic completion request" do
      stub_request(:post, "https://api.openai.com/v1/responses")
        .to_return(status: 200, body: mock_response.to_json)

      result = provider.responses_completion(
        messages: messages,
        model: model
      )

      expect(result).to include(:id, :output, :usage)
      expect(result[:id]).to eq("resp_test_123")
    end

    context "with tools parameter" do
      let(:tools) do
        [
          {
            type: "function",
            function: {
              name: "get_weather",
              description: "Get current weather",
              parameters: {
                type: "object",
                properties: { location: { type: "string" } },
                required: ["location"]
              }
            }
          }
        ]
      end

      it "processes tools parameter correctly" do
        stub_request(:post, "https://api.openai.com/v1/responses")
          .to_return(status: 200, body: mock_response.to_json)

        result = provider.responses_completion(
          messages: messages,
          model: model,
          tools: tools
        )

        expect(result).to include(:id, :output, :usage)
        expect(WebMock).to have_requested(:post, "https://api.openai.com/v1/responses")
          .with(body: hash_including("tools"))
      end
    end

    context "with additional parameters" do
      it "handles temperature, max_tokens, and other options" do
        stub_request(:post, "https://api.openai.com/v1/responses")
          .to_return(status: 200, body: mock_response.to_json)

        provider.responses_completion(
          messages: messages,
          model: model,
          temperature: 0.7,
          max_tokens: 150,
          top_p: 0.9
        )

        expect(WebMock).to have_requested(:post, "https://api.openai.com/v1/responses")
          .with(body: hash_including("temperature", "max_output_tokens", "top_p"))
      end
    end
  end

  describe "API error handling" do
    let(:messages) { [{ role: "user", content: "Test message" }] }
    let(:model) { "gpt-4o" }

    it "handles 400 Bad Request errors" do
      error_body = {
        error: {
          message: "Invalid request format",
          type: "invalid_request_error",
          code: "bad_request"
        }
      }

      stub_request(:post, "https://api.openai.com/v1/responses")
        .to_return(status: 400, body: error_body.to_json)

      expect {
        provider.responses_completion(messages: messages, model: model)
      }.to raise_error(RAAF::Models::APIError, /Invalid request format/)
    end

    it "handles 401 Unauthorized errors" do
      error_body = {
        error: {
          message: "Invalid API key",
          type: "authentication_error"
        }
      }

      stub_request(:post, "https://api.openai.com/v1/responses")
        .to_return(status: 401, body: error_body.to_json)

      expect {
        provider.responses_completion(messages: messages, model: model)
      }.to raise_error(RAAF::Models::APIError, /Invalid API key/)
    end

    it "handles network timeouts" do
      stub_request(:post, "https://api.openai.com/v1/responses")
        .to_timeout

      expect {
        provider.responses_completion(messages: messages, model: model)
      }.to raise_error(Timeout::Error)
    end
  end

  describe "authentication and headers" do
    let(:messages) { [{ role: "user", content: "Test" }] }
    let(:model) { "gpt-4o" }

    it "includes correct authorization header" do
      stub_request(:post, "https://api.openai.com/v1/responses")
        .to_return(status: 200, body: { id: "test", output: [], usage: {} }.to_json)

      provider.responses_completion(messages: messages, model: model)

      expect(WebMock).to have_requested(:post, "https://api.openai.com/v1/responses")
        .with(headers: { 'Authorization' => 'Bearer sk-test-key' })
    end

    it "includes correct content-type header" do
      stub_request(:post, "https://api.openai.com/v1/responses")
        .to_return(status: 200, body: { id: "test", output: [], usage: {} }.to_json)

      provider.responses_completion(messages: messages, model: model)

      expect(WebMock).to have_requested(:post, "https://api.openai.com/v1/responses")
        .with(headers: { 'Content-Type' => 'application/json' })
    end

    it "includes user-agent header" do
      stub_request(:post, "https://api.openai.com/v1/responses")
        .to_return(status: 200, body: { id: "test", output: [], usage: {} }.to_json)

      provider.responses_completion(messages: messages, model: model)

      expect(WebMock).to have_requested(:post, "https://api.openai.com/v1/responses")
        .with(headers: { 'User-Agent' => /Agents/ })
    end
  end

  describe "streaming functionality" do
    let(:messages) { [{ role: "user", content: "Stream test" }] }
    let(:model) { "gpt-4o" }

    context "stream_completion method" do
      it "enables streaming in responses_completion" do
        expect(provider).to receive(:responses_completion).with(
          messages: messages,
          model: model,
          tools: nil,
          stream: true
        )

        provider.stream_completion(messages: messages, model: model) {}
      end

      it "passes tools parameter to streaming" do
        tools = [{ type: "function", function: { name: "test" } }]

        expect(provider).to receive(:responses_completion).with(
          messages: messages,
          model: model,
          tools: tools,
          stream: true
        )

        provider.stream_completion(messages: messages, model: model, tools: tools) {}
      end
    end
  end

  describe "edge cases" do
    let(:messages) { [{ role: "user", content: "Test" }] }
    let(:model) { "gpt-4o" }

    it "handles empty messages array" do
      stub_request(:post, "https://api.openai.com/v1/responses")
        .to_return(status: 200, body: { id: "test", output: [], usage: {} }.to_json)

      result = provider.responses_completion(messages: [], model: model)
      expect(result[:id]).to eq("test")
    end

    it "handles very large message content" do
      large_content = "x" * 1000
      large_messages = [{ role: "user", content: large_content }]

      stub_request(:post, "https://api.openai.com/v1/responses")
        .to_return(status: 200, body: { id: "test", output: [], usage: {} }.to_json)

      expect {
        provider.responses_completion(messages: large_messages, model: model)
      }.not_to raise_error
    end

    it "handles non-JSON response bodies" do
      stub_request(:post, "https://api.openai.com/v1/responses")
        .to_return(status: 200, body: "Not JSON")

      expect {
        provider.responses_completion(messages: messages, model: model)
      }.to raise_error(JSON::ParserError)
    end
  end

  describe "performance" do
    let(:messages) { [{ role: "user", content: "Performance test" }] }
    let(:model) { "gpt-4o" }

    it "completes requests within reasonable time" do
      stub_request(:post, "https://api.openai.com/v1/responses")
        .to_return(status: 200, body: { id: "test", output: [], usage: {} }.to_json)

      start_time = Time.now
      provider.responses_completion(messages: messages, model: model)
      duration = Time.now - start_time

      expect(duration).to be < 1.0 # Should complete within 1 second (mocked)
    end
  end
end