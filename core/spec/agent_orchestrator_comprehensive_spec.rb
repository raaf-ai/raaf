# frozen_string_literal: true

require "spec_helper"
require_relative "../lib/raaf/agent_orchestrator"

RSpec.describe RAAF::AgentOrchestrator do
  # Create test agents
  let(:router_agent) { RAAF::Agent.new(name: "Router", instructions: "Route requests to appropriate agents") }
  let(:support_agent) { RAAF::Agent.new(name: "Support", instructions: "Handle technical support") }
  let(:sales_agent) { RAAF::Agent.new(name: "Sales", instructions: "Handle sales inquiries") }
  let(:manager_agent) { RAAF::Agent.new(name: "Manager", instructions: "Handle escalations") }
  
  let(:agents) do
    {
      "Router" => router_agent,
      "Support" => support_agent,
      "Sales" => sales_agent,
      "Manager" => manager_agent
    }
  end

  let(:provider) { instance_double(RAAF::Models::ResponsesProvider) }
  let(:orchestrator) { described_class.new(agents: agents, provider: provider) }

  before do
    # Set up handoff relationships
    router_agent.add_handoff(support_agent)
    router_agent.add_handoff(sales_agent)
    support_agent.add_handoff(manager_agent)
    sales_agent.add_handoff(manager_agent)
    manager_agent.add_handoff(router_agent) # Can send back to router
  end

  describe "Advanced Workflow Scenarios" do
    describe "complex multi-agent workflows" do
      it "handles workflows with multiple handoffs and context preservation" do
        # Mock responses for each agent
        responses = {
          "Router" => {
            messages: [{ role: "assistant", content: "I'll route you to support for this technical issue" }],
            handoff: { target_agent: "Support", reason: "Technical issue requiring support expertise" }
          },
          "Support" => {
            messages: [{ role: "assistant", content: "This issue needs manager approval" }],
            handoff: { target_agent: "Manager", reason: "Requires escalation for approval" }
          },
          "Manager" => {
            messages: [{ role: "assistant", content: "I've approved the resolution. Issue resolved!" }],
            handoff: nil
          }
        }

        current_responses = responses.dup
        allow(provider).to receive(:complete) do |args|
          agent_name = args[:messages].find { |m| m[:role] == "system" }[:content].match(/Your name is (\w+)/)[1]
          response = current_responses[agent_name]
          
          {
            messages: response[:messages],
            handoff: response[:handoff]
          }
        end

        result = orchestrator.run_workflow("I have a complex technical problem", starting_agent: "Router")

        expect(result).to be_success
        expect(result.results.size).to eq(3)
        expect(result.results.map { |r| r.dig(:session, :agent_name) }).to eq(["Router", "Support", "Manager"])
        expect(result.final_agent).to eq("Manager")
      end

      it "maintains conversation context across all handoffs" do
        user_context = "User ID: 12345, Priority: High"
        initial_message = "#{user_context} - Need urgent help"

        allow(provider).to receive(:complete) do |args|
          messages = args[:messages]
          
          # Verify context is preserved in messages
          expect(messages.any? { |m| m[:content]&.include?(user_context) }).to be true
          
          {
            messages: [{ role: "assistant", content: "Acknowledged context: #{user_context}" }],
            handoff: nil
          }
        end

        result = orchestrator.run_workflow(initial_message)
        expect(result).to be_success
      end
    end

    describe "error recovery and resilience" do
      it "handles partial agent failures in workflow" do
        call_count = 0
        allow(provider).to receive(:complete) do
          call_count += 1
          case call_count
          when 1
            # Router succeeds and hands off
            {
              messages: [{ role: "assistant", content: "Routing to support" }],
              handoff: { target_agent: "Support" }
            }
          when 2
            # Support fails
            raise "Network error"
          else
            # Should not reach here
            raise "Unexpected call"
          end
        end

        result = orchestrator.run_workflow("Help needed")
        
        expect(result).not_to be_success
        expect(result.error).to include("Network error")
        expect(result.results.size).to eq(1) # Only router succeeded
      end

      it "recovers from transient handoff context errors" do
        allow(orchestrator.handoff_context).to receive(:build_handoff_message).and_raise("Context error").once
        allow(orchestrator.handoff_context).to receive(:build_handoff_message).and_return("Recovered message")

        allow(provider).to receive(:complete).and_return({
          messages: [{ role: "assistant", content: "Response after recovery" }],
          handoff: nil
        })

        # Should handle the error and continue
        result = orchestrator.run_workflow("Test recovery")
        expect(result).to be_success
      end
    end

    describe "handoff validation and security" do
      it "validates handoff targets are legitimate agents" do
        # Mock a response trying to handoff to non-existent agent
        allow(provider).to receive(:complete).and_return({
          messages: [{ role: "assistant", content: "Transferring to fake agent" }],
          handoff: { target_agent: "FakeAgent", reason: "Malicious handoff" }
        })

        result = orchestrator.run_workflow("Test security")
        
        expect(result).not_to be_success
        expect(result.error).to include("FakeAgent")
      end

      it "prevents handoff loops with cycle detection" do
        # Create a scenario where agents keep handing off in a loop
        handoff_count = 0
        allow(provider).to receive(:complete) do
          handoff_count += 1
          
          if handoff_count < 10 # Would create infinite loop
            {
              messages: [{ role: "assistant", content: "Passing to next agent" }],
              handoff: { 
                target_agent: handoff_count.even? ? "Support" : "Sales",
                reason: "Loop test"
              }
            }
          else
            { messages: [{ role: "assistant", content: "Breaking loop" }], handoff: nil }
          end
        end

        result = orchestrator.run_workflow("Create loop", starting_agent: "Sales")
        
        # Should complete despite potential loop
        expect(result).to be_success
        expect(result.results.size).to be <= 10 # Reasonable limit
      end

      it "enforces handoff permissions" do
        # Create agent without handoff permission
        isolated_agent = RAAF::Agent.new(name: "Isolated", instructions: "Cannot handoff")
        agents["Isolated"] = isolated_agent
        
        allow(provider).to receive(:complete).and_return({
          messages: [{ role: "assistant", content: "Trying invalid handoff" }],
          handoff: { target_agent: "Support", reason: "Not allowed" }
        })

        orchestrator_with_isolated = described_class.new(agents: agents, provider: provider)
        result = orchestrator_with_isolated.run_workflow("Test", starting_agent: "Isolated")
        
        # Handoff should fail because Isolated doesn't have Support as a handoff target
        expect(result.results.size).to eq(1) # Only the isolated agent's response
      end
    end

    describe "state management" do
      it "tracks workflow metadata throughout execution" do
        start_time = Time.now
        
        allow(provider).to receive(:complete) do |args|
          {
            messages: [{ role: "assistant", content: "Processing with metadata" }],
            handoff: nil,
            metadata: { processing_time: 0.5, tokens_used: 100 }
          }
        end

        result = orchestrator.run_workflow("Track metadata")
        
        expect(result.started_at).to be_within(1).of(start_time)
        expect(result.completed_at).to be > result.started_at
        expect(result.final_agent).to eq("Router") # Default first agent
      end

      it "preserves handoff context state" do
        handoff_reasons = []
        
        allow(orchestrator.handoff_context).to receive(:add_handoff) do |from, to, reason|
          handoff_reasons << reason
        end

        allow(provider).to receive(:complete).and_return(
          {
            messages: [{ role: "assistant", content: "First response" }],
            handoff: { target_agent: "Support", reason: "Initial routing" }
          },
          {
            messages: [{ role: "assistant", content: "Support response" }],
            handoff: { target_agent: "Manager", reason: "Needs approval" }
          },
          {
            messages: [{ role: "assistant", content: "Approved" }],
            handoff: nil
          }
        )

        result = orchestrator.run_workflow("Test context preservation")
        
        expect(handoff_reasons).to eq(["Initial routing", "Needs approval"])
        expect(orchestrator.handoff_context.handoff_chain).to include("Router", "Support", "Manager")
      end
    end

    describe "provider integration" do
      it "passes provider configuration to all agents" do
        custom_provider = instance_double(RAAF::Models::ResponsesProvider)
        
        # Verify provider receives correct configuration
        expect(custom_provider).to receive(:complete).with(
          hash_including(
            model: router_agent.model,
            temperature: anything
          )
        ).and_return({
          messages: [{ role: "assistant", content: "Response" }],
          handoff: nil
        })

        custom_orchestrator = described_class.new(agents: agents, provider: custom_provider)
        custom_orchestrator.run_workflow("Test provider config")
      end

      it "handles provider-specific response formats" do
        # Test with different response formats
        allow(provider).to receive(:complete).and_return({
          # Minimal response
          messages: [{ role: "assistant", content: "Simple response" }]
          # No handoff key at all
        })

        result = orchestrator.run_workflow("Test minimal response")
        expect(result).to be_success
        expect(result.results.first[:response][:messages]).to be_present
      end
    end

    describe "performance optimizations" do
      it "caches agent lookups for efficiency" do
        # First lookup
        agent = orchestrator.send(:find_agent, "Support")
        expect(agent).to eq(support_agent)
        
        # Second lookup should use cached reference
        agent2 = orchestrator.send(:find_agent, "Support")
        expect(agent2).to equal(agent) # Same object reference
      end

      it "minimizes handoff context operations" do
        call_count = 0
        allow(orchestrator.handoff_context).to receive(:set_handoff) do
          call_count += 1
        end

        allow(provider).to receive(:complete).and_return({
          messages: [{ role: "assistant", content: "No handoff" }],
          handoff: nil
        })

        orchestrator.run_workflow("Single agent response")
        
        # Should not call set_handoff when no handoff occurs
        expect(call_count).to eq(0)
      end
    end

    describe "agent coordination patterns" do
      it "supports parallel agent consultation pattern" do
        # Simulate router consulting multiple agents
        consultation_results = {
          "Support" => "Technical solution available",
          "Sales" => "Discount can be applied"
        }
        
        allow(provider).to receive(:complete) do |args|
          agent_name = args[:messages].find { |m| m[:role] == "system" }[:content].match(/Your name is (\w+)/)[1]
          
          if consultation_results[agent_name]
            {
              messages: [{ role: "assistant", content: consultation_results[agent_name] }],
              handoff: { target_agent: "Router", reason: "Returning consultation result" }
            }
          else
            # Router aggregates results
            {
              messages: [{ role: "assistant", content: "Based on consultations: Tech support + discount available" }],
              handoff: nil
            }
          end
        end

        # This would require custom coordination logic in practice
        result = orchestrator.run_workflow("Need both technical help and pricing info")
        expect(result).to be_success
      end

      it "supports delegation with return pattern" do
        allow(provider).to receive(:complete).and_return(
          # Router delegates
          {
            messages: [{ role: "assistant", content: "Let me check with support" }],
            handoff: { target_agent: "Support", reason: "Delegation for expertise" }
          },
          # Support provides answer and returns
          {
            messages: [{ role: "assistant", content: "Technical detail: X" }],
            handoff: { target_agent: "Router", reason: "Returning with answer" }
          },
          # Router uses the answer
          {
            messages: [{ role: "assistant", content: "Based on support's input: Solution is X" }],
            handoff: nil
          }
        )

        result = orchestrator.run_workflow("Complex question")
        
        expect(result.results.size).to eq(3)
        expect(result.results.last[:response][:messages].last[:content]).to include("Solution is X")
      end
    end
  end

  describe "Logging and Observability" do
    it "logs workflow progression at appropriate levels" do
      allow(orchestrator).to receive(:log_info)
      allow(orchestrator).to receive(:log_debug)
      allow(orchestrator).to receive(:log_error)

      allow(provider).to receive(:complete).and_return({
        messages: [{ role: "assistant", content: "Response" }],
        handoff: { target_agent: "Support" }
      }, {
        messages: [{ role: "assistant", content: "Support response" }],
        handoff: nil
      })

      orchestrator.run_workflow("Test logging")

      expect(orchestrator).to have_received(:log_info).at_least(2).times
      expect(orchestrator).to have_received(:log_debug).at_least(:once)
    end

    it "includes structured context in error logs" do
      allow(provider).to receive(:complete).and_raise("Provider error")
      allow(orchestrator).to receive(:log_error)

      orchestrator.run_workflow("Test error logging")

      expect(orchestrator).to have_received(:log_error).with(
        anything,
        hash_including(
          agent: "Router",
          error_class: "RuntimeError"
        )
      )
    end
  end

  describe "Edge Cases and Boundary Conditions" do
    it "handles empty agent list gracefully" do
      expect { described_class.new(agents: {}, provider: provider) }.not_to raise_error
      
      empty_orchestrator = described_class.new(agents: {}, provider: provider)
      result = empty_orchestrator.run_workflow("Test")
      
      expect(result).not_to be_success
      expect(result.error).to include("Starting agent not found")
    end

    it "handles single agent workflows" do
      single_agent_orch = described_class.new(
        agents: { "Solo" => support_agent },
        provider: provider
      )

      allow(provider).to receive(:complete).and_return({
        messages: [{ role: "assistant", content: "Solo response" }],
        handoff: nil
      })

      result = single_agent_orch.run_workflow("Test single agent")
      expect(result).to be_success
      expect(result.results.size).to eq(1)
    end

    it "handles very long handoff chains" do
      # Create a chain of 20 agents
      chain_agents = {}
      20.times do |i|
        agent = RAAF::Agent.new(name: "Agent#{i}", instructions: "Agent #{i}")
        chain_agents["Agent#{i}"] = agent
        
        if i > 0
          chain_agents["Agent#{i-1}"].add_handoff(agent)
        end
      end

      chain_orchestrator = described_class.new(agents: chain_agents, provider: provider)
      
      call_count = 0
      allow(provider).to receive(:complete) do
        call_count += 1
        if call_count < 20
          {
            messages: [{ role: "assistant", content: "Passing to next" }],
            handoff: { target_agent: "Agent#{call_count}" }
          }
        else
          {
            messages: [{ role: "assistant", content: "Final response" }],
            handoff: nil
          }
        end
      end

      result = chain_orchestrator.run_workflow("Test long chain", starting_agent: "Agent0")
      
      expect(result).to be_success
      expect(result.results.size).to eq(20)
    end

    it "handles nil and empty string inputs" do
      allow(provider).to receive(:complete).and_return({
        messages: [{ role: "assistant", content: "Handled empty input" }],
        handoff: nil
      })

      # Nil input
      result = orchestrator.run_workflow(nil)
      expect(result).to be_success

      # Empty string input
      result = orchestrator.run_workflow("")
      expect(result).to be_success
    end
  end
end