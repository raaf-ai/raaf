# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Execution::ToolExecutor, "Enhanced Coverage Tests" do
  let(:agent) { create_test_agent(name: "EnhancedToolAgent") }
  let(:runner) { instance_double(RAAF::Runner) }
  let(:tool_executor) { described_class.new(agent, runner) }
  let(:context_wrapper) { instance_double(RAAF::RunContextWrapper) }
  let(:conversation) { [{ role: "user", content: "Execute enhanced tools" }] }

  # Setup comprehensive tool collection
  before do
    # Basic calculation tool
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

    # Tool that can throw different types of errors
    def error_tool(error_type)
      case error_type
      when "runtime"
        raise RuntimeError, "Runtime error occurred"
      when "argument" 
        raise ArgumentError, "Invalid argument provided"
      when "type"
        raise TypeError, "Type mismatch error"
      when "timeout"
        sleep 10 # This would timeout in real scenarios
        "Should not reach here"
      else
        "No error triggered"
      end
    end

    # Tool that returns complex data structures
    def data_tool(format)
      case format
      when "hash"
        { status: "success", data: [1, 2, 3], metadata: { timestamp: Time.now.to_i } }
      when "array"
        ["item1", "item2", { nested: "value" }]
      when "string"
        "Simple string response"
      when "nil"
        nil
      when "empty"
        ""
      else
        { error: "Unknown format: #{format}" }
      end
    end

    # Tool with complex parameter validation
    def validation_tool(required_param, optional_param: "default", **kwargs)
      {
        required: required_param,
        optional: optional_param,
        extra_args: kwargs,
        total_params: [required_param, optional_param, kwargs].flatten.size
      }
    end

    agent.add_tool(method(:calculator))
    agent.add_tool(method(:error_tool))
    agent.add_tool(method(:data_tool))
    agent.add_tool(method(:validation_tool))

    # Mock runner methods
    allow(runner).to receive(:call_hook)
    allow(runner).to receive(:execute_tool) do |name, args, agent_obj, context|
      # Simulate the actual tool execution
      case name
      when "calculator"
        calculator(args[:operation], args[:a], args[:b])
      when "error_tool"
        error_tool(args[:error_type])
      when "data_tool"
        data_tool(args[:format])
      when "validation_tool"
        validation_tool(args[:required_param], **args.except(:required_param))
      else
        "Tool not found: #{name}"
      end
    end
  end

  describe "comprehensive tool execution scenarios" do
    context "with mathematical operations" do
      let(:tool_calls) do
        [
          {
            "id" => "call_math_1",
            "type" => "function",
            "function" => {
              "name" => "calculator",
              "arguments" => '{"operation": "add", "a": 15, "b": 25}'
            }
          }
        ]
      end

      it "executes mathematical operations correctly" do
        result = tool_executor.execute_tool_calls(tool_calls, conversation, context_wrapper, {})

        expect(result).to be true
        expect(conversation.size).to eq(2) # Original + tool result
        expect(conversation.last[:role]).to eq("tool")
        expect(conversation.last[:content]).to eq("40")
        expect(conversation.last[:tool_call_id]).to eq("call_math_1")
      end

      it "handles division by zero gracefully" do
        division_calls = [
          {
            "id" => "call_div_zero",
            "type" => "function", 
            "function" => {
              "name" => "calculator",
              "arguments" => '{"operation": "divide", "a": 10, "b": 0}'
            }
          }
        ]

        tool_executor.execute_tool_calls(division_calls, conversation, context_wrapper, {})

        expect(conversation.last[:content]).to eq("Cannot divide by zero")
      end

      it "handles unknown mathematical operations" do
        unknown_op_calls = [
          {
            "id" => "call_unknown_op",
            "type" => "function",
            "function" => {
              "name" => "calculator", 
              "arguments" => '{"operation": "power", "a": 2, "b": 3}'
            }
          }
        ]

        tool_executor.execute_tool_calls(unknown_op_calls, conversation, context_wrapper, {})

        expect(conversation.last[:content]).to eq("Unknown operation: power")
      end
    end

    context "with error scenarios" do
      it "handles runtime errors during tool execution" do
        allow(runner).to receive(:execute_tool).and_raise(RuntimeError, "Simulated runtime error")

        error_calls = [
          {
            "id" => "call_runtime_error",
            "type" => "function",
            "function" => {
              "name" => "error_tool",
              "arguments" => '{"error_type": "runtime"}'
            }
          }
        ]

        tool_executor.execute_tool_calls(error_calls, conversation, context_wrapper, {})

        expect(conversation.last[:role]).to eq("tool")
        expect(conversation.last[:content]).to include("Tool execution failed")
        expect(conversation.last[:content]).to include("Simulated runtime error")
      end

      it "handles argument errors during tool execution" do
        allow(runner).to receive(:execute_tool).and_raise(ArgumentError, "Invalid arguments")

        arg_error_calls = [
          {
            "id" => "call_arg_error", 
            "type" => "function",
            "function" => {
              "name" => "error_tool",
              "arguments" => '{"error_type": "argument"}'
            }
          }
        ]

        tool_executor.execute_tool_calls(arg_error_calls, conversation, context_wrapper, {})

        expect(conversation.last[:content]).to include("Tool execution failed")
        expect(conversation.last[:content]).to include("Invalid arguments")
      end

      it "handles type errors during tool execution" do
        allow(runner).to receive(:execute_tool).and_raise(TypeError, "Type mismatch")

        type_error_calls = [
          {
            "id" => "call_type_error",
            "type" => "function", 
            "function" => {
              "name" => "error_tool",
              "arguments" => '{"error_type": "type"}'
            }
          }
        ]

        tool_executor.execute_tool_calls(type_error_calls, conversation, context_wrapper, {})

        expect(conversation.last[:content]).to include("Tool execution failed")
        expect(conversation.last[:content]).to include("Type mismatch")
      end
    end

    context "with complex data structures" do
      it "handles hash return values" do
        hash_calls = [
          {
            "id" => "call_hash_data",
            "type" => "function",
            "function" => {
              "name" => "data_tool",
              "arguments" => '{"format": "hash"}'
            }
          }
        ]

        tool_executor.execute_tool_calls(hash_calls, conversation, context_wrapper, {})

        result_content = conversation.last[:content]
        expect(result_content).to include("status")
        expect(result_content).to include("success")
        expect(result_content).to include("data")
      end

      it "handles array return values" do
        array_calls = [
          {
            "id" => "call_array_data",
            "type" => "function",
            "function" => {
              "name" => "data_tool", 
              "arguments" => '{"format": "array"}'
            }
          }
        ]

        tool_executor.execute_tool_calls(array_calls, conversation, context_wrapper, {})

        result_content = conversation.last[:content]
        expect(result_content).to include("item1")
        expect(result_content).to include("item2")
        expect(result_content).to include("nested")
      end

      it "handles nil return values" do
        nil_calls = [
          {
            "id" => "call_nil_data",
            "type" => "function",
            "function" => {
              "name" => "data_tool",
              "arguments" => '{"format": "nil"}'
            }
          }
        ]

        tool_executor.execute_tool_calls(nil_calls, conversation, context_wrapper, {})

        expect(conversation.last[:content]).to eq("")
      end

      it "handles empty string return values" do
        empty_calls = [
          {
            "id" => "call_empty_data",
            "type" => "function", 
            "function" => {
              "name" => "data_tool",
              "arguments" => '{"format": "empty"}'
            }
          }
        ]

        tool_executor.execute_tool_calls(empty_calls, conversation, context_wrapper, {})

        expect(conversation.last[:content]).to eq("")
      end
    end

    context "with malformed JSON arguments" do
      it "handles completely invalid JSON" do
        invalid_json_calls = [
          {
            "id" => "call_invalid_json",
            "type" => "function",
            "function" => {
              "name" => "calculator",
              "arguments" => '{"operation": "add", "a": 1, "b"'  # Incomplete JSON
            }
          }
        ]

        tool_executor.execute_tool_calls(invalid_json_calls, conversation, context_wrapper, {})

        expect(conversation.last[:role]).to eq("tool")
        expect(conversation.last[:content]).to include("Failed to parse tool arguments")
      end

      it "handles JSON with unexpected structure" do
        weird_json_calls = [
          {
            "id" => "call_weird_json",
            "type" => "function",
            "function" => {
              "name" => "calculator",
              "arguments" => '[1, 2, 3]'  # Array instead of object
            }
          }
        ]

        allow(runner).to receive(:execute_tool).and_raise(ArgumentError, "Expected hash arguments")

        tool_executor.execute_tool_calls(weird_json_calls, conversation, context_wrapper, {})

        expect(conversation.last[:content]).to include("Tool execution failed")
      end

      it "handles empty JSON arguments" do
        empty_json_calls = [
          {
            "id" => "call_empty_json",
            "type" => "function",
            "function" => {
              "name" => "validation_tool", 
              "arguments" => '{}'
            }
          }
        ]

        allow(runner).to receive(:execute_tool).and_raise(ArgumentError, "Missing required parameter")

        tool_executor.execute_tool_calls(empty_json_calls, conversation, context_wrapper, {})

        expect(conversation.last[:content]).to include("Tool execution failed")
      end
    end

    context "with multiple concurrent tool calls" do
      it "executes multiple different tools in sequence" do
        multiple_calls = [
          {
            "id" => "call_1",
            "type" => "function",
            "function" => {
              "name" => "calculator",
              "arguments" => '{"operation": "add", "a": 5, "b": 3}'
            }
          },
          {
            "id" => "call_2", 
            "type" => "function",
            "function" => {
              "name" => "data_tool",
              "arguments" => '{"format": "string"}'
            }
          },
          {
            "id" => "call_3",
            "type" => "function",
            "function" => {
              "name" => "validation_tool",
              "arguments" => '{"required_param": "test_value"}'
            }
          }
        ]

        original_size = conversation.size
        tool_executor.execute_tool_calls(multiple_calls, conversation, context_wrapper, {})

        expect(conversation.size).to eq(original_size + 3) # 3 tool results added
        expect(conversation[-3][:content]).to eq("8") # Calculator result
        expect(conversation[-2][:content]).to eq("Simple string response") # Data tool result  
        expect(conversation[-1][:content]).to include("test_value") # Validation tool result
      end

      it "continues execution even when one tool fails" do
        mixed_calls = [
          {
            "id" => "call_success",
            "type" => "function", 
            "function" => {
              "name" => "calculator",
              "arguments" => '{"operation": "multiply", "a": 4, "b": 7}'
            }
          },
          {
            "id" => "call_failure",
            "type" => "function",
            "function" => {
              "name" => "calculator", 
              "arguments" => 'invalid json here'
            }
          },
          {
            "id" => "call_success_2",
            "type" => "function",
            "function" => {
              "name" => "data_tool",
              "arguments" => '{"format": "string"}'
            }
          }
        ]

        tool_executor.execute_tool_calls(mixed_calls, conversation, context_wrapper, {})

        expect(conversation.size).to eq(4) # Original + 3 results
        expect(conversation[-3][:content]).to eq("28") # First success
        expect(conversation[-2][:content]).to include("Failed to parse") # Failure
        expect(conversation[-1][:content]).to eq("Simple string response") # Second success
      end
    end
  end

  describe "hook integration and lifecycle" do
    it "calls tool start hook before execution" do
      tool_calls = [
        {
          "id" => "hook_test",
          "type" => "function",
          "function" => {
            "name" => "calculator",
            "arguments" => '{"operation": "add", "a": 1, "b": 1}'
          }
        }
      ]

      # on_tool_start is called with only context_wrapper and function name (no arguments)
      expect(runner).to receive(:call_hook).with(:on_tool_start, context_wrapper, "calculator")
      expect(runner).to receive(:call_hook).with(:on_tool_end, context_wrapper, "calculator", 2)

      tool_executor.execute_tool_calls(tool_calls, conversation, context_wrapper, {})
    end

    it "calls tool end hook after successful execution" do
      tool_calls = [
        {
          "id" => "hook_success_test",
          "type" => "function",
          "function" => {
            "name" => "data_tool",
            "arguments" => '{"format": "string"}'
          }
        }
      ]

      expect(runner).to receive(:call_hook).with(:on_tool_end, context_wrapper, "data_tool", "Simple string response")

      tool_executor.execute_tool_calls(tool_calls, conversation, context_wrapper, {})
    end

    it "calls tool error hook after tool execution failure" do
      allow(runner).to receive(:execute_tool).and_raise(StandardError, "Tool failed")

      tool_calls = [
        {
          "id" => "hook_failure_test", 
          "type" => "function",
          "function" => {
            "name" => "error_tool",
            "arguments" => '{"error_type": "runtime"}'
          }
        }
      ]

      # on_tool_error is called instead of on_tool_end when there's an error
      expect(runner).to receive(:call_hook).with(:on_tool_start, context_wrapper, "error_tool")
      expect(runner).to receive(:call_hook) do |event, context, func_name, error|
        expect(event).to eq(:on_tool_error)
        expect(context).to eq(context_wrapper)
        expect(func_name).to eq("error_tool")
        expect(error).to be_a(StandardError)
        expect(error.message).to eq("Tool failed")
      end

      tool_executor.execute_tool_calls(tool_calls, conversation, context_wrapper, {})
    end
  end

  describe "tool wrapper functionality" do
    it "executes tools through wrapper block when provided" do
      tool_calls = [
        {
          "id" => "wrapper_test",
          "type" => "function", 
          "function" => {
            "name" => "calculator",
            "arguments" => '{"operation": "multiply", "a": 3, "b": 4}'
          }
        }
      ]

      wrapper_called = false
      wrapper_block = proc do |func_name, args, &tool_execution|
        wrapper_called = true
        expect(func_name).to eq("calculator")
        expect(args).to eq({ operation: "multiply", a: 3, b: 4 })
        
        # Modify the result through the wrapper
        original_result = tool_execution.call
        "Wrapped result: #{original_result}"
      end

      tool_executor.execute_tool_calls(tool_calls, conversation, context_wrapper, {}, &wrapper_block)

      expect(wrapper_called).to be true
      expect(conversation.last[:content]).to eq("Wrapped result: 12")
    end

    it "allows wrapper to intercept and modify errors" do
      allow(runner).to receive(:execute_tool).and_raise(StandardError, "Original error")

      tool_calls = [
        {
          "id" => "wrapper_error_test",
          "type" => "function",
          "function" => {
            "name" => "error_tool", 
            "arguments" => '{"error_type": "runtime"}'
          }
        }
      ]

      wrapper_block = proc do |func_name, args, &tool_execution|
        begin
          tool_execution.call
        rescue StandardError => e
          "Wrapper caught error: #{e.message}"
        end
      end

      tool_executor.execute_tool_calls(tool_calls, conversation, context_wrapper, {}, &wrapper_block)

      expect(conversation.last[:content]).to eq("Wrapper caught error: Original error")
    end
  end

  describe "edge cases and robustness" do
    context "with malformed tool call structures" do
      it "handles missing function key" do
        malformed_calls = [
          {
            "id" => "missing_function",
            "type" => "function"
            # Missing "function" key
          }
        ]

        # Since the function key is missing, dig will return nil and we'll get a NoMethodError
        expect {
          tool_executor.execute_tool_calls(malformed_calls, conversation, context_wrapper, {})
        }.to raise_error(NoMethodError)
      end

      it "handles missing function name" do
        malformed_calls = [
          {
            "id" => "missing_name",
            "type" => "function",
            "function" => {
              "arguments" => '{"test": "value"}'
              # Missing "name" key  
            }
          }
        ]

        # Since the name key is missing, the second part of || will try to access [:function][:name] on nil
        expect {
          tool_executor.execute_tool_calls(malformed_calls, conversation, context_wrapper, {})
        }.to raise_error(NoMethodError)
      end

      it "handles missing arguments" do
        malformed_calls = [
          {
            "id" => "missing_args",
            "type" => "function",
            "function" => {
              "name" => "calculator"
              # Missing "arguments" key
            }
          }
        ]

        # Since the arguments key is missing, the second part of || will try to access [:function][:arguments] on nil
        expect {
          tool_executor.execute_tool_calls(malformed_calls, conversation, context_wrapper, {})
        }.to raise_error(NoMethodError)
      end

      it "handles missing tool call id" do
        malformed_calls = [
          {
            "type" => "function",
            "function" => {
              "name" => "calculator",
              "arguments" => '{"operation": "add", "a": 1, "b": 2}'
            }
            # Missing "id" key
          }
        ]

        # The test was calling with 3 arguments but the method expects 4
        tool_executor.execute_tool_calls(malformed_calls, conversation, context_wrapper, {})

        expect(conversation.last[:tool_call_id]).to be_nil
      end
    end

    context "with large data volumes" do
      it "handles large argument payloads" do
        large_data = "x" * 10000
        large_arg_calls = [
          {
            "id" => "large_args",
            "type" => "function",
            "function" => {
              "name" => "validation_tool",
              "arguments" => "{\"required_param\": \"#{large_data}\"}"
            }
          }
        ]

        start_time = Time.now
        tool_executor.execute_tool_calls(large_arg_calls, conversation, context_wrapper, {})
        duration = Time.now - start_time

        expect(duration).to be < 1.0 # Should handle large data efficiently
        expect(conversation.last[:content]).to include(large_data[0..100]) # Partial match
      end

      it "handles large return values" do
        allow(runner).to receive(:execute_tool).and_return("y" * 50000)

        large_result_calls = [
          {
            "id" => "large_result",
            "type" => "function",
            "function" => {
              "name" => "data_tool",
              "arguments" => '{"format": "string"}'
            }
          }
        ]

        tool_executor.execute_tool_calls(large_result_calls, conversation, context_wrapper, {})

        expect(conversation.last[:content]).to eq("y" * 50000)
      end
    end

    context "with unicode and special characters" do
      it "handles unicode in arguments" do
        unicode_calls = [
          {
            "id" => "unicode_test",
            "type" => "function",
            "function" => {
              "name" => "validation_tool",
              "arguments" => '{"required_param": "Hello 🌍 こんにちは"}'
            }
          }
        ]

        tool_executor.execute_tool_calls(unicode_calls, conversation, context_wrapper, {})

        expect(conversation.last[:content]).to include("Hello 🌍 こんにちは")
      end

      it "handles special characters in tool names" do
        # This would be a malformed tool name, but we should handle it gracefully
        special_char_calls = [
          {
            "id" => "special_chars",
            "type" => "function", 
            "function" => {
              "name" => "tool-with-dashes_and_underscores",
              "arguments" => '{"param": "value"}'
            }
          }
        ]

        allow(runner).to receive(:execute_tool).and_return("Special tool result")

        tool_executor.execute_tool_calls(special_char_calls, conversation, context_wrapper, {})

        expect(conversation.last[:content]).to eq("Special tool result")
      end
    end
  end
end