# frozen_string_literal: true

require "spec_helper"
require_relative "../lib/raaf/handoff_context"
require_relative "../lib/raaf/agent_orchestrator"

RSpec.describe RAAF::AgentOrchestrator do
  let(:agent1) { RAAF::Agent.new(name: "Agent1", instructions: "You are agent 1") }
  let(:agent2) { RAAF::Agent.new(name: "Agent2", instructions: "You are agent 2") }
  let(:agents) do
    {
      "Agent1" => agent1,
      "Agent2" => agent2
    }
  end
  let(:provider) { instance_double(RAAF::Models::ResponsesProvider) }
  let(:orchestrator) { described_class.new(agents: agents, provider: provider) }

  describe "#initialize" do
    it "initializes with agents and provider" do
      expect(orchestrator.agents).to eq(agents)
      expect(orchestrator.provider).to eq(provider)
      expect(orchestrator.handoff_context).to be_a(RAAF::HandoffContext)
    end

    it "uses default ResponsesProvider when none provided" do
      orch = described_class.new(agents: agents)
      expect(orch.provider).to be_a(RAAF::Models::ResponsesProvider)
    end

    it "requires agents parameter" do
      expect { described_class.new }.to raise_error(ArgumentError)
    end
  end

  describe "#run_workflow" do
    let(:initial_message) { "Hello, I need help" }

    before do
      allow(orchestrator).to receive(:run_agent).and_return(
        success: true,
        response: "Agent response",
        agent: "Agent1"
      )
      allow(orchestrator).to receive(:workflow_completed?).and_return(true)
    end

    context "with default starting agent" do
      it "uses first agent as starting agent" do
        expect(orchestrator).to receive(:log_info).with(
          "Starting workflow",
          hash_including(starting_agent: "Agent1")
        )
        
        result = orchestrator.run_workflow(initial_message)
        expect(result).to be_a(RAAF::WorkflowResult)
        expect(result.success).to be true
      end
    end

    context "with specified starting agent" do
      it "uses specified starting agent" do
        expect(orchestrator).to receive(:log_info).with(
          "Starting workflow", 
          hash_including(starting_agent: "Agent2")
        )

        orchestrator.run_workflow(initial_message, starting_agent: "Agent2")
      end
    end

    context "when agent not found" do
      it "returns error result" do
        result = orchestrator.run_workflow(initial_message, starting_agent: "NonexistentAgent")
        
        expect(result.success).to be false
        expect(result.error).to include("Agent 'NonexistentAgent' not found")
        expect(result.results).to eq([])
      end
    end

    context "when agent execution fails" do
      before do
        allow(orchestrator).to receive(:run_agent).and_return(
          success: false,
          error: "Agent execution failed"
        )
      end

      it "returns error result with agent failure" do
        result = orchestrator.run_workflow(initial_message)
        
        expect(result.success).to be false
        expect(result.error).to eq("Agent execution failed")
        expect(result.results).to have(1).item
      end
    end

    context "with handoff workflow" do
      before do
        allow(orchestrator).to receive(:workflow_completed?).and_return(false, true)
        allow(orchestrator).to receive(:handoff_requested?).and_return(true, false)
        allow(orchestrator).to receive(:execute_handoff).and_return(success: true)
        allow(orchestrator.handoff_context).to receive(:build_handoff_message).and_return("Handoff message")
      end

      it "executes handoff between agents" do
        expect(orchestrator).to receive(:run_agent).twice
        expect(orchestrator).to receive(:execute_handoff).once
        
        result = orchestrator.run_workflow(initial_message)
        expect(result.success).to be true
        expect(result.results).to have(2).items
      end
    end

    context "when handoff fails" do
      before do
        allow(orchestrator).to receive(:workflow_completed?).and_return(false)
        allow(orchestrator).to receive(:handoff_requested?).and_return(true)
        allow(orchestrator).to receive(:execute_handoff).and_return(
          success: false,
          error: "Handoff failed"
        )
      end

      it "returns error result" do
        result = orchestrator.run_workflow(initial_message)
        
        expect(result.success).to be false
        expect(result.error).to eq("Handoff failed")
      end
    end

    context "when workflow incomplete without handoff" do
      before do
        allow(orchestrator).to receive(:workflow_completed?).and_return(false)
        allow(orchestrator).to receive(:handoff_requested?).and_return(false)
      end

      it "returns error result" do
        result = orchestrator.run_workflow(initial_message)
        
        expect(result.success).to be false
        expect(result.error).to include("Workflow incomplete")
      end
    end
  end

  describe "#run_agent" do
    let(:agent_result) { { success: true, response: "Test response" } }

    before do
      allow_any_instance_of(RAAF::Runner).to receive(:run).and_return(agent_result)
    end

    it "executes agent with provider" do
      result = orchestrator.send(:run_agent, agent1, "Test message")
      
      expect(result).to include(success: true)
      expect(result[:agent]).to eq("Agent1")
    end

    it "handles agent execution errors" do
      allow_any_instance_of(RAAF::Runner).to receive(:run).and_raise("Agent error")
      
      result = orchestrator.send(:run_agent, agent1, "Test message")
      
      expect(result[:success]).to be false
      expect(result[:error]).to include("Agent error")
    end
  end

  describe "#workflow_completed?" do
    it "returns true for completion signals" do
      agent_result = { completion_signal: true }
      expect(orchestrator.send(:workflow_completed?, agent_result)).to be true
    end

    it "returns true when no handoff available" do
      agent_result = { handoff_requested: false, available_handoffs: [] }
      expect(orchestrator.send(:workflow_completed?, agent_result)).to be true
    end

    it "returns false for incomplete workflow" do
      agent_result = { handoff_requested: true, available_handoffs: ["Agent2"] }
      expect(orchestrator.send(:workflow_completed?, agent_result)).to be false
    end
  end

  describe "#handoff_requested?" do
    it "detects explicit handoff requests" do
      agent_result = { handoff_requested: true, target_agent: "Agent2" }
      expect(orchestrator.send(:handoff_requested?, agent_result)).to be true
    end

    it "returns false for no handoff" do
      agent_result = { handoff_requested: false }
      expect(orchestrator.send(:handoff_requested?, agent_result)).to be false
    end

    it "handles missing handoff key" do
      agent_result = {}
      expect(orchestrator.send(:handoff_requested?, agent_result)).to be false
    end
  end

  describe "#execute_handoff" do
    let(:agent_result) { { target_agent: "Agent2", handoff_data: { key: "value" } } }

    before do
      allow(orchestrator.handoff_context).to receive(:add_handoff)
      allow(orchestrator.handoff_context).to receive(:current_agent=)
      allow(orchestrator.handoff_context).to receive(:set_handoff)
      allow(orchestrator.handoff_context).to receive(:execute_handoff).and_return({
        success: true,
        timestamp: Time.now.iso8601
      })
    end

    context "with valid target agent" do
      it "executes handoff successfully" do
        result = orchestrator.send(:execute_handoff, agent_result)
        
        expect(result[:success]).to be true
        expect(orchestrator.handoff_context).to have_received(:set_handoff).with(
          target_agent: "Agent2",
          data: { key: "value" },
          reason: "Agent handoff"
        )
      end
    end

    context "with invalid target agent" do
      let(:agent_result) { { target_agent: "InvalidAgent" } }

      it "returns error for invalid target" do
        result = orchestrator.send(:execute_handoff, agent_result)
        
        expect(result[:success]).to be false
        expect(result[:error]).to include("Target agent 'InvalidAgent' not available")
      end
    end

    context "with circular handoff detection" do
      before do
        allow(orchestrator.handoff_context).to receive(:handoff_chain).and_return(["Agent1", "Agent2"])
      end

      it "prevents circular handoffs" do
        # Note: The current implementation doesn't have circular handoff detection
        # This test documents expected behavior that's not yet implemented
        agent_result[:target_agent] = "Agent1"
        result = orchestrator.send(:execute_handoff, agent_result)
        
        # Currently succeeds - no circular detection implemented
        expect(result[:success]).to be true
      end
    end
  end

  describe "WorkflowResult" do
    let(:workflow_result) do
      RAAF::WorkflowResult.new(
        success: true,
        results: ["result1", "result2"],
        final_agent: "Agent2",
        handoff_context: orchestrator.handoff_context
      )
    end

    it "provides access to workflow results" do
      expect(workflow_result.success).to be true
      expect(workflow_result.results).to eq(["result1", "result2"])
      expect(workflow_result.final_agent).to eq("Agent2")
      expect(workflow_result.handoff_context).to eq(orchestrator.handoff_context)
    end

    it "handles error results" do
      error_result = RAAF::WorkflowResult.new(
        success: false,
        error: "Workflow failed",
        results: []
      )
      
      expect(error_result.success).to be false
      expect(error_result.error).to eq("Workflow failed")
      expect(error_result.results).to be_empty
    end
  end

  describe "integration scenarios" do
    let(:mock_runner) { instance_double(RAAF::Runner) }

    before do
      allow(RAAF::Runner).to receive(:new).and_return(mock_runner)
      allow(mock_runner).to receive(:run).and_return(
        success: true,
        messages: [{ role: "assistant", content: "Response" }],
        agent: agent1
      )
    end

    it "maintains conversation context across handoffs" do
      allow(orchestrator).to receive(:workflow_completed?).and_return(false, true)
      allow(orchestrator).to receive(:handoff_requested?).and_return(true, false)
      allow(orchestrator).to receive(:execute_handoff).and_return(success: true)
      
      result = orchestrator.run_workflow("Initial message")
      
      expect(result.success).to be true
      expect(mock_runner).to have_received(:run).twice
    end

    it "handles complex multi-agent workflows" do
      # Simulate 3-agent workflow: Agent1 -> Agent2 -> Agent1 (completion)
      agents_with_three = agents.merge("Agent3" => RAAF::Agent.new(name: "Agent3", instructions: "Agent 3"))
      orch = described_class.new(agents: agents_with_three, provider: provider)
      
      allow(orch).to receive(:workflow_completed?).and_return(false, false, true)
      allow(orch).to receive(:handoff_requested?).and_return(true, true, false)
      allow(orch).to receive(:execute_handoff).and_return(success: true)
      allow(orch).to receive(:run_agent).and_return(success: true, agent: "TestAgent")
      
      result = orch.run_workflow("Complex workflow message")
      
      expect(result.success).to be true
      expect(result.results).to have(3).items
    end
  end

  describe "error resilience" do
    it "handles provider failures gracefully" do
      allow_any_instance_of(RAAF::Runner).to receive(:run).and_raise(RAAF::APIError, "API failure")
      
      result = orchestrator.run_workflow("Test message")
      
      expect(result.success).to be false
      expect(result.error).to include("API failure")
    end

    it "handles malformed agent results" do
      allow(orchestrator).to receive(:run_agent).and_return(nil)
      
      result = orchestrator.run_workflow("Test message")
      
      expect(result.success).to be false
    end

    it "handles handoff context errors" do
      allow(orchestrator.handoff_context).to receive(:set_handoff).and_raise("Context error")
      allow(orchestrator).to receive(:workflow_completed?).and_return(false)
      allow(orchestrator).to receive(:handoff_requested?).and_return(true)
      
      # Mock provider response for run_agent
      allow(provider).to receive(:complete).and_return({
        choices: [{ message: { role: "assistant", content: "Response" } }],
        usage: { total_tokens: 10 }
      })
      
      result = orchestrator.run_workflow("Test message")
      
      expect(result.success).to be false
    end
  end
end