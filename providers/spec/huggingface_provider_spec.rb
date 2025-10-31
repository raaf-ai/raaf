# frozen_string_literal: true

require "spec_helper"
require "raaf/huggingface_provider"

RSpec.describe RAAF::Models::HuggingFaceProvider do
  let(:api_key) { "test_huggingface_key" }
  let(:provider) { described_class.new(api_key: api_key) }

  describe "#initialize" do
    it "initializes with explicit API key" do
      expect(provider.instance_variable_get(:@api_key)).to eq(api_key)
    end

    it "uses HUGGINGFACE_API_KEY environment variable" do
      ENV["HUGGINGFACE_API_KEY"] = "env_key"
      provider = described_class.new
      expect(provider.instance_variable_get(:@api_key)).to eq("env_key")
      ENV.delete("HUGGINGFACE_API_KEY")
    end

    it "falls back to HF_TOKEN environment variable" do
      ENV["HF_TOKEN"] = "hf_token"
      provider = described_class.new
      expect(provider.instance_variable_get(:@api_key)).to eq("hf_token")
      ENV.delete("HF_TOKEN")
    end

    it "prefers HUGGINGFACE_API_KEY over HF_TOKEN" do
      ENV["HUGGINGFACE_API_KEY"] = "primary_key"
      ENV["HF_TOKEN"] = "fallback_key"
      provider = described_class.new
      expect(provider.instance_variable_get(:@api_key)).to eq("primary_key")
      ENV.delete("HUGGINGFACE_API_KEY")
      ENV.delete("HF_TOKEN")
    end

    it "raises error when no API key is provided" do
      expect { described_class.new }.to raise_error(RAAF::AuthenticationError, /API key is required/)
    end

    it "uses default API base" do
      expect(provider.instance_variable_get(:@api_base)).to eq("https://router.huggingface.co/v1")
    end

    it "uses custom API base when provided" do
      custom_provider = described_class.new(api_key: api_key, api_base: "https://custom.endpoint.com/v1")
      expect(custom_provider.instance_variable_get(:@api_base)).to eq("https://custom.endpoint.com/v1")
    end

    it "uses environment variable for API base" do
      ENV["HUGGINGFACE_API_BASE"] = "https://env.endpoint.com/v1"
      provider = described_class.new(api_key: api_key)
      expect(provider.instance_variable_get(:@api_base)).to eq("https://env.endpoint.com/v1")
      ENV.delete("HUGGINGFACE_API_BASE")
    end

    it "uses default timeout" do
      expect(provider.http_timeout).to eq(180)
    end

    it "uses custom timeout when provided" do
      custom_provider = described_class.new(api_key: api_key, timeout: 300)
      expect(custom_provider.http_timeout).to eq(300)
    end

    it "uses environment variable for timeout" do
      ENV["HUGGINGFACE_TIMEOUT"] = "240"
      provider = described_class.new(api_key: api_key)
      expect(provider.http_timeout).to eq(240)
      ENV.delete("HUGGINGFACE_TIMEOUT")
    end
  end

  describe "#provider_name" do
    it "returns HuggingFace" do
      expect(provider.provider_name).to eq("HuggingFace")
    end
  end

  describe "#supported_models" do
    it "returns array of verified models" do
      models = provider.supported_models
      expect(models).to be_an(Array)
      expect(models).to include("deepseek-ai/DeepSeek-R1-0528")
      expect(models).to include("meta-llama/Llama-3-70B-Instruct")
      expect(models).to include("mistralai/Mixtral-8x7B-Instruct-v0.1")
      expect(models).to include("microsoft/phi-4")
    end
  end

  describe "#perform_chat_completion" do
    let(:messages) { [{ role: "user", content: "Hello!" }] }
    let(:model) { "deepseek-ai/DeepSeek-R1-0528" }

    let(:mock_response) do
      {
        "choices" => [{
          "message" => {
            "role" => "assistant",
            "content" => "Hello! How can I help you today?"
          },
          "finish_reason" => "stop"
        }],
        "usage" => {
          "prompt_tokens" => 10,
          "completion_tokens" => 20,
          "total_tokens" => 30
        },
        "model" => model
      }
    end

    before do
      allow(provider).to receive(:make_api_call).and_return(mock_response)
    end

    it "validates model format" do
      expect { provider.perform_chat_completion(messages: messages, model: "invalid-model") }
        .to raise_error(ArgumentError, /must use format: org\/model-name/)
    end

    it "logs warning for unverified models" do
      unverified_model = "custom-org/custom-model"
      expect(provider).to receive(:log_warn).with(
        /not in the verified models list/,
        hash_including(provider: "HuggingFaceProvider", model: unverified_model)
      )
      provider.perform_chat_completion(messages: messages, model: unverified_model)
    end

    it "does not log warning for verified models" do
      expect(provider).not_to receive(:log_warn).with(/not in the verified models list/, anything)
      provider.perform_chat_completion(messages: messages, model: model)
    end

    it "builds correct request body" do
      expect(provider).to receive(:make_api_call).with(
        hash_including(
          model: model,
          messages: messages,
          stream: false
        )
      ).and_return(mock_response)

      provider.perform_chat_completion(messages: messages, model: model)
    end

    it "includes temperature parameter when provided" do
      expect(provider).to receive(:make_api_call).with(
        hash_including(temperature: 0.7)
      ).and_return(mock_response)

      provider.perform_chat_completion(messages: messages, model: model, temperature: 0.7)
    end

    it "includes max_tokens parameter when provided" do
      expect(provider).to receive(:make_api_call).with(
        hash_including(max_tokens: 1024)
      ).and_return(mock_response)

      provider.perform_chat_completion(messages: messages, model: model, max_tokens: 1024)
    end

    it "returns OpenAI-compatible response" do
      result = provider.perform_chat_completion(messages: messages, model: model)
      expect(result).to eq(mock_response)
      expect(result["choices"]).to be_an(Array)
      expect(result["choices"][0]["message"]["content"]).to eq("Hello! How can I help you today?")
      expect(result["usage"]).to be_a(Hash)
    end

    context "with tools" do
      let(:tools) do
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

      it "includes prepared tools in request" do
        expect(provider).to receive(:prepare_tools).with(tools).and_call_original
        expect(provider).to receive(:make_api_call).with(
          hash_including(tools: anything)
        ).and_return(mock_response)

        provider.perform_chat_completion(messages: messages, model: model, tools: tools)
      end

      it "logs warning when using tools with non-function-calling model" do
        non_fc_model = "custom-org/non-function-calling-model"
        expect(provider).to receive(:log_warn).with(
          /may not support function calling/,
          hash_including(provider: "HuggingFaceProvider", model: non_fc_model)
        )

        provider.perform_chat_completion(messages: messages, model: non_fc_model, tools: tools)
      end

      it "does not log warning for verified function-calling models" do
        expect(provider).not_to receive(:log_warn).with(/may not support function calling/, anything)
        provider.perform_chat_completion(messages: messages, model: model, tools: tools)
      end

      it "includes tool_choice when provided" do
        expect(provider).to receive(:make_api_call).with(
          hash_including(tool_choice: "auto")
        ).and_return(mock_response)

        provider.perform_chat_completion(messages: messages, model: model, tools: tools, tool_choice: "auto")
      end
    end
  end

  describe "#perform_stream_completion" do
    let(:messages) { [{ role: "user", content: "Tell me a story" }] }
    let(:model) { "deepseek-ai/DeepSeek-R1-0528" }

    let(:sse_chunks) do
      [
        'data: {"choices":[{"delta":{"content":"Once"},"index":0}]}',
        'data: {"choices":[{"delta":{"content":" upon"},"index":0}]}',
        'data: {"choices":[{"delta":{"content":" a"},"index":0}]}',
        'data: {"choices":[{"delta":{"content":" time"},"index":0}]}',
        "data: [DONE]"
      ]
    end

    before do
      allow(provider).to receive(:make_streaming_request) do |_body, &block|
        sse_chunks.each { |chunk| block.call(chunk) }
      end
    end

    it "validates model format" do
      expect { provider.perform_stream_completion(messages: messages, model: "invalid") }
        .to raise_error(ArgumentError, /must use format: org\/model-name/)
    end

    it "yields content chunks" do
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

      final_chunk = chunks.last
      expect(final_chunk[:type]).to eq("finish")
      expect(final_chunk[:accumulated_content]).to eq("Once upon a time")
    end

    it "returns final accumulated content" do
      result = provider.perform_stream_completion(messages: messages, model: model)
      expect(result[:content]).to eq("Once upon a time")
      expect(result[:tool_calls]).to eq([])
    end

    context "with tool calls" do
      let(:sse_chunks_with_tools) do
        [
          'data: {"choices":[{"delta":{"tool_calls":[{"id":"call_1","type":"function","function":{"name":"get_weather","arguments":"{\"location\":\"Tokyo\"}"}}]},"index":0}]}',
          "data: [DONE]"
        ]
      end

      before do
        allow(provider).to receive(:make_streaming_request) do |_body, &block|
          sse_chunks_with_tools.each { |chunk| block.call(chunk) }
        end
      end

      it "yields tool call chunks" do
        chunks = []
        provider.perform_stream_completion(messages: messages, model: model) do |chunk|
          chunks << chunk
        end

        tool_chunks = chunks.select { |c| c[:type] == "tool_calls" }
        expect(tool_chunks).not_to be_empty
        expect(tool_chunks.first[:tool_calls]).to be_an(Array)
      end

      it "accumulates tool calls" do
        result = provider.perform_stream_completion(messages: messages, model: model)
        expect(result[:tool_calls]).to be_an(Array)
        expect(result[:tool_calls].length).to be > 0
      end
    end

    it "handles malformed JSON gracefully" do
      malformed_chunks = [
        'data: {"invalid json',
        'data: {"choices":[{"delta":{"content":"valid"},"index":0}]}',
        "data: [DONE]"
      ]

      allow(provider).to receive(:make_streaming_request) do |_body, &block|
        malformed_chunks.each { |chunk| block.call(chunk) }
      end

      expect(provider).to receive(:log_warn).with(/Failed to parse streaming chunk/, anything)

      result = provider.perform_stream_completion(messages: messages, model: model)
      expect(result[:content]).to eq("valid")
    end
  end

  describe "private methods" do
    describe "#validate_model" do
      it "accepts models with org/model format" do
        expect { provider.send(:validate_model, "org/model") }.not_to raise_error
      end

      it "rejects models without org prefix" do
        expect { provider.send(:validate_model, "just-model-name") }
          .to raise_error(ArgumentError, /must use format: org\/model-name/)
      end

      it "logs warning for unverified models" do
        expect(provider).to receive(:log_warn).with(
          /not in the verified models list/,
          hash_including(provider: "HuggingFaceProvider")
        )
        provider.send(:validate_model, "custom-org/unverified-model")
      end
    end

    describe "#build_request_body" do
      let(:messages) { [{ role: "user", content: "Test" }] }
      let(:model) { "deepseek-ai/DeepSeek-R1-0528" }

      it "builds basic request body" do
        body = provider.send(:build_request_body, messages, model, nil)
        expect(body[:model]).to eq(model)
        expect(body[:messages]).to eq(messages)
      end

      it "includes generation parameters" do
        body = provider.send(:build_request_body, messages, model, nil,
                             temperature: 0.7,
                             max_tokens: 1024,
                             top_p: 0.9)

        expect(body[:temperature]).to eq(0.7)
        expect(body[:max_tokens]).to eq(1024)
        expect(body[:top_p]).to eq(0.9)
      end

      it "includes tools when provided" do
        tools = [{ type: "function", function: { name: "test" } }]
        allow(provider).to receive(:prepare_tools).and_return(tools)

        body = provider.send(:build_request_body, messages, model, tools)
        expect(body[:tools]).to eq(tools)
      end
    end
  end
end
