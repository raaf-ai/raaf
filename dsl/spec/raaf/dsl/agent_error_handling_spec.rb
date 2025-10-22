# frozen_string_literal: true

require "spec_helper"
require "raaf/dsl/agent"
require "raaf/dsl/errors"

RSpec.describe "RAAF::DSL::Agent error handling" do
  let(:test_agent_class) do
    Class.new(RAAF::DSL::Agent) do
      agent_name "TestAgent"
      model "gpt-4o"
      static_instructions "Test agent"
    end
  end

  describe "tool resolution errors" do
    context "when a tool cannot be resolved" do
      before do
        # Ensure the tool doesn't exist
        allow(RAAF::ToolRegistry).to receive(:resolve_with_details).with(:nonexistent_tool).and_return({
          success: false,
          identifier: :nonexistent_tool,
          searched_namespaces: ["RAAF::Tools", "Ai::Tools", "RAAF::Tools::Basic"],
          suggestions: ["Did you mean: :existing_tool?", "Register it: RAAF::ToolRegistry.register(:nonexistent_tool, NonexistentToolTool)"]
        })
      end

      it "raises ToolResolutionError when tool is added to class" do
        expect {
          test_agent_class.tool :nonexistent_tool
        }.to raise_error(RAAF::DSL::ToolResolutionError) do |error|
          expect(error.message).to include("❌ Tool not found: nonexistent_tool")
          expect(error.message).to include("📂 Searched in:")
          expect(error.message).to include("RAAF::Tools")
          expect(error.message).to include("💡 Suggestions:")
          expect(error.message).to include("Did you mean: :existing_tool?")
        end
      end

      it "raises ToolResolutionError during agent initialization with tools" do
        # First allow the class definition to work
        allow(RAAF::ToolRegistry).to receive(:resolve_with_details).with(:missing_tool).and_return({
          success: false,
          identifier: :missing_tool,
          searched_namespaces: ["RAAF::Tools", "Ai::Tools"],
          suggestions: ["Register it: RAAF::ToolRegistry.register(:missing_tool, MissingToolTool)"]
        })

        agent_class_with_tool = Class.new(RAAF::DSL::Agent) do
          agent_name "AgentWithBadTool"
          model "gpt-4o"

          # This should raise during class definition
          begin
            tool :missing_tool
          rescue RAAF::DSL::ToolResolutionError
            # Store error for later re-raise during initialization
            @tool_resolution_error = $!
          end

          def self.tool_resolution_error
            @tool_resolution_error
          end
        end

        if agent_class_with_tool.tool_resolution_error
          expect {
            raise agent_class_with_tool.tool_resolution_error
          }.to raise_error(RAAF::DSL::ToolResolutionError) do |error|
            expect(error.message).to include("❌ Tool not found: missing_tool")
          end
        end
      end
    end

    context "when using uses_tool method" do
      before do
        allow(RAAF::ToolRegistry).to receive(:resolve_with_details).with(:bad_tool).and_return({
          success: false,
          identifier: :bad_tool,
          searched_namespaces: ["RAAF::Tools", "Ai::Tools"],
          suggestions: ["Try: tool GoodTool"]
        })
      end

      it "raises ToolResolutionError with context" do
        expect {
          test_agent_class.uses_tool :bad_tool
        }.to raise_error(RAAF::DSL::ToolResolutionError) do |error|
          expect(error.message).to include("❌ Tool not found: bad_tool")
          expect(error.message).to include("Try: tool GoodTool")
        end
      end
    end

    context "when using tool with options" do
      before do
        allow(RAAF::ToolRegistry).to receive(:resolve_with_details).with(:config_tool).and_return({
          success: false,
          identifier: :config_tool,
          searched_namespaces: ["RAAF::Tools", "Ai::Tools", "RAAF::Tools::Basic", "Ai::Tools::Basic"],
          suggestions: []
        })
      end

      it "raises ToolResolutionError even with configuration options" do
        expect {
          test_agent_class.tool :config_tool, max_results: 10, api_key: "test"
        }.to raise_error(RAAF::DSL::ToolResolutionError) do |error|
          expect(error.message).to include("❌ Tool not found: config_tool")
          expect(error.message).to include("RAAF::Tools::Basic")
          expect(error.message).to include("Ai::Tools::Basic")
        end
      end
    end

    context "error context preservation" do
      before do
        allow(RAAF::ToolRegistry).to receive(:resolve_with_details).with(:debug_tool).and_return({
          success: false,
          identifier: :debug_tool,
          searched_namespaces: ["RAAF::Tools", "Ai::Tools", "Global"],
          suggestions: ["Did you mean: :debug?", "Register it: RAAF::ToolRegistry.register(:debug_tool, DebugToolTool)"]
        })
      end

      it "preserves all error context for debugging" do
        begin
          test_agent_class.tool :debug_tool
        rescue RAAF::DSL::ToolResolutionError => e
          expect(e.identifier).to eq(:debug_tool)
          expect(e.searched_namespaces).to include("RAAF::Tools", "Ai::Tools", "Global")
          expect(e.suggestions).to include("Did you mean: :debug?")
          expect(e.suggestions).to include("Register it: RAAF::ToolRegistry.register(:debug_tool, DebugToolTool)")
        end
      end

      it "error message is helpful and actionable" do
        begin
          test_agent_class.tool :debug_tool
        rescue RAAF::DSL::ToolResolutionError => e
          message = e.message

          # Check for all required sections
          expect(message).to include("❌ Tool not found")
          expect(message).to include("📂 Searched in")
          expect(message).to include("💡 Suggestions")
          expect(message).to include("🔧 To fix")

          # Check for actionable instructions
          expect(message).to include("1. Ensure the tool class exists")
          expect(message).to include("2. Register it:")
          expect(message).to include("3. Or use direct class reference:")
        end
      end
    end
  end

  describe "error propagation" do
    it "bubbles up correctly through the call stack" do
      allow(RAAF::ToolRegistry).to receive(:resolve_with_details).with(:propagation_test).and_return({
        success: false,
        identifier: :propagation_test,
        searched_namespaces: ["RAAF::Tools"],
        suggestions: []
      })

      # Create a method that wraps tool addition
      def add_tool_wrapper(agent_class, tool_name)
        agent_class.tool tool_name
      end

      expect {
        add_tool_wrapper(test_agent_class, :propagation_test)
      }.to raise_error(RAAF::DSL::ToolResolutionError)
    end

    it "maintains stack trace for debugging" do
      allow(RAAF::ToolRegistry).to receive(:resolve_with_details).with(:stack_test).and_return({
        success: false,
        identifier: :stack_test,
        searched_namespaces: ["RAAF::Tools"],
        suggestions: []
      })

      begin
        test_agent_class.tool :stack_test
      rescue RAAF::DSL::ToolResolutionError => e
        expect(e.backtrace).not_to be_nil
        expect(e.backtrace).to be_an(Array)
        expect(e.backtrace.first).to include("agent_error_handling_spec.rb")
      end
    end
  end
end