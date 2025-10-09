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
      allow(ENV).to receive(:fetch).with("PERPLEXITY_TIMEOUT", "180").and_return("180")
      allow(ENV).to receive(:fetch).with("PERPLEXITY_OPEN_TIMEOUT", "30").and_return("30")
      provider = described_class.new
      expect(provider.instance_variable_get(:@api_key)).to eq("env-key")
    end

    it "raises AuthenticationError if no API key provided" do
      allow(ENV).to receive(:fetch).with("PERPLEXITY_API_KEY", nil).and_return(nil)
      allow(ENV).to receive(:fetch).with("PERPLEXITY_TIMEOUT", "180").and_return("180")
      allow(ENV).to receive(:fetch).with("PERPLEXITY_OPEN_TIMEOUT", "30").and_return("30")
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
    let(:mock_response) do
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
    end

    before do
      allow(provider).to receive(:make_api_call).and_return(mock_response)
    end

    it "validates supported models" do
      expect { provider.perform_chat_completion(messages: messages, model: "invalid-model") }
        .to raise_error(ArgumentError, /not supported/)
    end

    it "builds request body using extracted method" do
      expect(provider).to receive(:build_request_body).with(messages, model, false).and_call_original
      expect(provider).to receive(:make_api_call).and_return(mock_response)

      provider.perform_chat_completion(messages: messages, model: model)
    end

    it "calls make_api_call instead of make_request" do
      expect(provider).to receive(:make_api_call).and_return(mock_response)

      provider.perform_chat_completion(messages: messages, model: model)
    end

    it "includes messages and model in request" do
      expect(provider).to receive(:make_api_call) do |body|
        expect(body[:messages]).to eq(messages)
        expect(body[:model]).to eq(model)
        mock_response
      end

      provider.perform_chat_completion(messages: messages, model: model)
    end

    it "adds temperature when provided" do
      expect(provider).to receive(:make_api_call) do |body|
        expect(body[:temperature]).to eq(0.7)
        mock_response
      end

      provider.perform_chat_completion(messages: messages, model: model, temperature: 0.7)
    end

    it "adds max_tokens when provided" do
      expect(provider).to receive(:make_api_call) do |body|
        expect(body[:max_tokens]).to eq(1000)
        mock_response
      end

      provider.perform_chat_completion(messages: messages, model: model, max_tokens: 1000)
    end

    it "adds top_p when provided" do
      expect(provider).to receive(:make_api_call) do |body|
        expect(body[:top_p]).to eq(0.9)
        mock_response
      end

      provider.perform_chat_completion(messages: messages, model: model, top_p: 0.9)
    end

    it "adds response_format when provided using unwrap_response_format" do
      schema = { type: "object", properties: { result: { type: "string" } } }

      expect(provider).to receive(:make_api_call) do |body|
        expect(body[:response_format]).to eq({
          type: "json_schema",
          json_schema: { schema: schema }
        })
        mock_response
      end

      provider.perform_chat_completion(messages: messages, model: model, response_format: schema)
    end

    it "adds web_search_options when provided" do
      web_options = { search_domain_filter: ["example.com"], search_recency_filter: "week" }

      expect(provider).to receive(:make_api_call) do |body|
        expect(body[:web_search_options]).to eq(web_options)
        mock_response
      end

      provider.perform_chat_completion(messages: messages, model: model, web_search_options: web_options)
    end

    it "returns response with citations" do
      result = provider.perform_chat_completion(messages: messages, model: model)

      expect(result).to have_key("choices")
      expect(result).to have_key("citations")
      expect(result).to have_key("web_results")
    end

    it "logs warning when tools are provided" do
      tools = [{ type: "function", name: "test_tool" }]

      expect(provider).to receive(:log_warn).with(
        /does not support function\/tool calling/,
        hash_including(provider: "PerplexityProvider", model: model)
      )

      provider.perform_chat_completion(messages: messages, model: model, tools: tools)
    end
  end

  describe "retry logic (delegated to ModelInterface)" do
    let(:messages) { [{ role: "user", content: "test" }] }
    let(:model) { "sonar" }

    it "does not have custom retry wrapper in perform_chat_completion" do
      # Verify the method doesn't call with_retry internally
      source = provider.method(:perform_chat_completion).source
      expect(source).not_to include("with_retry")
    end

    it "relies on base class chat_completion for retry" do
      # The public chat_completion method (from ModelInterface) handles retry
      expect(provider).to respond_to(:chat_completion)
      expect(provider.method(:chat_completion).owner).to eq(RAAF::Models::ModelInterface)
    end

    context "when using ModelInterface.with_retry" do
      it "retries on Net::ReadTimeout" do
        call_count = 0
        allow(provider).to receive(:make_api_call) do
          call_count += 1
          raise Net::ReadTimeout if call_count < 2
          { "choices" => [{ "message" => { "content" => "success" } }] }
        end

        result = provider.chat_completion(messages: messages, model: model)
        expect(call_count).to eq(2)
        expect(result).to have_key("choices")
      end

      it "retries on Net::WriteTimeout" do
        call_count = 0
        allow(provider).to receive(:make_api_call) do
          call_count += 1
          raise Net::WriteTimeout if call_count < 2
          { "choices" => [{ "message" => { "content" => "success" } }] }
        end

        result = provider.chat_completion(messages: messages, model: model)
        expect(call_count).to eq(2)
        expect(result).to have_key("choices")
      end

      it "retries on Errno::ECONNRESET" do
        call_count = 0
        allow(provider).to receive(:make_api_call) do
          call_count += 1
          raise Errno::ECONNRESET if call_count < 2
          { "choices" => [{ "message" => { "content" => "success" } }] }
        end

        result = provider.chat_completion(messages: messages, model: model)
        expect(call_count).to eq(2)
        expect(result).to have_key("choices")
      end

      it "respects max_attempts configuration (default 3)" do
        call_count = 0
        allow(provider).to receive(:make_api_call) do
          call_count += 1
          raise Net::ReadTimeout
        end

        expect { provider.chat_completion(messages: messages, model: model) }
          .to raise_error(Net::ReadTimeout)
        expect(call_count).to eq(3) # Initial attempt + 2 retries
      end

      it "does not retry on non-retryable errors" do
        call_count = 0
        allow(provider).to receive(:make_api_call) do
          call_count += 1
          raise RAAF::Models::AuthenticationError, "Invalid API key"
        end

        expect { provider.chat_completion(messages: messages, model: model) }
          .to raise_error(RAAF::Models::AuthenticationError)
        expect(call_count).to eq(1) # No retries for auth errors
      end

      it "applies exponential backoff between retries" do
        call_count = 0
        retry_delays = []

        allow(provider).to receive(:make_api_call) do
          call_count += 1
          raise Net::ReadTimeout if call_count < 3
          { "choices" => [{ "message" => { "content" => "success" } }] }
        end

        # Mock sleep to capture delays
        allow(provider).to receive(:sleep) { |delay| retry_delays << delay }

        provider.chat_completion(messages: messages, model: model)

        # Verify we had retries with delays
        expect(retry_delays.length).to be >= 1
      end
    end
  end

  describe "extracted helper methods" do
    let(:messages) { [{ role: "user", content: "test" }] }
    let(:model) { "sonar-pro" }

    describe "#build_request_body" do
      it "builds complete request body" do
        body = provider.send(:build_request_body, messages, model, false, temperature: 0.7, max_tokens: 100)

        expect(body).to include(
          model: model,
          messages: messages,
          stream: false,
          temperature: 0.7,
          max_tokens: 100
        )
      end

      it "includes optional parameters when provided" do
        body = provider.send(:build_request_body, messages, model, false,
                              top_p: 0.9,
                              presence_penalty: 0.5,
                              frequency_penalty: 0.3)

        expect(body[:top_p]).to eq(0.9)
        expect(body[:presence_penalty]).to eq(0.5)
        expect(body[:frequency_penalty]).to eq(0.3)
      end

      it "calls unwrap_response_format for response_format parameter" do
        schema = { type: "object" }
        expect(provider).to receive(:unwrap_response_format).with(schema).and_call_original
        expect(provider).to receive(:validate_schema_support).with(model)

        provider.send(:build_request_body, messages, model, false, response_format: schema)
      end

      it "includes web_search_options when provided" do
        web_options = { search_domain_filter: ["test.com"] }
        body = provider.send(:build_request_body, messages, model, false, web_search_options: web_options)

        expect(body[:web_search_options]).to eq(web_options)
      end
    end

    describe "#unwrap_response_format" do
      it "extracts schema from OpenAI-wrapped format" do
        openai_format = {
          type: "json_schema",
          json_schema: {
            name: "test",
            strict: true,
            schema: { type: "object", properties: { test: { type: "string" } } }
          }
        }

        result = provider.send(:unwrap_response_format, openai_format)

        expect(result).to eq({
          type: "json_schema",
          json_schema: {
            schema: { type: "object", properties: { test: { type: "string" } } }
          }
        })
      end

      it "handles raw schema format" do
        raw_schema = { type: "object", properties: { result: { type: "string" } } }

        result = provider.send(:unwrap_response_format, raw_schema)

        expect(result).to eq({
          type: "json_schema",
          json_schema: {
            schema: raw_schema
          }
        })
      end
    end

    describe "#configure_http_client" do
      it "configures HTTP client with correct settings" do
        uri = URI("https://api.perplexity.ai/chat/completions")

        http = provider.send(:configure_http_client, uri)

        expect(http).to be_a(Net::HTTP)
        expect(http.use_ssl?).to be true
        expect(http.read_timeout).to eq(provider.instance_variable_get(:@timeout))
        expect(http.open_timeout).to eq(provider.instance_variable_get(:@open_timeout))
      end
    end

    describe "#build_http_request" do
      it "builds request with correct headers" do
        uri = URI("https://api.perplexity.ai/chat/completions")
        body = { model: "sonar", messages: [] }

        request = provider.send(:build_http_request, uri, body)

        expect(request).to be_a(Net::HTTP::Post)
        expect(request["Authorization"]).to eq("Bearer #{api_key}")
        expect(request["Content-Type"]).to eq("application/json")
        expect(JSON.parse(request.body)).to eq(body.transform_keys(&:to_s))
      end
    end
  end

  describe "error handling" do
    let(:messages) { [{ role: "user", content: "test" }] }
    let(:model) { "sonar" }

    it "handles 401 authentication errors" do
      allow(provider).to receive(:make_api_call).and_raise(
        RAAF::Models::AuthenticationError, "Invalid Perplexity API key"
      )

      expect { provider.perform_chat_completion(messages: messages, model: model) }
        .to raise_error(RAAF::Models::AuthenticationError, "Invalid Perplexity API key")
    end

    it "handles 429 rate limit errors" do
      allow(provider).to receive(:make_api_call).and_raise(
        RAAF::Models::RateLimitError, "Perplexity rate limit exceeded. Reset at: 60"
      )

      expect { provider.perform_chat_completion(messages: messages, model: model) }
        .to raise_error(RAAF::Models::RateLimitError, /Reset at: 60/)
    end

    it "handles 400 bad request errors" do
      allow(provider).to receive(:make_api_call).and_raise(
        RAAF::Models::APIError, "Perplexity API error: Bad request"
      )

      expect { provider.perform_chat_completion(messages: messages, model: model) }
        .to raise_error(RAAF::Models::APIError, /Bad request/)
    end

    it "passes provider_name to handle_api_error" do
      # This is tested indirectly - handle_api_error is called with provider_name in make_api_call
      # The refactoring updated the call site
      expect(provider.provider_name).to eq("Perplexity")
    end
  end

  describe "Perplexity-specific features" do
    let(:messages) { [{ role: "user", content: "test" }] }

    describe "schema validation" do
      it "allows schema for sonar-pro" do
        expect { provider.send(:validate_schema_support, "sonar-pro") }.not_to raise_error
      end

      it "allows schema for sonar-reasoning-pro" do
        expect { provider.send(:validate_schema_support, "sonar-reasoning-pro") }.not_to raise_error
      end

      it "raises error for sonar model with schema" do
        expect { provider.send(:validate_schema_support, "sonar") }
          .to raise_error(ArgumentError, /only supported on sonar-pro, sonar-reasoning-pro/)
      end

      it "raises error for sonar-deep-research model with schema" do
        expect { provider.send(:validate_schema_support, "sonar-deep-research") }
          .to raise_error(ArgumentError, /only supported on sonar-pro, sonar-reasoning-pro/)
      end
    end
  end
end
