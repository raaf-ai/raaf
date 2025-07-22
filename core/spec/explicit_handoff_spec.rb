# frozen_string_literal: true

require "spec_helper"
require_relative "../lib/raaf/explicit_handoff"

RSpec.describe RAAF::ExplicitHandoff do
  let(:agent) { RAAF::Agent.new(name: "TestAgent", instructions: "Test agent") }
  let(:handoff_context) { instance_double(RAAF::HandoffContext) }
  let(:handoff_tool) { instance_double(RAAF::HandoffTool) }

  describe ".add_handoff_tools" do
    let(:handoff_configs) do
      [
        {
          target_agent: "CompanyDiscoveryAgent",
          data_contract: { strategies: { type: "array" } }
        },
        {
          target_agent: "SupportAgent",
          data_contract: { issue_type: { type: "string" } }
        }
      ]
    end

    before do
      allow(RAAF::HandoffTool).to receive(:create_handoff_tool).and_return(handoff_tool)
      allow(agent).to receive(:add_tool)
    end

    it "creates handoff tools for each configuration" do
      described_class.add_handoff_tools(agent, handoff_context, handoff_configs)

      expect(RAAF::HandoffTool).to have_received(:create_handoff_tool).with(
        target_agent: "CompanyDiscoveryAgent",
        handoff_context: handoff_context,
        data_contract: { strategies: { type: "array" } }
      )

      expect(RAAF::HandoffTool).to have_received(:create_handoff_tool).with(
        target_agent: "SupportAgent",
        handoff_context: handoff_context,
        data_contract: { issue_type: { type: "string" } }
      )
    end

    it "adds created tools to the agent" do
      described_class.add_handoff_tools(agent, handoff_context, handoff_configs)

      expect(agent).to have_received(:add_tool).twice
    end

    it "handles empty handoff configs" do
      expect do
        described_class.add_handoff_tools(agent, handoff_context, [])
      end.not_to raise_error

      expect(RAAF::HandoffTool).not_to have_received(:create_handoff_tool)
      expect(agent).not_to have_received(:add_tool)
    end

    it "uses empty data contract when none provided" do
      configs_without_contract = [{ target_agent: "TestAgent" }]

      described_class.add_handoff_tools(agent, handoff_context, configs_without_contract)

      expect(RAAF::HandoffTool).to have_received(:create_handoff_tool).with(
        target_agent: "TestAgent",
        handoff_context: handoff_context,
        data_contract: {}
      )
    end

    it "handles handoff tool creation errors" do
      allow(RAAF::HandoffTool).to receive(:create_handoff_tool)
        .and_raise(StandardError, "Tool creation failed")

      expect do
        described_class.add_handoff_tools(agent, handoff_context, handoff_configs)
      end.to raise_error(StandardError, "Tool creation failed")
    end
  end

  describe ".create_search_agent" do
    let(:search_agent) { instance_double(RAAF::Agent) }

    before do
      allow(RAAF::Agent).to receive(:new).and_return(search_agent)
      allow(described_class).to receive(:add_handoff_tools)
      allow(search_agent).to receive(:add_tool)
    end

    it "creates agent with search-specific instructions" do
      described_class.create_search_agent(handoff_context)

      expect(RAAF::Agent).to have_received(:new).with(
        hash_including(
          name: "SearchAgent",
          instructions: include("market research")
        )
      )
    end

    it "adds handoff tools to the created agent" do
      described_class.create_search_agent(handoff_context)

      expect(search_agent).to have_received(:add_tool).at_least(:once)
    end

    it "returns the configured agent" do
      result = described_class.create_search_agent(handoff_context)
      expect(result).to eq(search_agent)
    end

    it "handles agent creation errors" do
      allow(RAAF::Agent).to receive(:new).and_raise(ArgumentError, "Invalid agent config")

      expect do
        described_class.create_search_agent(handoff_context)
      end.to raise_error(ArgumentError, "Invalid agent config")
    end
  end

  describe ".create_company_discovery_agent" do
    let(:discovery_agent) { instance_double(RAAF::Agent) }

    before do
      allow(RAAF::Agent).to receive(:new).and_return(discovery_agent)
      allow(discovery_agent).to receive(:add_tool)
      # Mock the HandoffTool.create_completion_tool method
      completion_tool = instance_double(RAAF::FunctionTool)
      allow(RAAF::HandoffTool).to receive(:create_completion_tool).and_return(completion_tool)
    end

    it "creates agent with discovery-specific instructions" do
      described_class.create_company_discovery_agent(handoff_context)

      expect(RAAF::Agent).to have_received(:new).with(
        hash_including(
          name: "CompanyDiscoveryAgent",
          instructions: include("company discovery")
        )
      )
    end

    it "adds completion tool to the agent" do
      described_class.create_company_discovery_agent(handoff_context)

      expect(discovery_agent).to have_received(:add_tool).at_least(:once)
    end

    it "returns the configured discovery agent" do
      result = described_class.create_company_discovery_agent(handoff_context)
      expect(result).to eq(discovery_agent)
    end
  end

  describe "integration scenarios" do
    let(:real_agent) { RAAF::Agent.new(name: "RealAgent", instructions: "Real agent for testing") }
    let(:real_context) { RAAF::HandoffContext.new }

    before do
      allow(RAAF::HandoffTool).to receive(:create_handoff_tool) do |args|
        # Return a real FunctionTool that can be added to agent
        target = args[:target_agent] || "unknown"
        tool_name = "transfer_to_#{target.downcase}"
        handoff_proc = proc { |**data| "Handoff to #{target} with #{data}" }
        RAAF::FunctionTool.new(handoff_proc, name: tool_name)
      end
      
      # Mock create_completion_tool for company discovery agent
      allow(RAAF::HandoffTool).to receive(:create_completion_tool) do |args|
        completion_proc = proc { |**data| "Workflow completed with #{data}" }
        RAAF::FunctionTool.new(completion_proc, name: "complete_workflow")
      end
    end

    it "creates functional multi-agent workflow" do
      configs = [
        { target_agent: "Agent1", data_contract: { data: { type: "string" } } },
        { target_agent: "Agent2", data_contract: { priority: { type: "number" } } }
      ]

      expect do
        described_class.add_handoff_tools(real_agent, real_context, configs)
      end.not_to raise_error

      expect(real_agent.tools).to have(2).items
    end

    it "handles real handoff context integration" do
      search_agent = described_class.create_search_agent(real_context)
      discovery_agent = described_class.create_company_discovery_agent(real_context)

      expect(search_agent).to be_a(RAAF::Agent)
      expect(discovery_agent).to be_a(RAAF::Agent)
    end

    it "maintains handoff data contract integrity" do
      contract = {
        strategies: {
          type: "array",
          items: { type: "string" },
          description: "Research strategies to use"
        }
      }

      configs = [{ target_agent: "TestAgent", data_contract: contract }]

      described_class.add_handoff_tools(real_agent, real_context, configs)

      expect(RAAF::HandoffTool).to have_received(:create_handoff_tool)
        .with(hash_including(data_contract: contract))
    end
  end

  describe "error handling and edge cases" do
    it "handles nil handoff context gracefully" do
      expect do
        described_class.add_handoff_tools(agent, nil, [])
      end.not_to raise_error
    end

    it "handles nil agent gracefully" do
      # With empty configs array, no error should occur even with nil agent
      # because the method won't iterate over anything
      expect do
        described_class.add_handoff_tools(nil, handoff_context, [])
      end.not_to raise_error
      
      # But with actual configs, it should raise an error
      expect do
        described_class.add_handoff_tools(nil, handoff_context, [{ target_agent: "TestAgent" }])
      end.to raise_error(NoMethodError)
    end

    it "handles malformed handoff configurations" do
      # Mock HandoffTool to handle nil/empty target_agent gracefully
      allow(RAAF::HandoffTool).to receive(:create_handoff_tool) do |args|
        if args[:target_agent].nil? || args[:target_agent].empty?
          raise ArgumentError, "target_agent is required"
        end
        instance_double(RAAF::FunctionTool)
      end
      
      malformed_configs = [
        {},  # Missing target_agent
        { target_agent: nil },  # Nil target_agent
        { target_agent: "" }    # Empty target_agent
      ]

      malformed_configs.each do |config|
        expect do
          described_class.add_handoff_tools(agent, handoff_context, [config])
        end.to raise_error(ArgumentError, "target_agent is required")
      end
    end

    it "handles handoff tool execution errors" do
      allow(RAAF::HandoffTool).to receive(:create_handoff_tool)
        .and_raise(RAAF::HandoffError, "Handoff failed")

      expect do
        described_class.add_handoff_tools(agent, handoff_context, [{ target_agent: "TestAgent" }])
      end.to raise_error(RAAF::HandoffError)
    end
  end

  describe "data contract validation" do
    let(:strict_contract) do
      {
        priority: {
          type: "integer",
          minimum: 1,
          maximum: 5,
          description: "Task priority level"
        },
        category: {
          type: "string",
          enum: ["urgent", "normal", "low"],
          description: "Task category"
        }
      }
    end

    before do
      # Set up spy for HandoffTool to track method calls
      # Return a proper FunctionTool instance that can be added to the agent
      function_tool = RAAF::FunctionTool.new(proc { "handoff executed" }, name: "test_handoff")
      allow(RAAF::HandoffTool).to receive(:create_handoff_tool).and_return(function_tool)
    end

    it "passes data contract to handoff tool creation" do
      configs = [{ target_agent: "TaskAgent", data_contract: strict_contract }]

      described_class.add_handoff_tools(agent, handoff_context, configs)

      expect(RAAF::HandoffTool).to have_received(:create_handoff_tool)
        .with(hash_including(data_contract: strict_contract))
    end

    it "handles complex nested data contracts" do
      nested_contract = {
        user: {
          type: "object",
          properties: {
            name: { type: "string" },
            preferences: {
              type: "object",
              properties: {
                language: { type: "string" },
                notifications: { type: "boolean" }
              }
            }
          }
        }
      }

      configs = [{ target_agent: "UserAgent", data_contract: nested_contract }]

      expect do
        described_class.add_handoff_tools(agent, handoff_context, configs)
      end.not_to raise_error
    end
  end
end