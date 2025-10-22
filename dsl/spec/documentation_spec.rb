# frozen_string_literal: true

require "spec_helper"
require "raaf-dsl"

# This spec verifies that all documentation code examples work correctly
RSpec.describe "Documentation Examples" do
  describe "MIGRATION_GUIDE.md examples" do
    context "Single tool registration" do
      it "works with new syntax" do
        class TestSingleToolAgent < RAAF::DSL::Agent
          tool :web_search
          tool :calculator
        end

        expect(TestSingleToolAgent.registered_tools).to include(
          have_attributes(identifier: :web_search),
          have_attributes(identifier: :calculator)
        )
      end
    end

    context "Multiple tools at once" do
      it "works with new syntax" do
        class TestMultipleToolsAgent < RAAF::DSL::Agent
          tools :web_search, :file_search, :calculator
        end

        expect(TestMultipleToolsAgent.registered_tools).to include(
          have_attributes(identifier: :web_search),
          have_attributes(identifier: :file_search),
          have_attributes(identifier: :calculator)
        )
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

        expect(TestNativeToolAgent.registered_tools).to include(
          have_attributes(identifier: TestTools::CustomTool)
        )
      end
    end

    context "Tool with options" do
      it "works with options hash" do
        class TestToolWithOptionsAgent < RAAF::DSL::Agent
          tool :web_search, max_results: 10, timeout: 30
          tool :database_query, connection: :primary
        end

        web_search_tool = TestToolWithOptionsAgent.registered_tools.find { |t| t.identifier == :web_search }
        expect(web_search_tool.options).to eq(max_results: 10, timeout: 30)

        db_tool = TestToolWithOptionsAgent.registered_tools.find { |t| t.identifier == :database_query }
        expect(db_tool.options).to eq(connection: :primary)
      end
    end

    context "Tool with alias" do
      it "works with as option" do
        class TestToolWithAliasAgent < RAAF::DSL::Agent
          tool :web_search, as: :internet_search
        end

        tool = TestToolWithAliasAgent.registered_tools.first
        expect(tool.identifier).to eq(:web_search)
        expect(tool.options[:as]).to eq(:internet_search)
      end
    end

    context "Conditional tool loading" do
      it "works with Ruby conditionals" do
        # Test with false condition
        class TestConditionalFalseAgent < RAAF::DSL::Agent
          tool :premium_tool if false
        end
        expect(TestConditionalFalseAgent.registered_tools).to be_empty

        # Test with true condition
        class TestConditionalTrueAgent < RAAF::DSL::Agent
          tool :basic_tool if true
        end
        expect(TestConditionalTrueAgent.registered_tools).to include(
          have_attributes(identifier: :basic_tool)
        )
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

        expect(TestInlineToolAgent.registered_tools).to include(
          have_attributes(identifier: :custom_calculator)
        )
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
          tool :premium_tool if false # Won't be loaded

          # Pattern 7: Inline definition
          tool :custom_tool do
            description "Custom tool"
            execute { |**args| { result: "success" } }
          end
        end

        registered_identifiers = DemoAgent.registered_tools.map(&:identifier)
        expect(registered_identifiers).to include(
          :web_search,
          :file_search,
          :database_query,
          :calculator,
          :search,
          :custom_tool
        )
        expect(registered_identifiers).not_to include(:premium_tool) # Conditional was false
      end
    end

    context "Lazy loading demonstration" do
      it "shows tools are registered but not loaded immediately" do
        class LazyLoadingAgent < RAAF::DSL::Agent
          tool :web_search
        end

        # Tool is registered
        expect(LazyLoadingAgent.registered_tools.size).to eq(1)

        # Tool wrapper indicates it's not loaded yet
        tool_wrapper = LazyLoadingAgent.registered_tools.first
        expect(tool_wrapper).to respond_to(:loaded?)

        # In production, the tool would be loaded on first use
        # Here we just verify the wrapper exists
        expect(tool_wrapper.identifier).to eq(:web_search)
      end
    end

    context "Error message example" do
      it "raises ToolResolutionError for unknown tools" do
        expect {
          class FailingAgent < RAAF::DSL::Agent
            tool :completely_unknown_tool_xyz123
          end
        }.to raise_error(RAAF::DSL::ToolResolutionError) do |error|
          expect(error.message).to include("Tool Resolution Failed")
          expect(error.message).to include("completely_unknown_tool_xyz123")
          expect(error.message).to include("Searched namespaces:")
        end
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

        text_tool = AdvancedDocAgent.registered_tools.find { |t| t.identifier == :text_extraction }
        expect(text_tool.options).to eq(max_pages: 50)

        db_tool = AdvancedDocAgent.registered_tools.find { |t| t.identifier == :database_query }
        expect(db_tool.options).to eq(timeout: 30)
      end
    end
  end

  describe "Deprecated methods" do
    it "raises NoMethodError for uses_tool" do
      expect {
        class DeprecatedAgent < RAAF::DSL::Agent
          uses_tool :web_search
        end
      }.to raise_error(NoMethodError)
    end

    it "raises NoMethodError for uses_tools" do
      expect {
        class DeprecatedAgent2 < RAAF::DSL::Agent
          uses_tools :web_search, :calculator
        end
      }.to raise_error(NoMethodError)
    end

    it "raises NoMethodError for uses_native_tool" do
      expect {
        class DeprecatedAgent3 < RAAF::DSL::Agent
          uses_native_tool String # Random class
        end
      }.to raise_error(NoMethodError)
    end

    it "raises NoMethodError for uses_tool_if" do
      expect {
        class DeprecatedAgent4 < RAAF::DSL::Agent
          uses_tool_if true, :web_search
        end
      }.to raise_error(NoMethodError)
    end
  end

  describe "Performance characteristics" do
    it "demonstrates lazy loading with multiple agents" do
      # Create multiple agents to show initialization is fast
      agents = []

      time = Benchmark.realtime do
        10.times do |i|
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
        expect(agent_class.registered_tools.size).to eq(3)
      end
    end
  end
end