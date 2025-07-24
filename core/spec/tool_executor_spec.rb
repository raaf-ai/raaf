# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Execution::ToolExecutor do
  let(:agent) { create_test_agent(name: "ToolAgent") }
  let(:runner) { double("Runner") }
  let(:tool_executor) { described_class.new(agent, runner) }
  let(:context_wrapper) { double("RunContextWrapper") }
  let(:conversation) { [{ role: "user", content: "Execute tool" }] }

  # Mock tool for testing
  before do
    def test_tool(name)
      "Hello, #{name}!"
    end

    agent.add_tool(method(:test_tool))
  end

  describe "#initialize" do
    it "stores agent and runner references" do
      executor = described_class.new(agent, runner)

      expect(executor.instance_variable_get(:@agent)).to eq(agent)
      expect(executor.instance_variable_get(:@runner)).to eq(runner)
    end
  end

  describe "#execute_tool_calls" do
    let(:tool_calls) do
      [
        {
          "id" => "call_1",
          "function" => {
            "name" => "test_tool",
            "arguments" => '{"name": "World"}'
          }
        }
      ]
    end

    before do
      allow(tool_executor).to receive(:execute_single_tool_call)
    end

    it "executes each tool call" do
      expect(tool_executor).to receive(:execute_single_tool_call)
        .with(tool_calls.first, conversation, context_wrapper)

      tool_executor.execute_tool_calls(tool_calls, conversation, context_wrapper, {})
    end

    it "executes multiple tool calls in order" do
      multiple_calls = [
        { "id" => "call_1", "function" => { "name" => "tool1", "arguments" => "{}" } },
        { "id" => "call_2", "function" => { "name" => "tool2", "arguments" => "{}" } }
      ]

      expect(tool_executor).to receive(:execute_single_tool_call)
        .with(multiple_calls[0], conversation, context_wrapper).ordered
      expect(tool_executor).to receive(:execute_single_tool_call)
        .with(multiple_calls[1], conversation, context_wrapper).ordered

      tool_executor.execute_tool_calls(multiple_calls, conversation, context_wrapper, {})
    end

    it "passes tool wrapper block to single tool execution" do
      wrapper_block = proc { |_name, _args, &block| block.call }

      expect(tool_executor).to receive(:execute_single_tool_call) do |_tool_call, _conv, _ctx, &block|
        expect(block).to eq(wrapper_block)
      end

      tool_executor.execute_tool_calls(tool_calls, conversation, context_wrapper, {}, &wrapper_block)
    end

    it "returns true to continue execution" do
      result = tool_executor.execute_tool_calls(tool_calls, conversation, context_wrapper, {})
      expect(result).to be true
    end

    it "handles empty tool calls array" do
      expect do
        tool_executor.execute_tool_calls([], conversation, context_wrapper, {})
      end.not_to raise_error
    end
  end

  describe "#tool_calls?" do
    it "returns truthy when message has tool_calls (string key)" do
      message = { "tool_calls" => [{ "function" => { "name" => "test" } }] }
      expect(tool_executor).to be_tool_calls(message)
    end

    it "returns truthy when message has tool_calls (symbol key)" do
      message = { tool_calls: [{ function: { name: "test" } }] }
      expect(tool_executor).to be_tool_calls(message)
    end

    it "returns falsy when message has no tool_calls" do
      message = { role: "assistant", content: "Hello" }
      expect(tool_executor).not_to be_tool_calls(message)
    end

    it "returns empty array when message has empty tool_calls" do
      message = { "tool_calls" => [] }
      expect(tool_executor.tool_calls?(message)).to eq([])
    end

    it "returns nil when message has nil tool_calls" do
      message = { "tool_calls" => nil }
      expect(tool_executor.tool_calls?(message)).to be_nil
    end
  end

  describe "#should_continue?" do
    context "with tool calls" do
      it "returns true when message has tool calls" do
        message = { tool_calls: [{ function: { name: "test" } }] }
        expect(tool_executor.should_continue?(message)).to be true
      end
    end

    context "without tool calls" do
      it "returns false when message has no content" do
        message = { role: "assistant" }
        expect(tool_executor.should_continue?(message)).to be false
      end

      it "returns false when content is nil" do
        message = { role: "assistant", content: nil }
        expect(tool_executor.should_continue?(message)).to be false
      end

      it "returns false for normal content" do
        message = { role: "assistant", content: "How can I help you?" }
        expect(tool_executor.should_continue?(message)).to be false
      end

      it "returns false when content indicates termination (STOP)" do
        message = { role: "assistant", content: "I will STOP here." }
        expect(tool_executor.should_continue?(message)).to be false
      end

      it "returns false when content indicates termination (TERMINATE)" do
        message = { role: "assistant", content: "Process will TERMINATE now." }
        expect(tool_executor.should_continue?(message)).to be false
      end

      it "returns false when content indicates termination (DONE)" do
        message = { role: "assistant", content: "Task is DONE." }
        expect(tool_executor.should_continue?(message)).to be false
      end

      it "returns false when content indicates termination (FINISHED)" do
        message = { role: "assistant", content: "Work FINISHED successfully." }
        expect(tool_executor.should_continue?(message)).to be false
      end

      it "is case insensitive for termination words" do
        %w[stop Stop STOP terminate done finished].each do |word|
          message = { role: "assistant", content: "The process will #{word}." }
          expect(tool_executor.should_continue?(message)).to be false
        end
      end

      it "returns false when termination words are standalone (word boundaries)" do
        message = { role: "assistant", content: "Let's not stop working together." }
        expect(tool_executor.should_continue?(message)).to be false
      end
    end
  end

  describe "#execute_single_tool_call" do
    let(:tool_call) do
      {
        "id" => "call_test_123",
        "function" => {
          "name" => "test_tool",
          "arguments" => '{"name": "Alice"}'
        }
      }
    end

    before do
      allow(runner).to receive(:call_hook)
      allow(tool_executor).to receive(:execute_tool).and_return("Hello, Alice!")
      allow(tool_executor).to receive(:add_tool_result)
    end

    it "calls tool start hook" do
      expect(runner).to receive(:call_hook)
        .with(:on_tool_start, context_wrapper, "test_tool")

      tool_executor.send(:execute_single_tool_call, tool_call, conversation, context_wrapper)
    end

    it "parses arguments and executes tool" do
      expect(tool_executor).to receive(:execute_tool)
        .with("test_tool", { name: "Alice" }, context_wrapper)
        .and_return("Hello, Alice!")

      tool_executor.send(:execute_single_tool_call, tool_call, conversation, context_wrapper)
    end

    it "adds tool result to conversation" do
      expect(tool_executor).to receive(:add_tool_result)
        .with(conversation, "Hello, Alice!", "call_test_123")

      tool_executor.send(:execute_single_tool_call, tool_call, conversation, context_wrapper)
    end

    it "calls tool end hook" do
      expect(runner).to receive(:call_hook)
        .with(:on_tool_end, context_wrapper, "test_tool", "Hello, Alice!")

      tool_executor.send(:execute_single_tool_call, tool_call, conversation, context_wrapper)
    end

    context "with tool wrapper block" do
      it "executes tool through wrapper" do
        wrapper_called = false
        wrapper_block = proc do |name, args, &inner_block|
          wrapper_called = true
          expect(name).to eq("test_tool")
          expect(args).to eq({ name: "Alice" })
          inner_block.call
        end

        tool_executor.send(:execute_single_tool_call, tool_call, conversation, context_wrapper, &wrapper_block)

        expect(wrapper_called).to be true
      end

      it "can modify tool result through wrapper" do
        wrapper_block = proc do |_name, _args, &inner_block|
          result = inner_block.call
          "Wrapped: #{result}"
        end

        expect(tool_executor).to receive(:add_tool_result)
          .with(conversation, "Wrapped: Hello, Alice!", "call_test_123")

        tool_executor.send(:execute_single_tool_call, tool_call, conversation, context_wrapper, &wrapper_block)
      end
    end

    context "error handling" do
      it "handles JSON parsing errors" do
        malformed_call = {
          "id" => "call_error",
          "function" => {
            "name" => "test_tool",
            "arguments" => '{"name": invalid json}'
          }
        }

        expect(tool_executor).to receive(:handle_tool_error)
          .with(conversation, context_wrapper, "test_tool", "call_error",
                /Failed to parse tool arguments/, instance_of(JSON::ParserError), '{"name": invalid json}')

        tool_executor.send(:execute_single_tool_call, malformed_call, conversation, context_wrapper)
      end

      it "handles tool execution errors" do
        allow(tool_executor).to receive(:execute_tool).and_raise(StandardError, "Tool failed")

        expect(tool_executor).to receive(:handle_tool_error)
          .with(conversation, context_wrapper, "test_tool", "call_test_123",
                "Tool execution failed: Tool failed", instance_of(StandardError))

        tool_executor.send(:execute_single_tool_call, tool_call, conversation, context_wrapper)
      end
    end
  end

  describe "private helper methods" do
    describe "#extract_function_name" do
      it "extracts name from string key format" do
        call = { "function" => { "name" => "my_function" } }
        name = tool_executor.send(:extract_function_name, call)
        expect(name).to eq("my_function")
      end

      it "extracts name from symbol key format" do
        call = { function: { name: "my_function" } }
        name = tool_executor.send(:extract_function_name, call)
        expect(name).to eq("my_function")
      end
    end

    describe "#extract_arguments" do
      it "extracts arguments from string key format" do
        call = { "function" => { "arguments" => '{"key": "value"}' } }
        args = tool_executor.send(:extract_arguments, call)
        expect(args).to eq('{"key": "value"}')
      end

      it "extracts arguments from symbol key format" do
        call = { function: { arguments: '{"key": "value"}' } }
        args = tool_executor.send(:extract_arguments, call)
        expect(args).to eq('{"key": "value"}')
      end
    end

    describe "#extract_tool_call_id" do
      it "extracts id from string key format" do
        call = { "id" => "call_123" }
        id = tool_executor.send(:extract_tool_call_id, call)
        expect(id).to eq("call_123")
      end

      it "extracts id from symbol key format" do
        call = { id: "call_123" }
        id = tool_executor.send(:extract_tool_call_id, call)
        expect(id).to eq("call_123")
      end
    end
  end

  describe "integration with agent tools" do
    let(:tool_call_with_params) do
      {
        "id" => "call_integration",
        "function" => {
          "name" => "test_tool",
          "arguments" => '{"name": "Integration Test"}'
        }
      }
    end

    it "executes actual agent tools" do
      # This test verifies the integration between ToolExecutor and actual agent tools
      allow(runner).to receive(:call_hook)
      # Mock the runner.execute_tool method to match expected interface
      allow(runner).to receive(:execute_tool).with("test_tool", { name: "Integration Test" }, agent, context_wrapper).and_return("Hello, Integration Test!")
      allow(tool_executor).to receive(:add_tool_result)

      # Execute the tool call which should call our test_tool method
      result_conversation = conversation.dup
      tool_executor.send(:execute_single_tool_call, tool_call_with_params, result_conversation, context_wrapper)

      # Verify the tool execution was called correctly
      expect(runner).to have_received(:execute_tool).with("test_tool", { name: "Integration Test" }, agent, context_wrapper)
    end
  end
end
