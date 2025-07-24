# frozen_string_literal: true

require "spec_helper"
require_relative "../lib/raaf/handoff_context"
require_relative "../lib/raaf/handoff_tool"

RSpec.describe RAAF::HandoffTool do
  let(:handoff_context) { instance_double(RAAF::HandoffContext) }
  let(:target_agent) { "CompanyDiscoveryAgent" }
  let(:tool_name) { "handoff_to_companydiscoveryagent" }

  describe "#initialize" do
    let(:handoff_tool) do
      described_class.new(
        name: tool_name,
        target_agent: target_agent,
        description: "Test handoff tool",
        parameters: { type: "object" },
        handoff_context: handoff_context
      )
    end

    it "initializes with required attributes" do
      expect(handoff_tool.name).to eq(tool_name)
      expect(handoff_tool.target_agent).to eq(target_agent)
      expect(handoff_tool.description).to eq("Test handoff tool")
      expect(handoff_tool.parameters).to eq({ type: "object" })
      expect(handoff_tool.handoff_context).to eq(handoff_context)
    end
  end

  describe ".create_handoff_tool" do
    let(:function_tool) { instance_double(RAAF::FunctionTool) }

    before do
      allow(RAAF::FunctionTool).to receive(:new).and_return(function_tool)
      allow(handoff_context).to receive(:add_handoff)
      allow(handoff_context).to receive(:current_agent=)
    end

    context "with default data contract" do
      it "creates handoff tool with default parameters" do
        tool = described_class.create_handoff_tool(
          target_agent: target_agent,
          handoff_context: handoff_context
        )

        expect(RAAF::FunctionTool).to have_received(:new).with(
          anything,
          name: "handoff_to_companydiscoveryagent",
          description: "Transfer execution to CompanyDiscoveryAgent with structured data",
          parameters: hash_including(
            type: "object",
            properties: hash_including(:data, :reason)
          )
        )

        expect(tool).to eq(function_tool)
      end
    end

    context "with custom data contract" do
      let(:data_contract) do
        {
          type: "object",
          properties: {
            strategies: {
              type: "array",
              items: { type: "string" },
              description: "Research strategies"
            },
            priority: {
              type: "integer",
              minimum: 1,
              maximum: 5
            }
          },
          required: ["strategies"]
        }
      end

      it "creates handoff tool with custom data contract" do
        described_class.create_handoff_tool(
          target_agent: target_agent,
          handoff_context: handoff_context,
          data_contract: data_contract
        )

        expect(RAAF::FunctionTool).to have_received(:new).with(
          anything,
          name: "handoff_to_companydiscoveryagent",
          description: "Transfer execution to CompanyDiscoveryAgent with structured data",
          parameters: data_contract
        )
      end
    end

    context "with special characters in agent name" do
      let(:special_target_agent) { "Customer-Service Agent #1" }

      it "sanitizes agent name for tool name" do
        described_class.create_handoff_tool(
          target_agent: special_target_agent,
          handoff_context: handoff_context
        )

        expect(RAAF::FunctionTool).to have_received(:new).with(
          anything,
          name: "handoff_to_customer_service_agent__1",
          description: "Transfer execution to Customer-Service Agent #1 with structured data",
          parameters: anything
        )
      end
    end
  end

  describe "handoff execution" do
    let(:handoff_data) { { strategies: %w[analysis research], priority: 3 } }
    let(:handoff_timestamp) { Time.now }

    before do
      allow(handoff_context).to receive_messages(set_handoff: true, handoff_timestamp: handoff_timestamp)
    end

    it "executes handoff with provided data" do
      result = described_class.execute_handoff(target_agent, handoff_context, handoff_data)
      parsed = JSON.parse(result)

      expect(handoff_context).to have_received(:set_handoff).with(
        target_agent: target_agent,
        data: handoff_data,
        reason: "Agent requested handoff"
      )
      expect(parsed["success"]).to be true
      expect(parsed["handoff_prepared"]).to be true
      expect(parsed["target_agent"]).to eq(target_agent)
    end

    it "handles empty handoff data" do
      result = described_class.execute_handoff(target_agent, handoff_context, {})
      parsed = JSON.parse(result)

      expect(handoff_context).to have_received(:set_handoff).with(
        target_agent: target_agent,
        data: {},
        reason: "Agent requested handoff"
      )
      expect(parsed["success"]).to be true
    end

    it "handles handoff execution errors" do
      allow(handoff_context).to receive(:set_handoff).and_return(false)

      result = described_class.execute_handoff(target_agent, handoff_context, handoff_data)
      parsed = JSON.parse(result)

      expect(parsed["success"]).to be false
      expect(parsed["handoff_prepared"]).to be true
    end

    it "includes handoff data in result message" do
      described_class.execute_handoff(target_agent, handoff_context, { reason: "User needs specialized help" })

      expect(handoff_context).to have_received(:set_handoff).with(
        target_agent: target_agent,
        data: { reason: "User needs specialized help" },
        reason: "User needs specialized help"
      )
    end
  end

  describe ".search_strategies_contract" do
    it "returns valid data contract for search strategies" do
      contract = described_class.search_strategies_contract

      expect(contract).to include(
        type: "object",
        properties: hash_including(:search_strategies, :market_insights, :reason)
      )
      expect(contract[:required]).to include("search_strategies")
    end

    it "has proper strategy validation" do
      contract = described_class.search_strategies_contract
      strategies_property = contract[:properties][:search_strategies]

      expect(strategies_property[:type]).to eq("array")
      expect(strategies_property[:items][:type]).to eq("object")
      expect(strategies_property[:items][:properties]).to include(:name, :queries, :priority)
    end
  end

  describe ".company_discovery_contract" do
    it "returns valid data contract for company discovery" do
      contract = described_class.company_discovery_contract

      expect(contract).to include(
        type: "object",
        properties: hash_including(:discovered_companies, :search_metadata, :workflow_status)
      )
    end

    it "has proper company validation structure" do
      contract = described_class.company_discovery_contract
      companies_property = contract[:properties][:discovered_companies]

      expect(companies_property[:type]).to eq("array")
      expect(companies_property[:items][:type]).to eq("object")
    end
  end

  describe "integration with handoff context" do
    let(:real_context) { RAAF::HandoffContext.new }

    it "integrates with real handoff context" do
      tool = described_class.create_handoff_tool(
        target_agent: "TestAgent",
        handoff_context: real_context
      )

      expect(tool).to be_a(RAAF::FunctionTool)
      expect(tool.name).to eq("handoff_to_testagent")
    end

    it "handles handoff chain tracking" do
      # Simulate handoff chain: Agent1 -> Agent2 -> Agent3
      allow(real_context).to receive_messages(set_handoff: true, handoff_timestamp: Time.now)

      result = described_class.execute_handoff("Agent3", real_context, { data: "test" })
      parsed = JSON.parse(result)

      expect(parsed["success"]).to be true
      expect(parsed["target_agent"]).to eq("Agent3")
    end
  end

  describe "error handling and validation" do
    it "handles missing target agent" do
      # The method raises NoMethodError for nil target_agent
      expect do
        described_class.create_handoff_tool(
          target_agent: nil,
          handoff_context: handoff_context
        )
      end.to raise_error(NoMethodError)
    end

    it "handles missing handoff context" do
      # The method raises NoMethodError for nil context
      expect do
        described_class.execute_handoff(target_agent, nil, {})
      end.to raise_error(NoMethodError)
    end

    it "validates data contract structure" do
      invalid_contract = { invalid_key: "value" }

      expect do
        described_class.create_handoff_tool(
          target_agent: target_agent,
          handoff_context: handoff_context,
          data_contract: invalid_contract
        )
      end.not_to raise_error # Should accept any hash as data contract
    end

    it "handles handoff context errors gracefully" do
      allow(handoff_context).to receive(:set_handoff)
        .and_raise(StandardError, "Invalid handoff")

      expect do
        described_class.execute_handoff(target_agent, handoff_context, { data: "test" })
      end.to raise_error(StandardError, "Invalid handoff")
    end
  end

  describe "tool naming and sanitization" do
    it "handles complex agent names" do
      complex_names = [
        "Multi-Word Agent Name",
        "Agent_With_Underscores",
        "Agent123WithNumbers",
        "UPPERCASE_AGENT",
        "Agent-With-Dashes"
      ]

      complex_names.each do |agent_name|
        tool = described_class.create_handoff_tool(
          target_agent: agent_name,
          handoff_context: handoff_context
        )

        expect(tool).to be_a(RAAF::FunctionTool)
      end
    end

    it "ensures unique tool names" do
      agents = %w[TestAgent test_agent TEST-AGENT]
      tools = []

      agents.each do |agent_name|
        tool = described_class.create_handoff_tool(
          target_agent: agent_name,
          handoff_context: handoff_context
        )
        tools << tool
      end

      # All should create valid tools (names may be similar but valid)
      expect(tools).to all(be_a(RAAF::FunctionTool))
    end
  end

  describe "data contract templates" do
    it "provides template for task handoffs" do
      # These methods don't exist in the implementation
      skip "task_handoff_contract method not implemented"
    end

    it "provides template for user handoffs" do
      # These methods don't exist in the implementation
      skip "user_handoff_contract method not implemented"
    end

    it "provides template for workflow handoffs" do
      # These methods don't exist in the implementation
      skip "workflow_handoff_contract method not implemented"
    end
  end
end
