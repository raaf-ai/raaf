# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Rails Integration", :with_rails do
  # Mock tool classes for testing Rails eager loading scenarios
  before do
    # Clear registry before each test
    RAAF::ToolRegistry.clear! if defined?(RAAF::ToolRegistry)
  end

  after do
    # Clean up any constants we created
    %w[CustomSearchTool WebAnalyzerTool DataProcessorTool].each do |const_name|
      %w[Ai::Tools RAAF::Tools].each do |namespace|
        full_name = "#{namespace}::#{const_name}"
        next unless Object.const_defined?(full_name)
        Object.send(:remove_const, full_name.split("::").last) if Object.const_defined?(full_name)
      end
    end
  end

  describe "Rails eager loading scenarios" do
    it "resolves tools correctly when classes load in arbitrary order" do
      # Simulate Rails eager loading by defining agent before tool class exists
      agent_class = Class.new(RAAF::DSL::Agent) do
        agent_name "EagerLoadingAgent"
        model "gpt-4o"

        # Use tool before it's defined (simulates Rails eager loading)
        tool :custom_search
      end

      # Define tool class after agent (simulates eager loading order)
      custom_tool_class = Class.new do
        def call(query:)
          { results: ["result for #{query}"] }
        end
      end

      # Register the tool after agent class is defined
      stub_const("Ai::Tools::CustomSearchTool", custom_tool_class)

      # Agent should resolve tool successfully during initialization
      expect { agent_class.new }.not_to raise_error

      # Verify tool is properly configured
      agent = agent_class.new
      tools_config = agent.class._tools_config
      expect(tools_config).not_to be_empty
      expect(tools_config.first[:name]).to eq(:custom_search)
    end

    it "handles multi-agent tool sharing in Rails environment" do
      # Define a shared tool
      shared_tool = Class.new do
        def call(data:)
          { processed: data.upcase }
        end
      end
      stub_const("Ai::Tools::SharedProcessorTool", shared_tool)

      # Define multiple agents using the same tool
      agent1_class = Class.new(RAAF::DSL::Agent) do
        agent_name "Agent1"
        model "gpt-4o"
        tool :shared_processor
      end

      agent2_class = Class.new(RAAF::DSL::Agent) do
        agent_name "Agent2"
        model "gpt-4o"
        tool :shared_processor
      end

      agent3_class = Class.new(RAAF::DSL::Agent) do
        agent_name "Agent3"
        model "gpt-4o"
        tool :shared_processor
      end

      # All agents should successfully initialize and share the tool
      agent1 = agent1_class.new
      agent2 = agent2_class.new
      agent3 = agent3_class.new

      # Verify all agents have access to the shared tool
      [agent1, agent2, agent3].each do |agent|
        tools_config = agent.class._tools_config
        expect(tools_config.first[:tool_class]).to eq(shared_tool)
      end
    end

    it "works with Rails autoloading and constant reloading" do
      # Simulate Rails constant unloading/reloading
      tool_v1 = Class.new do
        def call
          { version: 1 }
        end
      end

      stub_const("Ai::Tools::ReloadableToolTool", tool_v1)

      # Define agent using the tool
      agent_class = Class.new(RAAF::DSL::Agent) do
        agent_name "ReloadableAgent"
        model "gpt-4o"
        tool :reloadable_tool
      end

      # Initialize first agent
      agent1 = agent_class.new
      expect(agent1.class._tools_config.first[:tool_class]).to eq(tool_v1)

      # Simulate Rails constant reloading
      Object.send(:remove_const, "Ai") if defined?(Ai)

      # Redefine with new version
      tool_v2 = Class.new do
        def call
          { version: 2 }
        end
      end

      module Ai
        module Tools
        end
      end

      stub_const("Ai::Tools::ReloadableToolTool", tool_v2)

      # New agent instance should get the updated tool
      agent_class2 = Class.new(RAAF::DSL::Agent) do
        agent_name "ReloadableAgent2"
        model "gpt-4o"
        tool :reloadable_tool
      end

      agent2 = agent_class2.new
      expect(agent2.class._tools_config.first[:tool_class]).to eq(tool_v2)
    end

    it "handles production-like loading conditions with many tools" do
      # Simulate production environment with many tools loading
      tools_to_load = 20
      tool_classes = {}

      # Define many tools in different namespaces
      tools_to_load.times do |i|
        # Alternate between namespaces
        namespace = i.even? ? "Ai::Tools" : "RAAF::Tools"

        tool_class = Class.new do
          define_method :call do |**args|
            { tool_id: i, namespace: namespace, args: args }
          end
        end

        const_name = "ProductionTool#{i}Tool"
        full_name = "#{namespace}::#{const_name}"

        # Ensure namespace exists
        namespace.split("::").inject(Object) do |mod, name|
          mod.const_defined?(name) ? mod.const_get(name) : mod.const_set(name, Module.new)
        end

        stub_const(full_name, tool_class)
        tool_classes["production_tool#{i}".to_sym] = tool_class
      end

      # Define agent using multiple tools
      agent_class = Class.new(RAAF::DSL::Agent) do
        agent_name "ProductionAgent"
        model "gpt-4o"

        # Register all tools
        20.times do |i|
          tool "production_tool#{i}".to_sym
        end
      end

      # Measure initialization time
      start_time = Time.now
      agent = agent_class.new
      init_time = (Time.now - start_time) * 1000 # Convert to milliseconds

      # Verify all tools are registered
      expect(agent.class._tools_config.length).to eq(tools_to_load)

      # Check performance requirement (< 5ms per spec)
      expect(init_time).to be < 5.0
    end

    it "provides clear errors when tools cannot be resolved in Rails" do
      # Define agent with non-existent tool
      agent_class = Class.new(RAAF::DSL::Agent) do
        agent_name "FailingAgent"
        model "gpt-4o"
        tool :nonexistent_tool
      end

      # Should raise a clear error
      expect { agent_class.new }.to raise_error(RAAF::DSL::ToolResolutionError) do |error|
        expect(error.message).to include("nonexistent_tool")
        expect(error.message).to include("Could not find tool")
        expect(error.searched_namespaces).to include("Ai::Tools", "RAAF::Tools")
        expect(error.suggestions).not_to be_empty
      end
    end

    it "handles circular dependencies gracefully" do
      # Create tools with potential circular reference issues
      tool_a = Class.new do
        def call
          { name: "tool_a" }
        end
      end

      tool_b = Class.new do
        def call
          { name: "tool_b" }
        end
      end

      stub_const("Ai::Tools::CircularATool", tool_a)
      stub_const("Ai::Tools::CircularBTool", tool_b)

      # Agent A uses tool B
      agent_a_class = Class.new(RAAF::DSL::Agent) do
        agent_name "CircularAgentA"
        model "gpt-4o"
        tool :circular_b
      end

      # Agent B uses tool A
      agent_b_class = Class.new(RAAF::DSL::Agent) do
        agent_name "CircularAgentB"
        model "gpt-4o"
        tool :circular_a
      end

      # Both should initialize without issues
      expect { agent_a_class.new }.not_to raise_error
      expect { agent_b_class.new }.not_to raise_error
    end

    it "works with Rails zeitwerk autoloader patterns" do
      # Simulate Zeitwerk's constant loading behavior

      # First, define the tool in a namespace that Rails would autoload
      zeitwerk_tool = Class.new do
        def call(input:)
          { zeitwerk_processed: input }
        end
      end

      # Zeitwerk would load this as app/ai/tools/zeitwerk_compatible_tool.rb
      stub_const("Ai::Tools::ZeitwerkCompatibleTool", zeitwerk_tool)

      # Agent defined in app/ai/agents/example_agent.rb
      agent_class = Class.new(RAAF::DSL::Agent) do
        agent_name "ZeitwerkExampleAgent"
        model "gpt-4o"

        # Zeitwerk-style tool reference
        tool :zeitwerk_compatible
      end

      # Should work seamlessly
      agent = agent_class.new
      expect(agent.class._tools_config.first[:tool_class]).to eq(zeitwerk_tool)
    end

    it "handles tool resolution with mocked registry" do
      # Create a mock registry for testing
      mock_tool = Class.new do
        def call
          { mocked: true }
        end
      end

      # Mock the registry lookup
      allow(RAAF::ToolRegistry).to receive(:resolve).with(:mocked_tool).and_return(mock_tool)

      # Define agent using mocked tool
      agent_class = Class.new(RAAF::DSL::Agent) do
        agent_name "MockedAgent"
        model "gpt-4o"
        tool :mocked_tool
      end

      # Should use the mocked tool
      agent = agent_class.new
      expect(agent.class._tools_config.first[:tool_class]).to eq(mock_tool)
    end

    it "maintains thread safety during concurrent Rails requests" do
      # Simulate concurrent Rails requests trying to load tools
      tool_class = Class.new do
        def call
          { concurrent: true }
        end
      end

      stub_const("Ai::Tools::ConcurrentTool", tool_class)

      # Create multiple threads simulating Rails request handling
      threads = 10.times.map do |i|
        Thread.new do
          # Each thread creates its own agent instance
          agent_class = Class.new(RAAF::DSL::Agent) do
            agent_name "ConcurrentAgent#{i}"
            model "gpt-4o"
            tool :concurrent
          end

          agent_class.new
        end
      end

      # All threads should complete successfully
      agents = threads.map(&:value)
      expect(agents).to all(be_a(RAAF::DSL::Agent))

      # All agents should have the same tool resolved
      agents.each do |agent|
        expect(agent.class._tools_config.first[:tool_class]).to eq(tool_class)
      end
    end

    it "handles namespace conflicts between user and framework tools" do
      # Define same tool in both namespaces
      user_tool = Class.new do
        def call
          { source: "user" }
        end
      end

      framework_tool = Class.new do
        def call
          { source: "framework" }
        end
      end

      stub_const("Ai::Tools::ConflictTool", user_tool)
      stub_const("RAAF::Tools::ConflictTool", framework_tool)

      # Agent should prefer user tool (Ai::Tools)
      agent_class = Class.new(RAAF::DSL::Agent) do
        agent_name "ConflictResolutionAgent"
        model "gpt-4o"
        tool :conflict
      end

      agent = agent_class.new
      # Should resolve to user tool (Ai::Tools takes precedence)
      expect(agent.class._tools_config.first[:tool_class]).to eq(user_tool)
    end
  end

  describe "Rails-specific edge cases" do
    it "handles tools defined in Rails engines" do
      # Simulate a tool from a Rails engine
      engine_tool = Class.new do
        def call
          { engine: "custom_engine" }
        end
      end

      # Rails engines typically have their own namespace
      stub_const("CustomEngine::Tools::EngineTool", engine_tool)

      # Register the engine namespace
      RAAF::ToolRegistry.instance_variable_get(:@namespaces).unshift("CustomEngine::Tools")

      agent_class = Class.new(RAAF::DSL::Agent) do
        agent_name "EngineAgent"
        model "gpt-4o"
        tool :engine
      end

      agent = agent_class.new
      expect(agent.class._tools_config.first[:tool_class]).to eq(engine_tool)
    end

    it "works with Rails concerns and modules" do
      # Define a tool within a concern/module structure
      module ToolConcerns
        module Searchable
          class SearchTool
            def call(query:)
              { concern_search: query }
            end
          end
        end
      end

      stub_const("Ai::Tools::SearchTool", ToolConcerns::Searchable::SearchTool)

      agent_class = Class.new(RAAF::DSL::Agent) do
        agent_name "ConcernAgent"
        model "gpt-4o"
        tool :search
      end

      agent = agent_class.new
      expect(agent.class._tools_config.first[:tool_class]).to eq(ToolConcerns::Searchable::SearchTool)
    end

    it "handles STI (Single Table Inheritance) tool patterns" do
      # Base tool class
      base_tool = Class.new do
        def call
          { type: "base" }
        end
      end

      # Specialized tool inheriting from base
      specialized_tool = Class.new(base_tool) do
        def call
          { type: "specialized" }
        end
      end

      stub_const("Ai::Tools::BaseTool", base_tool)
      stub_const("Ai::Tools::SpecializedTool", specialized_tool)

      # Agent using specialized tool
      agent_class = Class.new(RAAF::DSL::Agent) do
        agent_name "STIAgent"
        model "gpt-4o"
        tool :specialized
      end

      agent = agent_class.new
      expect(agent.class._tools_config.first[:tool_class]).to eq(specialized_tool)
      expect(agent.class._tools_config.first[:tool_class].superclass).to eq(base_tool)
    end
  end
end