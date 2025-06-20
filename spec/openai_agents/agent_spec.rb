# frozen_string_literal: true

require "spec_helper"

RSpec.describe OpenAIAgents::Agent do
  describe "#initialize" do
    it "creates an agent with default values" do
      agent = described_class.new(name: "TestAgent")

      expect(agent.name).to eq("TestAgent")
      expect(agent.instructions).to be_nil
      expect(agent.tools).to be_empty
      expect(agent.handoffs).to be_empty
      expect(agent.model).to eq("gpt-4")
      expect(agent.max_turns).to eq(10)
    end

    it "creates an agent with custom values" do
      agent = described_class.new(
        name: "CustomAgent",
        instructions: "You are a helpful assistant",
        model: "gpt-3.5-turbo",
        max_turns: 5
      )

      expect(agent.name).to eq("CustomAgent")
      expect(agent.instructions).to eq("You are a helpful assistant")
      expect(agent.model).to eq("gpt-3.5-turbo")
      expect(agent.max_turns).to eq(5)
    end

    it "creates an agent with pre-configured tools and handoffs" do
      existing_tool = OpenAIAgents::FunctionTool.new(proc { |value| value * 2 })
      other_agent = described_class.new(name: "OtherAgent")

      agent = described_class.new(
        name: "ConfiguredAgent",
        tools: [existing_tool],
        handoffs: [other_agent]
      )

      expect(agent.tools.size).to eq(1)
      expect(agent.handoffs.size).to eq(1)
      expect(agent.handoffs.first).to eq(other_agent)
    end

    it "duplicates tools and handoffs arrays to prevent mutation" do
      tools = []
      handoffs = []
      agent = described_class.new(name: "TestAgent", tools: tools, handoffs: handoffs)

      expect(agent.tools).not_to be(tools)
      expect(agent.handoffs).not_to be(handoffs)
    end
  end

  describe "#add_tool" do
    let(:agent) { described_class.new(name: "TestAgent") }

    it "adds a proc as a tool" do
      tool_proc = proc { |value| value * 2 }
      agent.add_tool(tool_proc)

      expect(agent.tools.size).to eq(1)
      expect(agent.tools.first).to be_a(OpenAIAgents::FunctionTool)
    end

    it "adds a method as a tool" do
      def test_method(value)
        value * 2
      end

      agent.add_tool(method(:test_method))

      expect(agent.tools.size).to eq(1)
      expect(agent.tools.first).to be_a(OpenAIAgents::FunctionTool)
    end

    it "adds a FunctionTool directly" do
      function_tool = OpenAIAgents::FunctionTool.new(proc { |value| value * 2 })
      agent.add_tool(function_tool)

      expect(agent.tools.size).to eq(1)
      expect(agent.tools.first).to eq(function_tool)
    end

    it "raises error for invalid tool" do
      expect { agent.add_tool("invalid") }.to raise_error(OpenAIAgents::ToolError)
    end

    it "accumulates multiple tools" do
      agent.add_tool(proc { |value| value * 2 })
      agent.add_tool(proc { |value| value + 1 })

      expect(agent.tools.size).to eq(2)
    end
  end

  describe "#add_handoff" do
    let(:agent) { described_class.new(name: "Agent1") }
    let(:other_agent) { described_class.new(name: "Agent2") }

    it "adds another agent as handoff" do
      agent.add_handoff(other_agent)

      expect(agent.handoffs.size).to eq(1)
      expect(agent.handoffs.first).to eq(other_agent)
    end

    it "raises error for invalid handoff" do
      expect { agent.add_handoff("invalid") }.to raise_error(OpenAIAgents::HandoffError)
    end

    it "accumulates multiple handoffs" do
      agent1 = described_class.new(name: "Agent1")
      agent2 = described_class.new(name: "Agent2")

      agent.add_handoff(agent1)
      agent.add_handoff(agent2)

      expect(agent.handoffs.size).to eq(2)
    end
  end

  describe "#can_handoff_to?" do
    let(:agent) { described_class.new(name: "Agent1") }
    let(:other_agent) { described_class.new(name: "Agent2") }

    it "returns true if handoff is available" do
      agent.add_handoff(other_agent)
      expect(agent.can_handoff_to?("Agent2")).to be true
    end

    it "returns false if handoff is not available" do
      expect(agent.can_handoff_to?("Agent2")).to be false
    end
  end

  describe "#find_handoff" do
    let(:agent) { described_class.new(name: "MainAgent") }
    let(:agent1) { described_class.new(name: "Agent1") }
    let(:agent2) { described_class.new(name: "Agent2") }

    before do
      agent.add_handoff(agent1)
      agent.add_handoff(agent2)
    end

    it "returns the correct agent when found" do
      expect(agent.find_handoff("Agent1")).to eq(agent1)
      expect(agent.find_handoff("Agent2")).to eq(agent2)
    end

    it "returns nil when agent not found" do
      expect(agent.find_handoff("NonExistent")).to be_nil
    end
  end

  describe "#tools?" do
    let(:agent) { described_class.new(name: "TestAgent") }

    it "returns false when no tools are added" do
      expect(agent.tools?).to be false
    end

    it "returns true when tools are added" do
      agent.add_tool(proc { |value| value })
      expect(agent.tools?).to be true
    end
  end

  describe "#execute_tool" do
    let(:agent) { described_class.new(name: "TestAgent") }

    before do
      agent.add_tool(OpenAIAgents::FunctionTool.new(
                       proc { |value:| value * 2 },
                       name: "double",
                       description: "Doubles a number"
                     ))
      agent.add_tool(OpenAIAgents::FunctionTool.new(
                       proc { |name:| "Hello, #{name}!" },
                       name: "greet",
                       description: "Greets a person"
                     ))
    end

    it "executes the correct tool by name" do
      result = agent.execute_tool("double", value: 5)
      expect(result).to eq(10)
    end

    it "executes tool with keyword arguments" do
      result = agent.execute_tool("greet", name: "Alice")
      expect(result).to eq("Hello, Alice!")
    end

    it "raises error when tool not found" do
      expect do
        agent.execute_tool("nonexistent")
      end.to raise_error(OpenAIAgents::ToolError, /Tool 'nonexistent' not found/)
    end

    it "propagates tool execution errors" do
      agent.add_tool(OpenAIAgents::FunctionTool.new(
                       proc { raise StandardError, "Tool failed" },
                       name: "failing_tool"
                     ))

      expect do
        agent.execute_tool("failing_tool")
      end.to raise_error(OpenAIAgents::ToolError, /Error executing tool 'failing_tool'/)
    end
  end

  describe "#to_h" do
    let(:agent) { described_class.new(name: "TestAgent") }

    it "returns a hash representation of the agent" do
      hash = agent.to_h

      expect(hash).to include(
        name: "TestAgent",
        instructions: nil,
        tools: [],
        handoffs: [],
        model: "gpt-4",
        max_turns: 10
      )
    end

    it "includes tools and handoffs in hash" do
      tool = OpenAIAgents::FunctionTool.new(proc { |value| value }, name: "test_tool")
      other_agent = described_class.new(name: "OtherAgent")

      agent.add_tool(tool)
      agent.add_handoff(other_agent)

      hash = agent.to_h

      expect(hash[:tools].size).to eq(1)
      expect(hash[:tools].first).to be_a(Hash)
      expect(hash[:handoffs]).to eq(["OtherAgent"])
    end

    it "handles custom instructions and model" do
      agent = described_class.new(
        name: "CustomAgent",
        instructions: "Custom instructions",
        model: "gpt-3.5-turbo"
      )

      hash = agent.to_h

      expect(hash[:instructions]).to eq("Custom instructions")
      expect(hash[:model]).to eq("gpt-3.5-turbo")
    end
  end

  describe "attribute accessors" do
    let(:agent) { described_class.new(name: "TestAgent") }

    it "allows reading and writing all attributes" do
      agent.name = "NewName"
      agent.instructions = "New instructions"
      agent.model = "claude-3-sonnet"
      agent.max_turns = 20

      expect(agent.name).to eq("NewName")
      expect(agent.instructions).to eq("New instructions")
      expect(agent.model).to eq("claude-3-sonnet")
      expect(agent.max_turns).to eq(20)
    end

    it "allows direct manipulation of tools and handoffs arrays" do
      tool = OpenAIAgents::FunctionTool.new(proc { |value| value })
      other_agent = described_class.new(name: "OtherAgent")

      agent.tools << tool
      agent.handoffs << other_agent

      expect(agent.tools).to include(tool)
      expect(agent.handoffs).to include(other_agent)
    end
  end
end
