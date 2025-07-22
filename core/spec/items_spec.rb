# frozen_string_literal: true

require "spec_helper"
require_relative "../lib/raaf/items"

RSpec.describe RAAF::Items do
  let(:mock_agent) { double("Agent", name: "TestAgent") }

  describe RAAF::Items::RunItemBase do
    let(:raw_item) { { "type" => "message", "content" => "Hello" } }
    let(:item) { described_class.new(agent: mock_agent, raw_item: raw_item) }

    describe "#initialize" do
      it "stores agent and raw item" do
        expect(item.agent).to eq(mock_agent)
        expect(item.raw_item).to eq(raw_item)
      end
    end
  end

  describe RAAF::Items::MessageOutputItem do
    let(:raw_message) do
      {
        "type" => "message",
        "role" => "assistant",
        "content" => "Hello there!"
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
  end

  describe RAAF::Items::ToolCallItem do
    let(:raw_tool_call) do
      {
        "type" => "tool_call",
        "name" => "get_weather",
        "arguments" => { "location" => "NYC" },
        "call_id" => "call_123"
      }
    end
    
    let(:tool_item) { described_class.new(agent: mock_agent, raw_item: raw_tool_call) }

    describe "#initialize" do
      it "inherits from RunItemBase" do
        expect(tool_item).to be_a(RAAF::Items::RunItemBase)
        expect(tool_item.agent).to eq(mock_agent)
        expect(tool_item.raw_item).to eq(raw_tool_call)
      end
    end
  end

  describe RAAF::Items::ItemHelpers do
    describe ".extract_message_content" do
      it "extracts string content" do
        message = { "content" => "Simple string" }
        content = described_class.extract_message_content(message)
        
        expect(content).to eq("Simple string")
      end

      it "handles empty content" do
        message = { "content" => "" }
        content = described_class.extract_message_content(message)
        
        expect(content).to eq("")
      end
    end
  end
end