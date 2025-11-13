# frozen_string_literal: true

require "spec_helper"
require "raaf/ollama_provider"

RSpec.describe RAAF::Models::OllamaProvider do
  describe "#initialize" do
    it "initializes with default host" do
      provider = described_class.new
      expect(provider.instance_variable_get(:@host)).to eq("http://localhost:11434")
    end

    it "initializes with custom host parameter" do
      provider = described_class.new(host: "http://192.168.1.100:11434")
      expect(provider.instance_variable_get(:@host)).to eq("http://192.168.1.100:11434")
    end

    it "uses OLLAMA_HOST environment variable" do
      ENV["OLLAMA_HOST"] = "http://server:11434"
      provider = described_class.new
      expect(provider.instance_variable_get(:@host)).to eq("http://server:11434")
      ENV.delete("OLLAMA_HOST")
    end

    it "prefers explicit host parameter over environment variable" do
      ENV["OLLAMA_HOST"] = "http://env-server:11434"
      provider = described_class.new(host: "http://param-server:11434")
      expect(provider.instance_variable_get(:@host)).to eq("http://param-server:11434")
      ENV.delete("OLLAMA_HOST")
    end

    it "initializes with default timeout" do
      provider = described_class.new
      expect(provider.http_timeout).to eq(120)
    end

    it "initializes with custom timeout parameter" do
      provider = described_class.new(timeout: 300)
      expect(provider.http_timeout).to eq(300)
    end

    it "uses RAAF_OLLAMA_TIMEOUT environment variable" do
      ENV["RAAF_OLLAMA_TIMEOUT"] = "180"
      provider = described_class.new
      expect(provider.http_timeout).to eq(180)
      ENV.delete("RAAF_OLLAMA_TIMEOUT")
    end

    it "prefers explicit timeout parameter over environment variable" do
      ENV["RAAF_OLLAMA_TIMEOUT"] = "180"
      provider = described_class.new(timeout: 300)
      expect(provider.http_timeout).to eq(300)
      ENV.delete("RAAF_OLLAMA_TIMEOUT")
    end

    it "does not require API key (local provider)" do
      expect { described_class.new }.not_to raise_error
    end
  end

  describe "#provider_name" do
    it "returns Ollama" do
      provider = described_class.new
      expect(provider.provider_name).to eq("Ollama")
    end
  end

  describe "#supported_models" do
    it "returns empty array (Ollama is extensible)" do
      provider = described_class.new
      models = provider.supported_models
      expect(models).to be_an(Array)
      expect(models).to be_empty
    end
  end

  describe "#perform_chat_completion" do
    let(:provider) { described_class.new }
    let(:messages) { [{ role: "user", content: "Hello!" }] }
    let(:model) { "llama3.2" }

    let(:mock_ollama_response) do
      {
        "model" => "llama3.2",
        "created_at" => "2025-11-13T10:00:00Z",
        "message" => {
          "role" => "assistant",
          "content" => "Hello! How can I help you today?"
        },
        "done" => true,
        "done_reason" => "stop",
        "total_duration" => 5000000000,
        "load_duration" => 2000000000,
        "prompt_eval_count" => 10,
        "eval_count" => 15
      }
    end

    let(:expected_openai_response) do
      {
        "content" => "Hello! How can I help you today?",
        "usage" => {
          "prompt_tokens" => 10,
          "completion_tokens" => 15,
          "total_tokens" => 25,
          "total_duration" => 5000000000,
          "load_duration" => 2000000000,
          "prompt_eval_count" => 10,
          "eval_count" => 15
        },
        "model" => "llama3.2",
        "finish_reason" => "stop"
      }
    end

    before do
      # Mock make_request to return parsed response (it calls parse_response internally)
      allow(provider).to receive(:make_request).and_return(expected_openai_response)
    end

    it "performs basic chat completion" do
      result = provider.perform_chat_completion(messages: messages, model: model)
      expect(result).to be_a(Hash)
      expect(result["content"]).to eq("Hello! How can I help you today?")
      expect(result["model"]).to eq("llama3.2")
    end

    it "converts Ollama response to OpenAI format" do
      result = provider.perform_chat_completion(messages: messages, model: model)
      expect(result["usage"]["prompt_tokens"]).to eq(10)
      expect(result["usage"]["completion_tokens"]).to eq(15)
      expect(result["usage"]["total_tokens"]).to eq(25)
      expect(result["finish_reason"]).to eq("stop")
    end

    it "preserves Ollama-specific metadata in usage object" do
      result = provider.perform_chat_completion(messages: messages, model: model)
      expect(result["usage"]["total_duration"]).to eq(5000000000)
      expect(result["usage"]["load_duration"]).to eq(2000000000)
      expect(result["usage"]["prompt_eval_count"]).to eq(10)
      expect(result["usage"]["eval_count"]).to eq(15)
    end

    it "logs model loading progress on first request" do
      expect(provider).to receive(:log_info).with(
        /Loading model llama3.2/,
        hash_including(provider: "OllamaProvider", model: model)
      )
      provider.perform_chat_completion(messages: messages, model: model)
    end

    it "includes temperature parameter when provided" do
      expect(provider).to receive(:make_request).with(
        hash_including(options: hash_including(temperature: 0.7))
      ).and_return(mock_ollama_response)

      provider.perform_chat_completion(messages: messages, model: model, temperature: 0.7)
    end

    it "includes top_p parameter when provided" do
      expect(provider).to receive(:make_request).with(
        hash_including(options: hash_including(top_p: 0.9))
      ).and_return(mock_ollama_response)

      provider.perform_chat_completion(messages: messages, model: model, top_p: 0.9)
    end

    it "includes max_tokens parameter when provided" do
      expect(provider).to receive(:make_request).with(
        hash_including(options: hash_including(num_predict: 1024))
      ).and_return(mock_ollama_response)

      provider.perform_chat_completion(messages: messages, model: model, max_tokens: 1024)
    end

    it "includes stop sequences parameter when provided" do
      expect(provider).to receive(:make_request).with(
        hash_including(options: hash_including(stop: ["END", "STOP"]))
      ).and_return(mock_ollama_response)

      provider.perform_chat_completion(messages: messages, model: model, stop: ["END", "STOP"])
    end

    it "builds request body correctly" do
      expect(provider).to receive(:make_request).with(
        hash_including(
          model: model,
          messages: messages,
          stream: false
        )
      ).and_return(mock_ollama_response)

      provider.perform_chat_completion(messages: messages, model: model)
    end

    context "with tools" do
      let(:raaf_tools) do
        [{
          name: "get_weather",
          description: "Get weather for a location",
          parameters: {
            type: "object",
            properties: {
              location: { type: "string" }
            },
            required: ["location"]
          }
        }]
      end

      let(:expected_ollama_tools) do
        [{
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
      end

      let(:mock_tool_call_response) do
        {
          "model" => "llama3.2",
          "message" => {
            "role" => "assistant",
            "content" => "",
            "tool_calls" => [{
              "id" => "call_abc123",
              "function" => {
                "name" => "get_weather",
                "arguments" => '{"location": "Tokyo"}'
              }
            }]
          },
          "done" => true,
          "done_reason" => "stop",
          "prompt_eval_count" => 20,
          "eval_count" => 5
        }
      end

      let(:expected_tool_call_openai) do
        {
          "content" => "",
          "tool_calls" => [{
            "id" => "call_abc123",
            "type" => "function",
            "function" => {
              "name" => "get_weather",
              "arguments" => '{"location": "Tokyo"}'
            }
          }],
          "model" => "llama3.2",
          "finish_reason" => "stop",
          "usage" => {
            "prompt_tokens" => 20,
            "completion_tokens" => 5,
            "total_tokens" => 25,
            "total_duration" => nil,
            "load_duration" => nil,
            "prompt_eval_count" => 20,
            "eval_count" => 5
          }
        }
      end

      before do
        allow(provider).to receive(:make_request).and_return(expected_tool_call_openai)
      end

      it "includes tools in request" do
        expect(provider).to receive(:make_request).with(
          hash_including(tools: expected_ollama_tools)
        ).and_return(expected_tool_call_openai)

        provider.perform_chat_completion(messages: messages, model: model, tools: raaf_tools)
      end

      it "converts RAAF tools to Ollama format" do
        prepared_tools = provider.send(:prepare_tools, raaf_tools)
        expect(prepared_tools).to eq(expected_ollama_tools)
      end

      it "parses tool calls from Ollama to OpenAI format" do
        result = provider.perform_chat_completion(messages: messages, model: model, tools: raaf_tools)
        expect(result["tool_calls"]).to be_an(Array)
        expect(result["tool_calls"].length).to eq(1)
        expect(result["tool_calls"][0]["id"]).to eq("call_abc123")
        expect(result["tool_calls"][0]["type"]).to eq("function")
        expect(result["tool_calls"][0]["function"]["name"]).to eq("get_weather")
        expect(result["tool_calls"][0]["function"]["arguments"]).to eq('{"location": "Tokyo"}')
      end

      it "handles tools with string keys" do
        string_key_tools = [{
          "name" => "get_weather",
          "description" => "Get weather",
          "parameters" => { "type" => "object" }
        }]

        prepared = provider.send(:prepare_tools, string_key_tools)
        expect(prepared[0][:function][:name]).to eq("get_weather")
      end

      it "returns empty array when no tool calls in response" do
        no_tool_response = mock_ollama_response.merge(
          "message" => { "role" => "assistant", "content" => "No tools used" }
        )

        parsed_tools = provider.send(:parse_tool_calls, no_tool_response)
        expect(parsed_tools).to eq([])
      end

      it "generates UUID when tool call ID is missing" do
        no_id_response = {
          "message" => {
            "tool_calls" => [{
              "function" => {
                "name" => "test_tool",
                "arguments" => "{}"
              }
            }]
          }
        }

        parsed = provider.send(:parse_tool_calls, no_id_response)
        expect(parsed[0]["id"]).to match(/^[0-9a-f-]{36}$/)  # UUID format
      end
    end
  end

  describe "#perform_stream_completion" do
    let(:provider) { described_class.new }
    let(:messages) { [{ role: "user", content: "Tell me a story" }] }
    let(:model) { "llama3.2" }

    let(:streaming_chunks) do
      [
        '{"model":"llama3.2","created_at":"2025-11-13T10:00:00Z","message":{"role":"assistant","content":"Once"},"done":false}',
        '{"model":"llama3.2","created_at":"2025-11-13T10:00:01Z","message":{"role":"assistant","content":" upon"},"done":false}',
        '{"model":"llama3.2","created_at":"2025-11-13T10:00:02Z","message":{"role":"assistant","content":" a"},"done":false}',
        '{"model":"llama3.2","created_at":"2025-11-13T10:00:03Z","message":{"role":"assistant","content":" time"},"done":false}',
        '{"model":"llama3.2","created_at":"2025-11-13T10:00:04Z","message":{"role":"assistant","content":""},"done":true,"done_reason":"stop","total_duration":5000000000,"load_duration":2000000000,"prompt_eval_count":10,"eval_count":20}'
      ]
    end

    before do
      allow(provider).to receive(:make_streaming_request) do |_body, &block|
        streaming_chunks.each { |chunk| block.call(chunk) }
      end
    end

    it "yields content chunks progressively" do
      chunks = []
      provider.perform_stream_completion(messages: messages, model: model) do |chunk|
        chunks << chunk
      end

      content_chunks = chunks.select { |c| c[:type] == "content" }
      expect(content_chunks.map { |c| c[:content] }).to eq(["Once", " upon", " a", " time"])
    end

    it "accumulates content correctly" do
      chunks = []
      provider.perform_stream_completion(messages: messages, model: model) do |chunk|
        chunks << chunk
      end

      accumulated = chunks.select { |c| c[:type] == "content" }.last
      expect(accumulated[:accumulated_content]).to eq("Once upon a time")
    end

    it "yields final chunk with metadata" do
      chunks = []
      provider.perform_stream_completion(messages: messages, model: model) do |chunk|
        chunks << chunk
      end

      final_chunk = chunks.last
      expect(final_chunk[:type]).to eq("finish")
      expect(final_chunk[:finish_reason]).to eq("stop")
      expect(final_chunk[:usage]["prompt_tokens"]).to eq(10)
      expect(final_chunk[:usage]["completion_tokens"]).to eq(20)
    end

    it "returns accumulated content and metadata" do
      result = provider.perform_stream_completion(messages: messages, model: model)
      expect(result[:content]).to eq("Once upon a time")
      expect(result[:model]).to eq("llama3.2")
      expect(result[:finish_reason]).to eq("stop")
    end

    context "with tool calls in streaming" do
      let(:streaming_tool_chunks) do
        [
          '{"model":"llama3.2","message":{"role":"assistant","content":"","tool_calls":[{"id":"call_1","function":{"name":"get_weather","arguments":"{\"location\":"}}]},"done":false}',
          '{"model":"llama3.2","message":{"role":"assistant","content":"","tool_calls":[{"id":"call_1","function":{"arguments":"\"Tokyo\"}"}}]},"done":false}',
          '{"model":"llama3.2","message":{"role":"assistant","content":""},"done":true,"done_reason":"stop","prompt_eval_count":15,"eval_count":10}'
        ]
      end

      before do
        allow(provider).to receive(:make_streaming_request) do |_body, &block|
          streaming_tool_chunks.each { |chunk| block.call(chunk) }
        end
      end

      it "yields tool call chunks progressively" do
        chunks = []
        provider.perform_stream_completion(messages: messages, model: model) do |chunk|
          chunks << chunk
        end

        tool_chunks = chunks.select { |c| c[:type] == "tool_calls" }
        expect(tool_chunks).not_to be_empty
      end

      it "accumulates tool calls correctly" do
        chunks = []
        provider.perform_stream_completion(messages: messages, model: model) do |chunk|
          chunks << chunk
        end

        tool_chunks = chunks.select { |c| c[:type] == "tool_calls" }
        last_tool_chunk = tool_chunks.last
        expect(last_tool_chunk[:accumulated_tool_calls]).to be_an(Array)
        expect(last_tool_chunk[:accumulated_tool_calls].length).to be > 0
      end

      it "includes both incremental and accumulated tool calls" do
        chunks = []
        provider.perform_stream_completion(messages: messages, model: model) do |chunk|
          chunks << chunk
        end

        tool_chunks = chunks.select { |c| c[:type] == "tool_calls" }
        tool_chunks.each do |chunk|
          expect(chunk[:tool_calls]).to be_an(Array)  # Incremental
          expect(chunk[:accumulated_tool_calls]).to be_an(Array)  # Accumulated
        end
      end
    end

    it "handles malformed JSON gracefully" do
      malformed_chunks = [
        '{"invalid json',
        '{"model":"llama3.2","message":{"role":"assistant","content":"valid"},"done":false}',
        '{"model":"llama3.2","message":{"role":"assistant","content":""},"done":true,"done_reason":"stop"}'
      ]

      allow(provider).to receive(:make_streaming_request) do |_body, &block|
        malformed_chunks.each { |chunk| block.call(chunk) }
      end

      expect(provider).to receive(:log_warn).with(/Failed to parse streaming chunk/, anything)

      result = provider.perform_stream_completion(messages: messages, model: model)
      expect(result[:content]).to eq("valid")
    end

    it "builds streaming request correctly" do
      expect(provider).to receive(:make_streaming_request).with(
        hash_including(
          model: model,
          messages: messages,
          stream: true
        )
      )

      provider.perform_stream_completion(messages: messages, model: model)
    end
  end

  describe "error handling" do
    let(:provider) { described_class.new }
    let(:messages) { [{ role: "user", content: "Hello" }] }
    let(:model) { "llama3.2" }

    describe "connection errors" do
      it "raises ConnectionError when Ollama is not running" do
        # Mock at Net::HTTP level to let rescue block in make_request handle it
        mock_http = double("http")
        allow(Net::HTTP).to receive(:new).and_return(mock_http)
        allow(mock_http).to receive(:read_timeout=)
        allow(mock_http).to receive(:request).and_raise(Errno::ECONNREFUSED)

        expect { provider.perform_chat_completion(messages: messages, model: model) }
          .to raise_error(RAAF::Models::ConnectionError, /Ollama not running. Start with: ollama serve/)
      end

      it "provides helpful error message for connection refused" do
        # Mock at Net::HTTP level to let rescue block in make_request handle it
        mock_http = double("http")
        allow(Net::HTTP).to receive(:new).and_return(mock_http)
        allow(mock_http).to receive(:read_timeout=)
        allow(mock_http).to receive(:request).and_raise(Errno::ECONNREFUSED)

        begin
          provider.perform_chat_completion(messages: messages, model: model)
        rescue RAAF::Models::ConnectionError => e
          expect(e.message).to include("ollama serve")
        end
      end
    end

    describe "model not found errors" do
      it "raises ModelNotFoundError for HTTP 404" do
        # Mock HTTP response with 404 status to trigger handle_api_error
        mock_http = double("http")
        mock_response = double("response", code: "404", body: "model not found")

        allow(Net::HTTP).to receive(:new).and_return(mock_http)
        allow(mock_http).to receive(:read_timeout=)
        allow(mock_http).to receive(:request).and_return(mock_response)

        expect { provider.perform_chat_completion(messages: messages, model: model) }
          .to raise_error(RAAF::Models::ModelNotFoundError, /Model not found/)
      end

      it "provides helpful error message with pull command" do
        mock_response = double("response", code: "404", body: "model not found")

        begin
          provider.send(:handle_api_error, mock_response)
        rescue RAAF::Models::ModelNotFoundError => e
          expect(e.message).to include("ollama pull")
        end
      end
    end

    describe "timeout errors" do
      it "respects custom timeout configuration" do
        long_timeout_provider = described_class.new(timeout: 300)
        expect(long_timeout_provider.http_timeout).to eq(300)
      end

      it "uses default timeout when not configured" do
        default_provider = described_class.new
        expect(default_provider.http_timeout).to eq(120)
      end

      it "can configure timeout via environment variable" do
        ENV["RAAF_OLLAMA_TIMEOUT"] = "240"
        env_provider = described_class.new
        expect(env_provider.http_timeout).to eq(240)
        ENV.delete("RAAF_OLLAMA_TIMEOUT")
      end
    end

    describe "HTTP error codes" do
      it "raises APIError for HTTP 400" do
        mock_response = double("response", code: "400", body: "bad request")
        expect { provider.send(:handle_api_error, mock_response) }
          .to raise_error(RAAF::Models::APIError, /Ollama API error: 400/)
      end

      it "raises APIError for HTTP 500" do
        mock_response = double("response", code: "500", body: "internal server error")
        expect { provider.send(:handle_api_error, mock_response) }
          .to raise_error(RAAF::Models::APIError, /Ollama API error: 500/)
      end

      it "raises APIError for HTTP 503" do
        mock_response = double("response", code: "503", body: "service unavailable")
        expect { provider.send(:handle_api_error, mock_response) }
          .to raise_error(RAAF::Models::APIError, /Ollama API error: 503/)
      end

      it "includes response body in error message" do
        mock_response = double("response", code: "500", body: "detailed error message")

        begin
          provider.send(:handle_api_error, mock_response)
        rescue RAAF::Models::APIError => e
          expect(e.message).to include("detailed error message")
        end
      end
    end

    describe "invalid JSON handling" do
      it "logs warning for malformed JSON in streaming" do
        malformed_chunks = ['{"invalid json']

        allow(provider).to receive(:make_streaming_request) do |_body, &block|
          malformed_chunks.each { |chunk| block.call(chunk) }
        end

        expect(provider).to receive(:log_warn).with(
          /Failed to parse streaming chunk/,
          hash_including(provider: "OllamaProvider")
        )

        provider.perform_stream_completion(messages: messages, model: model)
      end

      it "continues processing after JSON parse error" do
        mixed_chunks = [
          '{"invalid json',
          '{"model":"llama3.2","message":{"role":"assistant","content":"valid"},"done":false}',
          '{"model":"llama3.2","message":{"role":"assistant","content":""},"done":true,"done_reason":"stop"}'
        ]

        allow(provider).to receive(:make_streaming_request) do |_body, &block|
          mixed_chunks.each { |chunk| block.call(chunk) }
        end

        allow(provider).to receive(:log_warn)

        result = provider.perform_stream_completion(messages: messages, model: model)
        expect(result[:content]).to eq("valid")
      end
    end

    describe "streaming connection errors" do
      it "raises ConnectionError when Ollama not running during streaming" do
        # Mock at Net::HTTP level to let rescue block in make_streaming_request handle it
        mock_http = double("http")
        allow(Net::HTTP).to receive(:new).and_return(mock_http)
        allow(mock_http).to receive(:read_timeout=)
        allow(mock_http).to receive(:request).and_raise(Errno::ECONNREFUSED)

        expect { provider.perform_stream_completion(messages: messages, model: model) }
          .to raise_error(RAAF::Models::ConnectionError, /Ollama not running/)
      end
    end
  end

  describe "ProviderRegistry integration" do
    describe ".create" do
      it "creates OllamaProvider via ProviderRegistry" do
        provider = RAAF::ProviderRegistry.create(:ollama)
        expect(provider).to be_a(RAAF::Models::OllamaProvider)
      end

      it "accepts string provider name" do
        provider = RAAF::ProviderRegistry.create("ollama")
        expect(provider).to be_a(RAAF::Models::OllamaProvider)
      end

      it "passes host option to OllamaProvider" do
        provider = RAAF::ProviderRegistry.create(:ollama, host: "http://localhost:11434")
        expect(provider.instance_variable_get(:@host)).to eq("http://localhost:11434")
      end

      it "passes timeout option to OllamaProvider" do
        provider = RAAF::ProviderRegistry.create(:ollama, timeout: 60)
        expect(provider.instance_variable_get(:@http_timeout)).to eq(60)
      end

      it "passes multiple options to OllamaProvider" do
        provider = RAAF::ProviderRegistry.create(
          :ollama,
          host: "http://custom-host:11434",
          timeout: 120
        )
        expect(provider.instance_variable_get(:@host)).to eq("http://custom-host:11434")
        expect(provider.instance_variable_get(:@http_timeout)).to eq(120)
      end
    end

    describe ".registered?" do
      it "returns true for :ollama" do
        expect(RAAF::ProviderRegistry.registered?(:ollama)).to be true
      end

      it "returns true for string 'ollama'" do
        expect(RAAF::ProviderRegistry.registered?("ollama")).to be true
      end
    end

    describe ".providers" do
      it "includes :ollama in provider list" do
        providers = RAAF::ProviderRegistry.providers
        expect(providers).to include(:ollama)
      end
    end
  end
end
