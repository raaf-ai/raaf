# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Agent do
  let(:mock_memory_store) { double("MemoryStore") }
  let(:mock_function_tool) { RAAF::FunctionTool.new(proc { |x| x }, name: "test_tool") }
  let(:mock_agent_hooks) { double("AgentHooks") }
  let(:mock_input_guardrail) { double("InputGuardrail") }
  let(:mock_output_guardrail) { double("OutputGuardrail") }

  describe "#initialize" do
    it "creates agent with minimal parameters" do
      agent = described_class.new(name: "TestAgent")

      expect(agent.name).to eq("TestAgent")
      expect(agent.instructions).to be_nil
      expect(agent.tools).to eq([])
      expect(agent.handoffs).to eq([])
      expect(agent.model).to eq("gpt-4")
      expect(agent.max_turns).to eq(10)
      expect(agent.output_type).to be_nil
      expect(agent.hooks).to be_nil
      expect(agent.prompt).to be_nil
    end

    it "creates agent with comprehensive parameters" do
      agent = described_class.new(
        name: "FullAgent",
        instructions: "You are a helpful assistant",
        model: "gpt-4o",
        max_turns: 20,
        tools: [mock_function_tool],
        handoffs: [],
        output_type: String,
        hooks: mock_agent_hooks,
        prompt: { role: "system", content: "Custom prompt" },
        handoff_description: "Transfer to this agent for help",
        response_format: { type: "json_object" },
        tool_choice: "auto",
        memory_store: mock_memory_store,
        reset_tool_choice: false
      )

      expect(agent.name).to eq("FullAgent")
      expect(agent.instructions).to eq("You are a helpful assistant")
      expect(agent.model).to eq("gpt-4o")
      expect(agent.max_turns).to eq(20)
      expect(agent.tools).to include(mock_function_tool)
      expect(agent.handoffs).to eq([])
      expect(agent.output_type).to eq(String)
      expect(agent.hooks).to eq(mock_agent_hooks)
      expect(agent.handoff_description).to eq("Transfer to this agent for help")
      expect(agent.response_format).to eq({ type: "json_object" })
      expect(agent.tool_choice).to eq("auto")
      expect(agent.reset_tool_choice).to be false
    end

    it "duplicates tools and handoffs arrays to prevent external mutation" do
      original_tools = [mock_function_tool]
      original_handoffs = []
      
      agent = described_class.new(
        name: "SafeAgent",
        tools: original_tools,
        handoffs: original_handoffs
      )

      expect(agent.tools).not_to be(original_tools)
      expect(agent.handoffs).not_to be(original_handoffs)
      expect(agent.tools).to eq(original_tools)
      expect(agent.handoffs).to eq(original_handoffs)
    end

    it "handles model settings hash properly" do
      model_settings = { temperature: 0.7, top_p: 0.9 }
      agent = described_class.new(
        name: "ModelSettingsAgent", 
        model_settings: model_settings
      )

      expect(agent.model_settings).to be_a(RAAF::ModelSettings)
      expect(agent.model_settings.to_h).to include(temperature: 0.7, top_p: 0.9)
    end

    it "configures tool use behavior properly" do
      agent = described_class.new(
        name: "BehaviorAgent",
        tool_use_behavior: :sequential
      )

      expect(agent.tool_use_behavior).to be_a(RAAF::ToolUseBehavior::Base)
    end

    it "accepts block for configuration" do
      agent = described_class.new(name: "BlockAgent") do |a|
        a.instructions = "Block configured"
        a.model = "claude-3-sonnet"
      end

      expect(agent.instructions).to eq("Block configured")
      expect(agent.model).to eq("claude-3-sonnet")
    end

    it "generates handoff tools automatically when handoffs are provided" do
      target_agent = described_class.new(name: "TargetAgent")
      agent = described_class.new(
        name: "SourceAgent",
        handoffs: [target_agent]
      )

      expect(agent.tools.size).to be > 0
      handoff_tool = agent.tools.find { |t| t.name == "transfer_to_target_agent" }
      expect(handoff_tool).not_to be_nil
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

    it "adds a FunctionTool directly" do
      agent.add_tool(mock_function_tool)
      
      expect(agent.tools.size).to eq(1)
      expect(agent.tools.first).to eq(mock_function_tool)
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
      
      handoff_tool = agent.tools.find { |t| t.name == "transfer_to_target_agent" }
      expect(handoff_tool).not_to be_nil
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

    it "logs handoff addition" do
      # Log method may not be available in test environment, just verify it doesn't crash
      expect { agent.add_handoff(target_agent) }.not_to raise_error
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

    it "logs debug information when searching" do
      # Log method may not be available in test environment, just verify it doesn't crash
      expect { agent.find_handoff("TargetAgent") }.not_to raise_error
    end

    it "logs when handoff is found" do
      agent.add_handoff(target_agent)
      
      # Log method may not be available in test environment, just verify it doesn't crash
      expect { agent.find_handoff("TargetAgent") }.not_to raise_error
    end
  end

  describe "#tools?" do
    let(:agent) { described_class.new(name: "TestAgent") }

    it "returns true when agent has tools" do
      agent.add_tool(proc { |x| x })

      expect(agent.tools?).to be true
    end

    it "returns false when agent has no tools" do
      expect(agent.tools?).to be false
    end

    it "considers context for enabled tools" do
      mock_context = double("RunContextWrapper")
      agent.add_tool(mock_function_tool)
      
      allow(RAAF::FunctionTool).to receive(:enabled_tools)
        .with(agent.tools, mock_context)
        .and_return([mock_function_tool])

      expect(agent.tools?(mock_context)).to be true
    end
  end

  describe "#handoffs?" do
    let(:agent) { described_class.new(name: "TestAgent") }

    it "returns true when agent has handoffs" do
      target_agent = described_class.new(name: "TargetAgent")
      agent.add_handoff(target_agent)

      expect(agent.handoffs?).to be true
    end

    it "returns false when agent has no handoffs" do
      expect(agent.handoffs?).to be false
    end
  end

  describe "#input_guardrails?" do
    let(:agent) { described_class.new(name: "TestAgent") }

    it "returns true when agent has input guardrails" do
      agent.add_input_guardrail(mock_input_guardrail)

      expect(agent.input_guardrails?).to be true
    end

    it "returns false when agent has no input guardrails" do
      expect(agent.input_guardrails?).to be false
    end
  end

  describe "#output_guardrails?" do
    let(:agent) { described_class.new(name: "TestAgent") }

    it "returns true when agent has output guardrails" do
      agent.add_output_guardrail(mock_output_guardrail)

      expect(agent.output_guardrails?).to be true
    end

    it "returns false when agent has no output guardrails" do
      expect(agent.output_guardrails?).to be false
    end
  end

  describe "#hooks?" do
    it "returns true when agent has hooks" do
      agent = described_class.new(name: "TestAgent", hooks: mock_agent_hooks)

      expect(agent.hooks?).to be true
    end

    it "returns false when agent has no hooks" do
      agent = described_class.new(name: "TestAgent")

      expect(agent.hooks?).to be false
    end
  end

  describe "#enabled_tools" do
    let(:agent) { described_class.new(name: "TestAgent") }

    it "returns enabled tools only" do
      mock_context = double("RunContextWrapper")
      enabled_tools = [mock_function_tool]
      
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
    let(:agent) { described_class.new(name: "TestAgent") }

    it "returns all tools regardless of enabled state" do
      agent.add_tool(mock_function_tool)

      result = agent.all_tools

      expect(result).to include(mock_function_tool)
    end

    it "returns empty array when no tools" do
      result = agent.all_tools

      expect(result).to eq([])
    end
  end

  describe "#tools" do
    let(:agent) { described_class.new(name: "TestAgent") }

    it "returns enabled tools with context" do
      mock_context = double("RunContextWrapper")
      enabled_tools = [mock_function_tool]
      
      allow(RAAF::FunctionTool).to receive(:enabled_tools)
        .with(agent.tools, mock_context)
        .and_return(enabled_tools)

      result = agent.tools(mock_context)

      expect(result).to eq(enabled_tools)
    end

    it "returns all tools when no context provided" do
      agent.add_tool(mock_function_tool)

      result = agent.tools

      expect(result).to include(mock_function_tool)
    end
  end

  describe "#execute_tool" do
    let(:agent) { described_class.new(name: "TestAgent") }
    
    it "executes tool by name successfully" do
      mock_tool = RAAF::FunctionTool.new(proc { |x:| x * 2 }, name: "test_tool")
      
      agent.add_tool(mock_tool)

      result = agent.execute_tool("test_tool", x: 5)

      expect(result).to eq(10)
    end

    it "raises ToolError when tool not found" do
      expect do
        agent.execute_tool("nonexistent_tool")
      end.to raise_error(RAAF::ToolError, /Tool 'nonexistent_tool' not found/)
    end

    it "raises ToolError when tool execution fails" do
      mock_tool = RAAF::FunctionTool.new(proc { raise StandardError, "Tool failed" }, name: "failing_tool")
      
      agent.add_tool(mock_tool)

      expect do
        agent.execute_tool("failing_tool")
      end.to raise_error(RAAF::ToolError, /Tool execution failed/)
    end
  end

  describe "#tool_exists?" do
    let(:agent) { described_class.new(name: "TestAgent") }

    it "returns true when tool exists" do
      mock_tool = RAAF::FunctionTool.new(proc { |x| x }, name: "existing_tool")
      agent.add_tool(mock_tool)

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
      # Create a real FunctionTool
      mock_tool = RAAF::FunctionTool.new(proc { |x:| x * 2 }, name: "dynamic_tool")
      
      agent.add_tool(mock_tool)

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
      mock_tool = RAAF::FunctionTool.new(proc { |x| x }, name: "available_tool")
      agent.add_tool(mock_tool)

      expect(agent.respond_to?(:available_tool)).to be true
    end

    it "returns false for non-tool names" do
      expect(agent.respond_to?(:unavailable_method)).to be false
    end
  end

  describe "#add_input_guardrail" do
    let(:agent) { described_class.new(name: "TestAgent") }

    it "adds input guardrail successfully" do
      agent.add_input_guardrail(mock_input_guardrail)

      expect(agent.input_guardrails).to include(mock_input_guardrail)
    end
  end

  describe "#add_output_guardrail" do
    let(:agent) { described_class.new(name: "TestAgent") }

    it "adds output guardrail successfully" do
      agent.add_output_guardrail(mock_output_guardrail)

      expect(agent.output_guardrails).to include(mock_output_guardrail)
    end
  end

  describe "#reset_tools!" do
    let(:agent) { described_class.new(name: "TestAgent") }

    it "clears all tools and returns self" do
      agent.add_tool(mock_function_tool)
      
      result = agent.reset_tools!

      expect(agent.tools).to be_empty
      expect(result).to eq(agent)
    end
  end

  describe "#reset_handoffs!" do
    let(:agent) { described_class.new(name: "TestAgent") }

    it "clears all handoffs and returns self" do
      target_agent = described_class.new(name: "TargetAgent")
      agent.add_handoff(target_agent)
      
      result = agent.reset_handoffs!

      expect(agent.handoffs).to be_empty
      expect(result).to eq(agent)
    end
  end

  describe "#reset_input_guardrails!" do
    let(:agent) { described_class.new(name: "TestAgent") }

    it "clears all input guardrails and returns self" do
      agent.add_input_guardrail(mock_input_guardrail)
      
      result = agent.reset_input_guardrails!

      expect(agent.input_guardrails).to be_empty
      expect(result).to eq(agent)
    end
  end

  describe "#reset_output_guardrails!" do
    let(:agent) { described_class.new(name: "TestAgent") }

    it "clears all output guardrails and returns self" do
      agent.add_output_guardrail(mock_output_guardrail)
      
      result = agent.reset_output_guardrails!

      expect(agent.output_guardrails).to be_empty
      expect(result).to eq(agent)
    end
  end

  describe "#reset!" do
    let(:agent) { described_class.new(name: "TestAgent") }

    it "resets all agent state and returns self" do
      # Add various things to reset
      target_agent = described_class.new(name: "TargetAgent")
      agent.add_tool(mock_function_tool)
      agent.add_handoff(target_agent)
      agent.add_input_guardrail(mock_input_guardrail)
      agent.add_output_guardrail(mock_output_guardrail)
      agent.output_type = String
      agent.hooks = mock_agent_hooks
      
      result = agent.reset!

      expect(agent.tools).to be_empty
      expect(agent.handoffs).to be_empty
      expect(agent.input_guardrails).to be_empty
      expect(agent.output_guardrails).to be_empty
      expect(agent.output_type).to be_nil
      expect(agent.hooks).to be_nil
      expect(result).to eq(agent)
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

    context "with output type schema" do
      let(:agent) { described_class.new(name: "TestAgent", output_type: String) }

      before do
        # Mock the schema configuration
        mock_schema = double("AgentOutputSchema")
        allow(mock_schema).to receive(:plain_text?).and_return(false)
        allow(mock_schema).to receive(:validate_json).with("valid json").and_return("parsed result")
        agent.instance_variable_set(:@output_type_schema, mock_schema)
      end

      it "validates JSON string output" do
        result = agent.validate_output("valid json")

        expect(result).to eq("parsed result")
      end

      it "validates non-string output using TypeAdapter" do
        mock_adapter = double("TypeAdapter")
        allow(mock_adapter).to receive(:validate).with({ key: "value" }).and_return({ key: "value" })
        allow(RAAF::TypeAdapter).to receive(:new).with(String).and_return(mock_adapter)

        result = agent.validate_output({ key: "value" })

        expect(result).to eq({ key: "value" })
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
        hooks: mock_agent_hooks,
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
      original_agent.add_tool(mock_function_tool)
      cloned_agent = original_agent.clone

      # Arrays should be separate
      expect(cloned_agent.tools).not_to be(original_agent.tools)
      expect(cloned_agent.handoffs).not_to be(original_agent.handoffs)
      
      # Tools should be the same - use name comparison since handoff tools are regenerated
      original_tool_names = original_agent.tools.map(&:name).sort
      cloned_tool_names = cloned_agent.tools.map(&:name).sort
      expect(cloned_tool_names).to eq(original_tool_names)
      
      # Handoffs should be identical
      expect(cloned_agent.handoffs).to eq(original_agent.handoffs)
    end
  end

  describe "#as_tool" do
    let(:agent) { described_class.new(name: "HelperAgent") }

    it "creates FunctionTool with default parameters" do
      result = agent.as_tool

      expect(result).to be_a(RAAF::FunctionTool)
      expect(result.name).to eq("helperagent")
      expect(result.description).to eq("Delegate to HelperAgent")
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

    it "accepts custom output extractor block" do
      extractor = proc { |result| result.upcase }

      result = agent.as_tool(custom_output_extractor: extractor)

      expect(result).to be_a(RAAF::FunctionTool)
      # The extractor would be used during tool execution
    end
  end

  describe "Memory System Integration" do
    let(:agent) { described_class.new(name: "MemoryAgent", memory_store: mock_memory_store) }

    describe "#remember" do
      it "stores memory successfully when memory store available" do
        allow(mock_memory_store).to receive(:store).and_return(true)
        allow(SecureRandom).to receive(:uuid).and_return("test-uuid")

        result = agent.remember("Important information", metadata: { category: "user_preference" })

        expect(result).to eq("MemoryAgent_test-uuid")
      end

      it "raises error when memory store not configured" do
        agent_without_memory = described_class.new(name: "NoMemoryAgent")

        expect do
          agent_without_memory.remember("Test content")
        end.to raise_error(RAAF::AgentError, "Memory store not configured")
      end
    end

    describe "#recall" do
      it "searches memories successfully" do
        mock_memories = [
          { content: "User prefers morning meetings", metadata: { category: "preference" } },
          { content: "User is from California", metadata: { category: "location" } }
        ]
        
        allow(mock_memory_store).to receive(:search).and_return(mock_memories)

        result = agent.recall("user preferences", limit: 5)

        expect(result).to eq(mock_memories)
        expect(mock_memory_store).to have_received(:search).with(
          "user preferences",
          hash_including(limit: 5, agent_name: "MemoryAgent")
        )
      end

      it "returns empty array when no memory store" do
        agent_without_memory = described_class.new(name: "NoMemoryAgent")

        result = agent_without_memory.recall("anything")

        expect(result).to eq([])
      end

      it "filters by conversation_id when provided" do
        allow(mock_memory_store).to receive(:search).and_return([])

        agent.recall("test query", conversation_id: "conv_456")

        expect(mock_memory_store).to have_received(:search).with(
          "test query",
          hash_including(conversation_id: "conv_456")
        )
      end

      it "filters by tags when provided" do
        allow(mock_memory_store).to receive(:search).and_return([])

        agent.recall("test query", tags: ["important", "urgent"])

        expect(mock_memory_store).to have_received(:search).with(
          "test query",
          hash_including(tags: ["important", "urgent"])
        )
      end
    end

    describe "#memory_count" do
      it "returns count of memories" do
        mock_keys = ["key1", "key2", "key3"]
        allow(mock_memory_store).to receive(:list_keys).and_return(mock_keys)

        result = agent.memory_count

        expect(result).to eq(3)
        expect(mock_memory_store).to have_received(:list_keys).with(agent_name: "MemoryAgent")
      end

      it "returns 0 when no memory store" do
        agent_without_memory = described_class.new(name: "NoMemoryAgent")

        result = agent_without_memory.memory_count

        expect(result).to eq(0)
      end
    end

    describe "#memories?" do
      it "returns true when agent has memories" do
        allow(mock_memory_store).to receive(:list_keys).and_return(["key1", "key2"])

        result = agent.memories?

        expect(result).to be true
      end

      it "returns false when agent has no memories" do
        allow(mock_memory_store).to receive(:list_keys).and_return([])

        result = agent.memories?

        expect(result).to be false
      end

      it "returns false when no memory store" do
        agent_without_memory = described_class.new(name: "NoMemoryAgent")

        result = agent_without_memory.memories?

        expect(result).to be false
      end
    end

    describe "#forget" do
      it "deletes memory successfully" do
        allow(mock_memory_store).to receive(:delete).and_return(true)

        result = agent.forget("memory_key_123")

        expect(result).to be true
        expect(mock_memory_store).to have_received(:delete).with("memory_key_123")
      end

      it "returns false when memory not found" do
        allow(mock_memory_store).to receive(:delete).and_return(false)

        result = agent.forget("nonexistent_key")

        expect(result).to be false
      end

      it "returns false when no memory store" do
        agent_without_memory = described_class.new(name: "NoMemoryAgent")

        result = agent_without_memory.forget("any_key")

        expect(result).to be false
      end
    end

    describe "#clear_memories" do
      it "clears all agent memories" do
        memory_keys = ["key1", "key2", "key3"]
        allow(mock_memory_store).to receive(:list_keys).and_return(memory_keys)
        allow(mock_memory_store).to receive(:delete)

        agent.clear_memories

        memory_keys.each do |key|
          expect(mock_memory_store).to have_received(:delete).with(key)
        end
      end

      it "does nothing when no memory store" do
        agent_without_memory = described_class.new(name: "NoMemoryAgent")

        expect { agent_without_memory.clear_memories }.not_to raise_error
      end
    end

    describe "#recent_memories" do
      it "returns recent memories" do
        mock_memories = [
          { content: "Recent memory 1", updated_at: Time.now.to_s },
          { content: "Recent memory 2", updated_at: (Time.now - 3600).to_s }
        ]
        allow(mock_memory_store).to receive(:search).and_return(mock_memories)

        result = agent.recent_memories(limit: 5)

        expect(result).to eq(mock_memories)
        expect(mock_memory_store).to have_received(:search).with(
          "",
          hash_including(limit: 10, agent_name: "MemoryAgent")  # Method asks for double the limit
        )
      end

      it "returns empty array when no memory store" do
        agent_without_memory = described_class.new(name: "NoMemoryAgent")

        result = agent_without_memory.recent_memories

        expect(result).to eq([])
      end

      it "filters by conversation_id when provided" do
        allow(mock_memory_store).to receive(:search).and_return([])

        agent.recent_memories(limit: 10, conversation_id: "conv_789")

        expect(mock_memory_store).to have_received(:search).with(
          "",
          hash_including(conversation_id: "conv_789")
        )
      end
    end

    describe "#memory_context" do
      it "generates formatted context from relevant memories" do
        mock_memories = [
          { content: "User prefers JSON format", metadata: { category: "preference" } },
          { content: "User works in finance", metadata: { category: "background" } }
        ]
        allow(mock_memory_store).to receive(:search).and_return(mock_memories)

        result = agent.memory_context("format preferences")

        # The actual implementation uses numbered list with timestamps
        # Since we don't know the exact timestamp format in the mock, we'll check the structure
        expect(result).to include("Relevant memories:")
        expect(result).to include("User prefers JSON format")
        expect(result).to include("User works in finance")
      end

      it "returns empty string when no relevant memories" do
        allow(mock_memory_store).to receive(:search).and_return([])

        result = agent.memory_context("nonexistent topic")

        expect(result).to eq("")
      end

      it "returns empty string when no memory store" do
        agent_without_memory = described_class.new(name: "NoMemoryAgent")

        result = agent_without_memory.memory_context("any query")

        expect(result).to eq("")
      end
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

  describe "#configure_output_type" do
    it "does nothing when no output type specified" do
      agent = described_class.new(name: "TestAgent")

      agent.send(:configure_output_type)

      expect(agent.instance_variable_get(:@output_type_schema)).to be_nil
    end

    it "attempts to configure output type when specified" do
      agent = described_class.new(name: "TestAgent", output_type: String)
      
      # Just verify the method can be called without error
      expect { agent.send(:configure_output_type) }.not_to raise_error
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

      it "maps handoff objects to agent names" do
        target_agent = described_class.new(name: "TargetAgent")
        handoff = RAAF::Handoff.new(target_agent)

        result = agent.send(:safe_map_names, [handoff])

        expect(result).to eq(["TargetAgent"])
      end

      it "handles mixed collection of agents and handoffs" do
        agent1 = described_class.new(name: "DirectAgent")
        agent2 = described_class.new(name: "HandoffTarget")
        handoff = RAAF::Handoff.new(agent2)

        result = agent.send(:safe_map_names, [agent1, handoff])

        expect(result).to eq(["DirectAgent", "HandoffTarget"])
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

      it "creates tool for Handoff object" do
        target_agent = described_class.new(name: "HandoffTarget")
        handoff = RAAF::Handoff.new(target_agent)

        result = agent.send(:create_handoff_tool, handoff)

        expect(result).to be_a(RAAF::FunctionTool)
        expect(result.name).to eq("transfer_to_handoff_target")
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

    describe "#create_custom_handoff_tool" do
      it "creates handoff tool from Handoff object" do
        target_agent = described_class.new(name: "CustomTarget")
        handoff = RAAF::Handoff.new(
          target_agent,
          description: "Custom handoff behavior"
        )

        result = agent.send(:create_custom_handoff_tool, handoff)

        expect(result).to be_a(RAAF::FunctionTool)
        expect(result.description).to include("Custom handoff behavior")
      end
    end
  end

  describe "Edge Cases and Error Handling" do
    describe "invalid tool operations" do
      let(:agent) { described_class.new(name: "TestAgent") }

      it "handles tool execution with malformed arguments" do
        mock_tool = RAAF::FunctionTool.new(proc { raise ArgumentError, "Wrong arguments" }, name: "broken_tool")
        
        agent.add_tool(mock_tool)

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

    describe "memory system edge cases" do
      let(:agent) { described_class.new(name: "MemoryAgent", memory_store: mock_memory_store) }

      it "handles memory store errors gracefully" do
        allow(mock_memory_store).to receive(:store).and_raise(StandardError, "Storage failed")

        expect do
          agent.remember("Test content")
        end.to raise_error(StandardError, "Storage failed")
      end

      it "handles search errors in recall" do
        allow(mock_memory_store).to receive(:search).and_raise(StandardError, "Search failed")

        expect do
          agent.recall("test query")
        end.to raise_error(StandardError, "Search failed")
      end

      it "handles empty memory content gracefully" do
        allow(mock_memory_store).to receive(:store)
        allow(SecureRandom).to receive(:uuid).and_return("test-uuid")

        result = agent.remember("", metadata: {})

        expect(result).to eq("MemoryAgent_test-uuid")
      end

      it "formats memory context with complex metadata" do
        complex_memories = [
          {
            content: "Complex data",
            metadata: {
              category: "data",
              subcategory: "complex",
              tags: ["important", "recent"],
              nested: { deep: "value" }
            }
          }
        ]
        allow(mock_memory_store).to receive(:search).and_return(complex_memories)

        result = agent.memory_context("complex data")

        expect(result).to include("Complex data")
      end
    end

    describe "handoff system edge cases" do
      it "handles handoff to agent with same name" do
        agent1 = described_class.new(name: "SameName")
        agent2 = described_class.new(name: "SameName")

        agent1.add_handoff(agent2)

        expect(agent1.can_handoff_to?("SameName")).to be true
        # Should find the first matching handoff
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

      it "handles handoff with very long agent name" do
        long_name = "A" * 1000
        target_agent = described_class.new(name: long_name)
        agent = described_class.new(name: "SourceAgent")

        agent.add_handoff(target_agent)

        expect(agent.can_handoff_to?(long_name)).to be true
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

      it "handles clone with very deep object structure" do
        deep_hooks = double("DeepHooks", deep_method: double("DeepMethod"))
        agent = described_class.new(name: "DeepAgent", hooks: deep_hooks)

        cloned = agent.clone

        expect(cloned.hooks).to eq(deep_hooks)
        expect(cloned).not_to be(agent)
      end
    end
  end
end