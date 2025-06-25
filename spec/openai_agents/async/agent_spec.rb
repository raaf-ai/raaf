# frozen_string_literal: true

require "spec_helper"
require "async"
require "openai_agents/async"

RSpec.describe OpenAIAgents::Async::Agent do
  let(:agent) { described_class.new(name: "AsyncAgent") }

  describe "#initialize" do
    it "inherits from base Agent class" do
      expect(agent).to be_a(OpenAIAgents::Agent)
    end

    it "includes Async::Base module" do
      expect(agent.class.ancestors).to include(OpenAIAgents::Async::Base)
    end
  end

  describe "#execute_tool_async" do
    let(:sync_tool) do
      OpenAIAgents::FunctionTool.new(
        proc { |value:| value * 2 },
        name: "double",
        description: "Doubles a number"
      )
    end

    let(:async_tool) do
      OpenAIAgents::Async::Agent::AsyncFunctionTool.new(
        proc { |value:| value * 3 },
        name: "triple",
        async: true
      )
    end

    before do
      agent.add_tool(sync_tool)
      agent.add_tool(async_tool)
    end

    it "executes synchronous tools asynchronously" do
      Async do
        result = agent.execute_tool_async("double", value: 5).wait
        expect(result).to eq(10)
      end
    end

    it "executes async tools directly" do
      Async do
        result = agent.execute_tool_async("triple", value: 4).wait
        expect(result).to eq(12)
      end
    end

    it "raises error for non-existent tools" do
      expect do
        agent.execute_tool_async("nonexistent")
      end.to raise_error(OpenAIAgents::ToolError, /Tool 'nonexistent' not found/)
    end

    it "handles tool execution errors" do
      failing_tool = OpenAIAgents::FunctionTool.new(
        proc { raise StandardError, "Tool failed" },
        name: "failing_tool"
      )
      agent.add_tool(failing_tool)

      Async do
        expect do
          agent.execute_tool_async("failing_tool").wait
        end.to raise_error(StandardError, "Tool failed")
      end
    end
  end

  describe "#execute_tools_async" do
    let(:double_tool) do
      OpenAIAgents::FunctionTool.new(
        proc { |value:| value * 2 },
        name: "double"
      )
    end

    let(:add_tool) do
      OpenAIAgents::FunctionTool.new(
        proc { |a:, b:| a + b },
        name: "add"
      )
    end

    before do
      agent.add_tool(double_tool)
      agent.add_tool(add_tool)
    end

    it "executes multiple tools in parallel" do
      tool_calls = [
        { name: "double", arguments: { value: 5 } },
        { name: "add", arguments: { a: 3, b: 4 } }
      ]

      Async do
        results = agent.execute_tools_async(tool_calls).wait
        
        expect(results.size).to eq(2)
        expect(results[0][:name]).to eq("double")
        expect(results[0][:result]).to eq(10)
        expect(results[1][:name]).to eq("add")
        expect(results[1][:result]).to eq(7)
      end
    end

    it "handles errors in individual tools" do
      failing_tool = OpenAIAgents::FunctionTool.new(
        proc { raise StandardError, "Tool failed" },
        name: "failing_tool"
      )
      agent.add_tool(failing_tool)

      tool_calls = [
        { name: "double", arguments: { value: 5 } },
        { name: "failing_tool", arguments: {} }
      ]

      Async do
        results = agent.execute_tools_async(tool_calls).wait
        
        expect(results.size).to eq(2)
        expect(results[0][:result]).to eq(10)
        expect(results[1][:error]).to eq("Tool failed")
      end
    end

    it "accepts tool calls with string keys" do
      tool_calls = [
        { "name" => "double", "arguments" => { "value" => 5 } }
      ]

      Async do
        results = agent.execute_tools_async(tool_calls).wait
        expect(results.first[:result]).to eq(10)
      end
    end
  end

  describe "#add_tool" do
    it "wraps procs in AsyncFunctionTool" do
      tool_proc = proc { |x:| x * 2 }
      agent.add_tool(tool_proc)

      added_tool = agent.tools.first
      expect(added_tool).to be_a(OpenAIAgents::Async::Agent::AsyncFunctionTool)
    end

    it "wraps methods in AsyncFunctionTool" do
      def test_method(x:)
        x + 1
      end

      agent.add_tool(method(:test_method))
      added_tool = agent.tools.first
      expect(added_tool).to be_a(OpenAIAgents::Async::Agent::AsyncFunctionTool)
    end

    it "preserves existing FunctionTool objects" do
      existing_tool = OpenAIAgents::FunctionTool.new(proc { |x:| x })
      agent.add_tool(existing_tool)

      expect(agent.tools.first).to eq(existing_tool)
    end
  end

  describe "AsyncFunctionTool" do
    let(:sync_function) { proc { |value:| value * 2 } }
    let(:async_tool) { OpenAIAgents::Async::Agent::AsyncFunctionTool.new(sync_function) }

    describe "#initialize" do
      it "inherits from FunctionTool" do
        expect(async_tool).to be_a(OpenAIAgents::FunctionTool)
      end

      it "auto-detects async functions" do
        expect(async_tool.async).to be_falsy # sync function
      end

      it "accepts explicit async flag" do
        explicit_async_tool = OpenAIAgents::Async::Agent::AsyncFunctionTool.new(
          sync_function, 
          async: true
        )
        expect(explicit_async_tool.async).to be true
      end
    end

    describe "#call_async" do
      it "wraps synchronous functions in Async blocks" do
        Async do
          result = async_tool.call_async(value: 5).wait
          expect(result).to eq(10)
        end
      end

      it "calls async functions directly when marked as async" do
        async_function = proc { |value:| value * 3 }
        async_tool = OpenAIAgents::Async::Agent::AsyncFunctionTool.new(
          async_function, 
          async: true
        )

        Async do
          result = async_tool.call_async(value: 4).wait
          expect(result).to eq(12)
        end
      end
    end

    describe "#call" do
      it "falls back to synchronous execution outside async context" do
        result = async_tool.call(value: 6)
        expect(result).to eq(12)
      end

      it "uses async execution when in async context and tool is async" do
        async_function = proc { |value:| value * 3 }
        async_tool = OpenAIAgents::Async::Agent::AsyncFunctionTool.new(
          async_function,
          async: true
        )

        # Mock in_async_context? to return true
        allow(async_tool).to receive(:in_async_context?).and_return(true)
        allow(async_tool).to receive(:call_async).and_return(double(wait: 15))

        result = async_tool.call(value: 5)
        expect(result).to eq(15)
      end
    end

    describe "#to_h" do
      it "includes async flag in hash representation when async" do
        async_function = proc { |value:| value * 2 }
        async_tool = OpenAIAgents::Async::Agent::AsyncFunctionTool.new(
          async_function,
          async: true
        )

        hash = async_tool.to_h
        expect(hash[:async]).to be true
      end

      it "omits async flag when not async" do
        hash = async_tool.to_h
        expect(hash).not_to have_key(:async)
      end
    end
  end

  describe "integration with base Agent functionality" do
    it "maintains all base agent features" do
      expect(agent).to respond_to(:add_handoff)
      expect(agent).to respond_to(:can_handoff_to?)
      expect(agent).to respond_to(:tools?)
      expect(agent).to respond_to(:handoffs?)
    end

    it "can be used in handoff scenarios" do
      other_agent = described_class.new(name: "OtherAsyncAgent")
      agent.add_handoff(other_agent)

      expect(agent.can_handoff_to?("OtherAsyncAgent")).to be true
    end

    it "preserves agent configuration" do
      configured_agent = described_class.new(
        name: "ConfiguredAgent",
        instructions: "Custom instructions",
        model: "gpt-4",
        max_turns: 15
      )

      expect(configured_agent.name).to eq("ConfiguredAgent")
      expect(configured_agent.instructions).to eq("Custom instructions")
      expect(configured_agent.model).to eq("gpt-4")
      expect(configured_agent.max_turns).to eq(15)
    end
  end

  describe "error handling" do
    it "handles tool not found errors properly" do
      expect do
        agent.execute_tool_async("nonexistent_tool")
      end.to raise_error(OpenAIAgents::ToolError, /Tool 'nonexistent_tool' not found/)
    end

    it "propagates tool execution errors" do
      failing_tool = OpenAIAgents::FunctionTool.new(
        proc { raise ArgumentError, "Invalid argument" },
        name: "failing_tool"
      )
      agent.add_tool(failing_tool)

      Async do
        expect do
          agent.execute_tool_async("failing_tool").wait
        end.to raise_error(ArgumentError, "Invalid argument")
      end
    end
  end
end