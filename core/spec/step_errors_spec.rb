# frozen_string_literal: true

require "spec_helper"

RSpec.describe "RAAF::Errors" do
  let(:test_agent) { RAAF::Agent.new(name: "TestAgent", instructions: "Test instructions") }

  describe RAAF::Errors::StepProcessingError do
    it "stores agent and step data" do
      error = described_class.new(
        "Step failed",
        agent: test_agent,
        step_data: { step: 1, action: "process" }
      )

      expect(error.message).to eq("Step failed")
      expect(error.agent).to eq(test_agent)
      expect(error.step_data).to eq({ step: 1, action: "process" })
    end

    it "works without optional parameters" do
      error = described_class.new("Simple error")
      
      expect(error.message).to eq("Simple error")
      expect(error.agent).to be_nil
      expect(error.step_data).to be_nil
    end
  end

  describe RAAF::Errors::ModelBehaviorError do
    it "stores model response" do
      response = { output: nil, error: "Invalid format" }
      error = described_class.new(
        "Model returned invalid response",
        model_response: response,
        agent: test_agent
      )

      expect(error.message).to eq("Model returned invalid response")
      expect(error.model_response).to eq(response)
      expect(error.agent).to eq(test_agent)
    end

    it "inherits from StepProcessingError" do
      error = described_class.new("Test")
      expect(error).to be_a(RAAF::Errors::StepProcessingError)
    end
  end

  describe RAAF::Errors::UserError do
    it "represents user configuration errors" do
      error = described_class.new(
        "Invalid configuration provided",
        agent: test_agent,
        step_data: { config: "invalid" }
      )

      expect(error.message).to eq("Invalid configuration provided")
      expect(error).to be_a(RAAF::Errors::StepProcessingError)
    end
  end

  describe RAAF::Errors::AgentError do
    it "represents agent execution errors" do
      error = described_class.new(
        "Agent execution failed",
        agent: test_agent,
        step_data: { turn: 5 }
      )

      expect(error.message).to eq("Agent execution failed")
      expect(error.agent).to eq(test_agent)
    end
  end

  describe RAAF::Errors::ToolExecutionError do
    let(:test_tool) { RAAF::FunctionTool.new(proc { "result" }, name: "test_tool") }
    let(:original_error) { StandardError.new("Tool crashed") }

    it "stores tool execution context" do
      error = described_class.new(
        "Tool execution failed",
        tool: test_tool,
        tool_arguments: { input: "test" },
        original_error: original_error,
        agent: test_agent
      )

      expect(error.message).to eq("Tool execution failed")
      expect(error.tool).to eq(test_tool)
      expect(error.tool_arguments).to eq({ input: "test" })
      expect(error.original_error).to eq(original_error)
      expect(error.agent).to eq(test_agent)
    end

    describe "#tool_name" do
      it "returns tool name when tool responds to name" do
        error = described_class.new("Error", tool: test_tool)
        expect(error.tool_name).to eq("test_tool")
      end

      it "returns string representation when tool doesn't respond to name" do
        error = described_class.new("Error", tool: "string_tool")
        expect(error.tool_name).to eq("string_tool")
      end

      it "handles nil tool" do
        error = described_class.new("Error", tool: nil)
        expect(error.tool_name).to eq("")
      end
    end
  end

  describe RAAF::Errors::HandoffError do
    let(:source_agent) { RAAF::Agent.new(name: "SourceAgent") }
    let(:target_agent) { RAAF::Agent.new(name: "TargetAgent") }

    it "stores handoff context" do
      handoff_data = { reason: "Escalation needed", context: "user request" }
      error = described_class.new(
        "Handoff failed",
        source_agent: source_agent,
        target_agent: target_agent,
        handoff_data: handoff_data
      )

      expect(error.message).to eq("Handoff failed")
      expect(error.source_agent).to eq(source_agent)
      expect(error.target_agent).to eq(target_agent)
      expect(error.handoff_data).to eq(handoff_data)
    end

    it "works with string agent names" do
      error = described_class.new(
        "Handoff error",
        source_agent: "Agent1",
        target_agent: "Agent2"
      )

      expect(error.source_agent).to eq("Agent1")
      expect(error.target_agent).to eq("Agent2")
    end
  end

  describe RAAF::Errors::ResponseProcessingError do
    it "stores response that caused the error" do
      bad_response = { invalid: "structure" }
      error = described_class.new(
        "Failed to process response",
        response: bad_response,
        agent: test_agent
      )

      expect(error.message).to eq("Failed to process response")
      expect(error.response).to eq(bad_response)
      expect(error.agent).to eq(test_agent)
    end
  end

  describe RAAF::Errors::CircularHandoffError do
    it "stores handoff chain that caused the loop" do
      chain = ["Agent1", "Agent2", "Agent3", "Agent1"]
      error = described_class.new(
        "Circular handoff detected",
        handoff_chain: chain,
        source_agent: "Agent3",
        target_agent: "Agent1"
      )

      expect(error.message).to eq("Circular handoff detected")
      expect(error.handoff_chain).to eq(chain)
      expect(error).to be_a(RAAF::Errors::HandoffError)
    end
  end

  describe RAAF::Errors::MaxIterationsError do
    it "stores iteration counts" do
      error = described_class.new(
        "Maximum iterations exceeded",
        max_iterations: 100,
        current_iterations: 101,
        agent: test_agent
      )

      expect(error.message).to eq("Maximum iterations exceeded")
      expect(error.max_iterations).to eq(100)
      expect(error.current_iterations).to eq(101)
      expect(error.agent).to eq(test_agent)
    end
  end
end

RSpec.describe RAAF::ErrorHandling do
  let(:test_agent) { RAAF::Agent.new(name: "TestAgent", instructions: "Test") }

  describe ".with_error_handling" do
    context "when block succeeds" do
      it "returns the block result" do
        result = described_class.with_error_handling(
          context: { operation: "test" },
          agent: test_agent
        ) do
          "success"
        end

        expect(result).to eq("success")
      end
    end

    context "when StepProcessingError is raised" do
      it "re-raises with additional context" do
        original_error = RAAF::Errors::AgentError.new("Agent failed")
        context = { operation: "test", step: 1 }

        expect do
          described_class.with_error_handling(context: context, agent: test_agent) do
            raise original_error
          end
        end.to raise_error(RAAF::Errors::AgentError) do |error|
          expect(error.message).to eq("Agent failed")
          expect(error.context).to eq(context)
          expect(error.agent).to eq(test_agent)
        end
      end

      it "preserves original agent if already set" do
        original_agent = RAAF::Agent.new(name: "OriginalAgent")
        original_error = RAAF::Errors::AgentError.new("Failed", agent: original_agent)

        expect do
          described_class.with_error_handling(agent: test_agent) do
            raise original_error
          end
        end.to raise_error(RAAF::Errors::AgentError) do |error|
          expect(error.agent).to eq(original_agent)
        end
      end
    end

    context "when JSON::ParserError is raised" do
      it "converts to ResponseProcessingError" do
        expect do
          described_class.with_error_handling(agent: test_agent) do
            raise JSON::ParserError, "Invalid JSON"
          end
        end.to raise_error(RAAF::Errors::ResponseProcessingError) do |error|
          expect(error.message).to include("Failed to parse JSON")
          expect(error.agent).to eq(test_agent)
        end
      end
    end

    context "when NoMethodError is raised" do
      it "converts nil errors to ModelBehaviorError" do
        expect do
          described_class.with_error_handling(agent: test_agent) do
            raise NoMethodError, "undefined method `foo' for nil:NilClass"
          end
        end.to raise_error(RAAF::Errors::ModelBehaviorError) do |error|
          expect(error.message).to include("Unexpected nil value")
          expect(error.agent).to eq(test_agent)
        end
      end

      it "converts other NoMethodErrors to AgentError" do
        expect do
          described_class.with_error_handling(agent: test_agent) do
            raise NoMethodError, "undefined method `bar' for String"
          end
        end.to raise_error(RAAF::Errors::AgentError) do |error|
          expect(error.message).to include("Agent execution error")
          expect(error.agent).to eq(test_agent)
        end
      end
    end

    context "when StandardError is raised" do
      it "converts to StepProcessingError" do
        expect do
          described_class.with_error_handling(agent: test_agent) do
            raise StandardError, "Generic error"
          end
        end.to raise_error(RAAF::Errors::StepProcessingError) do |error|
          expect(error.message).to include("Unexpected error")
          expect(error.message).to include("Generic error")
          expect(error.agent).to eq(test_agent)
        end
      end
    end
  end

  describe ".safe_tool_execution" do
    let(:test_tool) { RAAF::FunctionTool.new(proc { |x| x * 2 }, name: "multiply") }

    it "executes tool successfully" do
      result = described_class.safe_tool_execution(
        tool: test_tool,
        arguments: { x: 5 },
        agent: test_agent
      ) do
        10
      end

      expect(result).to eq(10)
    end

    it "handles ToolExecutionError gracefully" do
      original_error = RuntimeError.new("Tool crashed")
      
      result = described_class.safe_tool_execution(
        tool: test_tool,
        arguments: { x: 5 },
        agent: test_agent
      ) do
        raise RAAF::Errors::ToolExecutionError.new(
          "Execution failed",
          tool: test_tool,
          original_error: original_error
        )
      end

      expect(result).to eq("Error executing tool multiply: Execution failed")
    end

    it "handles other StepProcessingErrors" do
      result = described_class.safe_tool_execution(
        tool: test_tool,
        arguments: {},
        agent: test_agent
      ) do
        raise RAAF::Errors::AgentError.new("Agent issue")
      end

      expect(result).to eq("Error: Agent issue")
    end
  end

  describe ".validate_model_response" do
    it "accepts valid hash response with output" do
      response = { output: [{ type: "message", content: "test" }] }
      
      expect do
        described_class.validate_model_response(response, test_agent)
      end.not_to raise_error
    end

    it "accepts valid hash response with choices" do
      response = { choices: [{ message: { content: "test" } }] }
      
      expect do
        described_class.validate_model_response(response, test_agent)
      end.not_to raise_error
    end

    it "accepts valid hash response with content" do
      response = { content: "test response" }
      
      expect do
        described_class.validate_model_response(response, test_agent)
      end.not_to raise_error
    end

    it "raises error for nil response" do
      expect do
        described_class.validate_model_response(nil, test_agent)
      end.to raise_error(RAAF::Errors::ModelBehaviorError, "Model response is nil")
    end

    it "raises error for non-hash response" do
      expect do
        described_class.validate_model_response("string response", test_agent)
      end.to raise_error(RAAF::Errors::ModelBehaviorError, "Model response is not a hash")
    end

    it "raises error for response without expected structure" do
      response = { invalid: "structure" }
      
      expect do
        described_class.validate_model_response(response, test_agent)
      end.to raise_error(RAAF::Errors::ModelBehaviorError) do |error|
        expect(error.message).to include("missing expected content structure")
        expect(error.model_response).to eq(response)
        expect(error.agent).to eq(test_agent)
      end
    end
  end

  describe ".safe_agent_name" do
    it "returns nil for nil input" do
      expect(described_class.safe_agent_name(nil)).to be_nil
    end

    it "returns string input unchanged" do
      expect(described_class.safe_agent_name("AgentName")).to eq("AgentName")
    end

    it "extracts name from Agent object" do
      agent = RAAF::Agent.new(name: "TestAgent")
      expect(described_class.safe_agent_name(agent)).to eq("TestAgent")
    end

    it "calls name method on objects that respond to it" do
      obj = double("agent_like", name: "CustomAgent")
      expect(described_class.safe_agent_name(obj)).to eq("CustomAgent")
    end

    it "converts other objects to string" do
      expect(described_class.safe_agent_name(123)).to eq("123")
      expect(described_class.safe_agent_name(:symbol)).to eq("symbol")
    end
  end
end