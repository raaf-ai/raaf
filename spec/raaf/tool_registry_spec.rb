# frozen_string_literal: true

require "spec_helper"
require "raaf/tool_registry"

RSpec.describe RAAF::ToolRegistry do
  before(:each) do
    described_class.clear!
  end

  after(:each) do
    described_class.clear!
  end

  describe ".register" do
    let(:tool_class) { double("ToolClass") }

    it "registers a tool with a name" do
      described_class.register("my_tool", tool_class)
      expect(described_class.get("my_tool")).to eq(tool_class)
    end

    it "converts string names to symbols" do
      described_class.register("string_tool", tool_class)
      expect(described_class.get(:string_tool)).to eq(tool_class)
    end

    it "allows re-registration (override)" do
      original_class = double("OriginalTool")
      new_class = double("NewTool")
      
      described_class.register("tool", original_class)
      described_class.register("tool", new_class)
      
      expect(described_class.get("tool")).to eq(new_class)
    end

    it "logs registration in debug mode" do
      expect(described_class).to receive(:log_debug_tools).with(
        "Registering tool", 
        hash_including(name: "debug_tool")
      )
      described_class.register("debug_tool", tool_class)
    end
  end

  describe ".get" do
    let(:tool_class) { double("ToolClass") }

    before do
      described_class.register("existing_tool", tool_class)
    end

    it "retrieves registered tool by symbol" do
      expect(described_class.get(:existing_tool)).to eq(tool_class)
    end

    it "retrieves registered tool by string" do
      expect(described_class.get("existing_tool")).to eq(tool_class)
    end

    it "returns nil for unregistered tool" do
      expect(described_class.get("non_existent")).to be_nil
    end
  end

  describe ".lookup" do
    before do
      stub_const("Ai::Tools::CustomSearchTool", Class.new)
      stub_const("RAAF::Tools::WebSearchTool", Class.new)
      stub_const("DirectReferenceTool", Class.new)
    end

    context "with direct class reference" do
      it "returns the class directly" do
        expect(described_class.lookup(DirectReferenceTool)).to eq(DirectReferenceTool)
      end
    end

    context "with registered name" do
      before do
        described_class.register("registered_tool", DirectReferenceTool)
      end

      it "finds registered tool by symbol" do
        expect(described_class.lookup(:registered_tool)).to eq(DirectReferenceTool)
      end
    end

    context "with auto-discovery" do
      it "finds user-defined tools first" do
        result = described_class.lookup(:custom_search)
        expect(result).to eq(Ai::Tools::CustomSearchTool)
      end

      it "finds RAAF tools when no user tool exists" do
        result = described_class.lookup(:web_search)
        expect(result).to eq(RAAF::Tools::WebSearchTool)
      end

      it "converts symbol to class name format" do
        result = described_class.lookup(:custom_search)
        expect(result).to eq(Ai::Tools::CustomSearchTool)
      end
    end

    context "when tool not found" do
      it "returns nil" do
        expect(described_class.lookup(:non_existent_tool)).to be_nil
      end
    end
  end

  describe ".resolve" do
    before do
      stub_const("Ai::Tools::UserTool", Class.new)
      stub_const("RAAF::Tools::DefaultTool", Class.new)
      described_class.register("registry_tool", Class.new)
    end

    it "resolves class references" do
      expect(described_class.resolve(Ai::Tools::UserTool)).to eq(Ai::Tools::UserTool)
    end

    it "resolves registered names" do
      expect(described_class.resolve(:registry_tool)).not_to be_nil
    end

    it "resolves with auto-discovery" do
      expect(described_class.resolve(:user_tool)).to eq(Ai::Tools::UserTool)
    end

    it "prioritizes user namespace over RAAF" do
      stub_const("Ai::Tools::DefaultTool", Class.new)
      expect(described_class.resolve(:default_tool)).to eq(Ai::Tools::DefaultTool)
    end
  end

  describe ".safe_lookup" do
    before do
      stub_const("Ai::Tools::CustomSearchTool", Class.new)
      stub_const("RAAF::Tools::WebSearchTool", Class.new)
      stub_const("DirectReferenceTool", Class.new)
    end

    context "when ToolRegistry is fully loaded" do
      it "resolves class references directly" do
        expect(described_class.safe_lookup(DirectReferenceTool)).to eq(DirectReferenceTool)
      end

      it "resolves registered tools" do
        described_class.register("test_tool", DirectReferenceTool)
        expect(described_class.safe_lookup(:test_tool)).to eq(DirectReferenceTool)
      end

      it "resolves with auto-discovery" do
        expect(described_class.safe_lookup(:custom_search)).to eq(Ai::Tools::CustomSearchTool)
        expect(described_class.safe_lookup(:web_search)).to eq(RAAF::Tools::WebSearchTool)
      end

      it "returns nil for unregistered tools" do
        expect(described_class.safe_lookup(:non_existent_tool)).to be_nil
      end

      it "behaves identically to lookup in normal conditions" do
        expect(described_class.safe_lookup(:custom_search)).to eq(described_class.lookup(:custom_search))
      end
    end

    context "when ToolRegistry is not fully loaded" do
      it "returns nil on ToolRegistry NameError instead of raising" do
        allow(described_class).to receive(:lookup).and_raise(
          NameError.new("uninitialized constant RAAF::ToolRegistry")
        )
        expect(described_class.safe_lookup(:some_tool)).to be_nil
      end

      it "returns nil on NameError for uninitialized constant" do
        allow(described_class).to receive(:lookup).and_raise(
          NameError.new("uninitialized constant in tool resolution")
        )
        expect(described_class.safe_lookup(:some_tool)).to be_nil
      end

      it "re-raises NameErrors not related to ToolRegistry" do
        allow(described_class).to receive(:lookup).and_raise(
          NameError.new("undefined local variable foo")
        )
        expect { described_class.safe_lookup(:some_tool) }.to raise_error(
          NameError, /undefined local variable/
        )
      end

      it "re-raises other exceptions" do
        allow(described_class).to receive(:lookup).and_raise(
          StandardError.new("some other error")
        )
        expect { described_class.safe_lookup(:some_tool) }.to raise_error(StandardError)
      end
    end
  end

  describe ".list" do
    before do
      described_class.register("tool_a", double("ToolA"))
      described_class.register("tool_b", double("ToolB"))
      described_class.register("tool_c", double("ToolC"))
    end

    it "returns all registered tool names" do
      expect(described_class.list).to contain_exactly(:tool_a, :tool_b, :tool_c)
    end

    it "returns empty array when no tools registered" do
      described_class.clear!
      expect(described_class.list).to eq([])
    end
  end

  describe ".clear!" do
    before do
      described_class.register("tool", double("Tool"))
    end

    it "removes all registered tools" do
      expect(described_class.list).not_to be_empty
      described_class.clear!
      expect(described_class.list).to be_empty
    end

    it "allows re-registration after clearing" do
      described_class.clear!
      new_tool = double("NewTool")
      described_class.register("tool", new_tool)
      expect(described_class.get("tool")).to eq(new_tool)
    end
  end

  describe ".registered?" do
    before do
      described_class.register("existing", double("Tool"))
    end

    it "returns true for registered tools" do
      expect(described_class.registered?("existing")).to be true
      expect(described_class.registered?(:existing)).to be true
    end

    it "returns false for unregistered tools" do
      expect(described_class.registered?("non_existent")).to be false
    end
  end

  describe "thread safety" do
    it "handles concurrent registration" do
      tools = 10.times.map { |i| ["tool_#{i}", double("Tool#{i}")] }
      
      threads = tools.map do |name, klass|
        Thread.new { described_class.register(name, klass) }
      end
      
      threads.each(&:join)
      
      tools.each do |name, klass|
        expect(described_class.get(name)).to eq(klass)
      end
    end

    it "handles concurrent reads" do
      described_class.register("shared_tool", double("SharedTool"))
      
      results = []
      threads = 10.times.map do
        Thread.new { results << described_class.get("shared_tool") }
      end
      
      threads.each(&:join)
      
      expect(results.uniq.size).to eq(1)
      expect(results.first).not_to be_nil
    end
  end

  describe "namespace configuration" do
    it "searches configured namespaces in order" do
      # Default behavior - Ai::Tools takes precedence
      stub_const("Ai::Tools::PriorityTool", Class.new)
      stub_const("RAAF::Tools::PriorityTool", Class.new)
      
      result = described_class.lookup(:priority_tool)
      expect(result).to eq(Ai::Tools::PriorityTool)
    end

    it "falls back to next namespace if not found" do
      stub_const("RAAF::Tools::OnlyRaafTool", Class.new)
      
      result = described_class.lookup(:only_raaf_tool)
      expect(result).to eq(RAAF::Tools::OnlyRaafTool)
    end
  end
end