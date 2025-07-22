# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Models::ModelInterface do
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
      tool = RAAF::FunctionTool.new(proc { |value| value }, name: "test_tool")
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
      tool_object = RAAF::FunctionTool.new(proc { |value| value }, name: "object_tool")
      tools = [tool_hash, tool_object]

      result = interface.send(:prepare_tools, tools)

      expect(result.size).to eq(2)
      expect(result.all? { |t| t.is_a?(Hash) }).to be true
    end
  end

  describe "#handle_api_error" do
    it "raises AuthenticationError for 401" do
      mock_response = double("response", code: "401", body: "Unauthorized")

      expect do
        interface.send(:handle_api_error, mock_response, "TestProvider")
      end.to raise_error(RAAF::Models::AuthenticationError, /Invalid API key/)
    end

    it "raises RateLimitError for 429" do
      mock_response = double("response", code: "429", body: "Rate limit exceeded")

      expect do
        interface.send(:handle_api_error, mock_response, "TestProvider")
      end.to raise_error(RAAF::Models::RateLimitError, /Rate limit exceeded/)
    end

    it "raises ServerError for 5xx codes" do
      mock_response = double("response", code: "500", body: "Internal server error")

      expect do
        interface.send(:handle_api_error, mock_response, "TestProvider")
      end.to raise_error(RAAF::Models::ServerError, /Server error/)
    end

    it "raises APIError for other error codes" do
      mock_response = double("response", code: "400", body: "Bad request")

      expect do
        interface.send(:handle_api_error, mock_response, "TestProvider")
      end.to raise_error(RAAF::Models::APIError, /API error/)
    end
  end
end