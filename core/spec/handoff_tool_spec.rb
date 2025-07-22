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
          name: "handoff_to_companydiscoveryagent",
          description: "Transfer execution to CompanyDiscoveryAgent with structured data",
          parameters: hash_including(
            type: "object",
            properties: hash_including(:data, :reason)
          ),
          callable: anything
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
          name: "handoff_to_companydiscoveryagent",
          description: "Transfer execution to CompanyDiscoveryAgent with structured data",
          parameters: data_contract,
          callable: anything
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
          name: "handoff_to_customer_service_agent__1",
          description: "Transfer execution to Customer-Service Agent #1 with structured data",
          parameters: anything,
          callable: anything
        )
      end
    end
  end

  describe "handoff execution" do
    let(:callable) { nil }
    let(:handoff_data) { { strategies: ["analysis", "research"], priority: 3 } }

    before do
      allow(RAAF::FunctionTool).to receive(:new) do |args|
        callable = args[:callable]
        instance_double(RAAF::FunctionTool, name: args[:name])
      end

      allow(handoff_context).to receive(:add_handoff)
      allow(handoff_context).to receive(:current_agent=)

      described_class.create_handoff_tool(
        target_agent: target_agent,
        handoff_context: handoff_context
      )
    end

    it "executes handoff with provided data" do
      result = callable.call(handoff_data)

      expect(handoff_context).to have_received(:add_handoff).with(
        from_agent: nil,
        to_agent: target_agent,
        data: handoff_data
      )
      expect(handoff_context).to have_received(:current_agent=).with(target_agent)
      expect(result).to include("Handoff executed successfully")
      expect(result).to include(target_agent)
    end

    it "handles empty handoff data" do
      result = callable.call({})

      expect(handoff_context).to have_received(:add_handoff).with(
        from_agent: nil,
        to_agent: target_agent,
        data: {}
      )
      expect(result).to include("Handoff executed successfully")
    end

    it "handles handoff execution errors" do
      allow(handoff_context).to receive(:add_handoff)
        .and_raise(StandardError, "Context error")

      result = callable.call(handoff_data)

      expect(result).to include("Handoff failed")
      expect(result).to include("Context error")
    end

    it "includes handoff data in result message" do
      result = callable.call({ reason: "User needs specialized help" })

      expect(result).to include("User needs specialized help")
    end
  end

  describe ".search_strategies_contract" do
    it "returns valid data contract for search strategies" do
      contract = described_class.search_strategies_contract

      expect(contract).to include(
        type: "object",
        properties: hash_including(:strategies, :context, :priority)
      )
      expect(contract[:required]).to include("strategies")
    end

    it "has proper strategy validation" do
      contract = described_class.search_strategies_contract
      strategies_property = contract[:properties][:strategies]

      expect(strategies_property[:type]).to eq("array")
      expect(strategies_property[:items][:type]).to eq("string")
      expect(strategies_property[:minItems]).to be > 0
    end
  end

  describe ".discovery_data_contract" do
    it "returns valid data contract for company discovery" do
      contract = described_class.discovery_data_contract

      expect(contract).to include(
        type: "object",
        properties: hash_including(:companies, :criteria, :research_context)
      )
    end

    it "has proper company validation structure" do
      contract = described_class.discovery_data_contract
      companies_property = contract[:properties][:companies]

      expect(companies_property[:type]).to eq("array")
      expect(companies_property[:items][:type]).to eq("object")
    end
  end

  describe "integration with handoff context" do
    let(:real_context) { RAAF::HandoffContext.new }

    before do
      allow(real_context).to receive(:add_handoff)
      allow(real_context).to receive(:current_agent=)
    end

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
      allow(real_context).to receive(:handoff_chain).and_return(["Agent1", "Agent2"])

      tool = described_class.create_handoff_tool(
        target_agent: "Agent3",
        handoff_context: real_context
      )

      # Execute the handoff
      callable = nil
      allow(RAAF::FunctionTool).to receive(:new) do |args|
        callable = args[:callable]
        instance_double(RAAF::FunctionTool)
      end

      described_class.create_handoff_tool(
        target_agent: "Agent3",
        handoff_context: real_context
      )

      result = callable.call({ data: "test" })
      expect(result).to include("Handoff executed successfully")
    end
  end

  describe "error handling and validation" do
    it "handles missing target agent" do
      expect do
        described_class.create_handoff_tool(
          target_agent: nil,
          handoff_context: handoff_context
        )
      end.to raise_error(ArgumentError, /target_agent/)
    end

    it "handles missing handoff context" do
      expect do
        described_class.create_handoff_tool(
          target_agent: target_agent,
          handoff_context: nil
        )
      end.to raise_error(ArgumentError, /handoff_context/)
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
      allow(handoff_context).to receive(:add_handoff)
        .and_raise(RAAF::HandoffError, "Invalid handoff")

      callable = nil
      allow(RAAF::FunctionTool).to receive(:new) do |args|
        callable = args[:callable]
        instance_double(RAAF::FunctionTool)
      end

      described_class.create_handoff_tool(
        target_agent: target_agent,
        handoff_context: handoff_context
      )

      result = callable.call({ data: "test" })
      expect(result).to include("Handoff failed")
      expect(result).to include("Invalid handoff")
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
      agents = ["TestAgent", "test_agent", "TEST-AGENT"]
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
      contract = described_class.task_handoff_contract

      expect(contract).to include(:type, :properties)
      expect(contract[:properties]).to include(:task, :priority, :deadline)
    end

    it "provides template for user handoffs" do
      contract = described_class.user_handoff_contract

      expect(contract).to include(:type, :properties)
      expect(contract[:properties]).to include(:user_context, :session_data)
    end

    it "provides template for workflow handoffs" do
      contract = described_class.workflow_handoff_contract

      expect(contract).to include(:type, :properties)
      expect(contract[:properties]).to include(:workflow_state, :step_data)
    end
  end
end