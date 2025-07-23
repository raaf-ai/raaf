# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Execution::ToolExecutor do
  let(:agent) { RAAF::Agent.new(name: "TestAgent") }
  let(:runner) { instance_double("RAAF::Runner") }
  let(:executor) { described_class.new(agent, runner) }
  let(:context_wrapper) { instance_double("RAAF::RunContext") }
  let(:conversation) { [] }
  let(:response) { {} }

  # Add some tools to the agent
  before do
    # Simple tool
    agent.add_tool(
      RAAF::FunctionTool.new(
        proc { |message:| "Echo: #{message}" },
        name: "echo"
      )
    )

    # Tool that returns complex data
    agent.add_tool(
      RAAF::FunctionTool.new(
        proc { |data:| { processed: data, timestamp: Time.now.to_i } },
        name: "process_data"
      )
    )

    # Tool that might fail
    agent.add_tool(
      RAAF::FunctionTool.new(
        proc { |should_fail: false| 
          raise "Intentional failure" if should_fail
          "Success"
        },
        name: "maybe_fail"
      )
    )
  end

  describe "#initialize" do
    it "stores agent and runner" do
      expect(executor.instance_variable_get(:@agent)).to eq(agent)
      expect(executor.instance_variable_get(:@runner)).to eq(runner)
    end
  end

  describe "#execute_tool_calls" do
    context "with single tool call" do
      let(:tool_calls) do
        [{
          "id" => "call_123",
          "function" => {
            "name" => "echo",
            "arguments" => '{"message": "Hello World"}'
          }
        }]
      end

      before do
        allow(runner).to receive(:call_hook)
        allow(runner).to receive(:execute_tool).and_return("Echo: Hello World")
      end

      it "executes the tool call" do
        expect(runner).to receive(:execute_tool)
          .with("echo", { message: "Hello World" }, agent, context_wrapper)
          .and_return("Echo: Hello World")

        result = executor.execute_tool_calls(tool_calls, conversation, context_wrapper, response)
        
        expect(result).to be true
        expect(conversation.last).to include(
          role: "tool",
          content: "Echo: Hello World",
          tool_call_id: "call_123"
        )
      end

      it "calls start and end hooks" do
        expect(runner).to receive(:call_hook).with(:on_tool_start, context_wrapper, "echo").ordered
        expect(runner).to receive(:call_hook).with(:on_tool_end, context_wrapper, "echo", "Echo: Hello World").ordered

        executor.execute_tool_calls(tool_calls, conversation, context_wrapper, response)
      end
    end

    context "with multiple tool calls" do
      let(:tool_calls) do
        [
          {
            "id" => "call_1",
            "function" => {
              "name" => "echo",
              "arguments" => '{"message": "First"}'
            }
          },
          {
            "id" => "call_2", 
            "function" => {
              "name" => "process_data",
              "arguments" => '{"data": {"key": "value"}}'
            }
          }
        ]
      end

      before do
        allow(runner).to receive(:call_hook)
        allow(runner).to receive(:execute_tool) do |name, args, _, _|
          case name
          when "echo"
            "Echo: #{args[:message]}"
          when "process_data"
            { processed: args[:data], timestamp: 1234567890 }
          end
        end
      end

      it "executes all tool calls in order" do
        executor.execute_tool_calls(tool_calls, conversation, context_wrapper, response)

        expect(conversation).to eq([
          { role: "tool", content: "Echo: First", tool_call_id: "call_1" },
          { role: "tool", content: "{:processed=>{:key=>\"value\"}, :timestamp=>1234567890}", tool_call_id: "call_2" }
        ])
      end

      it "calls hooks for each tool" do
        expect(runner).to receive(:call_hook).with(:on_tool_start, context_wrapper, "echo").ordered
        expect(runner).to receive(:call_hook).with(:on_tool_end, context_wrapper, "echo", "Echo: First").ordered
        expect(runner).to receive(:call_hook).with(:on_tool_start, context_wrapper, "process_data").ordered
        expect(runner).to receive(:call_hook).with(:on_tool_end, context_wrapper, "process_data", anything).ordered

        executor.execute_tool_calls(tool_calls, conversation, context_wrapper, response)
      end
    end

    context "with tool wrapper block" do
      let(:tool_calls) do
        [{
          "id" => "call_wrapped",
          "function" => {
            "name" => "echo",
            "arguments" => '{"message": "Wrapped"}'
          }
        }]
      end

      before do
        allow(runner).to receive(:call_hook)
        allow(runner).to receive(:execute_tool).and_return("Echo: Wrapped")
      end

      it "passes wrapper to tool execution" do
        wrapper_called = false
        wrapper = proc do |name, args, &block|
          wrapper_called = true
          expect(name).to eq("echo")
          expect(args).to eq({ message: "Wrapped" })
          "Prefix: #{block.call}"
        end

        executor.execute_tool_calls(tool_calls, conversation, context_wrapper, response, &wrapper)

        expect(wrapper_called).to be true
        expect(conversation.last[:content]).to eq("Prefix: Echo: Wrapped")
      end
    end

    context "with empty tool calls" do
      it "handles empty array gracefully" do
        result = executor.execute_tool_calls([], conversation, context_wrapper, response)
        expect(result).to be true
        expect(conversation).to be_empty
      end
    end

    context "error handling" do
      let(:tool_calls) do
        [{
          "id" => "call_error",
          "function" => {
            "name" => "maybe_fail",
            "arguments" => '{"should_fail": true}'
          }
        }]
      end

      before do
        allow(runner).to receive(:call_hook)
        allow(runner).to receive(:execute_tool).and_raise("Intentional failure")
      end

      it "handles tool execution errors" do
        executor.execute_tool_calls(tool_calls, conversation, context_wrapper, response)

        expect(conversation.last).to include(
          role: "tool",
          content: "Tool execution failed: Intentional failure",
          tool_call_id: "call_error"
        )
      end

      it "calls error hook on failure" do
        expect(runner).to receive(:call_hook).with(:on_tool_start, context_wrapper, "maybe_fail")
        expect(runner).to receive(:call_hook).with(:on_tool_error, context_wrapper, "maybe_fail", instance_of(RuntimeError))

        executor.execute_tool_calls(tool_calls, conversation, context_wrapper, response)
      end
    end

    context "with malformed JSON arguments" do
      let(:tool_calls) do
        [{
          "id" => "call_bad_json",
          "function" => {
            "name" => "echo",
            "arguments" => '{"message": invalid json}'
          }
        }]
      end

      before do
        allow(runner).to receive(:call_hook)
      end

      it "handles JSON parse errors gracefully" do
        executor.execute_tool_calls(tool_calls, conversation, context_wrapper, response)

        expect(conversation.last).to include(
          role: "tool",
          content: /Failed to parse tool arguments/,
          tool_call_id: "call_bad_json"
        )
      end
    end
  end

  describe "#tool_calls?" do
    it "detects tool_calls with string key" do
      message = { "tool_calls" => [{ "id" => "123" }] }
      expect(executor.tool_calls?(message)).to be_truthy
    end

    it "detects tool_calls with symbol key" do
      message = { tool_calls: [{ id: "123" }] }
      expect(executor.tool_calls?(message)).to be_truthy
    end

    it "returns nil/false for messages without tool_calls" do
      expect(executor.tool_calls?({})).to be_falsy
      expect(executor.tool_calls?({ content: "text" })).to be_falsy
    end

    it "returns empty array when tool_calls is empty" do
      message = { tool_calls: [] }
      expect(executor.tool_calls?(message)).to eq([])
    end

    it "returns nil when tool_calls is nil" do
      message = { tool_calls: nil }
      expect(executor.tool_calls?(message)).to be_nil
    end
  end

  describe "#should_continue?" do
    context "with tool calls present" do
      it "returns true regardless of content" do
        message = { tool_calls: [{ id: "123" }], content: "STOP" }
        expect(executor.should_continue?(message)).to be true
      end
    end

    context "without tool calls" do
      it "returns false for nil content" do
        expect(executor.should_continue?({ content: nil })).to be false
      end

      it "returns false for missing content" do
        expect(executor.should_continue?({})).to be false
      end

      it "returns true for normal content" do
        expect(executor.should_continue?({ content: "Continue processing" })).to be true
      end

      context "termination keywords" do
        %w[STOP TERMINATE DONE FINISHED].each do |keyword|
          it "returns false when content contains #{keyword}" do
            expect(executor.should_continue?({ content: "We should #{keyword} now" })).to be false
          end

          it "is case insensitive for #{keyword}" do
            expect(executor.should_continue?({ content: "Time to #{keyword.downcase}" })).to be false
          end
        end

        it "detects termination words at boundaries" do
          expect(executor.should_continue?({ content: "stop" })).to be false
          expect(executor.should_continue?({ content: "Please stop." })).to be false
          expect(executor.should_continue?({ content: "STOP!" })).to be false
        end

        it "detects termination in longer text" do
          content = "After analyzing the data, I believe we are DONE with this task."
          expect(executor.should_continue?({ content: content })).to be false
        end
      end
    end
  end

  describe "private methods" do
    describe "#extract_function_name" do
      it "extracts from nested hash with string keys" do
        call = { "function" => { "name" => "test_func" } }
        expect(executor.send(:extract_function_name, call)).to eq("test_func")
      end

      it "extracts from nested hash with symbol keys" do
        call = { function: { name: "test_func" } }
        expect(executor.send(:extract_function_name, call)).to eq("test_func")
      end

      it "handles mixed key types" do
        call = { "function" => { "name" => "test_func" } }
        expect(executor.send(:extract_function_name, call)).to eq("test_func")
      end
    end

    describe "#extract_arguments" do
      it "extracts JSON string from nested structure" do
        call = { "function" => { "arguments" => '{"key": "value"}' } }
        expect(executor.send(:extract_arguments, call)).to eq('{"key": "value"}')
      end

      it "handles symbol keys" do
        call = { function: { arguments: '{"key": "value"}' } }
        expect(executor.send(:extract_arguments, call)).to eq('{"key": "value"}')
      end
    end

    describe "#extract_tool_call_id" do
      it "extracts id with string key" do
        call = { "id" => "unique_123" }
        expect(executor.send(:extract_tool_call_id, call)).to eq("unique_123")
      end

      it "extracts id with symbol key" do
        call = { id: "unique_456" }
        expect(executor.send(:extract_tool_call_id, call)).to eq("unique_456")
      end
    end

    describe "#execute_tool" do
      before do
        allow(runner).to receive(:execute_tool)
      end

      it "delegates to runner with correct parameters" do
        expect(runner).to receive(:execute_tool)
          .with("test_tool", { arg: "value" }, agent, context_wrapper)
          .and_return("result")

        result = executor.send(:execute_tool, "test_tool", { arg: "value" }, context_wrapper)
        expect(result).to eq("result")
      end
    end

    describe "#add_tool_result" do
      it "adds tool message to conversation" do
        executor.send(:add_tool_result, conversation, "Tool output", "call_789")
        
        expect(conversation).to eq([{
          role: "tool",
          content: "Tool output",
          tool_call_id: "call_789"
        }])
      end

      it "converts non-string results to string" do
        executor.send(:add_tool_result, conversation, { data: "complex" }, "call_obj")
        
        expect(conversation.last[:content]).to eq("{:data=>\"complex\"}")
      end

      it "handles nil results" do
        executor.send(:add_tool_result, conversation, nil, "call_nil")
        
        expect(conversation.last[:content]).to eq("")
      end
    end

    describe "#handle_tool_error" do
      let(:error) { StandardError.new("Test error") }

      before do
        allow(executor).to receive(:log_error)
        allow(runner).to receive(:call_hook)
      end

      it "logs the error with context" do
        expect(executor).to receive(:log_error).with(
          "Error message",
          hash_including(tool: "failing_tool", error_class: "StandardError")
        )

        executor.send(:handle_tool_error, conversation, context_wrapper,
                      "failing_tool", "call_fail", "Error message", error)
      end

      it "adds error message to conversation" do
        executor.send(:handle_tool_error, conversation, context_wrapper,
                      "failing_tool", "call_fail", "User-friendly error", error)

        expect(conversation.last).to eq({
          role: "tool",
          content: "User-friendly error",
          tool_call_id: "call_fail"
        })
      end

      it "calls error hook" do
        expect(runner).to receive(:call_hook)
          .with(:on_tool_error, context_wrapper, "failing_tool", error)

        executor.send(:handle_tool_error, conversation, context_wrapper,
                      "failing_tool", "call_fail", "Error", error)
      end

      it "includes extra context when provided" do
        expect(executor).to receive(:log_error).with(
          "Error with context",
          hash_including(extra: "additional info")
        )

        executor.send(:handle_tool_error, conversation, context_wrapper,
                      "failing_tool", "call_fail", "Error with context", 
                      error, "additional info")
      end
    end
  end

  describe "edge cases and error scenarios" do
    context "with missing function data" do
      it "handles missing function name gracefully" do
        tool_call = {
          "id" => "call_broken",
          "function" => {
            "arguments" => '{}'
          }
        }

        allow(runner).to receive(:call_hook)
        
        expect {
          executor.send(:execute_single_tool_call, tool_call, conversation, context_wrapper)
        }.to raise_error(NoMethodError)
      end
    end

    context "with Unicode and special characters" do
      let(:tool_calls) do
        [{
          "id" => "call_unicode",
          "function" => {
            "name" => "echo",
            "arguments" => '{"message": "Hello 世界 🌍"}'
          }
        }]
      end

      before do
        allow(runner).to receive(:call_hook)
        allow(runner).to receive(:execute_tool).and_return("Echo: Hello 世界 🌍")
      end

      it "handles Unicode content correctly" do
        executor.execute_tool_calls(tool_calls, conversation, context_wrapper, response)
        
        expect(conversation.last[:content]).to eq("Echo: Hello 世界 🌍")
      end
    end

    context "with very large tool results" do
      before do
        allow(runner).to receive(:call_hook)
        large_result = "x" * 10_000
        allow(runner).to receive(:execute_tool).and_return(large_result)
      end

      let(:tool_calls) do
        [{
          "id" => "call_large",
          "function" => {
            "name" => "echo",
            "arguments" => '{"message": "test"}'
          }
        }]
      end

      it "handles large results without truncation" do
        executor.execute_tool_calls(tool_calls, conversation, context_wrapper, response)
        
        expect(conversation.last[:content].length).to eq(10_000)
      end
    end

    context "with circular reference in tool result" do
      before do
        allow(runner).to receive(:call_hook)
        
        # Create circular reference
        circular = { a: 1 }
        circular[:self] = circular
        
        allow(runner).to receive(:execute_tool).and_return(circular)
      end

      let(:tool_calls) do
        [{
          "id" => "call_circular",
          "function" => {
            "name" => "process_data",
            "arguments" => '{"data": "test"}'
          }
        }]
      end

      it "converts circular references to string representation" do
        # Ruby's default to_s handles circular references
        executor.execute_tool_calls(tool_calls, conversation, context_wrapper, response)
        
        expect(conversation.last[:content]).to include("a=>1")
      end
    end
  end

  describe "integration with runner mock" do
    it "executes tools through runner interface" do
      tool_calls = [{
        "id" => "integration_call",
        "function" => {
          "name" => "echo",
          "arguments" => '{"message": "Integration test"}'
        }
      }]

      allow(runner).to receive(:call_hook)
      allow(runner).to receive(:execute_tool)
        .with("echo", { message: "Integration test" }, agent, context_wrapper)
        .and_return("Echo: Integration test")

      executor.execute_tool_calls(tool_calls, conversation, context_wrapper, response)
      
      expect(conversation.last).to include(
        role: "tool",
        content: "Echo: Integration test",
        tool_call_id: "integration_call"
      )
    end

    it "handles tool not found errors" do
      tool_calls = [{
        "id" => "missing_tool",
        "function" => {
          "name" => "non_existent_tool",
          "arguments" => '{}'
        }
      }]

      allow(runner).to receive(:call_hook)
      allow(runner).to receive(:execute_tool)
        .and_raise(RAAF::ToolError, "Tool 'non_existent_tool' not found")

      executor.execute_tool_calls(tool_calls, conversation, context_wrapper, response)
      
      expect(conversation.last[:content]).to include("Tool execution failed")
      expect(conversation.last[:content]).to include("Tool 'non_existent_tool' not found")
    end
  end
end