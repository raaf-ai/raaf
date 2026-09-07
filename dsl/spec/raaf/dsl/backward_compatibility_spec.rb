# frozen_string_literal: true

require "benchmark"
require "spec_helper"
require_relative "../../support/tool_mocking_helpers"

RSpec.describe "Backward Compatibility" do
  include ToolMockingHelpers

  before do
    # Create mock tools for testing
    @mock_search_tool = create_fixture_tool(:search)
    @mock_calc_tool = create_fixture_tool(:calculator)

    # Set up mock resolutions
    mock_tools(
      web_search: @mock_search_tool,
      calculator: @mock_calc_tool
    )
  end

  describe "deprecated method usage" do
    context "when using tool (the replacement for uses_tool)" do
      it "registers the tool" do
        agent_class = Class.new(RAAF::DSL::Agent) do
          agent_name "BackwardCompatAgent"
          model "gpt-4o"
          tool :web_search
        end

        expect { agent_class.new }.not_to raise_error
        expect(agent_class._tools_config.first[:tool_class]).to be_a(Class)
      end

      it "works with options hash" do
        agent_class = Class.new(RAAF::DSL::Agent) do
          agent_name "BackwardCompatAgent"
          model "gpt-4o"
          tool :calculator, max_retries: 3
        end

        config = agent_class._tools_config.first
        expect(config[:tool_class]).to be_a(Class)
        expect(config[:options][:max_retries]).to eq(3)
      end
    end

    context "when using old patterns that should fail" do
      it "raises error for uses_tool_if (removed method)" do
        expect do
          Class.new(RAAF::DSL::Agent) do
            agent_name "OldPatternAgent"
            model "gpt-4o"
            uses_tool_if true, :web_search
          end
        end.to raise_error(NoMethodError, /undefined method [`']uses_tool_if'/)
      end

      it "raises error for uses_external_tool (removed method)" do
        expect do
          Class.new(RAAF::DSL::Agent) do
            agent_name "OldPatternAgent"
            model "gpt-4o"
            uses_external_tool :web_search
          end
        end.to raise_error(NoMethodError, /undefined method [`']uses_external_tool'/)
      end

      it "raises error for uses_native_tool (removed method)" do
        expect do
          Class.new(RAAF::DSL::Agent) do
            agent_name "OldPatternAgent"
            model "gpt-4o"
            uses_native_tool Object
          end
        end.to raise_error(NoMethodError, /undefined method [`']uses_native_tool'/)
      end
    end

    context "when using multiple tool registration patterns" do
      it "registers several tools with tools" do
        agent_class = Class.new(RAAF::DSL::Agent) do
          agent_name "MultiToolAgent"
          model "gpt-4o"
          tools :web_search, :calculator
        end

        expect(agent_class._tools_config.length).to eq(2)
        expect(agent_class._tools_config.map { |c| c[:tool_class] }).to all(be_a(Class))
      end

      it "carries per-tool options through separate tool calls" do
        agent_class = Class.new(RAAF::DSL::Agent) do
          agent_name "ConfiguredAgent"
          model "gpt-4o"
          tool :web_search, max_results: 10
          tool :calculator, precision: 2
        end

        options = agent_class._tools_config.map { |c| c[:options] }

        expect(options).to contain_exactly({ max_results: 10 }, { precision: 2 })
      end

      it "no longer answers to the removed uses_tools and configure_tools" do
        expect(RAAF::DSL::Agent).not_to respond_to(:uses_tools)
        expect(RAAF::DSL::Agent).not_to respond_to(:configure_tools)
      end
    end
  end

  describe "migration path verification" do
    it "provides clear error messages for required migrations" do
      # Test that removed methods give helpful errors
      agent_class = Class.new(RAAF::DSL::Agent) do
        agent_name "MigrationTestAgent"
        model "gpt-4o"
      end

      agent = agent_class.new

      # The uses_* family was removed in 2.0.0 (see MIGRATION_GUIDE.md)
      expect(agent.class).not_to respond_to(:uses_tool)
      expect(agent.class).not_to respond_to(:uses_tools)
      expect(agent.class).not_to respond_to(:uses_tool_if)
      expect(agent.class).not_to respond_to(:uses_external_tool)
      expect(agent.class).not_to respond_to(:uses_native_tool)
      expect(agent.class).not_to respond_to(:configure_tools)

      # Its replacements
      expect(agent.class).to respond_to(:tool)
      expect(agent.class).to respond_to(:tools)
    end

    it "documents required code changes through error messages" do
      # When using an old pattern, the error should be clear
      error_raised = false
      error_message = nil

      begin
        Class.new(RAAF::DSL::Agent) do
          agent_name "ErrorAgent"
          model "gpt-4o"
          uses_tool_if true, :calculator
        end
      rescue NoMethodError => e
        error_raised = true
        error_message = e.message
      end

      expect(error_raised).to be true
      expect(error_message).to include("uses_tool_if")
    end
  end

  describe "tool resolution compatibility" do
    it "maintains compatibility with direct class references" do
      weather_tool = create_fixture_tool(:weather)

      agent_class = Class.new(RAAF::DSL::Agent) do
        agent_name "DirectRefAgent"
        model "gpt-4o"
        tool weather_tool
      end

      expect(agent_class._tools_config.first[:tool_class]).to eq(weather_tool)
    end

    it "maintains compatibility with symbol references" do
      agent_class = Class.new(RAAF::DSL::Agent) do
        agent_name "SymbolRefAgent"
        model "gpt-4o"
        tool :web_search
      end

      expect(agent_class._tools_config.first[:tool_class]).to be_a(Class)
    end

    it "maintains compatibility with string references" do
      string_tool = create_fixture_tool(:search)
      mock_tool_resolution("string_tool", string_tool)

      agent_class = Class.new(RAAF::DSL::Agent) do
        agent_name "StringRefAgent"
        model "gpt-4o"
        tool "string_tool"
      end

      expect(agent_class._tools_config.first[:tool_class]).to eq(string_tool)
    end
  end

  describe "error message improvements" do
    it "provides helpful suggestions when tool not found" do
      # Don't mock this tool so it fails to resolve
      clear_tool_mocks!

      expect do
        Class.new(RAAF::DSL::Agent) do
          agent_name "ErrorAgent"
          model "gpt-4o"
          tool "nonexistent_tool"
        end
      end.to raise_error(RAAF::DSL::ToolResolutionError) do |error|
        expect(error.message).to include("Tool not found")
        expect(error.message).to include("nonexistent_tool")
        expect(error.suggestions).not_to be_empty
      end
    end

    it "shows searched namespaces in error messages" do
      clear_tool_mocks!

      expect do
        Class.new(RAAF::DSL::Agent) do
          agent_name "NamespaceErrorAgent"
          model "gpt-4o"
          tool "missing_tool"
        end
      end.to raise_error(RAAF::DSL::ToolResolutionError) do |error|
        expect(error.searched_namespaces).to include("Ai::Tools")
        expect(error.searched_namespaces).to include("RAAF::Tools")
      end
    end
  end

  describe "configuration block compatibility" do
    it "supports old-style configuration blocks" do
      agent_class = Class.new(RAAF::DSL::Agent) do
        agent_name "BlockConfigAgent"
        model "gpt-4o"

        tool :web_search do
          max_results 20
          timeout 30
        end
      end

      config = agent_class._tools_config.first
      expect(config[:options]).to include(max_results: 20, timeout: 30)
    end

    it "supports new-style DSL configuration blocks" do
      # Mock a tool that accepts configuration
      configurable_tool = Class.new do
        attr_reader :config

        def initialize(config = {})
          @config = config
        end

        def call(**args)
          { configured: true, config: @config, args: args }
        end
      end

      mock_tool_resolution(:configurable, configurable_tool)

      agent_class = Class.new(RAAF::DSL::Agent) do
        agent_name "DSLConfigAgent"
        model "gpt-4o"

        tool :configurable do
          max_retries 5
          timeout 60
          custom_option "value"
        end
      end

      expect { agent_class.new }.not_to raise_error
    end
  end

  describe "namespace resolution compatibility" do
    it "maintains user namespace priority (Ai::Tools > RAAF::Tools)" do
      # Create tools in both namespaces
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

      stub_const("Ai::Tools::PriorityTestTool", user_tool)
      stub_const("RAAF::Tools::PriorityTestTool", framework_tool)

      agent_class = Class.new(RAAF::DSL::Agent) do
        agent_name "PriorityAgent"
        model "gpt-4o"
        tool :priority_test
      end

      agent = agent_class.new
      # Should resolve to user tool
      expect(agent.class._tools_config.first[:tool_class]).to eq(user_tool)
    end

    it "falls back to RAAF::Tools when not in Ai::Tools" do
      framework_tool = Class.new do
        def call
          { source: "framework" }
        end
      end

      stub_const("RAAF::Tools::FrameworkOnlyTool", framework_tool)

      agent_class = Class.new(RAAF::DSL::Agent) do
        agent_name "FallbackAgent"
        model "gpt-4o"
        tool :framework_only
      end

      agent = agent_class.new
      expect(agent.class._tools_config.first[:tool_class]).to eq(framework_tool)
    end
  end

  describe "performance impact verification" do
    it "registers tools without measurable per-call overhead" do
      # Tool registration is lazy: declaring a tool must not pay for resolving
      # or instantiating it.
      expect(RAAF::ToolRegistry).to receive(:safe_lookup).twice.and_call_original

      elapsed = Benchmark.realtime do
        Class.new(RAAF::DSL::Agent) do
          agent_name "PerfAgent"
          model "gpt-4o"
          tool :web_search
          tool :calculator
        end
      end

      expect(elapsed).to be < 0.1
    end
  end

  describe "common migration scenarios" do
    it "handles complex legacy agent configurations" do
      # Simulate a complex legacy agent that needs migration guidance
      legacy_agent = Class.new(RAAF::DSL::Agent) do
        agent_name "LegacyComplexAgent"
        model "gpt-4o"

        # The 2.0 equivalents of the uses_* family
        tool :web_search, max_results: 10
        tools :calculator
        tool :web_search, api_key: "test"
      end

      configs = legacy_agent._tools_config

      expect(configs.length).to eq(3)
      expect(configs.map { |c| c[:options] }).to contain_exactly(
        { max_results: 10 },
        {},
        { api_key: "test" }
      )
    end

    it "provides migration path for conditional tool loading" do
      # Old pattern: uses_tool_if (now removed)
      # New pattern: use conditional logic in class definition

      condition = true

      agent_class = Class.new(RAAF::DSL::Agent) do
        agent_name "ConditionalAgent"
        model "gpt-4o"

        # New way to conditionally add tools
        tool :web_search if condition
        tool :calculator unless condition
      end

      configs = agent_class._tools_config

      # Only web_search should be added
      expect(configs.length).to eq(1)
      expect(configs.first[:tool_class]).to eq(@mock_search_tool)
    end

    it "records the resolved class for a plain callable tool" do
      function_tool = Class.new do
        def call
          { type: "function" }
        end
      end

      mock_tool_resolution(:function_tool, function_tool)

      agent_class = Class.new(RAAF::DSL::Agent) do
        agent_name "TypeDetectionAgent"
        model "gpt-4o"
        tool :function_tool
      end

      expect(agent_class._tools_config.first[:tool_class]).to eq(function_tool)
    end
  end
end
