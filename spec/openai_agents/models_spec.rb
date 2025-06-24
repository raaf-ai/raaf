# frozen_string_literal: true

require "spec_helper"
require "net/http"

RSpec.describe OpenAIAgents::Models do
  shared_examples "a model provider" do
    it "responds to required interface methods" do
      expect(provider).to respond_to(:chat_completion)
      expect(provider).to respond_to(:stream_completion)
      expect(provider).to respond_to(:supported_models)
      expect(provider).to respond_to(:provider_name)
    end

    it "validates supported models" do
      supported_models = provider.supported_models
      expect(supported_models).to be_an(Array)
      expect(supported_models).not_to be_empty

      valid_model = supported_models.first
      expect { provider.send(:validate_model, valid_model) }.not_to raise_error

      expect { provider.send(:validate_model, "unsupported-model") }.to raise_error(ArgumentError, /not supported/)
    end

    it "has a provider name" do
      expect(provider.provider_name).to be_a(String)
      expect(provider.provider_name).not_to be_empty
    end
  end

  describe OpenAIAgents::Models::ModelInterface do
    let(:interface) { described_class.new }

    describe "abstract methods" do
      it "raises NotImplementedError for chat_completion" do
        expect { interface.chat_completion(messages: [], model: "test") }.to raise_error(NotImplementedError)
      end

      it "raises NotImplementedError for stream_completion" do
        expect { interface.stream_completion(messages: [], model: "test") }.to raise_error(NotImplementedError)
      end

      it "raises NotImplementedError for supported_models" do
        expect { interface.supported_models }.to raise_error(NotImplementedError)
      end

      it "raises NotImplementedError for provider_name" do
        expect { interface.provider_name }.to raise_error(NotImplementedError)
      end
    end

    describe "#prepare_tools" do
      it "returns nil for nil tools" do
        expect(interface.send(:prepare_tools, nil)).to be_nil
      end

      it "returns nil for empty tools" do
        expect(interface.send(:prepare_tools, [])).to be_nil
      end

      it "handles hash tools" do
        tools = [{ type: "function", function: { name: "test" } }]
        result = interface.send(:prepare_tools, tools)

        expect(result).to eq(tools)
      end

      it "handles FunctionTool objects" do
        tool = OpenAIAgents::FunctionTool.new(proc { |value| value }, name: "test_tool")
        tools = [tool]

        result = interface.send(:prepare_tools, tools)

        expect(result).to be_an(Array)
        expect(result.first).to be_a(Hash)
        expect(result.first).to have_key(:type)
        expect(result.first).to have_key(:function)
      end

      it "raises error for invalid tool types" do
        tools = ["invalid_tool"]

        expect { interface.send(:prepare_tools, tools) }.to raise_error(ArgumentError, /Invalid tool type/)
      end

      it "handles mixed tool types" do
        tool_hash = { type: "function", function: { name: "hash_tool" } }
        tool_object = OpenAIAgents::FunctionTool.new(proc { |value| value }, name: "object_tool")
        tools = [tool_hash, tool_object]

        result = interface.send(:prepare_tools, tools)

        expect(result.size).to eq(2)
        expect(result.all? { |t| t.is_a?(Hash) }).to be true
      end
    end

    describe "#handle_api_error" do
      let(:mock_response) { double("response", code: "401", body: "Unauthorized") }

      it "raises AuthenticationError for 401" do
        mock_response = double("response", code: "401", body: "Unauthorized")

        expect do
          interface.send(:handle_api_error, mock_response,
                         "TestProvider")
        end.to raise_error(OpenAIAgents::Models::AuthenticationError, /Invalid API key/)
      end

      it "raises RateLimitError for 429" do
        mock_response = double("response", code: "429", body: "Rate limit exceeded")

        expect do
          interface.send(:handle_api_error, mock_response,
                         "TestProvider")
        end.to raise_error(OpenAIAgents::Models::RateLimitError, /Rate limit exceeded/)
      end

      it "raises ServerError for 5xx codes" do
        mock_response = double("response", code: "500", body: "Internal server error")

        expect do
          interface.send(:handle_api_error, mock_response,
                         "TestProvider")
        end.to raise_error(OpenAIAgents::Models::ServerError, /Server error/)
      end

      it "raises APIError for other error codes" do
        mock_response = double("response", code: "400", body: "Bad request")

        expect do
          interface.send(:handle_api_error, mock_response,
                         "TestProvider")
        end.to raise_error(OpenAIAgents::Models::APIError, /API error/)
      end
    end
  end

  describe OpenAIAgents::Models::OpenAIProvider do
    let(:api_key) { "sk-test-key" }
    let(:provider) { described_class.new(api_key: api_key) }

    it_behaves_like "a model provider"

    describe "#initialize" do
      it "requires API key" do
        allow(ENV).to receive(:fetch).with("OPENAI_API_KEY", nil).and_return(nil)
        expect { described_class.new }.to raise_error(OpenAIAgents::Models::AuthenticationError, /API key is required/)
      end

      it "accepts API key parameter" do
        provider = described_class.new(api_key: "sk-test")
        expect(provider.instance_variable_get(:@api_key)).to eq("sk-test")
      end

      it "reads API key from environment" do
        allow(ENV).to receive(:fetch).with("OPENAI_API_KEY", nil).and_return("sk-env-key")
        allow(ENV).to receive(:[]).with("OPENAI_API_BASE").and_return(nil)
        allow(ENV).to receive(:[]).with("OPENAI_ORG_ID").and_return(nil)
        allow(ENV).to receive(:[]).with("OPENAI_PROJECT_ID").and_return(nil)

        provider = described_class.new
        expect(provider.instance_variable_get(:@api_key)).to eq("sk-env-key")
      end

      it "uses default API base" do
        provider = described_class.new(api_key: "sk-test")
        expect(provider.instance_variable_get(:@api_base)).to eq("https://api.openai.com/v1")
      end

      it "accepts custom API base" do
        provider = described_class.new(api_key: "sk-test", api_base: "https://custom.api.com")
        expect(provider.instance_variable_get(:@api_base)).to eq("https://custom.api.com")
      end

      it "reads API base from environment" do
        allow(ENV).to receive(:fetch).with("OPENAI_API_KEY", nil).and_return("sk-test")
        allow(ENV).to receive(:[]).with("OPENAI_API_BASE").and_return("https://env.api.com")
        allow(ENV).to receive(:[]).with("OPENAI_ORG_ID").and_return(nil)
        allow(ENV).to receive(:[]).with("OPENAI_PROJECT_ID").and_return(nil)

        provider = described_class.new
        expect(provider.instance_variable_get(:@api_base)).to eq("https://env.api.com")
      end
    end

    describe "#supported_models" do
      it "returns array of supported models" do
        models = provider.supported_models

        expect(models).to include("gpt-4", "gpt-3.5-turbo", "gpt-4o")
        expect(models).to be_frozen
      end
    end

    describe "#provider_name" do
      it "returns OpenAI" do
        expect(provider.provider_name).to eq("OpenAI")
      end
    end

    describe "#chat_completion" do
      let(:messages) { [{ role: "user", content: "Hello" }] }
      let(:model) { "gpt-4" }

      it "validates model before making request" do
        expect do
          provider.chat_completion(messages: messages, model: "invalid-model")
        end.to raise_error(ArgumentError, /not supported/)
      end
    end

    describe "#stream_completion" do
      let(:messages) { [{ role: "user", content: "Hello" }] }
      let(:model) { "gpt-4" }

      it "validates model before streaming" do
        expect do
          provider.stream_completion(messages: messages, model: "invalid-model")
        end.to raise_error(ArgumentError, /not supported/)
      end
    end

    describe "streaming chunk processing" do
      let(:provider) { described_class.new(api_key: api_key) }

      describe "#process_content_delta" do
        it "accumulates content and yields chunks" do
          accumulated_content = String.new
          yielded_chunks = []

          delta = { "content" => "Hello" }
          provider.send(:process_content_delta, delta, accumulated_content) do |chunk|
            yielded_chunks << chunk
          end

          expect(accumulated_content).to eq("Hello")
          expect(yielded_chunks.first[:type]).to eq("content")
          expect(yielded_chunks.first[:content]).to eq("Hello")
          expect(yielded_chunks.first[:accumulated_content]).to eq("Hello")
        end

        it "ignores deltas without content" do
          accumulated_content = ""
          yielded_chunks = []

          delta = { "role" => "assistant" }
          provider.send(:process_content_delta, delta, accumulated_content) do |chunk|
            yielded_chunks << chunk
          end

          expect(accumulated_content).to eq("")
          expect(yielded_chunks).to be_empty
        end
      end

      describe "#process_tool_call_delta" do
        it "accumulates tool calls and yields chunks" do
          accumulated_tool_calls = {}
          yielded_chunks = []

          delta = {
            "tool_calls" => [
              {
                "index" => 0,
                "id" => "call_123",
                "function" => { "name" => "test", "arguments" => "{" }
              }
            ]
          }

          provider.send(:process_tool_call_delta, delta, accumulated_tool_calls) do |chunk|
            yielded_chunks << chunk
          end

          expect(accumulated_tool_calls[0]["id"]).to eq("call_123")
          expect(accumulated_tool_calls[0]["function"]["name"]).to eq("test")
          expect(yielded_chunks.first[:type]).to eq("tool_call")
        end

        it "handles incremental tool call building" do
          accumulated_tool_calls = {}

          # First chunk - start of tool call
          delta1 = {
            "tool_calls" => [
              {
                "index" => 0,
                "id" => "call_",
                "function" => { "name" => "get_", "arguments" => "{\"ci" }
              }
            ]
          }

          # Second chunk - continuation
          delta2 = {
            "tool_calls" => [
              {
                "index" => 0,
                "id" => "123",
                "function" => { "name" => "weather", "arguments" => "ty\": \"" }
              }
            ]
          }

          provider.send(:process_tool_call_delta, delta1, accumulated_tool_calls)
          provider.send(:process_tool_call_delta, delta2, accumulated_tool_calls)

          expect(accumulated_tool_calls[0]["id"]).to eq("call_123")
          expect(accumulated_tool_calls[0]["function"]["name"]).to eq("get_weather")
          expect(accumulated_tool_calls[0]["function"]["arguments"]).to eq("{\"city\": \"")
        end
      end

      describe "#process_finish_reason" do
        it "yields finish event when finish_reason is present" do
          yielded_chunks = []

          json_data = {
            "choices" => [
              { "finish_reason" => "stop" }
            ]
          }

          provider.send(:process_finish_reason, json_data, "content", {}) do |chunk|
            yielded_chunks << chunk
          end

          expect(yielded_chunks.first[:type]).to eq("finish")
          expect(yielded_chunks.first[:finish_reason]).to eq("stop")
        end

        it "ignores data without finish_reason" do
          yielded_chunks = []

          json_data = {
            "choices" => [
              { "delta" => { "content" => "hello" } }
            ]
          }

          provider.send(:process_finish_reason, json_data, "content", {}) do |chunk|
            yielded_chunks << chunk
          end

          expect(yielded_chunks).to be_empty
        end
      end
    end
  end

  describe OpenAIAgents::Models::AnthropicProvider do
    let(:api_key) { "sk-ant-test-key" }
    let(:provider) { described_class.new(api_key: api_key) }

    it_behaves_like "a model provider"

    describe "#initialize" do
      it "requires API key" do
        expect { described_class.new }.to raise_error(OpenAIAgents::Models::AuthenticationError, /API key is required/)
      end

      it "accepts API key parameter" do
        provider = described_class.new(api_key: "sk-ant-test")
        expect(provider.instance_variable_get(:@api_key)).to eq("sk-ant-test")
      end

      it "reads API key from environment" do
        allow(ENV).to receive(:fetch).with("ANTHROPIC_API_KEY", nil).and_return("sk-ant-env-key")
        allow(ENV).to receive(:[]).with("ANTHROPIC_API_BASE").and_return(nil)

        provider = described_class.new
        expect(provider.instance_variable_get(:@api_key)).to eq("sk-ant-env-key")
      end

      it "uses default API base" do
        provider = described_class.new(api_key: "sk-ant-test")
        expect(provider.instance_variable_get(:@api_base)).to eq("https://api.anthropic.com")
      end

      it "accepts custom API base" do
        provider = described_class.new(api_key: "sk-ant-test", api_base: "https://custom.anthropic.com")
        expect(provider.instance_variable_get(:@api_base)).to eq("https://custom.anthropic.com")
      end
    end

    describe "#supported_models" do
      it "returns array of supported Claude models" do
        models = provider.supported_models

        expect(models).to include("claude-3-5-sonnet-20241022", "claude-3-opus-20240229")
        expect(models).to be_frozen
      end
    end

    describe "#provider_name" do
      it "returns Anthropic" do
        expect(provider.provider_name).to eq("Anthropic")
      end
    end
  end

  describe "Error classes" do
    it "defines model-specific error hierarchy" do
      expect(OpenAIAgents::Models::AuthenticationError).to be < OpenAIAgents::Error
      expect(OpenAIAgents::Models::RateLimitError).to be < OpenAIAgents::Error
      expect(OpenAIAgents::Models::ServerError).to be < OpenAIAgents::Error
      expect(OpenAIAgents::Models::APIError).to be < OpenAIAgents::Error
    end
  end
end
