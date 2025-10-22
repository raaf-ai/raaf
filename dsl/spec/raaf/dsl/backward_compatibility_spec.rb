# frozen_string_literal: true

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
    context "when using uses_tool (now aliased to tool)" do
      it "continues to work with the alias" do
        agent_class = Class.new(RAAF::DSL::Agent) do
          agent_name "BackwardCompatAgent"
          model "gpt-4o"
          uses_tool :web_search
        end

        expect { agent_class.new }.not_to raise_error
        agent = agent_class.new
        expect(agent.class._tools_config.first[:name]).to eq(:web_search)
      end

      it "works with options hash" do
        agent_class = Class.new(RAAF::DSL::Agent) do
          agent_name "BackwardCompatAgent"
          model "gpt-4o"
          uses_tool :calculator, max_retries: 3
        end

        agent = agent_class.new
        config = agent.class._tools_config.first
        expect(config[:name]).to eq(:calculator)
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
      it "supports uses_tools for backward compatibility" do
        agent_class = Class.new(RAAF::DSL::Agent) do
          agent_name "MultiToolAgent"
          model "gpt-4o"
          uses_tools :web_search, :calculator
        end

        agent = agent_class.new
        expect(agent.class._tools_config.length).to eq(2)
        expect(agent.class._tools_config.map { |c| c[:name] }).to contain_exactly(:web_search, :calculator)
      end

      it "supports configure_tools for backward compatibility" do
        agent_class = Class.new(RAAF::DSL::Agent) do
          agent_name "ConfiguredAgent"
          model "gpt-4o"
          configure_tools(
            web_search: { max_results: 10 },
            calculator: { precision: 2 }
          )
        end

        agent = agent_class.new
        configs = agent.class._tools_config

        web_search_config = configs.find { |c| c[:name] == :web_search }
        calc_config = configs.find { |c| c[:name] == :calculator }

        expect(web_search_config[:options][:max_results]).to eq(10)
        expect(calc_config[:options][:precision]).to eq(2)
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

      # These methods should not exist
      expect(agent.class).not_to respond_to(:uses_tool_if)
      expect(agent.class).not_to respond_to(:uses_external_tool)
      expect(agent.class).not_to respond_to(:uses_native_tool)

      # But these should work (backward compatible)
      expect(agent.class).to respond_to(:uses_tool)
      expect(agent.class).to respond_to(:uses_tools)
      expect(agent.class).to respond_to(:configure_tools)
      expect(agent.class).to respond_to(:tool)
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
      agent_class = Class.new(RAAF::DSL::Agent) do
        agent_name "DirectRefAgent"
        model "gpt-4o"
        tool create_fixture_tool(:weather)
      end

      agent = agent_class.new
      expect(agent.class._tools_config.first[:tool_class]).to be_a(Class)
    end

    it "maintains compatibility with symbol references" do
      agent_class = Class.new(RAAF::DSL::Agent) do
        agent_name "SymbolRefAgent"
        model "gpt-4o"
        tool :web_search
      end

      agent = agent_class.new
      expect(agent.class._tools_config.first[:name]).to eq(:web_search)
    end

    it "maintains compatibility with string references" do
      mock_tool_resolution("string_tool", create_fixture_tool(:search))

      agent_class = Class.new(RAAF::DSL::Agent) do
        agent_name "StringRefAgent"
        model "gpt-4o"
        tool "string_tool"
      end

      agent = agent_class.new
      expect(agent.class._tools_config.first[:name]).to eq("string_tool")
    end
  end

  describe "error message improvements" do
    it "provides helpful suggestions when tool not found" do
      # Don't mock this tool so it fails to resolve
      clear_tool_mocks!

      agent_class = Class.new(RAAF::DSL::Agent) do
        agent_name "ErrorAgent"
        model "gpt-4o"
        tool :nonexistent_tool
      end

      expect { agent_class.new }.to raise_error(RAAF::DSL::ToolResolutionError) do |error|
        expect(error.message).to include("Could not find tool")
        expect(error.message).to include("nonexistent_tool")
        expect(error.suggestions).not_to be_empty
      end
    end

    it "shows searched namespaces in error messages" do
      clear_tool_mocks!

      agent_class = Class.new(RAAF::DSL::Agent) do
        agent_name "NamespaceErrorAgent"
        model "gpt-4o"
        tool :missing_tool
      end

      expect { agent_class.new }.to raise_error(RAAF::DSL::ToolResolutionError) do |error|
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

        tool :web_search do |config|
          config[:max_results] = 20
          config[:timeout] = 30
        end
      end

      agent = agent_class.new
      config = agent.class._tools_config.first
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
    it "maintains performance with backward compatible patterns" do
      # Measure performance of old pattern (uses_tool)
      start_time = Time.now

      agent_class_old = Class.new(RAAF::DSL::Agent) do
        agent_name "OldPatternPerfAgent"
        model "gpt-4o"
        uses_tool :web_search
        uses_tool :calculator
      end

      old_pattern_time = (Time.now - start_time) * 1000

      # Measure performance of new pattern (tool)
      start_time = Time.now

      agent_class_new = Class.new(RAAF::DSL::Agent) do
        agent_name "NewPatternPerfAgent"
        model "gpt-4o"
        tool :web_search
        tool :calculator
      end

      new_pattern_time = (Time.now - start_time) * 1000

      # Performance should be similar (within 20%)
      expect(old_pattern_time).to be_within(new_pattern_time * 0.2).of(new_pattern_time)
    end
  end

  describe "common migration scenarios" do
    it "handles complex legacy agent configurations" do
      # Simulate a complex legacy agent that needs migration guidance
      legacy_agent = Class.new(RAAF::DSL::Agent) do
        agent_name "LegacyComplexAgent"
        model "gpt-4o"

        # Mix of patterns that should work
        uses_tool :web_search, max_results: 10
        uses_tools :calculator

        configure_tools(
          web_search: { api_key: "test" }
        )
      end

      agent = legacy_agent.new
      configs = agent.class._tools_config

      # Should have both tools configured
      expect(configs.length).to eq(2)

      # Web search should have merged options
      web_search_configs = configs.select { |c| c[:name] == :web_search }
      expect(web_search_configs.length).to eq(2) # Registered twice

      # Calculator should be registered once
      calc_configs = configs.select { |c| c[:name] == :calculator }
      expect(calc_configs.length).to eq(1)
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

      agent = agent_class.new
      configs = agent.class._tools_config

      # Only web_search should be added
      expect(configs.length).to eq(1)
      expect(configs.first[:name]).to eq(:web_search)
    end

    it "handles tool type detection for migration" do
      # Create different tool types
      dsl_tool = Class.new(RAAF::DSL::Tools::Base) do
        def call
          { type: "dsl" }
        end
      end if defined?(RAAF::DSL::Tools::Base)

      function_tool = Class.new do
        def call
          { type: "function" }
        end
      end

      mock_tool_resolution(:dsl_tool, dsl_tool) if dsl_tool
      mock_tool_resolution(:function_tool, function_tool)

      agent_class = Class.new(RAAF::DSL::Agent) do
        agent_name "TypeDetectionAgent"
        model "gpt-4o"
        tool :function_tool
      end

      agent = agent_class.new
      config = agent.class._tools_config.first

      # Tool type should be detected
      expect(config[:tool_type]).to be_in([:native, :external])
    end
  end
end