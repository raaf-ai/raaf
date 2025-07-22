# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Items do
  # Mock agent for testing
  let(:mock_agent) { double("Agent", name: "TestAgent") }
  let(:source_agent) { double("Agent", name: "SourceAgent") }
  let(:target_agent) { double("Agent", name: "TargetAgent") }

  describe RAAF::Items::RunItemBase do
    let(:raw_item) { { "type" => "message", "content" => "Hello" } }
    let(:item) { described_class.new(agent: mock_agent, raw_item: raw_item) }

    describe "#initialize" do
      it "stores agent and raw item correctly" do
        expect(item.agent).to eq(mock_agent)
        expect(item.raw_item).to eq(raw_item)
      end

      it "accepts hash raw items" do
        hash_item = { "test" => "data", "role" => "assistant" }
        item = described_class.new(agent: mock_agent, raw_item: hash_item)
        
        expect(item.raw_item).to eq(hash_item)
      end
    end

    describe "#to_input_item" do
      it "returns raw item when it's a hash" do
        result = item.to_input_item
        expect(result).to eq(raw_item)
      end

      it "raises ArgumentError for non-hash raw items" do
        string_item = described_class.new(agent: mock_agent, raw_item: "not a hash")
        
        expect {
          string_item.to_input_item
        }.to raise_error(ArgumentError, "Unexpected raw item type: String")
      end

      it "handles complex hash structures" do
        complex_item = {
          "type" => "complex",
          "nested" => { "data" => ["array", "values"] },
          "metadata" => { "id" => 123 }
        }
        item = described_class.new(agent: mock_agent, raw_item: complex_item)
        
        expect(item.to_input_item).to eq(complex_item)
      end
    end
  end

  describe RAAF::Items::MessageOutputItem do
    let(:raw_message) do
      {
        "type" => "message",
        "role" => "assistant", 
        "content" => [
          { "type" => "output_text", "text" => "Hello there!" }
        ]
      }
    end
    let(:message_item) { described_class.new(agent: mock_agent, raw_item: raw_message) }

    describe "#initialize" do
      it "inherits from RunItemBase" do
        expect(message_item).to be_a(RAAF::Items::RunItemBase)
        expect(message_item.agent).to eq(mock_agent)
        expect(message_item.raw_item).to eq(raw_message)
      end
    end

    describe "#type" do
      it "returns correct type identifier" do
        expect(message_item.type).to eq("message_output_item")
      end
    end

    describe "#to_input_item" do
      it "converts message to input format" do
        result = message_item.to_input_item
        expect(result).to eq(raw_message)
      end
    end
  end

  describe RAAF::Items::HandoffCallItem do
    let(:raw_handoff_call) do
      {
        "type" => "function_call",
        "name" => "transfer_to_support",
        "arguments" => { "context" => "user needs billing help" },
        "call_id" => "call_handoff_123"
      }
    end
    let(:handoff_call_item) { described_class.new(agent: mock_agent, raw_item: raw_handoff_call) }

    describe "#initialize" do
      it "inherits from RunItemBase" do
        expect(handoff_call_item).to be_a(RAAF::Items::RunItemBase)
        expect(handoff_call_item.agent).to eq(mock_agent)
        expect(handoff_call_item.raw_item).to eq(raw_handoff_call)
      end
    end

    describe "#type" do
      it "returns correct type identifier" do
        expect(handoff_call_item.type).to eq("handoff_call_item")
      end
    end
  end

  describe RAAF::Items::HandoffOutputItem do
    let(:raw_handoff_output) do
      {
        "type" => "handoff_output", 
        "from_agent" => "SourceAgent",
        "to_agent" => "TargetAgent",
        "context" => "transferred successfully"
      }
    end
    let(:handoff_output_item) do
      described_class.new(
        agent: mock_agent,
        raw_item: raw_handoff_output,
        source_agent: source_agent,
        target_agent: target_agent
      )
    end

    describe "#initialize" do
      it "inherits from RunItemBase and sets additional attributes" do
        expect(handoff_output_item).to be_a(RAAF::Items::RunItemBase)
        expect(handoff_output_item.agent).to eq(mock_agent)
        expect(handoff_output_item.raw_item).to eq(raw_handoff_output)
        expect(handoff_output_item.source_agent).to eq(source_agent)
        expect(handoff_output_item.target_agent).to eq(target_agent)
      end
    end

    describe "#type" do
      it "returns correct type identifier" do
        expect(handoff_output_item.type).to eq("handoff_output_item")
      end
    end

    describe "attribute readers" do
      it "provides access to source and target agents" do
        expect(handoff_output_item.source_agent).to eq(source_agent)
        expect(handoff_output_item.target_agent).to eq(target_agent)
      end
    end
  end

  describe RAAF::Items::ToolCallItem do
    let(:raw_tool_call) do
      {
        "type" => "function_call",
        "name" => "get_weather",
        "arguments" => { "location" => "NYC", "units" => "fahrenheit" },
        "call_id" => "call_weather_123"
      }
    end
    let(:tool_call_item) { described_class.new(agent: mock_agent, raw_item: raw_tool_call) }

    describe "#initialize" do
      it "inherits from RunItemBase" do
        expect(tool_call_item).to be_a(RAAF::Items::RunItemBase)
        expect(tool_call_item.agent).to eq(mock_agent)
        expect(tool_call_item.raw_item).to eq(raw_tool_call)
      end
    end

    describe "#type" do
      it "returns correct type identifier" do
        expect(tool_call_item.type).to eq("tool_call_item")
      end
    end

    it "handles complex tool call arguments" do
      complex_args = {
        "query" => "weather forecast",
        "options" => {
          "days" => 5,
          "include_hourly" => true,
          "metrics" => ["temperature", "precipitation", "wind"]
        }
      }
      complex_call = raw_tool_call.merge("arguments" => complex_args)
      item = described_class.new(agent: mock_agent, raw_item: complex_call)
      
      expect(item.raw_item["arguments"]).to eq(complex_args)
    end
  end

  describe RAAF::Items::ToolCallOutputItem do
    let(:tool_output) { { "weather" => "sunny", "temperature" => 72 } }
    let(:raw_tool_output) do
      {
        "type" => "function_call_output",
        "call_id" => "call_weather_123",
        "output" => tool_output
      }
    end
    let(:tool_output_item) do
      described_class.new(
        agent: mock_agent,
        raw_item: raw_tool_output,
        output: tool_output
      )
    end

    describe "#initialize" do
      it "inherits from RunItemBase and sets output" do
        expect(tool_output_item).to be_a(RAAF::Items::RunItemBase)
        expect(tool_output_item.agent).to eq(mock_agent)
        expect(tool_output_item.raw_item).to eq(raw_tool_output)
        expect(tool_output_item.output).to eq(tool_output)
      end
    end

    describe "#type" do
      it "returns correct type identifier" do
        expect(tool_output_item.type).to eq("tool_call_output_item")
      end
    end

    describe "output attribute" do
      it "provides access to tool execution result" do
        expect(tool_output_item.output).to eq(tool_output)
      end

      it "handles string outputs" do
        string_output = "Weather is sunny, 72°F"
        item = described_class.new(
          agent: mock_agent,
          raw_item: { "call_id" => "test" },
          output: string_output
        )
        
        expect(item.output).to eq(string_output)
      end

      it "handles complex object outputs" do
        complex_output = {
          "status" => "success",
          "data" => ["item1", "item2"],
          "metadata" => { "processed_at" => "2024-01-01" }
        }
        item = described_class.new(
          agent: mock_agent,
          raw_item: { "call_id" => "test" },
          output: complex_output
        )
        
        expect(item.output).to eq(complex_output)
      end
    end
  end

  describe RAAF::Items::FunctionCallOutputItem do
    let(:function_output) { "Function executed successfully" }
    let(:raw_function_output) do
      {
        "type" => "function_call_output",
        "call_id" => "call_func_123",
        "output" => function_output
      }
    end

    describe "#initialize" do
      it "inherits from RunItemBase and sets output" do
        item = described_class.new(
          agent: mock_agent,
          raw_item: raw_function_output,
          output: function_output
        )
        
        expect(item).to be_a(RAAF::Items::RunItemBase)
        expect(item.agent).to eq(mock_agent)
        expect(item.raw_item).to eq(raw_function_output)
        expect(item.output).to eq(function_output)
      end

      it "extracts output from raw_item when output parameter is nil" do
        item = described_class.new(
          agent: mock_agent,
          raw_item: raw_function_output
        )
        
        expect(item.output).to eq(function_output)
      end

      it "handles symbol keys in raw_item" do
        symbol_raw_item = {
          type: "function_call_output",
          call_id: "call_func_123",
          output: "symbol key output"
        }
        item = described_class.new(
          agent: mock_agent,
          raw_item: symbol_raw_item
        )
        
        expect(item.output).to eq("symbol key output")
      end

      it "prefers explicit output parameter over raw_item output" do
        explicit_output = "explicit output value"
        item = described_class.new(
          agent: mock_agent,
          raw_item: raw_function_output,
          output: explicit_output
        )
        
        expect(item.output).to eq(explicit_output)
      end
    end

    describe "#type" do
      it "returns correct type identifier" do
        item = described_class.new(agent: mock_agent, raw_item: raw_function_output)
        expect(item.type).to eq("function_call_output_item")
      end
    end

    describe "output extraction logic" do
      it "handles missing output in raw_item" do
        raw_without_output = { "call_id" => "test" }
        item = described_class.new(
          agent: mock_agent,
          raw_item: raw_without_output
        )
        
        expect(item.output).to be_nil
      end

      it "handles empty raw_item" do
        item = described_class.new(
          agent: mock_agent,
          raw_item: {}
        )
        
        expect(item.output).to be_nil
      end
    end
  end

  describe RAAF::Items::ReasoningItem do
    let(:raw_reasoning) do
      {
        "type" => "reasoning",
        "content" => "Let me think through this step by step...",
        "reasoning_type" => "chain_of_thought"
      }
    end
    let(:reasoning_item) { described_class.new(agent: mock_agent, raw_item: raw_reasoning) }

    describe "#initialize" do
      it "inherits from RunItemBase" do
        expect(reasoning_item).to be_a(RAAF::Items::RunItemBase)
        expect(reasoning_item.agent).to eq(mock_agent)
        expect(reasoning_item.raw_item).to eq(raw_reasoning)
      end
    end

    describe "#type" do
      it "returns correct type identifier" do
        expect(reasoning_item.type).to eq("reasoning_item")
      end
    end

    it "handles different reasoning types" do
      step_by_step_reasoning = {
        "type" => "reasoning",
        "steps" => [
          "First, analyze the problem",
          "Second, consider alternatives", 
          "Third, choose best approach"
        ]
      }
      item = described_class.new(agent: mock_agent, raw_item: step_by_step_reasoning)
      
      expect(item.raw_item["steps"]).to be_an(Array)
      expect(item.raw_item["steps"].length).to eq(3)
    end
  end

  describe RAAF::Items::ModelResponse do
    let(:message_item) do
      RAAF::Items::MessageOutputItem.new(
        agent: mock_agent,
        raw_item: { "role" => "assistant", "content" => "Hello!" }
      )
    end
    let(:tool_item) do
      RAAF::Items::ToolCallItem.new(
        agent: mock_agent,
        raw_item: { "name" => "get_data", "call_id" => "call_123" }
      )
    end
    let(:output_items) { [message_item, tool_item] }
    let(:usage_data) { { "input_tokens" => 10, "output_tokens" => 25, "total_tokens" => 35 } }
    let(:response_id) { "resp_abc123" }

    describe "#initialize" do
      it "stores output, usage, and response_id" do
        response = described_class.new(
          output: output_items,
          usage: usage_data,
          response_id: response_id
        )
        
        expect(response.output).to eq(output_items)
        expect(response.usage).to eq(usage_data)
        expect(response.response_id).to eq(response_id)
      end

      it "works without response_id" do
        response = described_class.new(
          output: output_items,
          usage: usage_data
        )
        
        expect(response.output).to eq(output_items)
        expect(response.usage).to eq(usage_data)
        expect(response.response_id).to be_nil
      end

      it "handles empty output array" do
        response = described_class.new(
          output: [],
          usage: usage_data
        )
        
        expect(response.output).to eq([])
        expect(response.usage).to eq(usage_data)
      end
    end

    describe "#to_input_items" do
      let(:response) do
        described_class.new(
          output: output_items,
          usage: usage_data,
          response_id: response_id
        )
      end

      it "converts output items to input format using to_h method" do
        # Mock to_h method on items
        allow(message_item).to receive(:to_h).and_return({ "converted" => "message" })
        allow(tool_item).to receive(:to_h).and_return({ "converted" => "tool" })
        
        result = response.to_input_items
        
        expect(result).to eq([
          { "converted" => "message" },
          { "converted" => "tool" }
        ])
      end

      it "handles hash items directly" do
        hash_items = [
          { "type" => "message", "content" => "direct hash" },
          { "type" => "tool_call", "name" => "direct_tool" }
        ]
        response = described_class.new(output: hash_items, usage: usage_data)
        
        result = response.to_input_items
        expect(result).to eq(hash_items)
      end

      it "raises ArgumentError for unconvertible items" do
        unconvertible_item = "string item"
        response = described_class.new(output: [unconvertible_item], usage: usage_data)
        
        expect {
          response.to_input_items
        }.to raise_error(ArgumentError, "Cannot convert item to input: String")
      end

      it "handles mixed convertible items" do
        hash_item = { "type" => "direct_hash" }
        convertible_item = double("ConvertibleItem")
        allow(convertible_item).to receive(:to_h).and_return({ "converted" => "item" })
        
        response = described_class.new(output: [hash_item, convertible_item], usage: usage_data)
        result = response.to_input_items
        
        expect(result).to eq([
          { "type" => "direct_hash" },
          { "converted" => "item" }
        ])
      end

      it "handles empty output array" do
        response = described_class.new(output: [], usage: usage_data)
        result = response.to_input_items
        
        expect(result).to eq([])
      end
    end

    describe "attribute readers" do
      let(:response) do
        described_class.new(
          output: output_items,
          usage: usage_data,
          response_id: response_id
        )
      end

      it "provides read access to all attributes" do
        expect(response.output).to eq(output_items)
        expect(response.usage).to eq(usage_data)
        expect(response.response_id).to eq(response_id)
      end
    end
  end

  describe RAAF::Items::ItemHelpers do
    describe ".extract_last_content" do
      it "extracts text from output_text content" do
        message = {
          "role" => "assistant",
          "content" => [
            { "type" => "output_text", "text" => "Hello there!" }
          ]
        }
        
        result = described_class.extract_last_content(message)
        expect(result).to eq("Hello there!")
      end

      it "extracts refusal content" do
        message = {
          "role" => "assistant",
          "content" => [
            { "type" => "refusal", "refusal" => "I cannot help with that" }
          ]
        }
        
        result = described_class.extract_last_content(message)
        expect(result).to eq("I cannot help with that")
      end

      it "returns last content when multiple items exist" do
        message = {
          "role" => "assistant",
          "content" => [
            { "type" => "output_text", "text" => "First text" },
            { "type" => "output_text", "text" => "Last text" }
          ]
        }
        
        result = described_class.extract_last_content(message)
        expect(result).to eq("Last text")
      end

      it "returns empty string for non-assistant messages" do
        user_message = {
          "role" => "user",
          "content" => [
            { "type" => "output_text", "text" => "User content" }
          ]
        }
        
        result = described_class.extract_last_content(user_message)
        expect(result).to eq("")
      end

      it "returns empty string for non-hash input" do
        result = described_class.extract_last_content("not a hash")
        expect(result).to eq("")
      end

      it "returns empty string for message without content array" do
        message = {
          "role" => "assistant",
          "content" => "simple string content"
        }
        
        result = described_class.extract_last_content(message)
        expect(result).to eq("")
      end

      it "returns empty string for empty content array" do
        message = {
          "role" => "assistant",
          "content" => []
        }
        
        result = described_class.extract_last_content(message)
        expect(result).to eq("")
      end

      it "returns empty string for unknown content type" do
        message = {
          "role" => "assistant",
          "content" => [
            { "type" => "unknown_type", "data" => "some data" }
          ]
        }
        
        result = described_class.extract_last_content(message)
        expect(result).to eq("")
      end

      it "handles missing text or refusal fields" do
        message_no_text = {
          "role" => "assistant",
          "content" => [
            { "type" => "output_text" }
          ]
        }
        
        message_no_refusal = {
          "role" => "assistant",
          "content" => [
            { "type" => "refusal" }
          ]
        }
        
        expect(described_class.extract_last_content(message_no_text)).to eq("")
        expect(described_class.extract_last_content(message_no_refusal)).to eq("")
      end
    end

    describe ".extract_last_text" do
      it "extracts text from output_text content" do
        message = {
          "role" => "assistant",
          "content" => [
            { "type" => "output_text", "text" => "Hello world!" }
          ]
        }
        
        result = described_class.extract_last_text(message)
        expect(result).to eq("Hello world!")
      end

      it "returns nil for refusal content" do
        message = {
          "role" => "assistant",
          "content" => [
            { "type" => "refusal", "refusal" => "Cannot help" }
          ]
        }
        
        result = described_class.extract_last_text(message)
        expect(result).to be_nil
      end

      it "returns last text when multiple items exist" do
        message = {
          "role" => "assistant",
          "content" => [
            { "type" => "output_text", "text" => "First" },
            { "type" => "refusal", "refusal" => "Cannot do" },
            { "type" => "output_text", "text" => "Final text" }
          ]
        }
        
        result = described_class.extract_last_text(message)
        expect(result).to eq("Final text")
      end

      it "returns nil for non-assistant messages" do
        message = {
          "role" => "user",
          "content" => [
            { "type" => "output_text", "text" => "User text" }
          ]
        }
        
        result = described_class.extract_last_text(message)
        expect(result).to be_nil
      end

      it "returns nil for invalid input" do
        expect(described_class.extract_last_text("string")).to be_nil
        expect(described_class.extract_last_text(nil)).to be_nil
        expect(described_class.extract_last_text({})).to be_nil
      end

      it "returns nil when no output_text in last position" do
        message = {
          "role" => "assistant",
          "content" => [
            { "type" => "output_text", "text" => "Good text" },
            { "type" => "unknown", "data" => "unknown" }
          ]
        }
        
        result = described_class.extract_last_text(message)
        expect(result).to be_nil
      end
    end

    describe ".input_to_new_input_list" do
      it "converts string input to user_text item" do
        result = described_class.input_to_new_input_list("Hello world")
        
        expect(result).to eq([
          { "type" => "user_text", "text" => "Hello world" }
        ])
      end

      it "handles empty string input" do
        result = described_class.input_to_new_input_list("")
        
        expect(result).to eq([
          { "type" => "user_text", "text" => "" }
        ])
      end

      it "converts message array to input items" do
        messages = [
          { "role" => "user", "content" => "Hello" },
          { "role" => "assistant", "content" => "Hi there" }
        ]
        
        result = described_class.input_to_new_input_list(messages)
        
        expect(result).to include(
          { "type" => "user_text", "text" => "Hello" },
          { "type" => "text", "text" => "Hi there" }
        )
      end

      it "returns copy of input item array" do
        input_items = [
          { "type" => "user_text", "text" => "Already formatted" }
        ]
        
        result = described_class.input_to_new_input_list(input_items)
        
        expect(result).to eq(input_items)
        expect(result).not_to be(input_items) # Should be a copy
      end

      it "handles empty array" do
        result = described_class.input_to_new_input_list([])
        expect(result).to eq([])
      end

      it "raises ArgumentError for unsupported input types" do
        expect {
          described_class.input_to_new_input_list(123)
        }.to raise_error(ArgumentError, "Input must be string or array, got Integer")

        expect {
          described_class.input_to_new_input_list({ "invalid" => "hash" })
        }.to raise_error(ArgumentError, "Input must be string or array, got Hash")
      end
    end

    describe ".convert_messages_to_input_items" do
      it "converts user messages to user_text items" do
        messages = [
          { "role" => "user", "content" => "First message" },
          { "role" => "user", "content" => "Second message" }
        ]
        
        result = described_class.convert_messages_to_input_items(messages)
        
        expect(result).to eq([
          { "type" => "user_text", "text" => "First message" },
          { "type" => "user_text", "text" => "Second message" }
        ])
      end

      it "converts assistant messages to text items" do
        messages = [
          { "role" => "assistant", "content" => "Assistant response" }
        ]
        
        result = described_class.convert_messages_to_input_items(messages)
        
        expect(result).to eq([
          { "type" => "text", "text" => "Assistant response" }
        ])
      end

      it "converts assistant messages with tool calls" do
        messages = [
          {
            "role" => "assistant",
            "tool_calls" => [
              {
                "id" => "call_123",
                "function" => {
                  "name" => "get_weather",
                  "arguments" => "{\"location\": \"NYC\"}"
                }
              }
            ]
          }
        ]
        
        result = described_class.convert_messages_to_input_items(messages)
        
        expect(result).to eq([
          {
            "type" => "function_call",
            "name" => "get_weather",
            "arguments" => "{\"location\": \"NYC\"}",
            "call_id" => "call_123"
          }
        ])
      end

      it "converts tool messages to function_call_output items" do
        messages = [
          {
            "role" => "tool",
            "tool_call_id" => "call_123",
            "content" => "Weather is sunny"
          }
        ]
        
        result = described_class.convert_messages_to_input_items(messages)
        
        expect(result).to eq([
          {
            "type" => "function_call_output",
            "call_id" => "call_123",
            "output" => "Weather is sunny"
          }
        ])
      end

      it "handles mixed message types" do
        messages = [
          { "role" => "user", "content" => "Question" },
          {
            "role" => "assistant",
            "content" => "I'll check that",
            "tool_calls" => [
              {
                "id" => "call_1",
                "function" => { "name" => "search", "arguments" => "{}" }
              }
            ]
          },
          { "role" => "tool", "tool_call_id" => "call_1", "content" => "Results" },
          { "role" => "assistant", "content" => "Here's what I found" }
        ]
        
        result = described_class.convert_messages_to_input_items(messages)
        
        expect(result).to eq([
          { "type" => "user_text", "text" => "Question" },
          { "type" => "function_call", "name" => "search", "arguments" => "{}", "call_id" => "call_1" },
          { "type" => "function_call_output", "call_id" => "call_1", "output" => "Results" },
          { "type" => "text", "text" => "Here's what I found" }
        ])
      end

      it "handles symbol keys in messages" do
        messages = [
          { role: "user", content: "Symbol key message" },
          {
            role: "assistant",
            tool_calls: [
              {
                id: "call_sym",
                function: { name: "func", arguments: "{}" }
              }
            ]
          }
        ]
        
        result = described_class.convert_messages_to_input_items(messages)
        
        expect(result).to include(
          { "type" => "user_text", "text" => "Symbol key message" },
          { "type" => "function_call", "name" => "func", "arguments" => "{}", "call_id" => "call_sym" }
        )
      end

      it "skips messages with unknown roles" do
        messages = [
          { "role" => "user", "content" => "Valid message" },
          { "role" => "system", "content" => "System message" },
          { "role" => "unknown", "content" => "Unknown role" }
        ]
        
        result = described_class.convert_messages_to_input_items(messages)
        
        expect(result).to eq([
          { "type" => "user_text", "text" => "Valid message" }
        ])
      end

      it "handles assistant messages without content or tool calls" do
        messages = [
          { "role" => "assistant" }
        ]
        
        result = described_class.convert_messages_to_input_items(messages)
        expect(result).to eq([])
      end
    end

    describe ".text_message_outputs" do
      let(:message_item1) do
        RAAF::Items::MessageOutputItem.new(
          agent: mock_agent,
          raw_item: {
            "content" => [
              { "type" => "output_text", "text" => "First message" }
            ]
          }
        )
      end

      let(:message_item2) do
        RAAF::Items::MessageOutputItem.new(
          agent: mock_agent,
          raw_item: {
            "content" => [
              { "type" => "output_text", "text" => "Second message" }
            ]
          }
        )
      end

      let(:non_message_item) { "not a message item" }

      it "concatenates text from multiple message output items" do
        items = [message_item1, message_item2]
        
        result = described_class.text_message_outputs(items)
        
        expect(result).to eq("First messageSecond message")
      end

      it "ignores non-MessageOutputItem objects" do
        items = [message_item1, non_message_item, message_item2]
        
        result = described_class.text_message_outputs(items)
        
        expect(result).to eq("First messageSecond message")
      end

      it "returns empty string for empty array" do
        result = described_class.text_message_outputs([])
        expect(result).to eq("")
      end

      it "returns empty string when no message items present" do
        items = ["not", "message", "items"]
        
        result = described_class.text_message_outputs(items)
        expect(result).to eq("")
      end
    end

    describe ".text_message_output" do
      it "extracts text from message output item" do
        message_item = RAAF::Items::MessageOutputItem.new(
          agent: mock_agent,
          raw_item: {
            "content" => [
              { "type" => "output_text", "text" => "Hello world!" }
            ]
          }
        )
        
        result = described_class.text_message_output(message_item)
        expect(result).to eq("Hello world!")
      end

      it "concatenates multiple text parts" do
        message_item = RAAF::Items::MessageOutputItem.new(
          agent: mock_agent,
          raw_item: {
            "content" => [
              { "type" => "output_text", "text" => "Part 1 " },
              { "type" => "output_text", "text" => "Part 2" }
            ]
          }
        )
        
        result = described_class.text_message_output(message_item)
        expect(result).to eq("Part 1 Part 2")
      end

      it "ignores non-text content types" do
        message_item = RAAF::Items::MessageOutputItem.new(
          agent: mock_agent,
          raw_item: {
            "content" => [
              { "type" => "output_text", "text" => "Text part" },
              { "type" => "refusal", "refusal" => "Cannot do this" },
              { "type" => "unknown", "data" => "Unknown data" }
            ]
          }
        )
        
        result = described_class.text_message_output(message_item)
        expect(result).to eq("Text part")
      end

      it "returns empty string for non-MessageOutputItem" do
        result = described_class.text_message_output("not a message item")
        expect(result).to eq("")
      end

      it "returns empty string for message without content array" do
        message_item = RAAF::Items::MessageOutputItem.new(
          agent: mock_agent,
          raw_item: { "content" => "string content" }
        )
        
        result = described_class.text_message_output(message_item)
        expect(result).to eq("")
      end

      it "returns empty string for message with no hash raw_item" do
        # Create item with invalid raw_item (will be handled gracefully)
        message_item = RAAF::Items::MessageOutputItem.new(
          agent: mock_agent,
          raw_item: {}
        )
        
        result = described_class.text_message_output(message_item)
        expect(result).to eq("")
      end
    end

    describe ".tool_call_output_item" do
      it "creates tool call output with call_id" do
        tool_call = { "call_id" => "call_123" }
        output = "Tool result"
        
        result = described_class.tool_call_output_item(tool_call, output)
        
        expect(result).to eq({
          "call_id" => "call_123",
          "output" => "Tool result",
          "type" => "function_call_output"
        })
      end

      it "uses id field when call_id not present" do
        tool_call = { "id" => "call_456" }
        output = { "result" => "success" }
        
        result = described_class.tool_call_output_item(tool_call, output)
        
        expect(result).to eq({
          "call_id" => "call_456",
          "output" => "{\"result\"=>\"success\"}",
          "type" => "function_call_output"
        })
      end

      it "converts output to string" do
        tool_call = { "call_id" => "call_789" }
        numeric_output = 42
        
        result = described_class.tool_call_output_item(tool_call, numeric_output)
        
        expect(result).to eq({
          "call_id" => "call_789",
          "output" => "42",
          "type" => "function_call_output"
        })
      end

      it "handles complex object output" do
        tool_call = { "id" => "call_complex" }
        complex_output = { "data" => [1, 2, 3], "status" => "complete" }
        
        result = described_class.tool_call_output_item(tool_call, complex_output)
        
        expect(result["call_id"]).to eq("call_complex")
        expect(result["output"]).to eq(complex_output.to_s)
        expect(result["type"]).to eq("function_call_output")
      end
    end

    describe ".extract_message_content" do
      it "extracts simple string content" do
        message = { "content" => "Simple string content" }
        
        result = described_class.extract_message_content(message)
        expect(result).to eq("Simple string content")
      end

      it "extracts content from array format" do
        message = {
          "content" => [
            { "type" => "text", "text" => "First part " },
            { "type" => "text", "text" => "Second part" },
            { "type" => "image", "data" => "image_data" }
          ]
        }
        
        result = described_class.extract_message_content(message)
        expect(result).to eq("First part Second part")
      end

      it "handles symbol keys" do
        message = {
          content: [
            { type: :text, text: "Symbol key content" }
          ]
        }
        
        result = described_class.extract_message_content(message)
        expect(result).to eq("Symbol key content")
      end

      it "returns empty string for non-hash input" do
        expect(described_class.extract_message_content("string")).to eq("")
        expect(described_class.extract_message_content(nil)).to eq("")
        expect(described_class.extract_message_content([])).to eq("")
      end

      it "returns empty string for message without content" do
        message = { "role" => "user" }
        
        result = described_class.extract_message_content(message)
        expect(result).to eq("")
      end

      it "handles empty content array" do
        message = { "content" => [] }
        
        result = described_class.extract_message_content(message)
        expect(result).to eq("")
      end

      it "ignores non-text array items" do
        message = {
          "content" => [
            { "type" => "image", "url" => "http://example.com/image.jpg" },
            { "type" => "text", "text" => "Text content" },
            { "type" => "video", "url" => "http://example.com/video.mp4" }
          ]
        }
        
        result = described_class.extract_message_content(message)
        expect(result).to eq("Text content")
      end
    end

    describe ".tool_calls?" do
      it "returns true for message with tool calls" do
        message = {
          "role" => "assistant",
          "tool_calls" => [
            { "id" => "call_1", "function" => { "name" => "test" } }
          ]
        }
        
        expect(described_class.tool_calls?(message)).to be true
      end

      it "returns false for message without tool calls" do
        message = { "role" => "assistant", "content" => "No tools here" }
        
        expect(described_class.tool_calls?(message)).to be false
      end

      it "returns false for empty tool calls array" do
        message = { "tool_calls" => [] }
        
        expect(described_class.tool_calls?(message)).to be false
      end

      it "returns false for nil tool calls" do
        message = { "tool_calls" => nil }
        
        expect(described_class.tool_calls?(message)).to be false
      end

      it "handles symbol keys" do
        message = {
          role: "assistant",
          tool_calls: [{ id: "call_1" }]
        }
        
        expect(described_class.tool_calls?(message)).to be true
      end

      it "returns false for non-hash input" do
        expect(described_class.tool_calls?("string")).to be false
        expect(described_class.tool_calls?(nil)).to be false
        expect(described_class.tool_calls?([])).to be false
      end
    end

    describe ".extract_tool_calls" do
      it "extracts tool calls array from message" do
        tool_calls = [
          { "id" => "call_1", "function" => { "name" => "func1" } },
          { "id" => "call_2", "function" => { "name" => "func2" } }
        ]
        message = { "tool_calls" => tool_calls }
        
        result = described_class.extract_tool_calls(message)
        expect(result).to eq(tool_calls)
      end

      it "returns empty array for message without tool calls" do
        message = { "role" => "assistant" }
        
        result = described_class.extract_tool_calls(message)
        expect(result).to eq([])
      end

      it "returns empty array for nil tool calls" do
        message = { "tool_calls" => nil }
        
        result = described_class.extract_tool_calls(message)
        expect(result).to eq([])
      end

      it "returns empty array for non-array tool calls" do
        message = { "tool_calls" => "not an array" }
        
        result = described_class.extract_tool_calls(message)
        expect(result).to eq([])
      end

      it "handles symbol keys" do
        tool_calls = [{ id: "call_sym" }]
        message = { tool_calls: tool_calls }
        
        result = described_class.extract_tool_calls(message)
        expect(result).to eq(tool_calls)
      end

      it "returns empty array for non-hash input" do
        expect(described_class.extract_tool_calls("string")).to eq([])
        expect(described_class.extract_tool_calls(nil)).to eq([])
      end
    end

    describe "message creation helpers" do
      describe ".user_message" do
        it "creates properly formatted user message" do
          result = described_class.user_message("Hello there")
          
          expect(result).to eq({
            "role" => "user",
            "content" => "Hello there"
          })
        end

        it "handles empty content" do
          result = described_class.user_message("")
          
          expect(result).to eq({
            "role" => "user",
            "content" => ""
          })
        end
      end

      describe ".assistant_message" do
        it "creates assistant message without tool calls" do
          result = described_class.assistant_message("Assistant response")
          
          expect(result).to eq({
            "role" => "assistant",
            "content" => "Assistant response"
          })
        end

        it "creates assistant message with tool calls" do
          tool_calls = [
            { "id" => "call_1", "function" => { "name" => "test_func" } }
          ]
          
          result = described_class.assistant_message("I'll call a function", tool_calls: tool_calls)
          
          expect(result).to eq({
            "role" => "assistant",
            "content" => "I'll call a function",
            "tool_calls" => tool_calls
          })
        end

        it "does not include tool_calls when nil" do
          result = described_class.assistant_message("No tools", tool_calls: nil)
          
          expect(result).to eq({
            "role" => "assistant",
            "content" => "No tools"
          })
          expect(result).not_to have_key("tool_calls")
        end
      end

      describe ".tool_message" do
        it "creates properly formatted tool message" do
          result = described_class.tool_message("call_123", "Tool execution result")
          
          expect(result).to eq({
            "role" => "tool",
            "tool_call_id" => "call_123",
            "content" => "Tool execution result"
          })
        end

        it "handles complex tool results" do
          complex_result = { "status" => "success", "data" => [1, 2, 3] }.to_s
          
          result = described_class.tool_message("call_complex", complex_result)
          
          expect(result).to eq({
            "role" => "tool",
            "tool_call_id" => "call_complex",
            "content" => complex_result
          })
        end
      end
    end
  end
end