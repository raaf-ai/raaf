# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Agent do
  # Create shared agents for testing
  let(:test_agent) { described_class.new(name: "TestAgent") }
  let(:support_agent) { described_class.new(name: "SupportAgent", instructions: "Handle support requests") }
  let(:sales_agent) { described_class.new(name: "SalesAgent", instructions: "Handle sales inquiries") }

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
      existing_tool = RAAF::FunctionTool.new(proc { |value| value * 2 })
      other_agent = described_class.new(name: "OtherAgent")

      agent = described_class.new(
        name: "ConfiguredAgent",
        tools: [existing_tool],
        handoffs: [other_agent]
      )

      expect(agent.tools.size).to eq(2) # 1 provided tool + 1 auto-generated handoff tool
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
      expect(agent.tools.first).to be_a(RAAF::FunctionTool)
    end

    it "adds a method as a tool" do
      def test_method(value)
        value * 2
      end

      agent.add_tool(method(:test_method))

      expect(agent.tools.size).to eq(1)
      expect(agent.tools.first).to be_a(RAAF::FunctionTool)
    end

    it "adds a FunctionTool directly" do
      function_tool = RAAF::FunctionTool.new(proc { |value| value * 2 })
      agent.add_tool(function_tool)

      expect(agent.tools.size).to eq(1)
      expect(agent.tools.first).to eq(function_tool)
    end

    it "raises error for invalid tool" do
      expect { agent.add_tool("invalid") }.to raise_error(RAAF::ToolError)
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
      expect { agent.add_handoff("invalid") }.to raise_error(RAAF::HandoffError)
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

  # MOVED TO GUARDRAILS GEM
  # describe "#input_guardrails?" do
  #   let(:agent) { described_class.new(name: "TestAgent") }
  #
  #   it "returns false when no input guardrails are set" do
  #     expect(agent.input_guardrails?).to be false
  #   end
  #
  #   it "returns true when input guardrails are set" do
  #     agent.input_guardrails = [RAAF::Guardrails::InputGuardrail.new(proc { |_, _, _| true })]
  #     expect(agent.input_guardrails?).to be true
  #   end
  # end
  #
  # describe "#output_guardrails?" do
  #   let(:agent) { described_class.new(name: "TestAgent") }
  #
  #   it "returns false when no output guardrails are set" do
  #     expect(agent.output_guardrails?).to be false
  #   end
  #
  #   it "returns true when output guardrails are set" do
  #     agent.output_guardrails = [RAAF::Guardrails::OutputGuardrail.new(proc { |_, _, _| true })]
  #     expect(agent.output_guardrails?).to be true
  #   end
  # end

  describe "bang methods for mutation" do
    let(:agent) do
      agent = described_class.new(name: "TestAgent")
      agent.add_tool(proc { |_| })
      handoff_agent = described_class.new(name: "HandoffAgent")
      agent.add_handoff(handoff_agent)
      # MOVED TO GUARDRAILS GEM - these lines would set guardrails
      # agent.input_guardrails = [RAAF::Guardrails::InputGuardrail.new(proc { |_, _, _| true })]
      # agent.output_guardrails = [RAAF::Guardrails::OutputGuardrail.new(proc { |_, _, _| true })]
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

    # MOVED TO GUARDRAILS GEM
    # describe "#reset_input_guardrails!" do
    #   it "clears all input guardrails and returns self" do
    #     expect(agent.input_guardrails?).to be true
    #     result = agent.reset_input_guardrails!
    #     expect(agent.input_guardrails?).to be false
    #     expect(result).to eq(agent)
    #   end
    # end
    #
    # describe "#reset_output_guardrails!" do
    #   it "clears all output guardrails and returns self" do
    #     expect(agent.output_guardrails?).to be true
    #     result = agent.reset_output_guardrails!
    #     expect(agent.output_guardrails?).to be false
    #     expect(result).to eq(agent)
    #   end
    # end

    describe "#reset!" do
      it "clears everything and returns self" do
        expect(agent.tools?).to be true
        expect(agent.handoffs?).to be true
        # MOVED TO GUARDRAILS GEM - guardrails checks
        # expect(agent.input_guardrails?).to be true
        # expect(agent.output_guardrails?).to be true

        result = agent.reset!

        expect(agent.tools?).to be false
        expect(agent.handoffs?).to be false
        # MOVED TO GUARDRAILS GEM - guardrails checks
        # expect(agent.input_guardrails?).to be false
        # expect(agent.output_guardrails?).to be false
        expect(result).to eq(agent)
      end
    end
  end

  describe "dynamic method calls via method_missing" do
    let(:agent) { described_class.new(name: "TestAgent") }

    before do
      agent.add_tool(RAAF::FunctionTool.new(
                       proc { |value:| value * 2 },
                       name: "double",
                       description: "Doubles a number"
                     ))
      agent.add_tool(RAAF::FunctionTool.new(
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
      agent.add_tool(RAAF::FunctionTool.new(
                       proc { |value:| value * 2 },
                       name: "double",
                       description: "Doubles a number"
                     ))
      agent.add_tool(RAAF::FunctionTool.new(
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
      end.to raise_error(RAAF::ToolError, /Tool 'nonexistent' not found/)
    end

    it "propagates tool execution errors" do
      agent.add_tool(RAAF::FunctionTool.new(
                       proc { raise StandardError, "Tool failed" },
                       name: "failing_tool"
                     ))

      expect do
        agent.execute_tool("failing_tool")
      end.to raise_error(RAAF::ToolError, /Error executing tool 'failing_tool'/)
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
      tool = RAAF::FunctionTool.new(proc { |value| value }, name: "test_tool")
      other_agent = described_class.new(name: "OtherAgent")

      agent.add_tool(tool)
      agent.add_handoff(other_agent)

      hash = agent.to_h

      expect(hash[:tools].size).to eq(2) # 1 manual tool + 1 auto-generated handoff tool
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

    it "allows setting additional attributes" do
      agent.output_type = String
      agent.hooks = double("hooks")
      agent.prompt = "test prompt"
      agent.handoff_description = "Transfer to me for help"
      agent.response_format = { type: "json_object" }
      agent.tool_choice = "auto"
      agent.model_settings = { temperature: 0.7 }
      agent.context = { user_id: "123" }
      agent.on_handoff = proc { |data| data }

      expect(agent.output_type).to eq(String)
      expect(agent.hooks).not_to be_nil
      expect(agent.prompt).to eq("test prompt")
      expect(agent.handoff_description).to eq("Transfer to me for help")
      expect(agent.response_format).to eq({ type: "json_object" })
      expect(agent.tool_choice).to eq("auto")
      expect(agent.model_settings).not_to be_nil
      expect(agent.context).to eq({ user_id: "123" })
      expect(agent.on_handoff).to be_a(Proc)
    end
  end

  describe "advanced initialization" do
    it "supports Python SDK compatible parameters" do
      agent = described_class.new(
        name: "AdvancedAgent",
        instructions: "You are a specialized assistant",
        model: "gpt-4o",
        model_settings: { temperature: 0.7, max_tokens: 1000 },
        context: { user_id: "123", session_id: "abc" },
        reset_tool_choice: false,
        tool_use_behavior: :return_direct
      )

      expect(agent.name).to eq("AdvancedAgent")
      expect(agent.model).to eq("gpt-4o")
      expect(agent.model_settings).to be_a(RAAF::ModelSettings)
      expect(agent.context).to eq({ user_id: "123", session_id: "abc" })
      expect(agent.reset_tool_choice).to be false
      expect(agent.tool_use_behavior).to be_a(RAAF::ToolUseBehavior::Base)
    end

    it "supports output type configuration" do
      agent = described_class.new(
        name: "TypedAgent",
        output_type: String
      )

      expect(agent.output_type).to eq(String)
    end

    it "supports response format configuration" do
      agent = described_class.new(
        name: "FormattedAgent",
        response_format: { type: "json_object" }
      )

      expect(agent.response_format).to eq({ type: "json_object" })
    end

    it "supports tool choice configuration" do
      agent = described_class.new(
        name: "ToolChoiceAgent",
        tool_choice: "required"
      )

      expect(agent.tool_choice).to eq("required")
    end
  end

  describe "#clone" do
    let(:base_agent) do
      tool = RAAF::FunctionTool.new(proc { |x| x * 2 }, name: "double")
      agent = described_class.new(
        name: "BaseAgent",
        instructions: "Base instructions",
        model: "gpt-4",
        max_turns: 10,
        tools: [tool],
        handoffs: [support_agent]
      )
      agent.handoff_description = "Base handoff description"
      agent.response_format = { type: "json_object" }
      agent
    end

    it "creates a new agent with same configuration" do
      cloned = base_agent.clone

      expect(cloned).not_to be(base_agent)
      expect(cloned.name).to eq("BaseAgent")
      expect(cloned.instructions).to eq("Base instructions")
      expect(cloned.model).to eq("gpt-4")
      expect(cloned.max_turns).to eq(10)
      expect(cloned.handoff_description).to eq("Base handoff description")
      expect(cloned.response_format).to eq({ type: "json_object" })
    end

    it "allows overriding specific parameters" do
      cloned = base_agent.clone(
        name: "ClonedAgent",
        instructions: "Cloned instructions",
        model: "gpt-4o",
        max_turns: 20
      )

      expect(cloned.name).to eq("ClonedAgent")
      expect(cloned.instructions).to eq("Cloned instructions")
      expect(cloned.model).to eq("gpt-4o")
      expect(cloned.max_turns).to eq(20)
      # Original values preserved
      expect(cloned.handoff_description).to eq("Base handoff description")
    end

    it "duplicates collections to prevent mutation" do
      cloned = base_agent.clone

      # Tools are duplicated
      expect(cloned.tools).not_to be(base_agent.tools)
      # But non-handoff tools are preserved
      expect(cloned.tools.reject { |t| t.name.start_with?("transfer_to_") }.size).to eq(1)

      # Handoffs are duplicated
      expect(cloned.handoffs).not_to be(base_agent.handoffs)
      expect(cloned.handoffs.size).to eq(base_agent.handoffs.size)
    end

    it "filters out handoff tools to avoid duplication" do
      # Base agent has 1 manual tool + 1 auto-generated handoff tool
      expect(base_agent.tools.size).to eq(2)
      expect(base_agent.tools.any? { |t| t.name.start_with?("transfer_to_") }).to be true

      cloned = base_agent.clone

      # Cloned agent regenerates handoff tools
      expect(cloned.tools.size).to eq(2)
      expect(cloned.tools.any? { |t| t.name.start_with?("transfer_to_") }).to be true
    end
  end

  describe "#as_tool" do
    let(:specialist_agent) do
      described_class.new(
        name: "Specialist",
        instructions: "Expert in specific domain",
        handoff_description: "Consult for expert analysis"
      )
    end

    it "converts agent to a FunctionTool" do
      tool = specialist_agent.as_tool

      expect(tool).to be_a(RAAF::FunctionTool)
      expect(tool.name).to eq("specialist")
      # Uses handoff_description when available
      expect(tool.description).to eq("Consult for expert analysis")
    end

    it "uses custom tool name and description" do
      tool = specialist_agent.as_tool(
        tool_name: "consult_expert",
        tool_description: "Get expert opinion"
      )

      expect(tool.name).to eq("consult_expert")
      expect(tool.description).to eq("Get expert opinion")
    end

    it "uses handoff_description when available" do
      tool = specialist_agent.as_tool

      expect(tool.description).to eq("Consult for expert analysis")
    end

    it "includes proper parameters schema" do
      tool = specialist_agent.as_tool

      expect(tool.parameters).to include(
        type: "object",
        properties: {
          input_text: {
            type: "string",
            description: include("Input text to send to the Specialist agent")
          }
        },
        required: ["input_text"]
      )
    end

    it "supports custom output extractor via parameter" do
      custom_extractor = proc { |result| "Custom: #{result}" }
      tool = specialist_agent.as_tool(custom_output_extractor: custom_extractor)

      expect(tool).to be_a(RAAF::FunctionTool)
    end

    it "supports custom output extractor via block" do
      tool = specialist_agent.as_tool do |result|
        "Block: #{result}"
      end

      expect(tool).to be_a(RAAF::FunctionTool)
    end
  end

  describe "#validate_output" do
    context "without output_type configured" do
      it "returns output unchanged" do
        agent = described_class.new(name: "Agent")

        expect(agent.validate_output("test")).to eq("test")
        expect(agent.validate_output({ key: "value" })).to eq({ key: "value" })
      end
    end

    context "with output_type configured" do
      it "validates string output type" do
        agent = described_class.new(name: "Agent", output_type: String)

        expect(agent.validate_output("valid string")).to eq("valid string")
      end

      it "validates and parses JSON when output type expects object" do
        agent = described_class.new(name: "Agent", output_type: Hash)
        json_string = '{"key": "value"}'

        # For non-plain-text types, it should parse and validate JSON
        expect { agent.validate_output(json_string) }.not_to raise_error
      end
    end
  end

  describe "#enabled_tools" do
    let(:agent) { described_class.new(name: "Agent") }
    let(:tool1) { RAAF::FunctionTool.new(proc { "tool1" }, name: "tool1") }
    let(:tool2) { RAAF::FunctionTool.new(proc { "tool2" }, name: "tool2") }

    before do
      agent.add_tool(tool1)
      agent.add_tool(tool2)
    end

    it "returns all tools when no context provided" do
      expect(agent.enabled_tools).to eq([tool1, tool2])
    end

    it "delegates to FunctionTool.enabled_tools with context" do
      context = double("context")
      expect(RAAF::FunctionTool).to receive(:enabled_tools).with([tool1, tool2], context)

      agent.enabled_tools(context)
    end
  end

  describe "#all_tools" do
    let(:agent) { described_class.new(name: "Agent") }

    it "returns empty array when no tools" do
      expect(agent.all_tools).to eq([])
    end

    it "returns all tools regardless of enabled state" do
      tool = RAAF::FunctionTool.new(proc { "tool" }, name: "tool")
      agent.add_tool(tool)

      expect(agent.all_tools).to eq([tool])
    end
  end

  describe "#tool_exists?" do
    let(:agent) { described_class.new(name: "Agent") }

    before do
      agent.add_tool(RAAF::FunctionTool.new(proc { "test" }, name: "test_tool"))
    end

    it "returns true for existing tool by string name" do
      expect(agent.tool_exists?("test_tool")).to be true
    end

    it "returns true for existing tool by symbol name" do
      expect(agent.tool_exists?(:test_tool)).to be true
    end

    it "returns false for non-existent tool" do
      expect(agent.tool_exists?("unknown_tool")).to be false
    end

    it "handles hosted tools with type field" do
      agent.instance_variable_set(:@tools, agent.tools + [{ type: "web_search" }])

      expect(agent.tool_exists?("web_search")).to be true
      expect(agent.tool_exists?(:web_search)).to be true
    end
  end

  describe "#get_input_schema" do
    it "returns basic schema without handoff description" do
      agent = described_class.new(name: "TestAgent")
      schema = agent.get_input_schema

      expect(schema).to eq({
                             type: "object",
                             properties: {
                               input: {
                                 type: "string",
                                 description: "Input text to send to the TestAgent agent"
                               }
                             },
                             required: ["input"],
                             additionalProperties: false
                           })
    end

    it "includes handoff description in schema" do
      agent = described_class.new(
        name: "ExpertAgent",
        handoff_description: "Specializes in complex analysis"
      )
      schema = agent.get_input_schema

      expect(schema[:properties][:input][:description]).to include("Specializes in complex analysis")
    end
  end

  describe "handoff tool generation" do
    it "automatically generates handoff tools for agents in constructor" do
      agent = described_class.new(
        name: "MainAgent",
        handoffs: [support_agent, sales_agent]
      )

      # Should have 2 auto-generated handoff tools
      expect(agent.tools.size).to eq(2)
      expect(agent.tools.all? { |t| t.name.start_with?("transfer_to_") }).to be true
      expect(agent.tools.map(&:name)).to contain_exactly(
        "transfer_to_support_agent",
        "transfer_to_sales_agent"
      )
    end

    it "generates handoff tool when adding handoff dynamically" do
      agent = described_class.new(name: "MainAgent")
      expect(agent.tools.size).to eq(0)

      agent.add_handoff(support_agent)

      expect(agent.tools.size).to eq(1)
      expect(agent.tools.first.name).to eq("transfer_to_support_agent")
    end

    it "handoff tool returns proper handoff data structure" do
      agent = described_class.new(name: "MainAgent")
      agent.add_handoff(support_agent)

      handoff_tool = agent.tools.first
      result = handoff_tool.call(input: "Help needed")

      expect(result).to be_a(Hash)
      expect(result[:__raaf_handoff__]).to be true
      expect(result[:target_agent]).to eq(support_agent)
      expect(result[:handoff_data]).to eq({ input: "Help needed" })
      expect(result[:handoff_reason]).to eq("Handoff requested")
    end

    it "supports handoff objects with custom configuration" do
      handoff = RAAF::Handoff.new(
        support_agent,
        tool_name_override: "escalate_to_support",
        tool_description_override: "Escalate complex issues to support"
      )

      agent = described_class.new(name: "MainAgent")
      agent.add_handoff(handoff)

      handoff_tool = agent.tools.first
      expect(handoff_tool.name).to eq("escalate_to_support")
      expect(handoff_tool.description).to eq("Escalate complex issues to support")
    end
  end

  describe "memory management" do
    let(:memory_store) { double("memory_store") }
    let(:agent) do
      described_class.new(
        name: "MemoryAgent",
        memory_store: memory_store
      )
    end

    describe "#remember" do
      it "stores content in memory with metadata" do
        expect(SecureRandom).to receive(:uuid).and_return("test-uuid")
        expect(memory_store).to receive(:store).with(
          "MemoryAgent_test-uuid",
          hash_including(
            content: "Important fact",
            agent_name: "MemoryAgent",
            metadata: hash_including(
              agent_name: "MemoryAgent",
              created_by: "RAAF::Agent#remember",
              type: "fact"
            )
          )
        )

        key = agent.remember("Important fact", metadata: { type: "fact" })
        expect(key).to eq("MemoryAgent_test-uuid")
      end

      it "includes conversation_id when provided" do
        expect(SecureRandom).to receive(:uuid).and_return("test-uuid")
        expect(memory_store).to receive(:store).with(
          anything,
          hash_including(conversation_id: "conv-123")
        )

        agent.remember("Test", conversation_id: "conv-123")
      end

      it "raises error when memory store not configured" do
        agent_no_memory = described_class.new(name: "NoMemory")

        expect do
          agent_no_memory.remember("Test")
        end.to raise_error(RAAF::AgentError, /Memory store not configured/)
      end
    end

    describe "#recall" do
      it "searches memory store with query and filters" do
        expect(memory_store).to receive(:search).with(
          "programming",
          hash_including(
            limit: 5,
            agent_name: "MemoryAgent",
            conversation_id: "conv-123",
            tags: %w[ruby code]
          )
        ).and_return([])

        result = agent.recall(
          "programming",
          limit: 5,
          conversation_id: "conv-123",
          tags: %w[ruby code]
        )

        expect(result).to eq([])
      end

      it "returns empty array when no memory store" do
        agent_no_memory = described_class.new(name: "NoMemory")

        expect(agent_no_memory.recall("test")).to eq([])
      end
    end

    describe "#memory_count" do
      it "returns count of memories for agent" do
        expect(memory_store).to receive(:list_keys).with(agent_name: "MemoryAgent").and_return(%w[key1 key2 key3])

        expect(agent.memory_count).to eq(3)
      end

      it "returns 0 when no memory store" do
        agent_no_memory = described_class.new(name: "NoMemory")

        expect(agent_no_memory.memory_count).to eq(0)
      end
    end

    describe "#memories?" do
      it "returns true when agent has memories" do
        allow(memory_store).to receive(:list_keys).and_return(["key1"])

        expect(agent.memories?).to be true
      end

      it "returns false when agent has no memories" do
        allow(memory_store).to receive(:list_keys).and_return([])

        expect(agent.memories?).to be false
      end
    end

    describe "#forget" do
      it "deletes specific memory" do
        expect(memory_store).to receive(:delete).with("memory-key-123").and_return(true)

        expect(agent.forget("memory-key-123")).to be true
      end

      it "returns false when no memory store" do
        agent_no_memory = described_class.new(name: "NoMemory")

        expect(agent_no_memory.forget("key")).to be false
      end
    end

    describe "#clear_memories" do
      it "deletes all memories for agent" do
        expect(memory_store).to receive(:list_keys).with(agent_name: "MemoryAgent").and_return(%w[key1 key2])
        expect(memory_store).to receive(:delete).with("key1")
        expect(memory_store).to receive(:delete).with("key2")

        agent.clear_memories
      end
    end

    describe "#recent_memories" do
      it "returns recent memories sorted by updated_at" do
        memories = [
          { content: "Old", updated_at: "2024-01-01T10:00:00Z" },
          { content: "New", updated_at: "2024-01-02T10:00:00Z" },
          { content: "Middle", updated_at: "2024-01-01T15:00:00Z" }
        ]

        expect(memory_store).to receive(:search).with(
          "",
          { limit: 4, agent_name: "MemoryAgent", conversation_id: nil }
        ).and_return(memories)

        result = agent.recent_memories(limit: 2)

        expect(result.map { |m| m[:content] }).to eq(%w[New Middle])
      end

      it "filters by conversation_id when provided" do
        expect(memory_store).to receive(:search).with(
          "",
          hash_including(conversation_id: "conv-123")
        ).and_return([])

        agent.recent_memories(conversation_id: "conv-123")
      end
    end

    describe "#memory_context" do
      it "formats memories as context string" do
        memories = [
          { content: "User prefers Python", updated_at: "2024-01-01T10:00:00Z" },
          { content: "User works on web apps", updated_at: "2024-01-01T11:00:00Z" }
        ]

        allow(memory_store).to receive(:search).and_return(memories)

        context = agent.memory_context("preferences", limit: 2)

        expect(context).to include("Relevant memories:")
        expect(context).to include("1. User prefers Python")
        expect(context).to include("2. User works on web apps")
      end

      it "returns empty string when no memories found" do
        allow(memory_store).to receive(:search).and_return([])

        expect(agent.memory_context("test")).to eq("")
      end
    end
  end

  describe "tool use behavior" do
    it "supports symbol configuration" do
      agent = described_class.new(
        name: "Agent",
        tool_use_behavior: :run_llm_again
      )

      expect(agent.tool_use_behavior).to be_a(RAAF::ToolUseBehavior::Base)
    end

    it "supports string configuration" do
      agent = described_class.new(
        name: "Agent",
        tool_use_behavior: "return_direct"
      )

      expect(agent.tool_use_behavior).to be_a(RAAF::ToolUseBehavior::Base)
    end

    it "defaults to run_llm_again behavior" do
      agent = described_class.new(name: "Agent")

      expect(agent.tool_use_behavior).to be_a(RAAF::ToolUseBehavior::Base)
    end

    it "supports reset_tool_choice configuration" do
      agent_reset = described_class.new(name: "Agent1", reset_tool_choice: true)
      agent_no_reset = described_class.new(name: "Agent2", reset_tool_choice: false)

      expect(agent_reset.reset_tool_choice).to be true
      expect(agent_no_reset.reset_tool_choice).to be false
    end

    it "defaults reset_tool_choice to true" do
      agent = described_class.new(name: "Agent")

      expect(agent.reset_tool_choice).to be true
    end
  end

  describe "guardrails" do
    let(:agent) { described_class.new(name: "Agent") }

    describe "#add_input_guardrail" do
      it "adds guardrail to collection" do
        guardrail = double("input_guardrail")
        agent.add_input_guardrail(guardrail)

        expect(agent.input_guardrails).to include(guardrail)
      end
    end

    describe "#add_output_guardrail" do
      it "adds guardrail to collection" do
        guardrail = double("output_guardrail")
        agent.add_output_guardrail(guardrail)

        expect(agent.output_guardrails).to include(guardrail)
      end
    end
  end

  describe "#hooks?" do
    it "returns false when no hooks configured" do
      agent = described_class.new(name: "Agent")
      expect(agent.hooks?).to be false
    end

    it "returns true when hooks configured" do
      agent = described_class.new(name: "Agent", hooks: double("hooks"))
      expect(agent.hooks?).to be true
    end
  end

  describe "error handling" do
    let(:agent) { described_class.new(name: "Agent") }

    it "provides helpful error for invalid tool in execute_tool" do
      expect do
        agent.execute_tool("non_existent")
      end.to raise_error(RAAF::ToolError, /Tool 'non_existent' not found/)
    end

    it "wraps tool execution errors" do
      failing_tool = RAAF::FunctionTool.new(
        proc { raise "Internal error" },
        name: "failing"
      )
      agent.add_tool(failing_tool)

      expect do
        agent.execute_tool("failing")
      end.to raise_error(RAAF::ToolError, /Tool execution failed:.*Internal error/)
    end
  end

  # Edge cases and boundary conditions
  describe "boundary conditions" do
    context "agent name limits" do
      it "handles extremely long agent names" do
        long_name = "Agent#{"X" * 1000}"
        agent = described_class.new(name: long_name, instructions: "Test agent")

        expect(agent.name).to eq(long_name)
        expect(agent.name.length).to eq(1005)
      end

      it "handles empty agent names" do
        agent = described_class.new(name: "", instructions: "Test agent")
        expect(agent.name).to eq("")
      end

      it "handles agent names with special characters" do
        special_names = [
          "Agent-With-Dashes",
          "Agent_With_Underscores",
          "Agent With Spaces",
          "Agent\tWith\tTabs",
          "Agent\nWith\nNewlines",
          "Agent🚀With🎭Emojis",
          "Agent<>With<>Brackets",
          "Agent\"With\"Quotes",
          "Agent'With'Apostrophes"
        ]

        special_names.each do |name|
          agent = described_class.new(name: name, instructions: "Test")
          expect(agent.name).to eq(name)
        end
      end
    end

    context "instructions boundary conditions" do
      it "handles extremely long instructions" do
        long_instructions = "You are a helpful assistant. " * 10_000
        agent = described_class.new(name: "TestAgent", instructions: long_instructions)

        expect(agent.instructions.length).to be > 250_000
        expect(agent.instructions).to eq(long_instructions)
      end

      it "handles nil instructions" do
        agent = described_class.new(name: "TestAgent", instructions: nil)
        expect(agent.instructions).to be_nil
      end

      it "handles empty string instructions" do
        agent = described_class.new(name: "TestAgent", instructions: "")
        expect(agent.instructions).to eq("")
      end

      it "handles instructions with Unicode and special encoding" do
        unicode_instructions = "You are 🤖 an AI assistant. Помогайте пользователям. 你是一个助手。 العربية"
        agent = described_class.new(name: "UnicodeAgent", instructions: unicode_instructions)

        expect(agent.instructions).to eq(unicode_instructions)
        expect(agent.instructions.encoding).to eq(Encoding::UTF_8)
      end
    end

    context "max_turns boundary conditions" do
      it "handles zero max_turns" do
        agent = described_class.new(name: "ZeroTurns", max_turns: 0)
        expect(agent.max_turns).to eq(0)
      end

      it "handles negative max_turns" do
        agent = described_class.new(name: "NegativeTurns", max_turns: -1)
        expect(agent.max_turns).to eq(-1)
      end

      it "handles extremely large max_turns" do
        large_turns = (2**31) - 1 # Max 32-bit integer
        agent = described_class.new(name: "LargeTurns", max_turns: large_turns)
        expect(agent.max_turns).to eq(large_turns)
      end
    end
  end

  # Regression cases - previously reported bugs
  describe "regression cases" do
    context "agent initialization issues" do
      it "allows agent creation with duplicate tool names (documented behavior)" do
        agent = described_class.new(name: "DuplicateToolAgent")

        # Add tool with same name twice
        tool1 = RAAF::FunctionTool.new(proc { "first" }, name: "duplicate_tool")
        tool2 = RAAF::FunctionTool.new(proc { "second" }, name: "duplicate_tool")

        agent.add_tool(tool1)
        agent.add_tool(tool2)

        # Currently allows duplicate tool names - this documents the behavior
        # In the future, we might want to prevent duplicates or warn about them
        tool_names = agent.tools.map(&:name)
        expect(tool_names).to include("duplicate_tool")
        expect(tool_names.count("duplicate_tool")).to eq(2) # Both tools are added
      end

      it "handles agent creation with nil model parameter" do
        # This was causing issues in early versions
        agent = described_class.new(name: "NilModelAgent", model: nil)

        expect(agent.model).to eq("gpt-4") # Agent defaults to gpt-4 when nil is passed
      end

      it "prevents memory leak in agent tool storage" do
        agent = described_class.new(name: "MemoryLeakAgent")

        # Add and remove many tools
        1000.times do |i|
          tool = RAAF::FunctionTool.new(
            proc { "temp tool #{i}" },
            name: "temp_tool_#{i}"
          )
          agent.add_tool(tool)
        end

        # Force garbage collection
        GC.start
        initial_objects = ObjectSpace.count_objects[:TOTAL]

        # Remove all tools by creating new agent
        agent = described_class.new(name: "CleanAgent")

        # Force garbage collection again
        GC.start
        final_objects = ObjectSpace.count_objects[:TOTAL]

        # Should not have significantly more objects (allowing some variation)
        expect(final_objects - initial_objects).to be < 100
      end
    end
  end
end
