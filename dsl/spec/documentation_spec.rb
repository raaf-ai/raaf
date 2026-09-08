# frozen_string_literal: true

require "spec_helper"
require "benchmark"
require "raaf-dsl"

# Tool registrations land in _tools_config as plain hashes. A symbol identifier
# is kept as :tool_identifier for lazy resolution; a class reference is resolved
# at class-definition time and kept as :tool_class.
def registered_identifiers(agent_class)
  agent_class._tools_config.map { |config| config[:tool_identifier] || config[:tool_class] }
end

def registered_options(agent_class, identifier)
  config = agent_class._tools_config.find do |c|
    (c[:tool_identifier] || c[:tool_class]) == identifier
  end
  config&.fetch(:options)
end

# This spec verifies that all documentation code examples work correctly
RSpec.describe "Documentation Examples" do
  describe "MIGRATION_GUIDE.md examples" do
    context "Single tool registration" do
      it "works with new syntax" do
        class TestSingleToolAgent < RAAF::DSL::Agent
          tool :web_search
          tool :calculator
        end

        expect(registered_identifiers(TestSingleToolAgent)).to include(:web_search, :calculator)
      end
    end

    context "Multiple tools at once" do
      it "works with new syntax" do
        class TestMultipleToolsAgent < RAAF::DSL::Agent
          tools :web_search, :file_search, :calculator
        end

        expect(registered_identifiers(TestMultipleToolsAgent)).to include(:web_search, :file_search, :calculator)
      end
    end

    context "Native tool classes" do
      # Mock native tool class for testing
      module TestTools
        class CustomTool
          def self.tool_name
            "custom_tool"
          end
        end
      end

      it "works with class references" do
        class TestNativeToolAgent < RAAF::DSL::Agent
          tool TestTools::CustomTool
        end

        expect(registered_identifiers(TestNativeToolAgent)).to include(TestTools::CustomTool)
        expect(TestNativeToolAgent._tools_config.first).to include(tool_class: TestTools::CustomTool)
      end
    end

    context "Tool with options" do
      it "works with options hash" do
        class TestToolWithOptionsAgent < RAAF::DSL::Agent
          tool :web_search, max_results: 10, timeout: 30
          tool :database_query, connection: :primary
        end

        expect(registered_options(TestToolWithOptionsAgent, :web_search)).to eq(max_results: 10, timeout: 30)
        expect(registered_options(TestToolWithOptionsAgent, :database_query)).to eq(connection: :primary)
      end
    end

    context "Tool with alias" do
      it "works with as option" do
        class TestToolWithAliasAgent < RAAF::DSL::Agent
          tool :web_search, as: :internet_search
        end

        config = TestToolWithAliasAgent._tools_config.first
        expect(config[:tool_identifier]).to eq(:web_search)
        expect(config[:options][:as]).to eq(:internet_search)
      end
    end

    context "Conditional tool loading" do
      it "works with Ruby conditionals" do
        # Test with false condition
        class TestConditionalFalseAgent < RAAF::DSL::Agent
        end
        expect(TestConditionalFalseAgent._tools_config).to be_empty

        # Test with true condition
        class TestConditionalTrueAgent < RAAF::DSL::Agent
          tool :basic_tool
        end
        expect(registered_identifiers(TestConditionalTrueAgent)).to include(:basic_tool)
      end
    end

    context "Inline tool definition" do
      it "works with block syntax" do
        class TestInlineToolAgent < RAAF::DSL::Agent
          tool :custom_calculator do
            description "Performs calculations"
            parameter :expression, type: :string

            execute do |expression:|
              { result: "calculated" }
            end
          end
        end

        expect(registered_identifiers(TestInlineToolAgent)).to include(:custom_calculator)

        # The block is folded into the tool's options rather than kept separately.
        options = registered_options(TestInlineToolAgent, :custom_calculator)
        expect(options[:description]).to eq("Performs calculations")
        expect(options[:execute]).to be true
      end
    end
  end

  describe "CLAUDE.md examples" do
    context "Tool Registration section examples" do
      it "demonstrates all 7 registration patterns" do
        class DemoAgent < RAAF::DSL::Agent
          agent_name "ToolDemoAgent"
          model "gpt-4o"

          # Pattern 1: Symbol identifier
          tool :web_search

          # Pattern 2: Multiple tools
          tools :file_search, :database_query

          # Pattern 3: Native tool class (using mock class)
          tool TestTools::CustomTool if defined?(TestTools::CustomTool)

          # Pattern 4: With options
          tool :calculator, precision: :high

          # Pattern 5: With alias
          tool :search, as: :internet_search

          # Pattern 6: Conditional loading
          # Won't be loaded

          # Pattern 7: Inline definition
          tool :custom_tool do
            description "Custom tool"
            execute { |**_args| { result: "success" } }
          end
        end

        identifiers = registered_identifiers(DemoAgent)
        expect(identifiers).to include(
          :web_search,
          :file_search,
          :database_query,
          :calculator,
          :search,
          :custom_tool
        )
        expect(identifiers).not_to include(:premium_tool) # Conditional was false
      end
    end

    context "Lazy loading demonstration" do
      it "shows tools are registered but not loaded immediately" do
        class LazyLoadingAgent < RAAF::DSL::Agent
          tool :web_search
        end

        # Tool is registered
        expect(LazyLoadingAgent._tools_config.size).to eq(1)

        # A symbol identifier is stored unresolved, so no tool class is loaded yet
        config = LazyLoadingAgent._tools_config.first
        expect(config[:tool_identifier]).to eq(:web_search)
        expect(config).not_to have_key(:tool_class)
      end
    end

    context "Error message example" do
      it "raises ToolResolutionError for an unknown non-symbol identifier" do
        expect do
          Class.new(RAAF::DSL::Agent) do
            tool "completely_unknown_tool_xyz123"
          end
        end.to raise_error(RAAF::DSL::ToolResolutionError) do |error|
          expect(error.message).to include("Tool not found: completely_unknown_tool_xyz123")
          expect(error.message).to include("Searched in:")
          expect(error.message).to include("RAAF::ToolRegistry")
          expect(error.message).to include("To fix:")
        end
      end

      it "defers an unknown symbol identifier instead of raising" do
        # Symbols are resolved lazily so that agent classes can be loaded before
        # the tool registry exists (background jobs, eager loading).
        agent_class = nil

        expect do
          agent_class = Class.new(RAAF::DSL::Agent) do
            tool :completely_unknown_tool_xyz123
          end
        end.not_to raise_error

        expect(agent_class._tools_config.first[:tool_identifier])
          .to eq(:completely_unknown_tool_xyz123)
      end
    end
  end

  describe "README.md examples" do
    context "Quick Start example" do
      it "works with tool method in AgentBuilder" do
        agent = RAAF::DSL::AgentBuilder.build do
          name "WebSearchAgent"
          instructions "You help users search the web"
          model "gpt-4o"

          # This uses the new tool method with block
          tool :web_search do
            description "Search the web for information"
            parameter :query, type: :string, required: true

            execute do |query:|
              { results: ["Result 1", "Result 2"] }
            end
          end
        end

        expect(agent.tools.size).to eq(1)
        expect(agent.tools.first).to respond_to(:call)
      end
    end

    context "Advanced tool configuration" do
      it "works with new tool syntax" do
        class AdvancedDocAgent < RAAF::DSL::Agent
          tool :text_extraction, max_pages: 50
          tool :database_query, timeout: 30
        end

        expect(registered_options(AdvancedDocAgent, :text_extraction)).to eq(max_pages: 50)
        expect(registered_options(AdvancedDocAgent, :database_query)).to eq(timeout: 30)
      end
    end
  end

  describe "Deprecated methods" do
    it "raises NoMethodError for uses_tool" do
      expect do
        class DeprecatedAgent < RAAF::DSL::Agent
          uses_tool :web_search
        end
      end.to raise_error(NoMethodError)
    end

    it "raises NoMethodError for uses_tools" do
      expect do
        class DeprecatedAgent2 < RAAF::DSL::Agent
          uses_tools :web_search, :calculator
        end
      end.to raise_error(NoMethodError)
    end

    it "raises NoMethodError for uses_native_tool" do
      expect do
        class DeprecatedAgent3 < RAAF::DSL::Agent
          uses_native_tool String # Random class
        end
      end.to raise_error(NoMethodError)
    end

    it "raises NoMethodError for uses_tool_if" do
      expect do
        class DeprecatedAgent4 < RAAF::DSL::Agent
          uses_tool_if true, :web_search
        end
      end.to raise_error(NoMethodError)
    end
  end

  describe "Performance characteristics" do
    it "demonstrates lazy loading with multiple agents" do
      # Create multiple agents to show initialization is fast
      agents = []

      time = Benchmark.realtime do
        10.times do |_i|
          klass = Class.new(RAAF::DSL::Agent) do
            tool :web_search
            tool :calculator
            tool :file_search
          end
          agents << klass
        end
      end

      # Should be very fast since tools aren't loaded yet
      expect(time).to be < 0.1 # Less than 100ms for 10 agents with 3 tools each

      # All agents should have registered tools
      agents.each do |agent_class|
        expect(agent_class._tools_config.size).to eq(3)
      end
    end
  end
end
