# frozen_string_literal: true

require "spec_helper"
require "webmock/rspec"

RSpec.describe RAAF::HTTPClient do
  describe "error classes" do
    it "defines the expected error hierarchy" do
      expect(described_class::Error).to be < StandardError
      expect(described_class::APIError).to be < described_class::Error
      expect(described_class::BadRequestError).to be < described_class::APIError
      expect(described_class::AuthenticationError).to be < described_class::APIError
      expect(described_class::RateLimitError).to be < described_class::APIError
    end
  end

  describe RAAF::HTTPClient::Client do
    let(:api_key) { "test-api-key-12345" }
    let(:base_url) { "https://api.openai.com/v1" }
    let(:client) { described_class.new(api_key: api_key, base_url: base_url) }

    before do
      WebMock.disable_net_connect!
    end

    after do
      WebMock.allow_net_connect!
    end

    describe "#initialize" do
      it "initializes with required parameters" do
        expect(client.api_key).to eq(api_key)
        expect(client.base_url).to eq(base_url)
      end

      it "uses default base URL" do
        client = described_class.new(api_key: api_key)
        expect(client.base_url).to eq("https://api.openai.com/v1")
      end

      it "accepts custom timeout options" do
        client = described_class.new(
          api_key: api_key,
          timeout: 60,
          open_timeout: 10
        )
        expect(client.instance_variable_get(:@timeout)).to eq(60)
        expect(client.instance_variable_get(:@open_timeout)).to eq(10)
      end

      it "uses default timeout values" do
        expect(client.instance_variable_get(:@timeout)).to eq(120)
        expect(client.instance_variable_get(:@open_timeout)).to eq(30)
      end
    end

    describe "#chat" do
      it "returns a ChatResource" do
        expect(client.chat).to be_a(RAAF::HTTPClient::ChatResource)
      end

      it "returns the same instance on repeated calls" do
        # rubocop:disable RSpec/IdenticalEqualityAssertion
        expect(client.chat).to be(client.chat)
        # rubocop:enable RSpec/IdenticalEqualityAssertion
      end
    end

    describe "#make_request" do
      context "successful requests" do
        it "makes GET requests" do
          response_body = { "data" => "test response" }
          stub_request(:get, "#{base_url}/test")
            .with(headers: {
                    "Authorization" => "Bearer #{api_key}",
                    "Content-Type" => "application/json",
                    "Accept" => "application/json"
                  })
            .to_return(status: 200, body: response_body.to_json)

          result = client.make_request("GET", "/test")
          expect(result).to eq(response_body)
        end

        it "makes POST requests with body" do
          request_body = { "model" => "gpt-4o", "messages" => [] }
          response_body = { "id" => "chatcmpl-123", "choices" => [] }

          stub_request(:post, "#{base_url}/chat/completions")
            .with(
              body: request_body.to_json,
              headers: {
                "Authorization" => "Bearer #{api_key}",
                "Content-Type" => "application/json",
                "Accept" => "application/json"
              }
            )
            .to_return(status: 200, body: response_body.to_json)

          result = client.make_request("POST", "/chat/completions", body: request_body)
          expect(result).to eq(response_body)
        end

        it "includes custom headers" do
          custom_headers = { "X-Custom-Header" => "custom-value" }
          response_body = { "success" => true }

          stub_request(:post, "#{base_url}/test")
            .with(headers: {
                    "Authorization" => "Bearer #{api_key}",
                    "Content-Type" => "application/json",
                    "Accept" => "application/json",
                    "X-Custom-Header" => "custom-value"
                  })
            .to_return(status: 200, body: response_body.to_json)

          result = client.make_request("POST", "/test", headers: custom_headers)
          expect(result).to eq(response_body)
        end
      end

      context "streaming requests" do
        it "processes streaming responses" do
          streaming_data = [
            "data: {\"id\":\"chatcmpl-123\",\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}\n",
            "data: {\"id\":\"chatcmpl-123\",\"choices\":[{\"delta\":{\"content\":\" world\"}}]}\n",
            "data: [DONE]\n"
          ]

          stub_request(:post, "#{base_url}/chat/completions")
            .with(
              body: hash_including(stream: true),
              headers: {
                "Authorization" => "Bearer #{api_key}",
                "Content-Type" => "application/json",
                "Accept" => "text/event-stream"
              }
            )
            .to_return(status: 200, body: streaming_data.join)

          received_chunks = []
          client.make_request("POST", "/chat/completions",
                              body: { model: "gpt-4o", stream: true },
                              stream: true) do |chunk|
            received_chunks << chunk
          end

          expect(received_chunks).to have(2).items
          expect(received_chunks[0]).to include("id" => "chatcmpl-123")
          expect(received_chunks[0]["choices"][0]["delta"]).to include("content" => "Hello")
        end

        it "handles streaming responses with invalid JSON" do
          streaming_data = [
            "data: {\"valid\":\"json\"}\n",
            "data: {invalid json}\n",
            "data: {\"another\":\"valid\"}\n",
            "data: [DONE]\n"
          ]

          stub_request(:post, "#{base_url}/chat/completions")
            .with(body: hash_including(stream: true))
            .to_return(status: 200, body: streaming_data.join)

          received_chunks = []
          client.make_request("POST", "/chat/completions",
                              body: { model: "gpt-4o", stream: true },
                              stream: true) do |chunk|
            received_chunks << chunk
          end

          # Should receive only valid JSON chunks
          expect(received_chunks).to have(2).items
          expect(received_chunks[0]).to include("valid" => "json")
          expect(received_chunks[1]).to include("another" => "valid")
        end

        it "ignores non-data lines and empty data" do
          streaming_data = [
            ": comment line\n",
            "event: start\n",
            "data: \n",
            "data: {\"content\":\"test\"}\n",
            "data: [DONE]\n"
          ]

          stub_request(:post, "#{base_url}/chat/completions")
            .to_return(status: 200, body: streaming_data.join)

          received_chunks = []
          client.make_request("POST", "/chat/completions",
                              body: { stream: true },
                              stream: true) do |chunk|
            received_chunks << chunk
          end

          expect(received_chunks).to have(1).item
          expect(received_chunks[0]).to include("content" => "test")
        end
      end

      context "error handling" do
        it "raises BadRequestError for 400" do
          error_response = { "error" => { "message" => "Invalid request", "type" => "invalid_request_error" } }
          stub_request(:post, "#{base_url}/test")
            .to_return(status: 400, body: error_response.to_json)

          expect do
            client.make_request("POST", "/test")
          end.to raise_error(RAAF::HTTPClient::BadRequestError, "Invalid request")
        end

        it "raises AuthenticationError for 401" do
          error_response = { "error" => { "message" => "Invalid API key", "type" => "invalid_api_key" } }
          stub_request(:post, "#{base_url}/test")
            .to_return(status: 401, body: error_response.to_json)

          expect do
            client.make_request("POST", "/test")
          end.to raise_error(RAAF::HTTPClient::AuthenticationError, "Invalid API key")
        end

        it "raises PermissionDeniedError for 403" do
          stub_request(:post, "#{base_url}/test")
            .to_return(status: 403, body: { error: { message: "Forbidden" } }.to_json)

          expect do
            client.make_request("POST", "/test")
          end.to raise_error(RAAF::HTTPClient::PermissionDeniedError, "Forbidden")
        end

        it "raises NotFoundError for 404" do
          stub_request(:post, "#{base_url}/test")
            .to_return(status: 404, body: { error: { message: "Not found" } }.to_json)

          expect do
            client.make_request("POST", "/test")
          end.to raise_error(RAAF::HTTPClient::NotFoundError, "Not found")
        end

        it "raises ConflictError for 409" do
          stub_request(:post, "#{base_url}/test")
            .to_return(status: 409, body: { error: { message: "Conflict" } }.to_json)

          expect do
            client.make_request("POST", "/test")
          end.to raise_error(RAAF::HTTPClient::ConflictError, "Conflict")
        end

        it "raises UnprocessableEntityError for 422" do
          stub_request(:post, "#{base_url}/test")
            .to_return(status: 422, body: { error: { message: "Unprocessable" } }.to_json)

          expect do
            client.make_request("POST", "/test")
          end.to raise_error(RAAF::HTTPClient::UnprocessableEntityError, "Unprocessable")
        end

        it "raises RateLimitError for 429" do
          stub_request(:post, "#{base_url}/test")
            .to_return(status: 429, body: { error: { message: "Rate limit exceeded" } }.to_json)

          expect do
            client.make_request("POST", "/test")
          end.to raise_error(RAAF::HTTPClient::RateLimitError, "Rate limit exceeded")
        end

        it "raises InternalServerError for 500" do
          stub_request(:post, "#{base_url}/test")
            .to_return(status: 500, body: { error: { message: "Internal server error" } }.to_json)

          expect do
            client.make_request("POST", "/test")
          end.to raise_error(RAAF::HTTPClient::InternalServerError, "Internal server error")
        end

        it "raises BadGatewayError for 502" do
          stub_request(:post, "#{base_url}/test")
            .to_return(status: 502, body: { error: { message: "Bad gateway" } }.to_json)

          expect do
            client.make_request("POST", "/test")
          end.to raise_error(RAAF::HTTPClient::BadGatewayError, "Bad gateway")
        end

        it "raises ServiceUnavailableError for 503" do
          stub_request(:post, "#{base_url}/test")
            .to_return(status: 503, body: { error: { message: "Service unavailable" } }.to_json)

          expect do
            client.make_request("POST", "/test")
          end.to raise_error(RAAF::HTTPClient::ServiceUnavailableError, "Service unavailable")
        end

        it "raises GatewayTimeoutError for 504" do
          stub_request(:post, "#{base_url}/test")
            .to_return(status: 504, body: { error: { message: "Gateway timeout" } }.to_json)

          expect do
            client.make_request("POST", "/test")
          end.to raise_error(RAAF::HTTPClient::GatewayTimeoutError, "Gateway timeout")
        end

        it "raises APIError for unknown status codes" do
          stub_request(:post, "#{base_url}/test")
            .to_return(status: 418, body: { error: { message: "I'm a teapot" } }.to_json)

          expect do
            client.make_request("POST", "/test")
          end.to raise_error(RAAF::HTTPClient::APIError, "HTTP 418: I'm a teapot")
        end

        it "handles non-JSON error responses" do
          stub_request(:post, "#{base_url}/test")
            .to_return(status: 500, body: "Internal Server Error")

          expect do
            client.make_request("POST", "/test")
          end.to raise_error(RAAF::HTTPClient::InternalServerError, "Internal Server Error")
        end

        it "handles error responses without error message" do
          stub_request(:post, "#{base_url}/test")
            .to_return(status: 400, body: {}.to_json)

          expect do
            client.make_request("POST", "/test")
          end.to raise_error(RAAF::HTTPClient::BadRequestError, "Unknown error")
        end

        it "handles streaming error responses" do
          stub_request(:post, "#{base_url}/test")
            .to_return(status: 401, body: { error: { message: "Unauthorized" } }.to_json)

          expect do
            # rubocop:disable Lint/EmptyBlock
            client.make_request("POST", "/test", stream: true) { |chunk| }
            # rubocop:enable Lint/EmptyBlock
          end.to raise_error(RAAF::HTTPClient::AuthenticationError, "Unauthorized")
        end
      end

      context "unsupported methods" do
        it "raises ArgumentError for unsupported HTTP methods" do
          expect do
            client.make_request("PUT", "/test")
          end.to raise_error(ArgumentError, "Unsupported HTTP method: PUT")
        end
      end
    end
  end

  describe RAAF::HTTPClient::ChatResource do
    let(:client) { double("client") }
    let(:chat_resource) { described_class.new(client) }

    describe "#initialize" do
      it "stores the client" do
        expect(chat_resource.instance_variable_get(:@client)).to eq(client)
      end
    end

    describe "#completions" do
      it "returns a CompletionsResource" do
        expect(chat_resource.completions).to be_a(RAAF::HTTPClient::CompletionsResource)
      end

      it "returns the same instance on repeated calls" do
        # rubocop:disable RSpec/IdenticalEqualityAssertion
        expect(chat_resource.completions).to be(chat_resource.completions)
        # rubocop:enable RSpec/IdenticalEqualityAssertion
      end

      it "passes the client to CompletionsResource" do
        completions = chat_resource.completions
        expect(completions.instance_variable_get(:@client)).to eq(client)
      end
    end
  end

  describe RAAF::HTTPClient::CompletionsResource do
    let(:client) { double("client") }
    let(:completions_resource) { described_class.new(client) }

    describe "#initialize" do
      it "stores the client" do
        expect(completions_resource.instance_variable_get(:@client)).to eq(client)
      end
    end

    describe "#create" do
      it "calls make_request with POST method and parameters" do
        parameters = { model: "gpt-4o", messages: [{ role: "user", content: "Hello" }] }

        expect(client).to receive(:make_request)
          .with("POST", "/chat/completions", body: parameters)
          .and_return({ "id" => "chatcmpl-123" })

        result = completions_resource.create(**parameters)
        expect(result).to eq({ "id" => "chatcmpl-123" })
      end

      it "handles empty parameters" do
        expect(client).to receive(:make_request)
          .with("POST", "/chat/completions", body: {})

        completions_resource.create
      end
    end

    describe "#stream_raw" do
      it "calls make_request with streaming parameters" do
        parameters = { model: "gpt-4o", messages: [] }
        expected_params = parameters.merge(stream: true)

        block = proc { |chunk| puts chunk }

        expect(client).to receive(:make_request)
          .with("POST", "/chat/completions", body: expected_params, stream: true, &block)

        completions_resource.stream_raw(parameters, &block)
      end

      it "merges stream: true with existing parameters" do
        parameters = { model: "gpt-4o", messages: [], temperature: 0.7 }
        expected_params = { model: "gpt-4o", messages: [], temperature: 0.7, stream: true }

        expect(client).to receive(:make_request)
          .with("POST", "/chat/completions", body: expected_params, stream: true)

        # rubocop:disable Lint/EmptyBlock
        completions_resource.stream_raw(parameters) { |chunk| }
        # rubocop:enable Lint/EmptyBlock
      end

      it "overwrites stream parameter if already present" do
        parameters = { model: "gpt-4o", messages: [], stream: false }
        expected_params = { model: "gpt-4o", messages: [], stream: true }

        expect(client).to receive(:make_request)
          .with("POST", "/chat/completions", body: expected_params, stream: true)

        # rubocop:disable Lint/EmptyBlock
        completions_resource.stream_raw(parameters) { |chunk| }
        # rubocop:enable Lint/EmptyBlock
      end
    end
  end

  describe "integration tests" do
    let(:api_key) { "test-api-key-12345" }
    let(:client) { RAAF::HTTPClient::Client.new(api_key: api_key) }

    before do
      WebMock.disable_net_connect!
    end

    after do
      WebMock.allow_net_connect!
    end

    describe "chat completions workflow" do
      it "creates a completion through the resource chain" do
        request_params = {
          model: "gpt-4o",
          messages: [{ role: "user", content: "Hello!" }],
          max_tokens: 100
        }

        response_body = {
          "id" => "chatcmpl-123",
          "object" => "chat.completion",
          "choices" => [{
            "index" => 0,
            "message" => {
              "role" => "assistant",
              "content" => "Hello! How can I help you today?"
            },
            "finish_reason" => "stop"
          }]
        }

        stub_request(:post, "https://api.openai.com/v1/chat/completions")
          .with(
            body: request_params.to_json,
            headers: {
              "Authorization" => "Bearer #{api_key}",
              "Content-Type" => "application/json",
              "Accept" => "application/json"
            }
          )
          .to_return(status: 200, body: response_body.to_json)

        result = client.chat.completions.create(**request_params)

        expect(result).to eq(response_body)
        expect(result["choices"][0]["message"]["content"]).to eq("Hello! How can I help you today?")
      end

      it "streams a completion through the resource chain" do
        streaming_response = [
          "data: {\"id\":\"chatcmpl-123\",\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}\n",
          "data: {\"id\":\"chatcmpl-123\",\"choices\":[{\"delta\":{\"content\":\" there!\"}}]}\n",
          "data: [DONE]\n"
        ].join

        stub_request(:post, "https://api.openai.com/v1/chat/completions")
          .with(
            body: hash_including(stream: true),
            headers: {
              "Authorization" => "Bearer #{api_key}",
              "Content-Type" => "application/json",
              "Accept" => "text/event-stream"
            }
          )
          .to_return(status: 200, body: streaming_response)

        received_content = []
        client.chat.completions.stream_raw(
          model: "gpt-4o",
          messages: [{ role: "user", content: "Hello!" }]
        ) do |chunk|
          content = chunk.dig("choices", 0, "delta", "content")
          received_content << content if content
        end

        expect(received_content).to eq(["Hello", " there!"])
      end
    end

    describe "error handling integration" do
      it "handles authentication errors in the resource chain" do
        stub_request(:post, "https://api.openai.com/v1/chat/completions")
          .to_return(
            status: 401,
            body: { error: { message: "Invalid API key provided" } }.to_json
          )

        expect do
          client.chat.completions.create(
            model: "gpt-4o",
            messages: [{ role: "user", content: "Hello!" }]
          )
        end.to raise_error(RAAF::HTTPClient::AuthenticationError, "Invalid API key provided")
      end

      it "handles rate limiting in streaming" do
        stub_request(:post, "https://api.openai.com/v1/chat/completions")
          .to_return(
            status: 429,
            body: { error: { message: "Rate limit exceeded" } }.to_json
          )

        expect do
          # rubocop:disable Lint/EmptyBlock
          client.chat.completions.stream_raw(
            model: "gpt-4o",
            messages: [{ role: "user", content: "Hello!" }]
          ) { |chunk| }
          # rubocop:enable Lint/EmptyBlock
        end.to raise_error(RAAF::HTTPClient::RateLimitError, "Rate limit exceeded")
      end
    end
  end
end
