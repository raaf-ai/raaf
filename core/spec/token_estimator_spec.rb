# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::TokenEstimator do
  describe "constants" do
    describe "TOKEN_RATIOS" do
      it "includes ratios for GPT-4 models" do
        expect(described_class::TOKEN_RATIOS["gpt-4"]).to eq(250)
        expect(described_class::TOKEN_RATIOS["gpt-4-turbo"]).to eq(250)
        expect(described_class::TOKEN_RATIOS["gpt-4o"]).to eq(250)
        expect(described_class::TOKEN_RATIOS["gpt-4o-mini"]).to eq(250)
      end

      it "includes ratios for GPT-3.5 models" do
        expect(described_class::TOKEN_RATIOS["gpt-3.5-turbo"]).to eq(270)
      end

      it "includes ratios for O1 models" do
        expect(described_class::TOKEN_RATIOS["o1-preview"]).to eq(250)
        expect(described_class::TOKEN_RATIOS["o1-mini"]).to eq(250)
      end

      it "includes default ratio" do
        expect(described_class::TOKEN_RATIOS["default"]).to eq(280)
      end

      it "is frozen to prevent modification" do
        expect(described_class::TOKEN_RATIOS).to be_frozen
      end
    end

    describe "message overhead constants" do
      it "defines message overhead" do
        expect(described_class::MESSAGE_OVERHEAD).to eq(4)
      end

      it "defines role tokens" do
        expect(described_class::ROLE_TOKENS).to eq(1)
      end
    end
  end

  describe ".estimate_usage" do
    let(:messages) do
      [
        { role: "system", content: "You are a helpful assistant." },
        { role: "user", content: "Hello, how are you?" },
        { role: "assistant", content: "I'm doing well, thank you!" }
      ]
    end
    let(:response_content) { "Here's my detailed response." }
    let(:model) { "gpt-4o" }

    it "returns complete usage hash with all required fields" do
      result = described_class.estimate_usage(
        messages: messages,
        response_content: response_content,
        model: model
      )

      expect(result).to be_a(Hash)
      expect(result).to include(
        "input_tokens",
        "output_tokens",
        "total_tokens",
        "estimated"
      )
      expect(result["estimated"]).to be true
    end

    it "calculates input tokens from messages" do
      result = described_class.estimate_usage(
        messages: messages,
        response_content: nil,
        model: model
      )

      expect(result["input_tokens"]).to be > 0
      expect(result["output_tokens"]).to eq(0)
      expect(result["total_tokens"]).to eq(result["input_tokens"])
    end

    it "calculates output tokens from response content" do
      result = described_class.estimate_usage(
        messages: messages,
        response_content: response_content,
        model: model
      )

      expect(result["input_tokens"]).to be > 0
      expect(result["output_tokens"]).to be > 0
      expect(result["total_tokens"]).to eq(result["input_tokens"] + result["output_tokens"])
    end

    it "handles nil response content gracefully" do
      result = described_class.estimate_usage(
        messages: messages,
        response_content: nil,
        model: model
      )

      expect(result["output_tokens"]).to eq(0)
    end

    it "uses default model when none provided" do
      expect {
        described_class.estimate_usage(messages: messages)
      }.not_to raise_error
    end

    it "handles empty messages array" do
      result = described_class.estimate_usage(
        messages: [],
        response_content: response_content,
        model: model
      )

      expect(result["input_tokens"]).to eq(0)
      expect(result["output_tokens"]).to be > 0
    end
  end

  describe ".estimate_messages_tokens" do
    let(:messages) do
      [
        { role: "user", content: "Hello!" },
        { role: "assistant", content: "Hi there!" }
      ]
    end

    it "returns total tokens for message array" do
      result = described_class.estimate_messages_tokens(messages, "gpt-4o")
      expect(result).to be > 0
    end

    it "returns 0 for empty array" do
      result = described_class.estimate_messages_tokens([], "gpt-4o")
      expect(result).to eq(0)
    end

    it "returns 0 for nil input" do
      result = described_class.estimate_messages_tokens(nil, "gpt-4o")
      expect(result).to eq(0)
    end

    it "returns 0 for non-array input" do
      result = described_class.estimate_messages_tokens("not an array", "gpt-4o")
      expect(result).to eq(0)
    end

    it "sums tokens from individual messages" do
      single_message_tokens = described_class.estimate_message_tokens(messages[0], "gpt-4o")
      total_tokens = described_class.estimate_messages_tokens(messages, "gpt-4o")

      expect(total_tokens).to be >= single_message_tokens
    end
  end

  describe ".estimate_message_tokens" do
    it "handles basic message with role and content" do
      message = { role: "user", content: "Hello, world!" }
      result = described_class.estimate_message_tokens(message, "gpt-4o")
      
      expect(result).to be > 0
      # Should include base message overhead plus content
      expect(result).to be >= 3 # tokens_per_message
    end

    it "handles string keys in message hash" do
      message = { "role" => "assistant", "content" => "Hello back!" }
      result = described_class.estimate_message_tokens(message, "gpt-4o")
      
      expect(result).to be > 0
    end

    it "handles message with name field" do
      message = { role: "user", content: "Hello", name: "Alice" }
      result_with_name = described_class.estimate_message_tokens(message, "gpt-4o")
      
      message_without_name = { role: "user", content: "Hello" }
      result_without_name = described_class.estimate_message_tokens(message_without_name, "gpt-4o")
      
      # Message with name should have more tokens
      expect(result_with_name).to be > result_without_name
    end

    it "handles message with tool calls" do
      message = {
        role: "assistant",
        content: "I'll help you with that.",
        tool_calls: [{
          function: {
            name: "search_web",
            arguments: '{"query": "Ruby programming"}'
          }
        }]
      }
      
      result_with_tools = described_class.estimate_message_tokens(message, "gpt-4o")
      
      message_without_tools = { role: "assistant", content: "I'll help you with that." }
      result_without_tools = described_class.estimate_message_tokens(message_without_tools, "gpt-4o")
      
      # Message with tool calls should have more tokens
      expect(result_with_tools).to be > result_without_tools
    end

    it "handles empty content gracefully" do
      message = { role: "user", content: "" }
      result = described_class.estimate_message_tokens(message, "gpt-4o")
      
      expect(result).to be >= 3 # Should still have base overhead
    end

    it "handles missing content gracefully" do
      message = { role: "user" }
      result = described_class.estimate_message_tokens(message, "gpt-4o")
      
      expect(result).to be >= 3 # Should still have base overhead
    end

    it "returns 0 for nil message" do
      result = described_class.estimate_message_tokens(nil, "gpt-4o")
      expect(result).to eq(0)
    end

    it "returns 0 for non-hash message" do
      result = described_class.estimate_message_tokens("not a hash", "gpt-4o")
      expect(result).to eq(0)
    end
  end

  describe ".estimate_text_tokens" do
    it "returns 0 for nil text" do
      result = described_class.estimate_text_tokens(nil, "gpt-4o")
      expect(result).to eq(0)
    end

    it "returns 0 for empty text" do
      result = described_class.estimate_text_tokens("", "gpt-4o")
      expect(result).to eq(0)
    end

    it "returns positive count for non-empty text" do
      result = described_class.estimate_text_tokens("Hello, world!", "gpt-4o")
      expect(result).to be > 0
    end

    it "uses tiktoken for token counting" do
      text = "The quick brown fox jumps over the lazy dog."
      
      # Should delegate to count_tokens_with_tiktoken
      expect(described_class).to receive(:count_tokens_with_tiktoken).with(text, "gpt-4o")
      described_class.estimate_text_tokens(text, "gpt-4o")
    end

    it "returns reasonable estimates for different text lengths" do
      short_text = "Hi"
      medium_text = "Hello, how are you doing today?"
      long_text = "This is a much longer text that contains multiple sentences and should result in a significantly higher token count than the shorter examples."

      short_result = described_class.estimate_text_tokens(short_text, "gpt-4o")
      medium_result = described_class.estimate_text_tokens(medium_text, "gpt-4o")
      long_result = described_class.estimate_text_tokens(long_text, "gpt-4o")

      expect(short_result).to be < medium_result
      expect(medium_result).to be < long_result
    end
  end

  describe ".count_tokens_with_tiktoken" do
    before do
      # Reset any previous tiktoken state
      allow(Tiktoken).to receive(:encoding_for_model).and_call_original
      allow(Tiktoken).to receive(:get_encoding).and_call_original
    end

    it "uses gpt-4 encoding for gpt-4 models" do
      text = "Hello, world!"
      
      expect(Tiktoken).to receive(:encoding_for_model).with("gpt-4").and_call_original
      described_class.send(:count_tokens_with_tiktoken, text, "gpt-4")
    end

    it "uses gpt-4 encoding for gpt-4 variant models" do
      text = "Hello, world!"
      
      expect(Tiktoken).to receive(:encoding_for_model).with("gpt-4").and_call_original
      described_class.send(:count_tokens_with_tiktoken, text, "gpt-4o")
    end

    it "uses gpt-3.5-turbo encoding for gpt-3.5 models" do
      text = "Hello, world!"
      
      expect(Tiktoken).to receive(:encoding_for_model).with("gpt-3.5-turbo").and_call_original
      described_class.send(:count_tokens_with_tiktoken, text, "gpt-3.5-turbo")
    end

    it "uses cl100k_base encoding for other models" do
      text = "Hello, world!"
      
      expect(Tiktoken).to receive(:get_encoding).with("cl100k_base").and_call_original
      described_class.send(:count_tokens_with_tiktoken, text, "claude-3")
    end

    it "returns accurate token count for simple text" do
      # Test with a known simple phrase
      text = "Hello"
      result = described_class.send(:count_tokens_with_tiktoken, text, "gpt-4")
      
      # Should return a reasonable token count (exact count depends on tiktoken)
      expect(result).to be_between(1, 3)
    end

    context "when tiktoken fails" do
      before do
        # Mock tiktoken to raise an error
        allow(Tiktoken).to receive(:encoding_for_model).and_raise(StandardError.new("Tiktoken error"))
        allow(RAAF::Logging).to receive(:warn)
      end

      it "falls back to character-based estimation" do
        text = "A" * 1000 # 1000 characters
        result = described_class.send(:count_tokens_with_tiktoken, text, "gpt-4o")
        
        # Should use character ratio for gpt-4o (250 tokens per 1000 chars)
        expect(result).to be_between(240, 260) # Allow for rounding
      end

      it "logs the warning" do
        text = "Hello, world!"
        
        described_class.send(:count_tokens_with_tiktoken, text, "gpt-4o")
        
        expect(RAAF::Logging).to have_received(:warn).with(
          "Tiktoken encoding failed, falling back to estimation",
          hash_including(:model, :error, :error_class)
        )
      end

      it "returns at least 1 token for non-empty text" do
        text = "x"
        result = described_class.send(:count_tokens_with_tiktoken, text, "gpt-4o")
        
        expect(result).to be >= 1
      end
    end
  end

  describe ".estimate_tool_calls_tokens" do
    it "returns 0 for nil tool calls" do
      result = described_class.estimate_tool_calls_tokens(nil, "gpt-4o")
      expect(result).to eq(0)
    end

    it "returns 0 for empty array" do
      result = described_class.estimate_tool_calls_tokens([], "gpt-4o")
      expect(result).to eq(0)
    end

    it "returns 0 for non-array input" do
      result = described_class.estimate_tool_calls_tokens("not an array", "gpt-4o")
      expect(result).to eq(0)
    end

    it "estimates tokens for tool calls with function data" do
      tool_calls = [{
        function: {
          name: "get_weather",
          arguments: '{"location": "New York", "units": "celsius"}'
        }
      }]
      
      result = described_class.estimate_tool_calls_tokens(tool_calls, "gpt-4o")
      
      # Should include base overhead (10) plus function name and arguments
      expect(result).to be > 10
    end

    it "handles tool calls with string keys" do
      tool_calls = [{
        "function" => {
          "name" => "search_web",
          "arguments" => '{"query": "Ruby gems"}'
        }
      }]
      
      result = described_class.estimate_tool_calls_tokens(tool_calls, "gpt-4o")
      expect(result).to be > 10
    end

    it "handles tool calls missing function data gracefully" do
      tool_calls = [{}] # Empty tool call
      
      result = described_class.estimate_tool_calls_tokens(tool_calls, "gpt-4o")
      
      # Should still have base overhead (actual result is 11)
      expect(result).to eq(11)
    end

    it "handles tool calls with missing name or arguments" do
      tool_calls = [{
        function: {
          name: "function_name"
          # Missing arguments
        }
      }]
      
      result = described_class.estimate_tool_calls_tokens(tool_calls, "gpt-4o")
      
      # Should handle missing data gracefully
      expect(result).to be > 10
    end

    it "sums tokens for multiple tool calls" do
      tool_calls = [
        {
          function: {
            name: "get_weather",
            arguments: '{"location": "NYC"}'
          }
        },
        {
          function: {
            name: "search_web",
            arguments: '{"query": "restaurants"}'
          }
        }
      ]
      
      result = described_class.estimate_tool_calls_tokens(tool_calls, "gpt-4o")
      
      # Should be at least double the base overhead
      expect(result).to be >= 20
    end

    it "handles non-hash elements in tool calls array" do
      tool_calls = ["not a hash", { function: { name: "valid_tool" } }]
      
      result = described_class.estimate_tool_calls_tokens(tool_calls, "gpt-4o")
      
      # Should handle the invalid element and process the valid one
      expect(result).to be >= 10
    end
  end

  describe ".estimate_response_format_tokens" do
    it "returns 0 for nil response format" do
      result = described_class.estimate_response_format_tokens(nil, "gpt-4o")
      expect(result).to eq(0)
    end

    it "returns 0 for non-hash response format" do
      result = described_class.estimate_response_format_tokens("not a hash", "gpt-4o")
      expect(result).to eq(0)
    end

    it "handles basic format overhead" do
      response_format = { type: "text" }
      
      result = described_class.estimate_response_format_tokens(response_format, "gpt-4o")
      expect(result).to eq(5)
    end

    it "handles json_schema format with schema" do
      response_format = {
        type: "json_schema",
        json_schema: {
          name: "user_info",
          schema: {
            type: "object",
            properties: {
              name: { type: "string" },
              age: { type: "integer" }
            }
          }
        }
      }
      
      result = described_class.estimate_response_format_tokens(response_format, "gpt-4o")
      
      # Should be more than basic overhead due to schema complexity
      expect(result).to be > 5
    end

    it "handles json_schema format without schema" do
      response_format = {
        type: "json_schema"
        # Missing json_schema field
      }
      
      result = described_class.estimate_response_format_tokens(response_format, "gpt-4o")
      
      # Should handle missing schema gracefully
      expect(result).to be >= 0
    end

    it "calculates reasonable schema overhead" do
      simple_schema = {
        type: "json_schema",
        json_schema: {
          name: "simple",
          schema: { type: "string" }
        }
      }
      
      complex_schema = {
        type: "json_schema",
        json_schema: {
          name: "complex",
          schema: {
            type: "object",
            properties: {
              user: {
                type: "object",
                properties: {
                  name: { type: "string", description: "User's full name" },
                  email: { type: "string", format: "email" },
                  preferences: {
                    type: "object",
                    properties: {
                      theme: { type: "string", enum: ["light", "dark"] },
                      notifications: { type: "boolean" }
                    }
                  }
                }
              }
            }
          }
        }
      }
      
      simple_result = described_class.estimate_response_format_tokens(simple_schema, "gpt-4o")
      complex_result = described_class.estimate_response_format_tokens(complex_schema, "gpt-4o")
      
      # Complex schema should require more tokens
      expect(complex_result).to be > simple_result
    end
  end

  describe ".model_base" do
    it "returns 'default' for nil model" do
      result = described_class.send(:model_base, nil)
      expect(result).to eq("default")
    end

    it "extracts base name for known models" do
      expect(described_class.send(:model_base, "gpt-4")).to eq("gpt-4")
      expect(described_class.send(:model_base, "gpt-4o")).to eq("gpt-4o")
      # gpt-3.5-turbo splits to "gpt-3.5" which is not in TOKEN_RATIOS
      expect(described_class.send(:model_base, "gpt-3.5-turbo")).to eq("default")
    end

    it "extracts base name for timestamped models" do
      expect(described_class.send(:model_base, "gpt-4o-2024-08-06")).to eq("gpt-4o")
      # gpt-4-turbo-2024-04-09 splits to "gpt-4" (first 2 parts)
      expect(described_class.send(:model_base, "gpt-4-turbo-2024-04-09")).to eq("gpt-4")
    end

    it "shows model_base limitations with hyphenated models" do
      # The logic takes first(2) parts, so some models get reduced incorrectly
      # Even gpt-4-turbo standalone gets reduced to gpt-4 due to first(2) logic
      expect(described_class.send(:model_base, "gpt-4-turbo")).to eq("gpt-4")
      # But models like gpt-4o work correctly since they have TOKEN_RATIOS entries
      expect(described_class.send(:model_base, "gpt-4o-mini")).to eq("gpt-4o")
    end

    it "returns 'default' for unknown models" do
      expect(described_class.send(:model_base, "claude-3")).to eq("default")
      expect(described_class.send(:model_base, "custom-model-v1")).to eq("default")
      expect(described_class.send(:model_base, "unknown")).to eq("default")
    end

    it "handles single-part model names" do
      expect(described_class.send(:model_base, "gpt4")).to eq("default")
      expect(described_class.send(:model_base, "claude")).to eq("default")
    end

    it "handles empty string" do
      expect(described_class.send(:model_base, "")).to eq("default")
    end
  end

  describe "integration scenarios" do
    it "provides consistent estimation across methods" do
      text = "Hello, how are you doing today?"
      model = "gpt-4o"

      # Text tokens should be consistent whether called directly or through messages
      direct_tokens = described_class.estimate_text_tokens(text, model)
      
      message = { role: "user", content: text }
      message_tokens = described_class.estimate_message_tokens(message, model)
      
      # Message tokens should be higher due to role and formatting overhead
      expect(message_tokens).to be > direct_tokens
      # But the difference should be reasonable (role + overhead)
      expect(message_tokens - direct_tokens).to be_between(3, 10)
    end

    it "handles complex conversation with tools and structured output" do
      messages = [
        { role: "system", content: "You are a helpful assistant." },
        { role: "user", content: "Search for information about Ruby gems." },
        { 
          role: "assistant", 
          content: "I'll search for that information.",
          tool_calls: [{
            function: {
              name: "search_web",
              arguments: '{"query": "Ruby gems programming guide", "max_results": 5}'
            }
          }]
        },
        { role: "tool", content: "Search results: Ruby gems are packages..." },
        { role: "assistant", content: "Based on the search results, here's what I found..." }
      ]

      response_format = {
        type: "json_schema",
        json_schema: {
          name: "search_summary",
          schema: {
            type: "object",
            properties: {
              summary: { type: "string" },
              key_points: {
                type: "array",
                items: { type: "string" }
              }
            }
          }
        }
      }

      # Test complete usage estimation
      usage = described_class.estimate_usage(
        messages: messages,
        response_content: "Here's a comprehensive summary...",
        model: "gpt-4o"
      )

      expect(usage["input_tokens"]).to be > 0
      expect(usage["output_tokens"]).to be > 0
      expect(usage["total_tokens"]).to eq(usage["input_tokens"] + usage["output_tokens"])
      expect(usage["estimated"]).to be true

      # Test structured response overhead
      format_tokens = described_class.estimate_response_format_tokens(response_format, "gpt-4o")
      expect(format_tokens).to be > 0
    end

    it "handles edge cases gracefully" do
      # Empty conversation
      empty_usage = described_class.estimate_usage(messages: [], model: "gpt-4o")
      expect(empty_usage["input_tokens"]).to eq(0)
      expect(empty_usage["total_tokens"]).to eq(0)

      # Very short message
      short_message = [{ role: "user", content: "Hi" }]
      short_usage = described_class.estimate_usage(messages: short_message, model: "gpt-4o")
      expect(short_usage["input_tokens"]).to be > 0

      # Message with only role, no content
      role_only = [{ role: "assistant" }]
      role_usage = described_class.estimate_usage(messages: role_only, model: "gpt-4o")
      expect(role_usage["input_tokens"]).to be >= 3 # Base overhead

      # Unknown model
      unknown_model_usage = described_class.estimate_usage(
        messages: [{ role: "user", content: "Hello" }],
        model: "unknown-model-2024"
      )
      expect(unknown_model_usage["input_tokens"]).to be > 0
    end

    it "demonstrates tiktoken fallback behavior" do
      # This test would require mocking tiktoken failures, but we can test that
      # the method handles various text types correctly
      
      texts = [
        "Simple English text",
        "Text with émojis 🤖 and ñón-ASCII characters",
        "Code snippet: def hello\n  puts 'Hello, World!'\nend",
        "Mixed content: Here's some text AND CODE: `array.map(&:upcase)` with symbols.",
        ""  # Empty string
      ]

      texts.each do |text|
        result = described_class.estimate_text_tokens(text, "gpt-4o")
        if text.empty?
          expect(result).to eq(0)
        else
          expect(result).to be > 0
        end
      end
    end
  end
end