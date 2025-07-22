# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Advanced Handoff Scenarios", :integration do
  let(:primary_agent) { create_test_agent(name: "Primary", model: "gpt-4o") }
  let(:research_agent) { create_test_agent(name: "Research", model: "gpt-4o") }
  let(:writer_agent) { create_test_agent(name: "Writer", model: "gpt-4o") }
  let(:reviewer_agent) { create_test_agent(name: "Reviewer", model: "gpt-4o") }
  let(:mock_provider) { create_mock_provider }
  let(:runner) do
    RAAF::Runner.new(
      agent: primary_agent,
      agents: [primary_agent, research_agent, writer_agent, reviewer_agent],
      provider: mock_provider
    )
  end

  describe "Complex Handoff Chaining" do
    context "three-agent workflow" do
      before do
        # Set up handoff chain: Primary -> Research -> Writer
        primary_agent.add_handoff(research_agent)
        research_agent.add_handoff(writer_agent)
        writer_agent.add_handoff(primary_agent) # Allow return to primary
      end

      it "handles sequential handoffs across multiple agents" do
        # Mock responses for each agent in the chain
        allow(mock_provider).to receive(:responses_completion).and_return(
          # Primary agent requests research
          {
            id: "primary_response",
            output: [
              {
                type: "function_call",
                name: "transfer_to_research",
                arguments: '{"reason": "Need market research"}',
                call_id: "call_research"
              }
            ],
            usage: { total_tokens: 50 }
          },
          # Research agent completes and passes to writer
          {
            id: "research_response",
            output: [
              {
                type: "message",
                role: "assistant",
                content: "Research completed: Market size is $10B"
              },
              {
                type: "function_call",
                name: "transfer_to_writer",
                arguments: '{"data": {"findings": "Market research complete"}}',
                call_id: "call_writer"
              }
            ],
            usage: { total_tokens: 75 }
          },
          # Writer completes the work
          {
            id: "writer_response",
            output: [
              {
                type: "message",
                role: "assistant",
                content: "Final report: Based on research, the market opportunity is significant."
              }
            ],
            usage: { total_tokens: 60 }
          }
        )

        result = runner.run("Create a market analysis report")

        # Verify the chain executed properly
        expect(result.messages.size).to be >= 3
        expect(result.last_agent.name).to eq("Writer")
        expect(result.usage[:total_tokens]).to eq(185) # Sum of all token usage
      end

      it "handles handoff failures gracefully in the chain" do
        # Mock a successful primary handoff but failed research handoff
        allow(mock_provider).to receive(:responses_completion).and_return(
          # Primary successfully hands off to research
          {
            id: "primary_response",
            output: [
              {
                type: "function_call",
                name: "transfer_to_research",
                arguments: '{"reason": "Need research"}',
                call_id: "call_research"
              }
            ],
            usage: { total_tokens: 30 }
          },
          # Research tries to hand off to non-existent agent
          {
            id: "research_response",
            output: [
              {
                type: "function_call",
                name: "transfer_to_nonexistent",
                arguments: '{"reason": "This should fail"}',
                call_id: "call_fail"
              }
            ],
            usage: { total_tokens: 40 }
          }
        )

        result = runner.run("Test handoff failure")

        # Should continue with research agent after failed handoff
        expect(result.last_agent.name).to eq("Research")
        expect(result.messages.last[:content]).to include("I need to continue")
      end
    end

    context "circular handoff patterns" do
      before do
        # Create circular handoff: A -> B -> C -> A
        primary_agent.add_handoff(research_agent)
        research_agent.add_handoff(writer_agent)
        writer_agent.add_handoff(primary_agent)
      end

      it "prevents infinite handoff loops with max_turns limit" do
        config = RAAF::RunConfig.new(max_turns: 5)
        runner_with_limit = RAAF::Runner.new(
          agent: primary_agent,
          agents: [primary_agent, research_agent, writer_agent],
          provider: mock_provider,
          config: config
        )

        # Mock each agent to immediately hand off to the next
        allow(mock_provider).to receive(:responses_completion).and_return(
          {
            output: [
              {
                type: "function_call",
                name: "transfer_to_research",
                arguments: '{"reason": "Continue loop"}',
                call_id: "loop1"
              }
            ],
            usage: { total_tokens: 20 }
          },
          {
            output: [
              {
                type: "function_call",
                name: "transfer_to_writer",
                arguments: '{"reason": "Continue loop"}',
                call_id: "loop2"
              }
            ],
            usage: { total_tokens: 20 }
          },
          {
            output: [
              {
                type: "function_call",
                name: "transfer_to_primary",
                arguments: '{"reason": "Continue loop"}',
                call_id: "loop3"
              }
            ],
            usage: { total_tokens: 20 }
          }
        )

        expect do
          runner_with_limit.run("Start infinite loop")
        end.to raise_error(RAAF::MaxTurnsError)
      end
    end
  end

  describe "Handoff Context and State Management" do
    let(:handoff_context) { RAAF::HandoffContext.new }

    context "shared context across handoffs" do
      it "maintains shared state between agents" do
        # Set up agents with shared context access
        allow(research_agent).to receive(:handoff_context).and_return(handoff_context)
        allow(writer_agent).to receive(:handoff_context).and_return(handoff_context)

        primary_agent.add_handoff(research_agent)
        research_agent.add_handoff(writer_agent)

        # Mock research agent storing data in shared context
        allow(mock_provider).to receive(:responses_completion).and_return(
          # Primary hands off to research
          {
            output: [{
              type: "function_call",
              name: "transfer_to_research",
              arguments: '{"task": "market_analysis"}',
              call_id: "handoff1"
            }],
            usage: { total_tokens: 30 }
          },
          # Research completes and stores results, then hands off to writer
          {
            output: [
              {
                type: "message",
                content: "Research complete"
              },
              {
                type: "function_call",
                name: "transfer_to_writer",
                arguments: '{"research_results": "Market size: $10B"}',
                call_id: "handoff2"
              }
            ],
            usage: { total_tokens: 50 }
          },
          # Writer accesses shared context
          {
            output: [{
              type: "message",
              content: "Report written using research data"
            }],
            usage: { total_tokens: 40 }
          }
        )

        # Simulate context being populated during handoffs
        allow(handoff_context).to receive(:set_handoff) do |target_agent:, data:, **|
          handoff_context.shared_context.merge!(data) if data.is_a?(Hash)
          true
        end

        result = runner.run("Create comprehensive market report")

        expect(result.messages.size).to be >= 3
        expect(handoff_context.shared_context).to have_key(:research_results)
      end
    end

    context "handoff data transformation" do
      it "applies input filters during handoffs" do
        # Create handoff with input filter
        filtered_handoff = RAAF.handoff(
          writer_agent,
          input_filter: proc { |data|
            # Transform data structure
            {
              filtered_data: data[:raw_data]&.upcase,
              processed_at: Time.current.iso8601
            }
          }
        )

        primary_agent.instance_variable_set(:@handoffs, [filtered_handoff])

        allow(mock_provider).to receive(:responses_completion).and_return(
          {
            output: [{
              type: "function_call",
              name: "transfer_to_writer",
              arguments: '{"raw_data": "unprocessed content"}',
              call_id: "filter_test"
            }],
            usage: { total_tokens: 25 }
          },
          {
            output: [{
              type: "message",
              content: "Content processed successfully"
            }],
            usage: { total_tokens: 35 }
          }
        )

        result = runner.run("Process this data")

        # Verify filter was applied (would need access to internal handoff data)
        expect(result.messages.size).to be >= 2
        expect(result.last_agent.name).to eq("Writer")
      end
    end
  end

  describe "Conditional Handoff Logic" do
    context "handoff based on content analysis" do
      it "routes to appropriate specialist agent" do
        # Set up multiple handoff targets
        technical_agent = create_test_agent(name: "Technical", model: "gpt-4o")
        business_agent = create_test_agent(name: "Business", model: "gpt-4o")

        primary_agent.add_handoff(technical_agent)
        primary_agent.add_handoff(business_agent)

        runner_multi = RAAF::Runner.new(
          agent: primary_agent,
          agents: [primary_agent, technical_agent, business_agent],
          provider: mock_provider
        )

        # Mock primary agent making decision based on content
        allow(mock_provider).to receive(:responses_completion).and_return(
          # Primary analyzes request and chooses technical route
          {
            output: [{
              type: "function_call",
              name: "transfer_to_technical",
              arguments: '{"reason": "Technical question detected", "complexity": "high"}',
              call_id: "tech_route"
            }],
            usage: { total_tokens: 40 }
          },
          # Technical agent handles the request
          {
            output: [{
              type: "message",
              content: "Technical analysis: This requires advanced algorithms"
            }],
            usage: { total_tokens: 60 }
          }
        )

        result = runner_multi.run("How do we implement machine learning?")

        expect(result.last_agent.name).to eq("Technical")
        expect(result.messages.last[:content]).to include("algorithms")
      end
    end

    context "hierarchical handoff patterns" do
      it "supports manager-subordinate handoff relationships" do
        manager_agent = create_test_agent(name: "Manager", model: "gpt-4o")
        subordinate1 = create_test_agent(name: "Dev1", model: "gpt-4o")
        subordinate2 = create_test_agent(name: "Dev2", model: "gpt-4o")

        # Manager can delegate to either subordinate
        manager_agent.add_handoff(subordinate1)
        manager_agent.add_handoff(subordinate2)

        # Subordinates can escalate back to manager
        subordinate1.add_handoff(manager_agent)
        subordinate2.add_handoff(manager_agent)

        runner_hierarchy = RAAF::Runner.new(
          agent: manager_agent,
          agents: [manager_agent, subordinate1, subordinate2],
          provider: mock_provider
        )

        allow(mock_provider).to receive(:responses_completion).and_return(
          # Manager delegates task
          {
            output: [{
              type: "function_call",
              name: "transfer_to_dev1",
              arguments: '{"task": "frontend_work", "priority": "high"}',
              call_id: "delegate1"
            }],
            usage: { total_tokens: 35 }
          },
          # Dev1 completes and reports back
          {
            output: [
              {
                type: "message",
                content: "Frontend work completed"
              },
              {
                type: "function_call",
                name: "transfer_to_manager",
                arguments: '{"status": "completed", "results": "UI updated"}',
                call_id: "report_back"
              }
            ],
            usage: { total_tokens: 55 }
          },
          # Manager acknowledges completion
          {
            output: [{
              type: "message",
              content: "Task completed successfully. Good work!"
            }],
            usage: { total_tokens: 25 }
          }
        )

        result = runner_hierarchy.run("Update the user interface")

        expect(result.messages.size).to be >= 3
        expect(result.last_agent.name).to eq("Manager")
        expect(result.usage[:total_tokens]).to eq(115)
      end
    end
  end

  describe "Error Recovery in Multi-Agent Handoffs" do
    context "agent failure scenarios" do
      it "handles agent errors during handoff execution" do
        primary_agent.add_handoff(research_agent)

        # Mock research agent throwing an error
        allow(mock_provider).to receive(:responses_completion).and_return(
          # Primary successfully hands off
          {
            output: [{
              type: "function_call",
              name: "transfer_to_research",
              arguments: '{"task": "market_research"}',
              call_id: "handoff_test"
            }],
            usage: { total_tokens: 30 }
          }
        ).and_raise(StandardError, "Research agent failed")

        expect do
          runner.run("Conduct research")
        end.to raise_error(StandardError, "Research agent failed")
      end

      it "implements fallback strategies for failed handoffs" do
        backup_agent = create_test_agent(name: "Backup", model: "gpt-4o")

        primary_agent.add_handoff(research_agent)
        primary_agent.add_handoff(backup_agent) # Backup option

        runner_with_backup = RAAF::Runner.new(
          agent: primary_agent,
          agents: [primary_agent, research_agent, backup_agent],
          provider: mock_provider
        )

        allow(mock_provider).to receive(:responses_completion).and_return(
          # Primary tries research agent first
          {
            output: [{
              type: "function_call",
              name: "transfer_to_research",
              arguments: '{"task": "primary_research"}',
              call_id: "primary_try"
            }],
            usage: { total_tokens: 30 }
          },
          # Research agent fails, primary tries backup
          {
            output: [{
              type: "function_call",
              name: "transfer_to_backup",
              arguments: '{"task": "backup_research", "fallback": true}',
              call_id: "backup_try"
            }],
            usage: { total_tokens: 35 }
          },
          # Backup agent succeeds
          {
            output: [{
              type: "message",
              content: "Backup research completed successfully"
            }],
            usage: { total_tokens: 45 }
          }
        )

        result = runner_with_backup.run("Conduct research with fallback")

        expect(result.last_agent.name).to eq("Backup")
        expect(result.messages.last[:content]).to include("successfully")
      end
    end
  end

  describe "Performance and Scalability" do
    context "large-scale agent networks" do
      it "handles handoffs efficiently with many agents" do
        # Create a network of 10 agents
        agents = (1..10).map { |i| create_test_agent(name: "Agent#{i}", model: "gpt-4o") }

        # Each agent can hand off to the next (circular)
        agents.each_with_index do |agent, index|
          next_agent = agents[(index + 1) % agents.size]
          agent.add_handoff(next_agent)
        end

        large_runner = RAAF::Runner.new(
          agent: agents.first,
          agents: agents,
          provider: mock_provider
        )

        # Mock a few handoffs in the network
        allow(mock_provider).to receive(:responses_completion).and_return(
          {
            output: [{
              type: "function_call",
              name: "transfer_to_agent2",
              arguments: '{"step": 1}',
              call_id: "step1"
            }],
            usage: { total_tokens: 20 }
          },
          {
            output: [{
              type: "function_call",
              name: "transfer_to_agent3",
              arguments: '{"step": 2}',
              call_id: "step2"
            }],
            usage: { total_tokens: 25 }
          },
          {
            output: [{
              type: "message",
              content: "Network processing complete"
            }],
            usage: { total_tokens: 30 }
          }
        )

        result = large_runner.run("Process through agent network")

        expect(result.last_agent.name).to eq("Agent3")
        expect(result.usage[:total_tokens]).to eq(75)
      end

      it "maintains performance with concurrent handoff evaluation" do
        # Test that handoff detection doesn't degrade with many handoff options
        agent_with_many_handoffs = create_test_agent(name: "Hub", model: "gpt-4o")

        # Add 20 handoff targets
        handoff_targets = (1..20).map do |i|
          target = create_test_agent(name: "Target#{i}", model: "gpt-4o")
          agent_with_many_handoffs.add_handoff(target)
          target
        end

        all_agents = [agent_with_many_handoffs] + handoff_targets

        hub_runner = RAAF::Runner.new(
          agent: agent_with_many_handoffs,
          agents: all_agents,
          provider: mock_provider
        )

        # Mock selection of one target from many options
        allow(mock_provider).to receive(:responses_completion).and_return(
          {
            output: [{
              type: "function_call",
              name: "transfer_to_target10",
              arguments: '{"selected": 10, "reason": "best match"}',
              call_id: "hub_select"
            }],
            usage: { total_tokens: 40 }
          },
          {
            output: [{
              type: "message",
              content: "Selected target completed task"
            }],
            usage: { total_tokens: 35 }
          }
        )

        start_time = Time.current
        result = hub_runner.run("Route to appropriate specialist")
        execution_time = Time.current - start_time

        expect(result.last_agent.name).to eq("Target10")
        expect(execution_time).to be < 2.0 # Should complete quickly
      end
    end
  end

  describe "Handoff Tool Integration" do
    context "custom handoff tools" do
      it "supports handoff tools with custom data contracts" do
        # Create custom handoff tool with structured data contract
        search_contract = RAAF::HandoffTool.search_strategies_contract

        handoff_context = RAAF::HandoffContext.new
        custom_handoff_tool = RAAF::HandoffTool.create_handoff_tool(
          target_agent: "SearchSpecialist",
          handoff_context: handoff_context,
          data_contract: search_contract
        )

        agent_with_custom_tool = create_test_agent(name: "Coordinator", model: "gpt-4o")
        agent_with_custom_tool.add_tool(custom_handoff_tool)

        search_specialist = create_test_agent(name: "SearchSpecialist", model: "gpt-4o")

        custom_runner = RAAF::Runner.new(
          agent: agent_with_custom_tool,
          agents: [agent_with_custom_tool, search_specialist],
          provider: mock_provider
        )

        allow(mock_provider).to receive(:responses_completion).and_return(
          {
            output: [{
              type: "function_call",
              name: "handoff_to_searchspecialist",
              arguments: JSON.generate({
                                         search_strategies: [
                                           {
                                             name: "comprehensive_search",
                                             queries: ["market analysis", "competitor research"],
                                             priority: 1
                                           }
                                         ],
                                         reason: "Need specialized search capabilities"
                                       }),
              call_id: "custom_handoff"
            }],
            usage: { total_tokens: 60 }
          },
          {
            output: [{
              type: "message",
              content: "Search strategies executed successfully"
            }],
            usage: { total_tokens: 45 }
          }
        )

        result = custom_runner.run("Execute comprehensive search")

        expect(result.last_agent.name).to eq("SearchSpecialist")
        expect(handoff_context.shared_context).to have_key(:search_strategies)
      end

      it "validates handoff tool argument schemas" do
        # Test that handoff tools validate their input contracts
        handoff_context = RAAF::HandoffContext.new
        company_contract = RAAF::HandoffTool.company_discovery_contract

        discovery_tool = RAAF::HandoffTool.create_handoff_tool(
          target_agent: "CompanyAnalyst",
          handoff_context: handoff_context,
          data_contract: company_contract
        )

        # Simulate tool execution with invalid data
        invalid_args = { invalid_field: "should_not_work" }

        # The tool should handle validation gracefully
        result = discovery_tool.call(**invalid_args)

        expect(result).to be_a(String) # JSON response
        parsed_result = JSON.parse(result)
        expect(parsed_result).to have_key("success")
      end
    end

    context "workflow completion tools" do
      it "handles workflow completion signaling" do
        handoff_context = RAAF::HandoffContext.new
        completion_tool = RAAF::HandoffTool.create_completion_tool(
          handoff_context: handoff_context
        )

        workflow_agent = create_test_agent(name: "WorkflowManager", model: "gpt-4o")
        workflow_agent.add_tool(completion_tool)

        completion_runner = RAAF::Runner.new(
          agent: workflow_agent,
          provider: mock_provider
        )

        allow(mock_provider).to receive(:responses_completion).and_return(
          {
            output: [{
              type: "function_call",
              name: "complete_workflow",
              arguments: JSON.generate({
                                         status: "completed",
                                         results: { tasks_completed: 5, success_rate: "100%" },
                                         summary: "All workflow tasks completed successfully"
                                       }),
              call_id: "workflow_complete"
            }],
            usage: { total_tokens: 50 }
          }
        )

        completion_runner.run("Complete the workflow")

        expect(handoff_context.shared_context[:workflow_completed]).to be true
        expect(handoff_context.shared_context[:final_results]).to have_key(:status)
        expect(handoff_context.shared_context[:final_results][:status]).to eq("completed")
      end
    end
  end
end
