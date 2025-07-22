# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Core Error Handling" do
  let(:mock_agent) { double("Agent", name: "TestAgent", tools: [], handoffs: []) }

  describe RAAF::Errors::ModelBehaviorError do
    it "captures model response context" do
      response = { error: "Invalid format" }
      error = described_class.new(
        "Model returned invalid response",
        model_response: response,
        agent: mock_agent
      )

      expect(error.message).to eq("Model returned invalid response")
      expect(error.model_response).to eq(response)
      expect(error.agent).to eq(mock_agent)
    end
  end

  describe RAAF::Errors::ToolExecutionError do
    it "captures tool execution context" do
      tool = double("Tool", name: "get_weather")
      arguments = { location: "NYC" }
      original_error = StandardError.new("Network timeout")

      error = described_class.new(
        "Tool execution failed",
        tool: tool,
        tool_arguments: arguments,
        original_error: original_error,
        agent: mock_agent
      )

      expect(error.tool_name).to eq("get_weather")
      expect(error.tool_arguments).to eq(arguments)
      expect(error.original_error).to eq(original_error)
    end
  end

  describe RAAF::ErrorHandling do
    describe ".validate_model_response" do
      it "validates non-nil response" do
        expect do
          described_class.validate_model_response(nil, mock_agent)
        end.to raise_error(RAAF::Errors::ModelBehaviorError, /Model response is nil/)
      end

      it "validates hash structure" do
        expect do
          described_class.validate_model_response("not a hash", mock_agent)
        end.to raise_error(RAAF::Errors::ModelBehaviorError, /not a hash/)
      end

      it "validates content structure" do
        expect do
          described_class.validate_model_response({}, mock_agent)
        end.to raise_error(RAAF::Errors::ModelBehaviorError, /missing expected content/)
      end

      it "passes valid responses" do
        valid_response = { output: [{ type: "message", content: "Hello" }] }
        expect do
          described_class.validate_model_response(valid_response, mock_agent)
        end.not_to raise_error
      end
    end

    describe ".safe_agent_name" do
      it "handles various agent identifier formats" do
        expect(described_class.safe_agent_name(nil)).to be_nil
        expect(described_class.safe_agent_name("AgentName")).to eq("AgentName")

        agent_obj = double("Agent", name: "ObjectAgent")
        expect(described_class.safe_agent_name(agent_obj)).to eq("ObjectAgent")
      end
    end
  end
end
