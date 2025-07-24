# frozen_string_literal: true

require "spec_helper"

require "async"
require "async/http"
require_relative "../../lib/raaf/streaming/async"

RSpec.describe RAAF::Async::Providers::ResponsesProvider do
  let(:api_key) { "test-api-key" }
  let(:provider) { described_class.new(api_key: api_key) }
  let(:messages) { [{ role: "user", content: "Hello" }] }

  describe "#initialize" do
    it "inherits from base ResponsesProvider" do
      expect(provider).to be_a(RAAF::Models::ResponsesProvider)
    end

    it "includes Async::Base module" do
      expect(provider.class.ancestors).to include(RAAF::Async::Base)
    end

    it "sets up HTTP endpoint" do
      endpoint = provider.instance_variable_get(:@endpoint)
      expect(endpoint).to be_a(Async::HTTP::Endpoint)
    end

    it "accepts custom base URL" do
      custom_provider = described_class.new(
        api_key: api_key,
        base_url: "https://custom-api.example.com"
      )
      endpoint = custom_provider.instance_variable_get(:@endpoint)
      expect(endpoint.to_s).to include("custom-api.example.com")
    end
  end

  describe "#async_chat_completion" do
    let(:mock_response_data) do
      {
        "id" => "response_123",
        "object" => "response",
        "created" => Time.now.to_i,
        "model" => "gpt-4o",
        "choices" => [
          {
            "index" => 0,
            "message" => {
              "role" => "assistant",
              "content" => "Hello! How can I help you?"
            },
            "finish_reason" => "stop"
          }
        ],
        "usage" => {
          "prompt_tokens" => 10,
          "completion_tokens" => 15,
          "total_tokens" => 25
        }
      }
    end

    before do
      # Mock the async HTTP request
      allow(provider).to receive(:make_async_request).and_return(mock_response_data)
    end

    it "makes async API calls" do
      Async do
        result = provider.async_chat_completion(
          messages: messages,
          model: "gpt-4o"
        ).wait

        expect(result).to be_a(Hash)
        expect(result["choices"]).not_to be_empty
      end
    end

    it "uses default model when none specified" do
      expect(provider).to receive(:make_async_request) do |_path, body|
        expect(body[:model]).to eq("gpt-4o-mini")
        mock_response_data
      end

      Async do
        provider.async_chat_completion(messages: messages).wait
      end
    end

    it "includes tools in request body when provided" do
      tools = [
        {
          type: "function",
          function: {
            name: "test_tool",
            description: "A test tool"
          }
        }
      ]

      expect(provider).to receive(:make_async_request) do |_path, body|
        expect(body[:tools]).to eq(tools)
        mock_response_data
      end

      Async do
        provider.async_chat_completion(
          messages: messages,
          tools: tools
        ).wait
      end
    end

    it "includes response_format when provided" do
      response_format = {
        type: "json_schema",
        json_schema: {
          name: "test_schema",
          strict: true,
          schema: { type: "object" }
        }
      }

      expect(provider).to receive(:make_async_request) do |_path, body|
        expect(body[:response_format]).to eq(response_format)
        mock_response_data
      end

      Async do
        provider.async_chat_completion(
          messages: messages,
          response_format: response_format
        ).wait
      end
    end

    it "includes additional parameters" do
      expect(provider).to receive(:make_async_request) do |_path, body|
        expect(body[:temperature]).to eq(0.7)
        expect(body[:max_completion_tokens]).to eq(100)
        mock_response_data
      end

      Async do
        provider.async_chat_completion(
          messages: messages,
          temperature: 0.7,
          max_completion_tokens: 100
        ).wait
      end
    end
  end

  describe "#chat_completion" do
    let(:mock_response_data) do
      {
        "choices" => [
          {
            "message" => {
              "role" => "assistant",
              "content" => "Response"
            }
          }
        ]
      }
    end

    it "uses async version when in async context" do
      allow(provider).to receive_messages(in_async_context?: true, async_chat_completion: double(wait: mock_response_data))

      result = provider.chat_completion(messages: messages)
      expect(result).to eq(mock_response_data)
    end

    it "falls back to synchronous version outside async context" do
      allow(provider).to receive(:in_async_context?).and_return(false)

      # Mock the superclass method
      allow_any_instance_of(RAAF::Models::ResponsesProvider)
        .to receive(:chat_completion).and_return(mock_response_data)

      result = provider.chat_completion(messages: messages)
      expect(result).to eq(mock_response_data)
    end
  end

  describe "#make_async_request" do
    let(:mock_client) { double("AsyncHTTPClient") }
    let(:mock_response) { double("AsyncHTTPResponse") }
    let(:response_body) { '{"test": "response"}' }

    before do
      allow(provider).to receive(:async_client).and_return(mock_client)
      allow(mock_response).to receive_messages(success?: true, read: response_body)
      allow(mock_client).to receive(:post).and_return(mock_response)
    end

    it "creates proper HTTP request" do
      expect(mock_client).to receive(:post) do |path, headers, _body|
        expect(path).to eq("/v1/responses")
        expect(headers["Content-Type"]).to eq("application/json")
        mock_response
      end

      Async do
        provider.send(:make_async_request, "/v1/responses", { test: "data" })
      end
    end

    it "includes proper headers" do
      expect(mock_client).to receive(:post) do |_path, headers, _body|
        expect(headers["Content-Type"]).to eq("application/json")
        expect(headers["Authorization"]).to eq("Bearer #{api_key}")
        expect(headers["OpenAI-Beta"]).to eq("agents-v1")
        mock_response
      end

      Async do
        provider.send(:make_async_request, "/v1/responses", { test: "data" })
      end
    end

    it "parses JSON response" do
      Async do
        result = provider.send(:make_async_request, "/v1/responses", {}).wait
        expect(result).to eq({ "test" => "response" })
      end
    end

    it "handles API errors" do
      error_response = double("ErrorResponse")
      allow(error_response).to receive_messages(success?: false, status: 401, read: '{"error": {"message": "Unauthorized"}}')
      allow(mock_client).to receive(:post).and_return(error_response)

      Async do
        expect do
          provider.send(:make_async_request, "/v1/responses", {}).wait
        end.to raise_error(RAAF::AuthenticationError, /Unauthorized/)
      end
    end

    it "handles timeout errors" do
      allow(mock_client).to receive(:post).and_raise(Async::TimeoutError, "Request timed out")

      Async do
        expect do
          provider.send(:make_async_request, "/v1/responses", {}).wait
        end.to raise_error(RAAF::APIError, /Request timeout/)
      end
    end

    it "handles general request errors" do
      allow(mock_client).to receive(:post).and_raise(StandardError, "Connection failed")

      Async do
        expect do
          provider.send(:make_async_request, "/v1/responses", {}).wait
        end.to raise_error(RAAF::APIError, /Request failed/)
      end
    end
  end

  describe "#build_request_body" do
    it "builds proper request body structure" do
      tools = [{ type: "function", function: { name: "test" } }]
      response_format = { type: "json_schema" }
      kwargs = { temperature: 0.5, max_completion_tokens: 50 }

      body = provider.send(
        :build_request_body,
        messages,
        "gpt-4o",
        tools,
        response_format,
        kwargs
      )

      expect(body[:model]).to eq("gpt-4o")
      expect(body[:messages]).not_to be_empty
      expect(body[:tools]).to eq(tools)
      expect(body[:response_format]).to eq(response_format)
      expect(body[:temperature]).to eq(0.5)
      expect(body[:max_completion_tokens]).to eq(50)
    end

    it "omits optional fields when not provided" do
      body = provider.send(:build_request_body, messages, "gpt-4o", nil, nil, {})

      expect(body).to have_key(:model)
      expect(body).to have_key(:messages)
      expect(body).not_to have_key(:tools)
      expect(body).not_to have_key(:response_format)
    end
  end

  describe "#parse_response" do
    it "converts responses API format to chat completion format" do
      responses_format = {
        "id" => "response_123",
        "created" => 1_234_567_890,
        "model" => "gpt-4o",
        "choices" => [
          {
            "message" => {
              "role" => "assistant",
              "content" => "Hello"
            },
            "finish_reason" => "stop"
          }
        ],
        "usage" => { "total_tokens" => 15 }
      }

      result = provider.send(:parse_response, responses_format)

      expect(result["object"]).to eq("chat.completion")
      expect(result["id"]).to eq("response_123")
      expect(result["choices"][0]["index"]).to eq(0)
      expect(result["choices"][0]["message"]["content"]).to eq("Hello")
      expect(result["usage"]).to eq({ "total_tokens" => 15 })
    end

    it "returns response as-is when not in expected format" do
      unexpected_format = { "custom_field" => "value" }
      result = provider.send(:parse_response, unexpected_format)
      expect(result).to eq(unexpected_format)
    end
  end

  describe "#handle_error" do
    it "raises AuthenticationError for 401 status" do
      expect do
        provider.send(:handle_error, 401, '{"error": {"message": "Invalid API key"}}')
      end.to raise_error(RAAF::AuthenticationError, /Invalid API key/)
    end

    it "raises RateLimitError for 429 status" do
      expect do
        provider.send(:handle_error, 429, '{"error": {"message": "Rate limit exceeded"}}')
      end.to raise_error(RAAF::RateLimitError, /Rate limit exceeded/)
    end

    it "raises ServerError for 5xx status" do
      expect do
        provider.send(:handle_error, 500, '{"error": {"message": "Internal server error"}}')
      end.to raise_error(RAAF::ServerError, /Internal server error/)
    end

    it "raises APIError for other status codes" do
      expect do
        provider.send(:handle_error, 400, '{"error": {"message": "Bad request"}}')
      end.to raise_error(RAAF::APIError, /Bad request/)
    end

    it "handles malformed error responses" do
      expect do
        provider.send(:handle_error, 400, "Not JSON")
      end.to raise_error(RAAF::APIError, /Not JSON/)
    end
  end

  describe "integration with async HTTP client" do
    it "creates HTTP client lazily" do
      client1 = provider.send(:async_client)
      client2 = provider.send(:async_client)
      expect(client1).to eq(client2) # Same instance
    end

    it "uses configured endpoint for client" do
      client = provider.send(:async_client)
      expect(client).to be_a(Async::HTTP::Client)
    end
  end
end
