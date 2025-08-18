# frozen_string_literal: true

require "spec_helper"
require "raaf/tool/api"
require "webmock/rspec"

RSpec.describe RAAF::Tool::API do
  let(:test_api_tool) do
    Class.new(described_class) do
      endpoint "https://api.example.com/search"
      method :post
      headers "Content-Type" => "application/json"
      timeout 30

      def call(query:, limit: 10)
        post("/search", json: { q: query, limit: limit })
      end
    end
  end

  describe "configuration DSL" do
    it "sets endpoint" do
      expect(test_api_tool.api_endpoint).to eq("https://api.example.com/search")
    end

    it "sets HTTP method" do
      expect(test_api_tool.api_method).to eq(:post)
    end

    it "sets headers" do
      expect(test_api_tool.api_headers).to include("Content-Type" => "application/json")
    end

    it "sets timeout" do
      expect(test_api_tool.api_timeout).to eq(30)
    end
  end

  describe "HTTP methods" do
    let(:tool_instance) { test_api_tool.new }

    before do
      stub_request(:post, "https://api.example.com/search")
        .with(body: { q: "test", limit: 10 }.to_json)
        .to_return(status: 200, body: { results: ["result1"] }.to_json)

      stub_request(:get, "https://api.example.com/search/status")
        .to_return(status: 200, body: { status: "ok" }.to_json)
    end

    describe "#get" do
      it "makes GET request" do
        tool = Class.new(described_class) do
          endpoint "https://api.example.com/search"
          
          def call
            get("/status")
          end
        end.new

        result = tool.call
        expect(result).to include("status" => "ok")
      end
    end

    describe "#post" do
      it "makes POST request with JSON body" do
        result = tool_instance.call(query: "test")
        expect(result).to include("results" => ["result1"])
      end
    end

    describe "#put" do
      before do
        stub_request(:put, "https://api.example.com/search/1")
          .with(body: { name: "updated" }.to_json)
          .to_return(status: 200, body: { success: true }.to_json)
      end

      it "makes PUT request" do
        tool = Class.new(described_class) do
          endpoint "https://api.example.com/search"
          
          def call(id:, name:)
            put("/#{id}", json: { name: name })
          end
        end.new

        result = tool.call(id: 1, name: "updated")
        expect(result).to include("success" => true)
      end
    end

    describe "#delete" do
      before do
        stub_request(:delete, "https://api.example.com/search/1")
          .to_return(status: 204, body: "")
      end

      it "makes DELETE request" do
        tool = Class.new(described_class) do
          endpoint "https://api.example.com/search"
          
          def call(id:)
            delete("/#{id}")
          end
        end.new

        result = tool.call(id: 1)
        expect(result).to be_nil
      end
    end
  end

  describe "API key management" do
    context "from environment variable" do
      let(:api_tool_with_env_key) do
        Class.new(described_class) do
          endpoint "https://api.example.com"
          api_key_env "TEST_API_KEY"
        end
      end

      it "reads API key from environment" do
        ENV["TEST_API_KEY"] = "secret_key"
        tool = api_tool_with_env_key.new
        expect(tool.api_key).to eq("secret_key")
        ENV.delete("TEST_API_KEY")
      end
    end

    context "from direct configuration" do
      let(:api_tool_with_direct_key) do
        Class.new(described_class) do
          endpoint "https://api.example.com"
          api_key "direct_secret_key"
        end
      end

      it "uses directly configured API key" do
        tool = api_tool_with_direct_key.new
        expect(tool.api_key).to eq("direct_secret_key")
      end
    end

    context "from initialization options" do
      let(:api_tool) do
        Class.new(described_class) do
          endpoint "https://api.example.com"
        end
      end

      it "accepts API key in constructor" do
        tool = api_tool.new(api_key: "instance_key")
        expect(tool.api_key).to eq("instance_key")
      end
    end
  end

  describe "error handling" do
    let(:tool_instance) { test_api_tool.new }

    context "with network errors" do
      before do
        stub_request(:post, "https://api.example.com/search")
          .to_timeout
      end

      it "raises appropriate error" do
        expect { tool_instance.call(query: "test") }.to raise_error(RAAF::Tool::API::RequestError)
      end
    end

    context "with HTTP errors" do
      before do
        stub_request(:post, "https://api.example.com/search")
          .to_return(status: 500, body: "Internal Server Error")
      end

      it "raises error for server errors" do
        expect { tool_instance.call(query: "test") }.to raise_error(RAAF::Tool::API::RequestError)
      end
    end

    context "with rate limiting" do
      before do
        stub_request(:post, "https://api.example.com/search")
          .to_return(status: 429, body: "Rate limit exceeded")
      end

      it "raises rate limit error" do
        expect { tool_instance.call(query: "test") }.to raise_error(RAAF::Tool::API::RateLimitError)
      end
    end
  end

  describe "retry logic" do
    let(:retryable_tool) do
      Class.new(described_class) do
        endpoint "https://api.example.com"
        retries 3
        retry_delay 0.1

        def call
          get("/flaky")
        end
      end
    end

    it "retries on failure" do
      stub_request(:get, "https://api.example.com/flaky")
        .to_return(status: 500)
        .then.to_return(status: 500)
        .then.to_return(status: 200, body: { success: true }.to_json)

      tool = retryable_tool.new
      result = tool.call
      expect(result).to include("success" => true)
    end
  end
end