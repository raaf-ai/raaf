# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Agent do
  describe "#initialize" do
    it "creates agent with minimal parameters" do
      agent = described_class.new(name: "TestAgent")

      expect(agent.name).to eq("TestAgent")
      expect(agent.instructions).to be_nil
      expect(agent.tools).to eq([])
      expect(agent.handoffs).to eq([])
      expect(agent.model).to eq("gpt-4")
      expect(agent.max_turns).to eq(10)
    end

    it "creates agent with comprehensive parameters" do
      agent = described_class.new(
        name: "FullAgent",
        instructions: "You are a helpful assistant",
        model: "gpt-4o",
        max_turns: 20,
        output_type: String,
        response_format: { type: "json_object" },
        tool_choice: "auto",
        reset_tool_choice: false
      )

      expect(agent.name).to eq("FullAgent")
      expect(agent.instructions).to eq("You are a helpful assistant")
      expect(agent.model).to eq("gpt-4o")
      expect(agent.max_turns).to eq(20)
      expect(agent.output_type).to eq(String)
      expect(agent.response_format).to eq({ type: "json_object" })
      expect(agent.tool_choice).to eq("auto")
      expect(agent.reset_tool_choice).to be false
    end

    it "duplicates arrays to prevent external mutation" do
      original_tools = []
      original_handoffs = []
      
      agent = described_class.new(
        name: "SafeAgent",
        tools: original_tools,
        handoffs: original_handoffs
      )

      expect(agent.tools).not_to be(original_tools)
      expect(agent.handoffs).not_to be(original_handoffs)
    end

    it "accepts block for configuration" do
      agent = described_class.new(name: "BlockAgent") do |a|
        a.instructions = "Block configured"
        a.model = "claude-3-sonnet"
      end

      expect(agent.instructions).to eq("Block configured")
      expect(agent.model).to eq("claude-3-sonnet")
    end
  end

  describe "#add_tool" do
    let(:agent) { described_class.new(name: "ToolAgent") }

    it "adds a Method tool" do
      def sample_method(x)
        x * 2
      end

      agent.add_tool(method(:sample_method))
      
      expect(agent.tools.size).to eq(1)
      expect(agent.tools.first).to be_a(RAAF::FunctionTool)
    end

    it "adds a Proc tool" do
      sample_proc = proc { |x| x + 1 }
      
      agent.add_tool(sample_proc)
      
      expect(agent.tools.size).to eq(1)
      expect(agent.tools.first).to be_a(RAAF::FunctionTool)
    end

    it "adds tool with options" do
      sample_proc = proc { |x| x * 3 }
      
      agent.add_tool(sample_proc, description: "Triple the input")
      
      expect(agent.tools.size).to eq(1)
      expect(agent.tools.first).to be_a(RAAF::FunctionTool)
    end

    it "raises error for unsupported tool type" do
      expect do
        agent.add_tool("invalid_tool")
      end.to raise_error(RAAF::ToolError)
    end
  end

  describe "#add_handoff" do
    let(:agent) { described_class.new(name: "SourceAgent") }
    let(:target_agent) { described_class.new(name: "TargetAgent") }

    it "adds Agent handoff and generates handoff tool" do
      initial_tool_count = agent.tools.size
      
      agent.add_handoff(target_agent)
      
      expect(agent.handoffs.size).to eq(1)
      expect(agent.handoffs.first).to eq(target_agent)
      expect(agent.tools.size).to eq(initial_tool_count + 1)
    end

    it "adds Handoff object" do
      handoff = RAAF::Handoff.new(target_agent)
      
      agent.add_handoff(handoff)
      
      expect(agent.handoffs.size).to eq(1)
      expect(agent.handoffs.first).to eq(handoff)
    end

    it "raises error for invalid handoff type" do
      expect do
        agent.add_handoff("invalid_handoff")
      end.to raise_error(RAAF::HandoffError)
    end
  end

  describe "#to_h" do
    it "converts agent to hash representation" do
      target_agent = described_class.new(name: "TargetAgent")
      agent = described_class.new(
        name: "TestAgent",
        instructions: "Test instructions",
        model: "gpt-4",
        max_turns: 15,
        handoffs: [target_agent],
        response_format: { type: "json_object" }
      )

      result = agent.to_h

      expect(result).to include(
        name: "TestAgent",
        instructions: "Test instructions",
        model: "gpt-4",
        max_turns: 15,
        response_format: { type: "json_object" }
      )
      expect(result[:tools]).to be_an(Array)
      expect(result[:handoffs]).to eq(["TargetAgent"])
    end

    it "handles agents with no handoffs" do
      agent = described_class.new(name: "SimpleAgent")

      result = agent.to_h

      expect(result[:handoffs]).to eq([])
      expect(result[:tools]).to eq([])
    end
  end

  describe "#can_handoff_to?" do
    let(:agent) { described_class.new(name: "SourceAgent") }
    let(:target_agent) { described_class.new(name: "TargetAgent") }

    it "returns true when handoff is available" do
      agent.add_handoff(target_agent)

      expect(agent.can_handoff_to?("TargetAgent")).to be true
    end

    it "returns false when handoff is not available" do
      expect(agent.can_handoff_to?("NonExistentAgent")).to be false
    end

    it "works with Handoff objects" do
      handoff = RAAF::Handoff.new(target_agent)
      agent.add_handoff(handoff)

      expect(agent.can_handoff_to?("TargetAgent")).to be true
    end
  end

  describe "#find_handoff" do
    let(:agent) { described_class.new(name: "SourceAgent") }
    let(:target_agent) { described_class.new(name: "TargetAgent") }

    it "finds handoff by agent name" do
      agent.add_handoff(target_agent)

      result = agent.find_handoff("TargetAgent")

      expect(result).to eq(target_agent)
    end

    it "returns nil for non-existent handoff" do
      result = agent.find_handoff("NonExistent")

      expect(result).to be_nil
    end
  end

  describe "tool checking methods" do
    let(:agent) { described_class.new(name: "TestAgent") }

    describe "#tools?" do
      it "returns true when agent has tools" do
        agent.add_tool(proc { |x| x })

        expect(agent.tools?).to be true
      end

      it "returns false when agent has no tools" do
        expect(agent.tools?).to be false
      end
    end

    describe "#handoffs?" do
      it "returns true when agent has handoffs" do
        target_agent = described_class.new(name: "TargetAgent")
        agent.add_handoff(target_agent)

        expect(agent.handoffs?).to be true
      end

      it "returns false when agent has no handoffs" do
        expect(agent.handoffs?).to be false
      end
    end
  end

  describe "tool access methods" do
    let(:agent) { described_class.new(name: "TestAgent") }
    let(:mock_tool) { double("FunctionTool", name: "test_tool") }

    describe "#enabled_tools" do
      it "returns enabled tools only" do
        mock_context = double("RunContextWrapper")
        enabled_tools = [mock_tool]
        
        allow(RAAF::FunctionTool).to receive(:enabled_tools)
          .with(agent.tools, mock_context)
          .and_return(enabled_tools)

        result = agent.enabled_tools(mock_context)

        expect(result).to eq(enabled_tools)
      end

      it "returns empty array when no tools" do
        result = agent.enabled_tools

        expect(result).to eq([])
      end
    end

    describe "#all_tools" do
      it "returns all tools regardless of enabled state" do
        allow(mock_tool).to receive(:is_a?).with(RAAF::FunctionTool).and_return(true)
        agent.instance_variable_set(:@tools, [mock_tool])

        result = agent.all_tools

        expect(result).to include(mock_tool)
      end

      it "returns empty array when no tools" do
        result = agent.all_tools

        expect(result).to eq([])
      end
    end

    describe "#tools" do
      it "returns enabled tools with context" do
        mock_context = double("RunContextWrapper")
        enabled_tools = [mock_tool]
        
        allow(RAAF::FunctionTool).to receive(:enabled_tools)
          .with(agent.tools, mock_context)
          .and_return(enabled_tools)

        result = agent.tools(mock_context)

        expect(result).to eq(enabled_tools)
      end
    end
  end

  describe "#execute_tool" do
    let(:agent) { described_class.new(name: "TestAgent") }
    
    it "executes tool by name successfully" do
      mock_tool = double("FunctionTool")
      allow(mock_tool).to receive(:name).and_return("test_tool")
      allow(mock_tool).to receive(:call).with(x: 5).and_return(10)
      
      agent.instance_variable_set(:@tools, [mock_tool])

      result = agent.execute_tool("test_tool", x: 5)

      expect(result).to eq(10)
    end

    it "raises ToolError when tool not found" do
      expect do
        agent.execute_tool("nonexistent_tool")
      end.to raise_error(RAAF::ToolError, /Tool 'nonexistent_tool' not found/)
    end

    it "raises ToolError when tool execution fails" do
      mock_tool = double("FunctionTool")
      allow(mock_tool).to receive(:name).and_return("failing_tool")
      allow(mock_tool).to receive(:call).and_raise(StandardError, "Tool failed")
      
      agent.instance_variable_set(:@tools, [mock_tool])

      expect do
        agent.execute_tool("failing_tool")
      end.to raise_error(RAAF::ToolError, /Tool execution failed/)
    end
  end

  describe "#tool_exists?" do
    let(:agent) { described_class.new(name: "TestAgent") }

    it "returns true when tool exists" do
      mock_tool = double("FunctionTool")
      allow(mock_tool).to receive(:name).and_return("existing_tool")
      agent.instance_variable_set(:@tools, [mock_tool])

      expect(agent.tool_exists?("existing_tool")).to be true
      expect(agent.tool_exists?(:existing_tool)).to be true
    end

    it "returns false when tool does not exist" do
      expect(agent.tool_exists?("nonexistent_tool")).to be false
    end
  end

  describe "#method_missing" do
    let(:agent) { described_class.new(name: "TestAgent") }

    it "delegates to tool execution for matching tool names" do
      mock_tool = double("FunctionTool")
      allow(mock_tool).to receive(:name).and_return("dynamic_tool")
      allow(mock_tool).to receive(:call).with(x: 10).and_return(20)
      
      agent.instance_variable_set(:@tools, [mock_tool])

      result = agent.dynamic_tool(x: 10)

      expect(result).to eq(20)
    end

    it "raises NoMethodError for non-existent tools" do
      expect do
        agent.nonexistent_method
      end.to raise_error(NoMethodError)
    end
  end

  describe "#respond_to?" do
    let(:agent) { described_class.new(name: "TestAgent") }

    it "returns true for tool names" do
      mock_tool = double("FunctionTool")
      allow(mock_tool).to receive(:name).and_return("available_tool")
      agent.instance_variable_set(:@tools, [mock_tool])

      expect(agent.respond_to?(:available_tool)).to be true
    end

    it "returns false for non-tool names" do
      expect(agent.respond_to?(:unavailable_method)).to be false
    end
  end

  describe "guardrail methods" do
    let(:agent) { described_class.new(name: "TestAgent") }
    let(:mock_input_guardrail) { double("InputGuardrail") }
    let(:mock_output_guardrail) { double("OutputGuardrail") }

    describe "#add_input_guardrail" do
      it "adds input guardrail successfully" do
        agent.add_input_guardrail(mock_input_guardrail)

        expect(agent.input_guardrails).to include(mock_input_guardrail)
      end
    end

    describe "#add_output_guardrail" do
      it "adds output guardrail successfully" do
        agent.add_output_guardrail(mock_output_guardrail)

        expect(agent.output_guardrails).to include(mock_output_guardrail)
      end
    end

    describe "#input_guardrails?" do
      it "returns true when agent has input guardrails" do
        agent.add_input_guardrail(mock_input_guardrail)

        expect(agent.input_guardrails?).to be true
      end

      it "returns false when agent has no input guardrails" do
        expect(agent.input_guardrails?).to be false
      end
    end

    describe "#output_guardrails?" do
      it "returns true when agent has output guardrails" do
        agent.add_output_guardrail(mock_output_guardrail)

        expect(agent.output_guardrails?).to be true
      end

      it "returns false when agent has no output guardrails" do
        expect(agent.output_guardrails?).to be false
      end
    end
  end

  describe "reset methods" do
    let(:agent) { described_class.new(name: "TestAgent") }
    let(:mock_input_guardrail) { double("InputGuardrail") }
    let(:mock_output_guardrail) { double("OutputGuardrail") }

    describe "#reset_tools!" do
      it "clears all tools and returns self" do
        agent.add_tool(proc { |x| x })
        
        result = agent.reset_tools!

        expect(agent.tools).to be_empty
        expect(result).to eq(agent)
      end
    end

    describe "#reset_handoffs!" do
      it "clears all handoffs and returns self" do
        target_agent = described_class.new(name: "TargetAgent")
        agent.add_handoff(target_agent)
        
        result = agent.reset_handoffs!

        expect(agent.handoffs).to be_empty
        expect(result).to eq(agent)
      end
    end

    describe "#reset_input_guardrails!" do
      it "clears all input guardrails and returns self" do
        agent.add_input_guardrail(mock_input_guardrail)
        
        result = agent.reset_input_guardrails!

        expect(agent.input_guardrails).to be_empty
        expect(result).to eq(agent)
      end
    end

    describe "#reset_output_guardrails!" do
      it "clears all output guardrails and returns self" do
        agent.add_output_guardrail(mock_output_guardrail)
        
        result = agent.reset_output_guardrails!

        expect(agent.output_guardrails).to be_empty
        expect(result).to eq(agent)
      end
    end

    describe "#reset!" do
      it "resets all agent state and returns self" do
        # Add various things to reset
        target_agent = described_class.new(name: "TargetAgent")
        agent.add_tool(proc { |x| x })
        agent.add_handoff(target_agent)
        agent.add_input_guardrail(mock_input_guardrail)
        agent.add_output_guardrail(mock_output_guardrail)
        agent.output_type = String
        
        result = agent.reset!

        expect(agent.tools).to be_empty
        expect(agent.handoffs).to be_empty
        expect(agent.input_guardrails).to be_empty
        expect(agent.output_guardrails).to be_empty
        expect(agent.output_type).to be_nil
        expect(result).to eq(agent)
      end
    end
  end

  describe "#validate_output" do
    context "without output type schema" do
      let(:agent) { described_class.new(name: "TestAgent") }

      it "returns output unchanged" do
        output = "test output"

        result = agent.validate_output(output)

        expect(result).to eq(output)
      end
    end
  end

  describe "#clone" do
    let(:original_agent) do
      target_agent = described_class.new(name: "TargetAgent")
      described_class.new(
        name: "OriginalAgent",
        instructions: "Original instructions",
        model: "gpt-4",
        max_turns: 10,
        handoffs: [target_agent],
        output_type: String,
        handoff_description: "Original description"
      )
    end

    it "creates exact clone with no overrides" do
      cloned_agent = original_agent.clone

      expect(cloned_agent.name).to eq(original_agent.name)
      expect(cloned_agent.instructions).to eq(original_agent.instructions)
      expect(cloned_agent.model).to eq(original_agent.model)
      expect(cloned_agent.max_turns).to eq(original_agent.max_turns)
      expect(cloned_agent.handoffs).to eq(original_agent.handoffs)
      expect(cloned_agent).not_to be(original_agent)
    end

    it "creates clone with parameter overrides" do
      cloned_agent = original_agent.clone(
        name: "ClonedAgent",
        instructions: "Cloned instructions",
        model: "gpt-3.5-turbo"
      )

      expect(cloned_agent.name).to eq("ClonedAgent")
      expect(cloned_agent.instructions).to eq("Cloned instructions")
      expect(cloned_agent.model).to eq("gpt-3.5-turbo")
      expect(cloned_agent.max_turns).to eq(original_agent.max_turns) # Unchanged
    end

    it "maintains separate arrays for tools and handoffs" do
      original_agent.add_tool(proc { |x| x })
      cloned_agent = original_agent.clone

      # Arrays should be separate
      expect(cloned_agent.tools).not_to be(original_agent.tools)
      expect(cloned_agent.handoffs).not_to be(original_agent.handoffs)
      
      # But content should be the same (order doesn't matter for tools)
      expect(cloned_agent.tools.map(&:name).sort).to eq(original_agent.tools.map(&:name).sort)
      expect(cloned_agent.handoffs).to eq(original_agent.handoffs)
    end
  end

  describe "#as_tool" do
    let(:agent) { described_class.new(name: "HelperAgent") }

    it "creates FunctionTool with default parameters" do
      result = agent.as_tool

      expect(result).to be_a(RAAF::FunctionTool)
      expect(result.name).to eq("helperagent")
    end

    it "creates FunctionTool with custom parameters" do
      result = agent.as_tool(
        tool_name: "custom_helper",
        tool_description: "Custom helper tool"
      )

      expect(result.name).to eq("custom_helper")
      expect(result.description).to eq("Custom helper tool")
    end

    it "uses handoff description when available" do
      agent.handoff_description = "Use me for specialized help"

      result = agent.as_tool

      expect(result.description).to eq("Use me for specialized help")
    end
  end

  describe "#get_input_schema" do
    it "returns basic schema for agent without handoff description" do
      agent = described_class.new(name: "BasicAgent")

      result = agent.get_input_schema

      expect(result).to include(
        type: "object",
        properties: {
          input: {
            type: "string",
            description: "Input text to send to the BasicAgent agent"
          }
        },
        required: ["input"]
      )
    end

    it "includes handoff description in schema when available" do
      agent = described_class.new(
        name: "DescribedAgent",
        handoff_description: "Use for complex analysis"
      )

      result = agent.get_input_schema

      expect(result[:properties][:input][:description]).to include("Use for complex analysis")
    end
  end

  describe "memory system integration" do
    context "without memory store" do
      let(:agent) { described_class.new(name: "NoMemoryAgent") }

      it "raises error when trying to remember without memory store" do
        expect do
          agent.remember("Test content")
        end.to raise_error(RAAF::AgentError, "Memory store not configured")
      end

      it "returns empty array when recalling without memory store" do
        result = agent.recall("anything")
        expect(result).to eq([])
      end

      it "returns 0 memory count without memory store" do
        result = agent.memory_count
        expect(result).to eq(0)
      end

      it "returns false for memories? without memory store" do
        result = agent.memories?
        expect(result).to be false
      end

      it "returns false when forgetting without memory store" do
        result = agent.forget("any_key")
        expect(result).to be false
      end

      it "does nothing when clearing memories without memory store" do
        expect { agent.clear_memories }.not_to raise_error
      end

      it "returns empty array for recent_memories without memory store" do
        result = agent.recent_memories
        expect(result).to eq([])
      end

      it "returns empty string for memory_context without memory store" do
        result = agent.memory_context("any query")
        expect(result).to eq("")
      end
    end
  end

  describe "Edge cases" do
    describe "handoff system edge cases" do
      it "handles handoff to agent with same name" do
        agent1 = described_class.new(name: "SameName")
        agent2 = described_class.new(name: "SameName")

        agent1.add_handoff(agent2)

        expect(agent1.can_handoff_to?("SameName")).to be true
        expect(agent1.find_handoff("SameName")).to eq(agent2)
      end

      it "handles circular handoffs" do
        agent1 = described_class.new(name: "Agent1")
        agent2 = described_class.new(name: "Agent2")

        agent1.add_handoff(agent2)
        agent2.add_handoff(agent1)

        expect(agent1.can_handoff_to?("Agent2")).to be true
        expect(agent2.can_handoff_to?("Agent1")).to be true
      end
    end

    describe "validation edge cases" do
      it "handles validation with complex output structures" do
        complex_output = {
          nested: {
            array: [1, 2, { deep: "value" }],
            boolean: true,
            null_value: nil
          },
          string: "test"
        }

        agent = described_class.new(name: "TestAgent")
        result = agent.validate_output(complex_output)

        expect(result).to eq(complex_output)
      end
    end

    describe "tool execution edge cases" do
      let(:agent) { described_class.new(name: "TestAgent") }

      it "handles tool execution with malformed arguments gracefully" do
        mock_tool = double("FunctionTool")
        allow(mock_tool).to receive(:name).and_return("broken_tool")
        allow(mock_tool).to receive(:call).and_raise(ArgumentError, "Wrong arguments")
        
        agent.instance_variable_set(:@tools, [mock_tool])

        expect do
          agent.execute_tool("broken_tool", invalid: "args")
        end.to raise_error(RAAF::ToolError, /Tool execution failed/)
      end

      it "handles method_missing with complex arguments" do
        expect do
          agent.complex_nonexistent_method(a: 1, b: [1, 2, 3]) { |x| x * 2 }
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe "private helper methods" do
    let(:agent) { described_class.new(name: "TestAgent") }

    describe "#safe_map_to_h" do
      it "maps collection with to_h method" do
        mock_items = [
          double("Item1", to_h: { name: "item1" }),
          double("Item2", to_h: { name: "item2" })
        ]

        result = agent.send(:safe_map_to_h, mock_items)

        expect(result).to eq([{ name: "item1" }, { name: "item2" }])
      end

      it "maps collection without to_h method" do
        simple_items = ["item1", "item2"]

        result = agent.send(:safe_map_to_h, simple_items)

        expect(result).to eq(["item1", "item2"])
      end

      it "handles empty collection" do
        result = agent.send(:safe_map_to_h, [])

        expect(result).to eq([])
      end
    end

    describe "#safe_map_names" do
      it "maps agents to names" do
        agents = [
          described_class.new(name: "Agent1"),
          described_class.new(name: "Agent2")
        ]

        result = agent.send(:safe_map_names, agents)

        expect(result).to eq(["Agent1", "Agent2"])
      end

      it "handles empty collection" do
        result = agent.send(:safe_map_names, [])

        expect(result).to eq([])
      end
    end

    describe "#generate_handoff_tools" do
      it "generates tools for each handoff" do
        target_agent1 = described_class.new(name: "Target1")
        target_agent2 = described_class.new(name: "Target2")
        
        agent.instance_variable_set(:@handoffs, [target_agent1, target_agent2])

        agent.send(:generate_handoff_tools)

        expect(agent.tools.size).to eq(2)
        tool_names = agent.tools.map(&:name)
        expect(tool_names).to include("transfer_to_target1")
        expect(tool_names).to include("transfer_to_target2")
      end

      it "handles empty handoffs list" do
        agent.instance_variable_set(:@handoffs, [])

        agent.send(:generate_handoff_tools)

        expect(agent.tools.size).to eq(0)
      end
    end

    describe "#create_handoff_tool" do
      it "creates tool for Agent handoff" do
        target_agent = described_class.new(name: "TargetAgent")

        result = agent.send(:create_handoff_tool, target_agent)

        expect(result).to be_a(RAAF::FunctionTool)
        expect(result.name).to eq("transfer_to_target_agent")
      end
    end

    describe "#create_agent_handoff_tool" do
      it "creates handoff tool with proper schema and behavior" do
        target_agent = described_class.new(name: "TargetAgent")

        result = agent.send(:create_agent_handoff_tool, target_agent)

        expect(result).to be_a(RAAF::FunctionTool)
        expect(result.name).to eq("transfer_to_target_agent")
        expect(result.description).to include("TargetAgent")
      end

      it "handles agent with handoff description" do
        target_agent = described_class.new(
          name: "DescribedTarget",
          handoff_description: "Use for specialized tasks"
        )

        result = agent.send(:create_agent_handoff_tool, target_agent)

        expect(result.description).to include("Use for specialized tasks")
      end
    end
  end
end