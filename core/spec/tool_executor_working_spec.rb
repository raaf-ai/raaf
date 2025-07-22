# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Execution::ToolExecutor, "Working Enhanced Coverage" do
  let(:agent) { create_test_agent(name: "WorkingToolAgent") }
  let(:runner) { instance_double(RAAF::Runner) }
  let(:tool_executor) { described_class.new(agent, runner) }
  let(:context_wrapper) { instance_double(RAAF::RunContextWrapper) }
  let(:conversation) { [{ role: "user", content: "Test tools" }] }

  before do
    # Simple calculator tool
    def calculator(operation, a, b)
      case operation
      when "add"
        a + b
      when "multiply"
        a * b
      when "divide"
        return "Cannot divide by zero" if b == 0
        a.to_f / b
      else
        "Unknown operation: #{operation}"
      end
    end

    # Data format tool
    def format_data(format, value)
      case format
      when "upper"
        value.to_s.upcase
      when "lower"
        value.to_s.downcase
      when "json"
        { formatted: value, timestamp: Time.now.to_i }
      else
        value.to_s
      end
    end

    agent.add_tool(method(:calculator))
    agent.add_tool(method(:format_data))

    # Mock runner methods with proper return values
    allow(runner).to receive(:call_hook)
    allow(runner).to receive(:execute_tool) do |name, args, agent_obj, context|
      case name
      when "calculator"
        calculator(args[:operation], args[:a], args[:b])
      when "format_data" 
        format_data(args[:format], args[:value])
      else
        "Tool not found: #{name}"
      end
    end
  end

  describe "core tool execution functionality" do
    context "with basic mathematical operations" do
      let(:add_tool_call) do
        {
          "id" => "call_add",
          "type" => "function",
          "function" => {
            "name" => "calculator",
            "arguments" => '{"operation": "add", "a": 10, "b": 20}'
          }
        }
      end

      it "executes addition correctly" do
        result = tool_executor.execute_tool_calls([add_tool_call], conversation, context_wrapper, {})

        expect(result).to be true
        expect(conversation.size).to eq(2)
        expect(conversation.last[:role]).to eq("tool")
        expect(conversation.last[:content]).to eq("30")
        expect(conversation.last[:tool_call_id]).to eq("call_add")
      end

      it "handles multiplication" do
        multiply_call = {
          "id" => "call_mult",
          "type" => "function",
          "function" => {
            "name" => "calculator", 
            "arguments" => '{"operation": "multiply", "a": 6, "b": 7}'
          }
        }

        tool_executor.execute_tool_calls([multiply_call], conversation, context_wrapper, {})

        expect(conversation.last[:content]).to eq("42")
      end

      it "handles division by zero gracefully" do
        divide_call = {
          "id" => "call_div_zero",
          "type" => "function",
          "function" => {
            "name" => "calculator",
            "arguments" => '{"operation": "divide", "a": 10, "b": 0}'
          }
        }

        tool_executor.execute_tool_calls([divide_call], conversation, context_wrapper, {})

        expect(conversation.last[:content]).to eq("Cannot divide by zero")
      end

      it "handles unknown operations" do
        unknown_call = {
          "id" => "call_unknown",
          "type" => "function", 
          "function" => {
            "name" => "calculator",
            "arguments" => '{"operation": "power", "a": 2, "b": 3}'
          }
        }

        tool_executor.execute_tool_calls([unknown_call], conversation, context_wrapper, {})

        expect(conversation.last[:content]).to eq("Unknown operation: power")
      end
    end

    context "with data formatting operations" do
      it "formats text to uppercase" do
        upper_call = {
          "id" => "call_upper",
          "type" => "function",
          "function" => {
            "name" => "format_data",
            "arguments" => '{"format": "upper", "value": "hello world"}'
          }
        }

        tool_executor.execute_tool_calls([upper_call], conversation, context_wrapper, {})

        expect(conversation.last[:content]).to eq("HELLO WORLD")
      end

      it "formats text to lowercase" do
        lower_call = {
          "id" => "call_lower",
          "type" => "function",
          "function" => {
            "name" => "format_data", 
            "arguments" => '{"format": "lower", "value": "HELLO WORLD"}'
          }
        }

        tool_executor.execute_tool_calls([lower_call], conversation, context_wrapper, {})

        expect(conversation.last[:content]).to eq("hello world")
      end

      it "formats data as JSON" do
        json_call = {
          "id" => "call_json",
          "type" => "function",
          "function" => {
            "name" => "format_data",
            "arguments" => '{"format": "json", "value": "test data"}'
          }
        }

        tool_executor.execute_tool_calls([json_call], conversation, context_wrapper, {})

        result_content = conversation.last[:content]
        expect(result_content).to include("formatted")
        expect(result_content).to include("test data")
        expect(result_content).to include("timestamp")
      end

      it "handles default formatting" do
        default_call = {
          "id" => "call_default",
          "type" => "function",
          "function" => {
            "name" => "format_data",
            "arguments" => '{"format": "unknown", "value": 123}'
          }
        }

        tool_executor.execute_tool_calls([default_call], conversation, context_wrapper, {})

        expect(conversation.last[:content]).to eq("123")
      end
    end

    context "with multiple tool calls in sequence" do
      it "executes multiple tools correctly" do
        multiple_calls = [
          {
            "id" => "call_1",
            "type" => "function",
            "function" => {
              "name" => "calculator",
              "arguments" => '{"operation": "add", "a": 5, "b": 5}'
            }
          },
          {
            "id" => "call_2",
            "type" => "function",
            "function" => {
              "name" => "format_data",
              "arguments" => '{"format": "upper", "value": "result"}'
            }
          }
        ]

        original_size = conversation.size
        tool_executor.execute_tool_calls(multiple_calls, conversation, context_wrapper, {})

        expect(conversation.size).to eq(original_size + 2)
        expect(conversation[-2][:content]).to eq("10")  # Calculator result
        expect(conversation[-1][:content]).to eq("RESULT")  # Format result
      end

      it "continues execution even when one tool has JSON parsing error" do
        mixed_calls = [
          {
            "id" => "call_success",
            "type" => "function", 
            "function" => {
              "name" => "calculator",
              "arguments" => '{"operation": "multiply", "a": 3, "b": 4}'
            }
          },
          {
            "id" => "call_json_error",
            "type" => "function",
            "function" => {
              "name" => "format_data",
              "arguments" => '{"format": "upper", "value":'  # Invalid JSON
            }
          },
          {
            "id" => "call_success_2", 
            "type" => "function",
            "function" => {
              "name" => "format_data",
              "arguments" => '{"format": "lower", "value": "SUCCESS"}'
            }
          }
        ]

        tool_executor.execute_tool_calls(mixed_calls, conversation, context_wrapper, {})

        expect(conversation.size).to eq(4) # Original + 3 results
        expect(conversation[-3][:content]).to eq("12")  # First success
        expect(conversation[-2][:content]).to include("Failed to parse tool arguments")  # JSON error
        expect(conversation[-1][:content]).to eq("success")  # Second success
      end
    end

    context "with error handling scenarios" do
      it "handles runtime errors during tool execution" do
        allow(runner).to receive(:execute_tool).and_raise(RuntimeError, "Tool crashed")

        error_call = {
          "id" => "call_error",
          "type" => "function",
          "function" => {
            "name" => "calculator", 
            "arguments" => '{"operation": "add", "a": 1, "b": 2}'
          }
        }

        tool_executor.execute_tool_calls([error_call], conversation, context_wrapper, {})

        expect(conversation.last[:role]).to eq("tool")
        expect(conversation.last[:content]).to include("Tool execution failed")
        expect(conversation.last[:content]).to include("Tool crashed")
      end

      it "handles argument errors during tool execution" do
        allow(runner).to receive(:execute_tool).and_raise(ArgumentError, "Invalid arguments provided")

        arg_error_call = {
          "id" => "call_arg_error",
          "type" => "function", 
          "function" => {
            "name" => "format_data",
            "arguments" => '{"format": "upper", "value": "test"}'
          }
        }

        tool_executor.execute_tool_calls([arg_error_call], conversation, context_wrapper, {})

        expect(conversation.last[:content]).to include("Tool execution failed")
        expect(conversation.last[:content]).to include("Invalid arguments provided")
      end
    end

    context "with hook integration" do
      it "calls tool start and end hooks" do
        tool_call = {
          "id" => "hook_test",
          "type" => "function",
          "function" => {
            "name" => "calculator",
            "arguments" => '{"operation": "add", "a": 1, "b": 1}'
          }
        }

        expect(runner).to receive(:call_hook).with(:on_tool_start, context_wrapper, "calculator")
        expect(runner).to receive(:call_hook).with(:on_tool_end, context_wrapper, "calculator", 2)

        tool_executor.execute_tool_calls([tool_call], conversation, context_wrapper, {})
      end

      it "calls tool end hook even after execution failure" do
        allow(runner).to receive(:execute_tool).and_raise(StandardError, "Tool failed")

        error_call = {
          "id" => "hook_error_test",
          "type" => "function",
          "function" => {
            "name" => "format_data",
            "arguments" => '{"format": "upper", "value": "test"}'
          }
        }

        expect(runner).to receive(:call_hook).with(:on_tool_start, anything, "format_data")
        expect(runner).to receive(:call_hook).with(:on_tool_error, anything, "format_data", anything)

        tool_executor.execute_tool_calls([error_call], conversation, context_wrapper, {})
      end
    end
  end

  describe "tool wrapper functionality" do
    it "executes tools through wrapper block when provided" do
      wrapper_call = {
        "id" => "wrapper_test",
        "type" => "function",
        "function" => {
          "name" => "format_data",
          "arguments" => '{"format": "upper", "value": "hello"}'
        }
      }

      wrapper_called = false
      wrapper_block = proc do |func_name, args, &tool_execution|
        wrapper_called = true
        expect(func_name).to eq("format_data")
        expect(args).to eq({ format: "upper", value: "hello" })

        original_result = tool_execution.call
        "Wrapped: #{original_result}"
      end

      tool_executor.execute_tool_calls([wrapper_call], conversation, context_wrapper, {}, &wrapper_block)

      expect(wrapper_called).to be true
      expect(conversation.last[:content]).to eq("Wrapped: HELLO")
    end

    it "allows wrapper to intercept and modify errors" do
      allow(runner).to receive(:execute_tool).and_raise(StandardError, "Original error")

      error_wrapper_call = {
        "id" => "error_wrapper_test", 
        "type" => "function",
        "function" => {
          "name" => "calculator",
          "arguments" => '{"operation": "add", "a": 1, "b": 1}'
        }
      }

      wrapper_block = proc do |func_name, args, &tool_execution|
        begin
          tool_execution.call
        rescue StandardError => e
          "Wrapper intercepted: #{e.message}"
        end
      end

      tool_executor.execute_tool_calls([error_wrapper_call], conversation, context_wrapper, {}, &wrapper_block)

      expect(conversation.last[:content]).to eq("Wrapper intercepted: Original error")
    end
  end

  describe "edge cases and data handling" do
    context "with special data types" do
      it "handles nil values correctly" do
        allow(runner).to receive(:execute_tool).and_return(nil)

        nil_call = {
          "id" => "nil_test",
          "type" => "function", 
          "function" => {
            "name" => "format_data",
            "arguments" => '{"format": "upper", "value": "test"}'
          }
        }

        tool_executor.execute_tool_calls([nil_call], conversation, context_wrapper, {})

        expect(conversation.last[:content]).to eq("")
      end

      it "handles empty string values" do
        allow(runner).to receive(:execute_tool).and_return("")

        empty_call = {
          "id" => "empty_test",
          "type" => "function",
          "function" => {
            "name" => "format_data",
            "arguments" => '{"format": "upper", "value": "test"}'
          }
        }

        tool_executor.execute_tool_calls([empty_call], conversation, context_wrapper, {})

        expect(conversation.last[:content]).to eq("")
      end

      it "handles complex hash return values" do
        complex_hash = { status: "success", data: [1, 2, 3], nested: { key: "value" } }
        allow(runner).to receive(:execute_tool).and_return(complex_hash)

        hash_call = {
          "id" => "hash_test",
          "type" => "function",
          "function" => {
            "name" => "format_data", 
            "arguments" => '{"format": "json", "value": "test"}'
          }
        }

        tool_executor.execute_tool_calls([hash_call], conversation, context_wrapper, {})

        result_content = conversation.last[:content]
        expect(result_content).to include("status")
        expect(result_content).to include("success")
        expect(result_content).to include("data")
      end
    end

    context "with large data handling" do
      it "handles reasonably large argument payloads efficiently" do
        medium_data = "x" * 1000  # 1KB of data
        large_arg_call = {
          "id" => "large_test",
          "type" => "function",
          "function" => {
            "name" => "format_data",
            "arguments" => "{\"format\": \"upper\", \"value\": \"#{medium_data}\"}"
          }
        }

        start_time = Time.now
        tool_executor.execute_tool_calls([large_arg_call], conversation, context_wrapper, {})
        duration = Time.now - start_time

        expect(duration).to be < 0.1  # Should complete quickly
        expect(conversation.last[:content]).to eq(medium_data.upcase)
      end

      it "handles unicode characters in arguments" do
        unicode_call = {
          "id" => "unicode_test",
          "type" => "function",
          "function" => {
            "name" => "format_data",
            "arguments" => '{"format": "upper", "value": "Hello 🌍 こんにちは"}'
          }
        }

        tool_executor.execute_tool_calls([unicode_call], conversation, context_wrapper, {})

        expect(conversation.last[:content]).to eq("HELLO 🌍 こんにちは")
      end
    end
  end
end