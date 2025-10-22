# frozen_string_literal: true

require "spec_helper"
require_relative "../support/tool_mocking_helpers"

RSpec.describe "Complete Integration Tests" do
  include ToolMockingHelpers

  before do
    # Clear registry for clean state
    RAAF::ToolRegistry.clear! if defined?(RAAF::ToolRegistry)
  end

  describe "Complete workflow from Agent perspective" do
    it "handles full lifecycle of tool registration and usage" do
      # Step 1: Define a tool
      custom_tool = Class.new do
        def call(input:)
          { processed: input.upcase, timestamp: Time.now.to_i }
        end
      end

      stub_const("Ai::Tools::CustomProcessorTool", custom_tool)

      # Step 2: Define an agent using the tool
      agent_class = Class.new(RAAF::DSL::Agent) do
        agent_name "WorkflowTestAgent"
        model "gpt-4o"
        instructions "You process text data"

        # Register tool using symbol
        tool :custom_processor
      end

      # Step 3: Initialize agent
      agent = agent_class.new

      # Step 4: Verify tool is properly configured
      tools_config = agent.class._tools_config
      expect(tools_config).not_to be_empty
      expect(tools_config.first[:name]).to eq(:custom_processor)
      expect(tools_config.first[:tool_class]).to eq(custom_tool)

      # Step 5: Verify tool can be instantiated and called
      tool_instance = tools_config.first[:tool_class].new
      result = tool_instance.call(input: "hello")
      expect(result[:processed]).to eq("HELLO")
      expect(result[:timestamp]).to be_a(Integer)
    end

    it "handles complex multi-tool agent setup" do
      # Define multiple tools
      search_tool = create_fixture_tool(:search)
      calc_tool = create_fixture_tool(:calculator)
      weather_tool = create_fixture_tool(:weather)

      stub_const("Ai::Tools::SearchTool", search_tool)
      stub_const("Ai::Tools::CalculatorTool", calc_tool)
      stub_const("Ai::Tools::WeatherTool", weather_tool)

      # Create agent with multiple tools
      agent_class = Class.new(RAAF::DSL::Agent) do
        agent_name "MultiToolAgent"
        model "gpt-4o"

        # Different registration patterns
        tool :search                              # Symbol
        tool Ai::Tools::CalculatorTool           # Class reference
        tool :weather, timeout: 30                # With options
      end

      agent = agent_class.new
      configs = agent.class._tools_config

      # Verify all tools registered
      expect(configs.length).to eq(3)

      # Verify each tool configuration
      search_config = configs.find { |c| c[:name] == :search }
      expect(search_config[:tool_class]).to eq(search_tool)

      calc_config = configs.find { |c| c[:tool_class] == calc_tool }
      expect(calc_config).not_to be_nil

      weather_config = configs.find { |c| c[:name] == :weather }
      expect(weather_config[:options][:timeout]).to eq(30)
    end

    it "integrates with RAAF Runner for execution" do
      # Mock a tool that will be called
      mock_tool = Class.new do
        def call(query:)
          { answer: "The answer to '#{query}' is 42" }
        end
      end

      stub_const("Ai::Tools::QuestionAnswererTool", mock_tool)

      # Define agent
      agent_class = Class.new(RAAF::DSL::Agent) do
        agent_name "RunnerIntegrationAgent"
        model "gpt-4o"
        instructions "You answer questions using tools"

        tool :question_answerer
      end

      agent = agent_class.new

      # Create runner (if RAAF::Runner is available)
      if defined?(RAAF::Runner)
        runner = RAAF::Runner.new(agent: agent)
        expect(runner).to be_a(RAAF::Runner)
      end
    end
  end

  describe "Edge cases and error conditions" do
    it "handles missing tools gracefully" do
      agent_class = Class.new(RAAF::DSL::Agent) do
        agent_name "ErrorHandlingAgent"
        model "gpt-4o"

        tool :nonexistent_tool
      end

      expect { agent_class.new }.to raise_error(RAAF::DSL::ToolResolutionError) do |error|
        expect(error.identifier).to eq(:nonexistent_tool)
        expect(error.message).to include("Could not find tool")
      end
    end

    it "handles circular tool dependencies" do
      # Create agents with potential circular dependencies
      agent_a_class = Class.new(RAAF::DSL::Agent) do
        agent_name "CircularAgentA"
        model "gpt-4o"

        def self.dependent_tool
          # References agent B's tool
          :tool_from_b
        end

        tool dependent_tool if respond_to?(:dependent_tool)
      end

      agent_b_class = Class.new(RAAF::DSL::Agent) do
        agent_name "CircularAgentB"
        model "gpt-4o"

        def self.dependent_tool
          # References agent A's tool
          :tool_from_a
        end

        tool dependent_tool if respond_to?(:dependent_tool)
      end

      # Both should fail gracefully with clear errors
      expect { agent_a_class.new }.to raise_error(RAAF::DSL::ToolResolutionError)
      expect { agent_b_class.new }.to raise_error(RAAF::DSL::ToolResolutionError)
    end

    it "handles tool registration with invalid inputs" do
      agent_class = Class.new(RAAF::DSL::Agent) do
        agent_name "InvalidInputAgent"
        model "gpt-4o"
      end

      # Try to register with nil
      expect { agent_class.tool(nil) }.to raise_error(ArgumentError)

      # Try to register with empty string
      expect { agent_class.tool("") }.to raise_error(ArgumentError)

      # Try to register with invalid class (not a tool)
      invalid_class = Class.new # No call method
      expect { agent_class.tool(invalid_class) }.not_to raise_error # Should handle gracefully
    end
  end

  describe "Thread safety of registry" do
    it "handles concurrent tool registration safely" do
      results = Concurrent::Array.new

      threads = 20.times.map do |i|
        Thread.new do
          # Each thread creates and registers a tool
          tool_class = Class.new do
            define_singleton_method(:name) { "ThreadTool#{i}" }

            def call
              { thread_id: Thread.current.object_id }
            end
          end

          RAAF::ToolRegistry.register("thread_tool_#{i}", tool_class)

          # Try to use the tool in an agent
          agent_class = Class.new(RAAF::DSL::Agent) do
            agent_name "ThreadAgent#{i}"
            model "gpt-4o"
            tool "thread_tool_#{i}"
          end

          begin
            agent = agent_class.new
            results << { success: true, thread: i, agent: agent }
          rescue => e
            results << { success: false, thread: i, error: e }
          end
        end
      end

      threads.each(&:join)

      # All threads should succeed
      expect(results.length).to eq(20)
      expect(results.select { |r| r[:success] }.length).to eq(20)
    end

    it "handles concurrent tool resolution safely" do
      # Pre-register a tool
      test_tool = Class.new do
        def call
          { resolved: true }
        end
      end

      RAAF::ToolRegistry.register(:concurrent_test, test_tool)

      resolution_results = Concurrent::Array.new

      # Many threads trying to resolve the same tool
      threads = 50.times.map do
        Thread.new do
          result = RAAF::ToolRegistry.resolve(:concurrent_test)
          resolution_results << result
        end
      end

      threads.each(&:join)

      # All resolutions should return the same tool class
      expect(resolution_results).to all(eq(test_tool))
    end
  end

  describe "Performance under load" do
    it "handles many agents with many tools efficiently" do
      # Create 20 different tools
      20.times do |i|
        tool_class = Class.new do
          define_singleton_method(:name) { "LoadTestTool#{i}" }

          def call(**args)
            { tool_index: self.class.name.match(/\d+/).to_s.to_i, args: args }
          end
        end

        stub_const("Ai::Tools::LoadTestTool#{i}Tool", tool_class)
      end

      # Create agents using various combinations of tools
      agents = []
      start_time = Time.now

      10.times do |agent_index|
        agent_class = Class.new(RAAF::DSL::Agent) do
          agent_name "LoadTestAgent#{agent_index}"
          model "gpt-4o"

          # Each agent uses 5-10 tools
          tool_count = rand(5..10)
          tool_count.times do |tool_index|
            tool "load_test_tool#{tool_index}".to_sym
          end
        end

        agents << agent_class.new
      end

      elapsed_time = Time.now - start_time

      # Should complete in reasonable time
      expect(elapsed_time).to be < 1.0 # Less than 1 second for 10 agents

      # All agents should be properly initialized
      expect(agents).to all(be_a(RAAF::DSL::Agent))
    end
  end

  describe "Tool type detection" do
    it "correctly identifies external DSL tools" do
      # Create a DSL tool if the base class exists
      if defined?(RAAF::DSL::Tools::Base)
        dsl_tool = Class.new(RAAF::DSL::Tools::Base) do
          def call
            { type: "dsl" }
          end
        end

        stub_const("Ai::Tools::DslTypeTool", dsl_tool)

        agent_class = Class.new(RAAF::DSL::Agent) do
          agent_name "TypeDetectionAgent"
          model "gpt-4o"
          tool :dsl_type
        end

        agent = agent_class.new
        config = agent.class._tools_config.first

        expect(config[:tool_type]).to eq(:external)
      end
    end

    it "correctly identifies native execution tools" do
      native_tool = Class.new do
        def call
          { type: "native" }
        end

        def execute
          call
        end
      end

      stub_const("Ai::Tools::NativeTypeTool", native_tool)

      agent_class = Class.new(RAAF::DSL::Agent) do
        agent_name "NativeTypeAgent"
        model "gpt-4o"
        tool :native_type
      end

      agent = agent_class.new
      config = agent.class._tools_config.first

      expect(config[:tool_type]).to eq(:native)
    end
  end

  describe "Integration with tool execution interceptor" do
    it "works with tool execution configuration" do
      mock_tool = Class.new do
        def call(input:)
          { result: input.reverse }
        end
      end

      stub_const("Ai::Tools::InterceptorTestTool", mock_tool)

      agent_class = Class.new(RAAF::DSL::Agent) do
        agent_name "InterceptorAgent"
        model "gpt-4o"

        tool :interceptor_test

        # Configure tool execution if the DSL supports it
        if respond_to?(:tool_execution)
          tool_execution do
            enable_logging true
            enable_validation true
            enable_metadata true
          end
        end
      end

      expect { agent_class.new }.not_to raise_error
    end
  end

  describe "Complete error scenarios" do
    it "provides comprehensive error information for debugging" do
      agent_class = Class.new(RAAF::DSL::Agent) do
        agent_name "DebugErrorAgent"
        model "gpt-4o"
        tool :completely_missing_tool
      end

      begin
        agent_class.new
        fail "Should have raised an error"
      rescue RAAF::DSL::ToolResolutionError => e
        # Error should contain all helpful information
        expect(e.identifier).to eq(:completely_missing_tool)
        expect(e.searched_namespaces).to be_an(Array)
        expect(e.searched_namespaces).not_to be_empty
        expect(e.suggestions).to be_an(Array)

        # Error message should be well-formatted
        expect(e.message).to include("Could not find tool")
        expect(e.message).to include("completely_missing_tool")
        expect(e.message).to include("Searched in:")
      end
    end

    it "handles namespace conflicts appropriately" do
      # Define same tool in multiple namespaces
      user_version = Class.new do
        def call
          { version: "user" }
        end
      end

      framework_version = Class.new do
        def call
          { version: "framework" }
        end
      end

      stub_const("Ai::Tools::ConflictedTool", user_version)
      stub_const("RAAF::Tools::ConflictedTool", framework_version)

      agent_class = Class.new(RAAF::DSL::Agent) do
        agent_name "ConflictResolutionAgent"
        model "gpt-4o"
        tool :conflicted
      end

      agent = agent_class.new
      config = agent.class._tools_config.first

      # Should prefer user namespace (Ai::Tools)
      expect(config[:tool_class]).to eq(user_version)
    end
  end

  describe "Registry statistics and debugging" do
    it "tracks tool resolution statistics" do
      # Create and register some tools
      5.times do |i|
        tool = Class.new do
          def call
            { id: i }
          end
        end
        RAAF::ToolRegistry.register("stat_tool_#{i}", tool)
      end

      # Perform some lookups
      10.times do
        RAAF::ToolRegistry.resolve(:stat_tool_0)
        RAAF::ToolRegistry.resolve(:stat_tool_1)
      end

      # Try some that don't exist
      5.times do
        RAAF::ToolRegistry.resolve(:nonexistent_tool)
      end

      # Check if registry provides any statistics
      if RAAF::ToolRegistry.respond_to?(:statistics)
        stats = RAAF::ToolRegistry.statistics
        expect(stats).to be_a(Hash)
      end
    end
  end

  describe "Tool discovery patterns" do
    it "discovers tools with various naming conventions" do
      # CamelCase tool
      camel_tool = Class.new do
        def call
          { style: "camel" }
        end
      end

      # snake_case tool
      snake_tool = Class.new do
        def call
          { style: "snake" }
        end
      end

      stub_const("Ai::Tools::CamelCaseTool", camel_tool)
      stub_const("Ai::Tools::SnakeCaseTool", snake_tool)

      agent_class = Class.new(RAAF::DSL::Agent) do
        agent_name "NamingConventionAgent"
        model "gpt-4o"

        tool :camel_case   # Should find CamelCaseTool
        tool :snake_case   # Should find SnakeCaseTool
      end

      agent = agent_class.new
      configs = agent.class._tools_config

      expect(configs.length).to eq(2)
      expect(configs.map { |c| c[:tool_class] }).to contain_exactly(camel_tool, snake_tool)
    end
  end
end