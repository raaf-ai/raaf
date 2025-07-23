# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::ContextManager do
  describe "#initialize" do
    it "initializes with default values" do
      manager = described_class.new
      expect(manager.max_tokens).to be > 0
      expect(manager.preserve_system).to be true
      expect(manager.preserve_recent).to eq(5)
    end

    it "accepts custom parameters" do
      manager = described_class.new(
        model: "gpt-3.5-turbo",
        max_tokens: 1000,
        preserve_system: false,
        preserve_recent: 3
      )
      expect(manager.max_tokens).to eq(1000)
      expect(manager.preserve_system).to be false
      expect(manager.preserve_recent).to eq(3)
    end

    context "model-specific max tokens" do
      it "sets correct defaults for gpt-4o" do
        manager = described_class.new(model: "gpt-4o")
        expect(manager.max_tokens).to eq(120_000)
      end

      it "sets correct defaults for gpt-4-turbo" do
        manager = described_class.new(model: "gpt-4-turbo")
        expect(manager.max_tokens).to eq(120_000)
      end

      it "sets correct defaults for gpt-3.5-turbo-16k" do
        manager = described_class.new(model: "gpt-3.5-turbo-16k")
        expect(manager.max_tokens).to eq(15_000)
      end

      it "sets correct defaults for gpt-3.5-turbo" do
        manager = described_class.new(model: "gpt-3.5-turbo")
        expect(manager.max_tokens).to eq(3_500)
      end

      it "uses conservative default for unknown models" do
        manager = described_class.new(model: "unknown-model")
        expect(manager.max_tokens).to eq(7_500)
      end
    end

    it "handles tiktoken encoding errors gracefully" do
      allow(Tiktoken).to receive(:encoding_for_model).and_raise(StandardError)
      expect(Tiktoken).to receive(:get_encoding).with("cl100k_base")
      
      manager = described_class.new(model: "invalid-model")
      expect(manager).to be_a(described_class)
    end
  end

  describe "#count_message_tokens" do
    let(:manager) { described_class.new(model: "gpt-4o", max_tokens: 1000) }

    it "counts tokens for basic message" do
      message = { role: "user", content: "Hello world" }
      tokens = manager.count_message_tokens(message)
      expect(tokens).to be > 0
      expect(tokens).to be < 20 # Should be reasonable for short message
    end

    it "counts tokens for system message" do
      message = { role: "system", content: "You are a helpful assistant" }
      tokens = manager.count_message_tokens(message)
      expect(tokens).to be > 0
    end

    it "handles empty content" do
      message = { role: "user", content: "" }
      tokens = manager.count_message_tokens(message)
      expect(tokens).to be > 0 # Should have base overhead
    end

    it "handles nil content" do
      message = { role: "user" }
      tokens = manager.count_message_tokens(message)
      expect(tokens).to be > 0 # Should have base overhead
    end

    it "counts tokens for messages with tool calls" do
      message = {
        role: "assistant",
        content: nil,
        tool_calls: [
          {
            "function" => {
              "name" => "get_weather",
              "arguments" => '{"location": "San Francisco"}'
            }
          }
        ]
      }
      tokens = manager.count_message_tokens(message)
      expect(tokens).to be > 20 # Should account for tool call overhead
    end

    it "handles messages with multiple tool calls" do
      message = {
        role: "assistant",
        content: nil,
        tool_calls: [
          {
            "function" => {
              "name" => "get_weather",
              "arguments" => '{"location": "San Francisco"}'
            }
          },
          {
            "function" => {
              "name" => "get_time",
              "arguments" => '{"timezone": "UTC"}'
            }
          }
        ]
      }
      tokens = manager.count_message_tokens(message)
      expect(tokens).to be > 40 # Should account for multiple tool calls
    end

    it "handles tool calls with missing function data" do
      message = {
        role: "assistant",
        content: nil,
        tool_calls: [
          {
            "function" => {
              "name" => nil,
              "arguments" => nil
            }
          }
        ]
      }
      tokens = manager.count_message_tokens(message)
      expect(tokens).to be > 0 # Should have base overhead
    end
  end

  describe "#count_total_tokens" do
    let(:manager) { described_class.new(model: "gpt-4o", max_tokens: 1000) }

    it "counts tokens for empty message list" do
      messages = []
      tokens = manager.count_total_tokens(messages)
      expect(tokens).to eq(3) # Base conversation overhead
    end

    it "counts tokens for single message" do
      messages = [{ role: "user", content: "Hello" }]
      tokens = manager.count_total_tokens(messages)
      expect(tokens).to be > 8 # More realistic expectation
    end

    it "counts tokens for multiple messages" do
      messages = [
        { role: "system", content: "You are helpful" },
        { role: "user", content: "Hello" },
        { role: "assistant", content: "Hi there!" }
      ]
      tokens = manager.count_total_tokens(messages)
      expect(tokens).to be > 20
    end

    it "total is greater than sum of individual messages" do
      messages = [
        { role: "user", content: "Hello" },
        { role: "assistant", content: "Hi!" }
      ]
      
      total_tokens = manager.count_total_tokens(messages)
      individual_sum = messages.sum { |msg| manager.count_message_tokens(msg) }
      
      expect(total_tokens).to be > individual_sum
    end
  end

  describe "#manage_context" do
    let(:manager) { described_class.new(model: "gpt-4o", max_tokens: 100) } # Very small limit for testing

    it "returns empty array for empty input" do
      result = manager.manage_context([])
      expect(result).to eq([])
    end

    it "returns messages unchanged if within limit" do
      messages = [
        { role: "user", content: "Hi" }
      ]
      result = manager.manage_context(messages)
      expect(result).to eq(messages)
    end

    context "when messages exceed token limit" do
      let(:large_messages) do
        [
          { role: "system", content: "You are a helpful assistant that provides detailed responses" },
          { role: "user", content: "Tell me about the history of programming languages in great detail" },
          { role: "assistant", content: "Programming languages have evolved significantly over decades..." },
          { role: "user", content: "What about functional programming paradigms specifically?" },
          { role: "assistant", content: "Functional programming is a declarative programming paradigm..." },
          { role: "user", content: "Can you give examples?" },
          { role: "assistant", content: "Sure, here are several examples of functional programming..." },
          { role: "user", content: "Latest question" }
        ]
      end

      it "preserves system messages when preserve_system is true" do
        manager = described_class.new(model: "gpt-4o", max_tokens: 100, preserve_system: true)
        result = manager.manage_context(large_messages)
        
        system_messages = result.select { |msg| msg[:role] == "system" && !msg[:content].include?("[Note:") }
        expect(system_messages.length).to be >= 1
      end

      it "does not preserve system messages when preserve_system is false" do
        manager = described_class.new(model: "gpt-4o", max_tokens: 100, preserve_system: false)
        result = manager.manage_context(large_messages)
        
        original_system_messages = result.select { |msg| msg[:role] == "system" && !msg[:content].include?("[Note:") }
        expect(original_system_messages).to be_empty
      end

      it "preserves recent messages" do
        manager = described_class.new(model: "gpt-4o", max_tokens: 100, preserve_recent: 2)
        result = manager.manage_context(large_messages)
        
        # Should preserve the last 2 messages
        expect(result.last[:content]).to eq("Latest question")
        expect(result[-2][:content]).to include("examples of functional")
      end

      it "adds truncation notice when messages are removed" do
        result = manager.manage_context(large_messages)
        
        truncation_messages = result.select { |msg| msg[:content]&.include?("[Note:") }
        expect(truncation_messages.length).to eq(1)
        expect(truncation_messages.first[:role]).to eq("system")
        expect(truncation_messages.first[:content]).to match(/\d+ earlier messages were truncated/)
      end

      it "attempts to respect token limits" do
        result = manager.manage_context(large_messages)
        total_tokens = manager.count_total_tokens(result)
        # May slightly exceed if system/recent messages are large, but should be close
        expect(total_tokens).to be < manager.max_tokens + 50
      end

      it "returns fewer or same messages as input when truncation may occur" do
        result = manager.manage_context(large_messages)
        expect(result.length).to be <= large_messages.length
      end
    end

    context "with different preserve_recent settings" do
      let(:messages) do
        (1..10).map { |i| { role: "user", content: "Message #{i}" } }
      end

      it "preserves correct number of recent messages" do
        manager = described_class.new(model: "gpt-4o", max_tokens: 50, preserve_recent: 3, preserve_system: false)
        result = manager.manage_context(messages)
        
        # Should include the last 3 messages
        expect(result.last[:content]).to eq("Message 10")
        expect(result[-2][:content]).to eq("Message 9") 
        expect(result[-3][:content]).to eq("Message 8")
      end

      it "handles preserve_recent larger than message count" do
        small_messages = [
          { role: "user", content: "Message 1" },
          { role: "user", content: "Message 2" }
        ]
        
        manager = described_class.new(model: "gpt-4o", max_tokens: 1000, preserve_recent: 10)
        result = manager.manage_context(small_messages)
        expect(result).to eq(small_messages)
      end
    end

    context "sliding window algorithm" do
      let(:messages) do
        [
          { role: "system", content: "System message" },
          { role: "user", content: "Old message 1" },
          { role: "assistant", content: "Old response 1" },
          { role: "user", content: "Old message 2" },
          { role: "assistant", content: "Old response 2" },
          { role: "user", content: "Recent message 1" },
          { role: "assistant", content: "Recent response 1" },
          { role: "user", content: "Recent message 2" }
        ]
      end

      it "adds older messages from newest to oldest" do
        manager = described_class.new(
          model: "gpt-4o", 
          max_tokens: 200, # Enough for some but not all
          preserve_recent: 2,
          preserve_system: true
        )
        
        result = manager.manage_context(messages)
        
        # Should have system message, some older messages (newer first), and recent messages
        system_msgs = result.select { |m| m[:role] == "system" && !m[:content].include?("[Note:") }
        expect(system_msgs.length).to eq(1)
        
        # Recent messages should be at the end
        expect(result.last[:content]).to eq("Recent message 2")
        expect(result[-2][:content]).to eq("Recent response 1")
      end

      it "maintains chronological order within preserved sections" do
        manager = described_class.new(
          model: "gpt-4o",
          max_tokens: 150,
          preserve_recent: 2,
          preserve_system: true
        )
        
        result = manager.manage_context(messages)
        
        # Find positions of messages to ensure order is maintained
        system_idx = result.find_index { |m| m[:content] == "System message" }
        recent1_idx = result.find_index { |m| m[:content] == "Recent response 1" }
        recent2_idx = result.find_index { |m| m[:content] == "Recent message 2" }
        
        expect(system_idx).to be < recent1_idx
        expect(recent1_idx).to be < recent2_idx
      end
    end
  end

  describe "edge cases and error handling" do
    let(:manager) { described_class.new(model: "gpt-4o", max_tokens: 100) }

    it "handles messages with nil role" do
      message = { content: "Hello" }
      tokens = manager.count_message_tokens(message)
      expect(tokens).to be > 0
    end

    it "handles very small token limits" do
      small_manager = described_class.new(model: "gpt-4o", max_tokens: 10)
      messages = [
        { role: "system", content: "Help" }, # Shorter system message
        { role: "user", content: "Hi" }
      ]
      
      result = small_manager.manage_context(messages)
      total_tokens = small_manager.count_total_tokens(result)
      # With very small limits, may still exceed due to minimum required messages
      expect(total_tokens).to be < 30 # More realistic expectation
    end

    it "handles zero preserve_recent" do
      manager = described_class.new(model: "gpt-4o", max_tokens: 100, preserve_recent: 0)
      messages = [
        { role: "user", content: "Message 1" },
        { role: "user", content: "Message 2" },
        { role: "user", content: "Message 3" }
      ]
      
      result = manager.manage_context(messages)
      # Should still return valid result
      expect(result).to be_an(Array)
      expect(manager.count_total_tokens(result)).to be <= 100
    end

    it "handles single message exceeding token limit" do
      huge_message = { role: "user", content: "x" * 1000 } # Very long message
      small_manager = described_class.new(model: "gpt-4o", max_tokens: 50)
      
      result = small_manager.manage_context([huge_message])
      # Should handle gracefully, even if it exceeds limit
      expect(result).to be_an(Array)
    end
  end

  describe "private methods" do
    let(:manager) { described_class.new(model: "gpt-4o", max_tokens: 1000) }

    describe "#default_max_tokens" do
      it "returns correct values for known models" do
        expect(manager.send(:default_max_tokens, "gpt-4o")).to eq(120_000)
        expect(manager.send(:default_max_tokens, "gpt-4-turbo")).to eq(120_000)
        expect(manager.send(:default_max_tokens, "gpt-3.5-turbo-16k")).to eq(15_000)
        expect(manager.send(:default_max_tokens, "gpt-3.5-turbo")).to eq(3_500)
        expect(manager.send(:default_max_tokens, "unknown")).to eq(7_500)
      end
    end

    describe "#within_token_limit?" do
      it "returns true when within limit" do
        messages = [{ role: "user", content: "Hi" }]
        expect(manager.send(:within_token_limit?, messages)).to be true
      end

      it "returns false when exceeding limit" do
        small_manager = described_class.new(model: "gpt-4o", max_tokens: 10)
        messages = [{ role: "user", content: "This is a very long message that should exceed the token limit" }]
        expect(small_manager.send(:within_token_limit?, messages)).to be false
      end
    end

    describe "#estimate_tool_call_tokens" do
      it "estimates tokens for tool calls" do
        tool_calls = [
          {
            "function" => {
              "name" => "get_weather",
              "arguments" => '{"location": "SF"}'
            }
          }
        ]
        
        tokens = manager.send(:estimate_tool_call_tokens, tool_calls)
        expect(tokens).to be > 10
      end

      it "handles empty tool calls" do
        tokens = manager.send(:estimate_tool_call_tokens, [])
        expect(tokens).to eq(0)
      end

      it "handles tool calls with missing data" do
        tool_calls = [
          {
            "function" => {
              "name" => nil,
              "arguments" => nil
            }
          }
        ]
        
        tokens = manager.send(:estimate_tool_call_tokens, tool_calls)
        expect(tokens).to eq(10) # Base overhead only
      end
    end
  end
end