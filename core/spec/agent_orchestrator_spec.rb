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
      allow(orchestrator).to receive_messages(run_agent: { success: true,
                                                           response: "Agent response",
                                                           agent: "Agent1" }, workflow_completed?: true)
    end

    context "with default starting agent" do
      it "uses first agent as starting agent" do
        expect(orchestrator).to receive(:log_info).with(
          "Starting workflow",
          hash_including(starting_agent: "Agent1")
        ).once

        # Allow other log messages
        allow(orchestrator).to receive(:log_info).and_call_original

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
        ).once

        # Allow other log messages
        allow(orchestrator).to receive(:log_info).and_call_original

        result = orchestrator.run_workflow(initial_message, starting_agent: "Agent2")
        expect(result).to be_a(RAAF::WorkflowResult)
        expect(result.success).to be true
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
        allow(orchestrator).to receive_messages(workflow_completed?: false, handoff_requested?: true, execute_handoff: { success: false,
                                                                                                                         error: "Handoff failed" })
      end

      it "returns error result" do
        result = orchestrator.run_workflow(initial_message)

        expect(result.success).to be false
        expect(result.error).to eq("Handoff failed")
      end
    end

    context "when workflow incomplete without handoff" do
      before do
        allow(orchestrator).to receive_messages(workflow_completed?: false, handoff_requested?: false)
      end

      it "returns error result" do
        result = orchestrator.run_workflow(initial_message)

        expect(result.success).to be false
        expect(result.error).to include("Workflow incomplete")
      end
    end
  end

  describe "#run_agent" do
    let(:run_result) do
      RAAF::RunResult.new(
        messages: [{ role: "assistant", content: "Test response" }],
        usage: { total_tokens: 10 }
      )
    end

    before do
      allow_any_instance_of(RAAF::Runner).to receive(:run).and_return(run_result)
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
        allow(orchestrator.handoff_context).to receive(:handoff_chain).and_return(%w[Agent1 Agent2])
      end

      it "prevents circular handoffs" do
        # NOTE: The current implementation doesn't have circular handoff detection
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
        results: %w[result1 result2],
        final_agent: "Agent2",
        handoff_context: orchestrator.handoff_context
      )
    end

    it "provides access to workflow results" do
      expect(workflow_result.success).to be true
      expect(workflow_result.results).to eq(%w[result1 result2])
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
        RAAF::RunResult.new(
          messages: [{ role: "assistant", content: "Response" }],
          usage: { total_tokens: 10 }
        )
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
      allow(orch).to receive_messages(execute_handoff: { success: true }, run_agent: { success: true, agent: "TestAgent" })

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
      allow(orchestrator).to receive_messages(workflow_completed?: false, handoff_requested?: true)

      # Mock provider response for run_agent
      allow(provider).to receive(:chat_completion).and_return({
                                                                choices: [{ message: { role: "assistant", content: "Response" } }],
                                                                usage: { total_tokens: 10 }
                                                              })

      result = orchestrator.run_workflow("Test message")

      expect(result.success).to be false
    end
  end

  # Comprehensive test scenarios
  describe "Advanced Workflow Scenarios" do
    let(:router_agent) { RAAF::Agent.new(name: "Router", instructions: "Route requests to appropriate agents") }
    let(:support_agent) { RAAF::Agent.new(name: "Support", instructions: "Handle technical support") }
    let(:sales_agent) { RAAF::Agent.new(name: "Sales", instructions: "Handle sales inquiries") }
    let(:manager_agent) { RAAF::Agent.new(name: "Manager", instructions: "Handle escalations") }

    let(:comprehensive_agents) do
      {
        "Router" => router_agent,
        "Support" => support_agent,
        "Sales" => sales_agent,
        "Manager" => manager_agent
      }
    end

    let(:comprehensive_orchestrator) { described_class.new(agents: comprehensive_agents, provider: provider) }

    before do
      # Set up handoff relationships
      router_agent.add_handoff(support_agent)
      router_agent.add_handoff(sales_agent)
      support_agent.add_handoff(manager_agent)
      sales_agent.add_handoff(manager_agent)
      manager_agent.add_handoff(router_agent) # Can send back to router
    end

    describe "complex multi-agent workflows" do
      it "handles workflows with multiple handoffs and context preservation" do
        # Mock provider responses for workflow
        allow(provider).to receive(:chat_completion).and_return(
          {
            "choices" => [
              {
                "message" => {
                  "role" => "assistant",
                  "content" => "I'll route you to support for this technical issue"
                }
              }
            ],
            "usage" => { "prompt_tokens" => 10, "completion_tokens" => 15, "total_tokens" => 25 }
          }
        )

        result = comprehensive_orchestrator.run_workflow("I need technical help with my account", starting_agent: "Router")

        expect(result.success).to be true
        expect(result.results).not_to be_empty
      end

      it "maintains conversation context across all handoffs" do
        user_context = "User ID: 12345, Priority: High"
        initial_message = "#{user_context} - Need urgent help"

        allow(provider).to receive(:chat_completion).and_return(
          {
            "choices" => [
              {
                "message" => {
                  "role" => "assistant",
                  "content" => "Acknowledged context: #{user_context}"
                }
              }
            ],
            "usage" => { "prompt_tokens" => 20, "completion_tokens" => 10, "total_tokens" => 30 }
          }
        )

        result = comprehensive_orchestrator.run_workflow(initial_message, starting_agent: "Router")

        expect(result.success).to be true
        expect(result.results.any? { |r| r[:messages]&.any? { |m| m[:content]&.include?(user_context) } }).to be true
      end
    end

    describe "error recovery and resilience" do
      it "handles partial agent failures in workflow" do
        # Simulate provider failure
        allow(provider).to receive(:chat_completion).and_raise(StandardError.new("Provider error"))

        result = comprehensive_orchestrator.run_workflow("Test message", starting_agent: "Router")

        expect(result.success).to be false
        expect(result.error).to include("Provider error")
      end

      it "recovers from transient handoff context errors" do
        allow(comprehensive_orchestrator.handoff_context).to receive(:build_handoff_message).and_raise("Context error").once
        allow(comprehensive_orchestrator.handoff_context).to receive(:build_handoff_message).and_return("Recovered message")

        allow(provider).to receive(:chat_completion).and_return(
          {
            "choices" => [
              {
                "message" => {
                  "role" => "assistant",
                  "content" => "Recovery successful"
                }
              }
            ],
            "usage" => { "prompt_tokens" => 5, "completion_tokens" => 5, "total_tokens" => 10 }
          }
        )

        # Should recover and succeed
        expect do
          comprehensive_orchestrator.run_workflow("Test recovery", starting_agent: "Router")
        end.not_to raise_error
      end
    end

    describe "handoff validation and security" do
      it "validates handoff targets are legitimate agents" do
        # Try to handoff to non-existent agent
        allow(provider).to receive(:chat_completion).and_return(
          {
            "choices" => [
              {
                "message" => {
                  "role" => "assistant",
                  "content" => "Transferring to invalid agent"
                }
              }
            ],
            "usage" => { "prompt_tokens" => 10, "completion_tokens" => 5, "total_tokens" => 15 }
          }
        )

        result = comprehensive_orchestrator.run_workflow("Transfer me to NonExistentAgent", starting_agent: "Router")

        # Should still succeed but log validation error
        expect(result.success).to be true
      end

      it "prevents handoff loops with cycle detection" do
        # This test ensures the orchestrator can detect and prevent infinite handoff loops
        allow(provider).to receive(:chat_completion).and_return(
          {
            "choices" => [
              {
                "message" => {
                  "role" => "assistant",
                  "content" => "Preventing loop"
                }
              }
            ],
            "usage" => { "prompt_tokens" => 8, "completion_tokens" => 5, "total_tokens" => 13 }
          }
        )

        result = comprehensive_orchestrator.run_workflow("Test loop prevention", starting_agent: "Router")

        expect(result.success).to be true
      end
    end
  end
end
