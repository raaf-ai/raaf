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

    it "supports block-based configuration" do
      agent = described_class.new(name: "TestAgent") do |agent|
        agent.instructions = "Custom instructions via block"
        agent.model = "gpt-3.5-turbo"
        agent.add_tool(proc { |x| x * 2 })
      end

      expect(agent.instructions).to eq("Custom instructions via block")
      expect(agent.model).to eq("gpt-3.5-turbo")
      expect(agent.tools.size).to eq(1)
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

  describe "#handoffs?" do
    let(:agent) { described_class.new(name: "TestAgent") }

    it "returns false when no handoffs are added" do
      expect(agent.handoffs?).to be false
    end

    it "returns true when handoffs are added" do
      handoff_agent = described_class.new(name: "HandoffAgent")
      agent.add_handoff(handoff_agent)
      expect(agent.handoffs?).to be true
    end
  end

  describe "#output_schema?" do
    let(:agent) { described_class.new(name: "TestAgent") }

    it "returns false when no output schema is set" do
      expect(agent.output_schema?).to be false
    end

    it "returns true when output schema is set" do
      agent_with_schema = described_class.new(name: "TestAgent", output_schema: String)
      expect(agent_with_schema.output_schema?).to be true
    end
  end

  describe "#input_guardrails?" do
    let(:agent) { described_class.new(name: "TestAgent") }

    it "returns false when no input guardrails are set" do
      expect(agent.input_guardrails?).to be false
    end

    it "returns true when input guardrails are set" do
      agent.input_guardrails = [OpenAIAgents::Guardrails::InputGuardrail.new(proc { |_,_,_| true })]
      expect(agent.input_guardrails?).to be true
    end
  end

  describe "#output_guardrails?" do
    let(:agent) { described_class.new(name: "TestAgent") }

    it "returns false when no output guardrails are set" do
      expect(agent.output_guardrails?).to be false
    end

    it "returns true when output guardrails are set" do
      agent.output_guardrails = [OpenAIAgents::Guardrails::OutputGuardrail.new(proc { |_,_,_| true })]
      expect(agent.output_guardrails?).to be true
    end
  end

  describe "bang methods for mutation" do
    let(:agent) do
      agent = described_class.new(name: "TestAgent")
      agent.add_tool(proc { |_| nil })
      handoff_agent = described_class.new(name: "HandoffAgent")
      agent.add_handoff(handoff_agent)
      agent.input_guardrails = [OpenAIAgents::Guardrails::InputGuardrail.new(proc { |_,_,_| true })]
      agent.output_guardrails = [OpenAIAgents::Guardrails::OutputGuardrail.new(proc { |_,_,_| true })]
      agent
    end

    describe "#reset_tools!" do
      it "clears all tools and returns self" do
        expect(agent.tools?).to be true
        result = agent.reset_tools!
        expect(agent.tools?).to be false
        expect(result).to eq(agent)
      end
    end

    describe "#reset_handoffs!" do
      it "clears all handoffs and returns self" do
        expect(agent.handoffs?).to be true
        result = agent.reset_handoffs!
        expect(agent.handoffs?).to be false
        expect(result).to eq(agent)
      end
    end

    describe "#reset_input_guardrails!" do
      it "clears all input guardrails and returns self" do
        expect(agent.input_guardrails?).to be true
        result = agent.reset_input_guardrails!
        expect(agent.input_guardrails?).to be false
        expect(result).to eq(agent)
      end
    end

    describe "#reset_output_guardrails!" do
      it "clears all output guardrails and returns self" do
        expect(agent.output_guardrails?).to be true
        result = agent.reset_output_guardrails!
        expect(agent.output_guardrails?).to be false
        expect(result).to eq(agent)
      end
    end

    describe "#reset!" do
      it "clears everything and returns self" do
        expect(agent.tools?).to be true
        expect(agent.handoffs?).to be true
        expect(agent.input_guardrails?).to be true
        expect(agent.output_guardrails?).to be true

        result = agent.reset!

        expect(agent.tools?).to be false
        expect(agent.handoffs?).to be false
        expect(agent.input_guardrails?).to be false
        expect(agent.output_guardrails?).to be false
        expect(result).to eq(agent)
      end
    end
  end

  describe "dynamic method calls via method_missing" do
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

    it "allows calling tools as methods" do
      result = agent.double(value: 5)
      expect(result).to eq(10)
    end

    it "passes arguments correctly through method_missing" do
      result = agent.greet(name: "Alice")
      expect(result).to eq("Hello, Alice!")
    end

    it "raises NoMethodError for non-existent tools" do
      expect do
        agent.non_existent_tool
      end.to raise_error(NoMethodError)
    end

    it "responds to tool methods via respond_to_missing?" do
      expect(agent.respond_to?(:double)).to be true
      expect(agent.respond_to?(:greet)).to be true
      expect(agent.respond_to?(:non_existent_tool)).to be false
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
