# frozen_string_literal: true

require "spec_helper"
require "raaf/ollama_provider"

# Integration tests for OllamaProvider
#
# These tests require a running Ollama instance with llama3.2 model pulled.
# To run these tests, set OLLAMA_INTEGRATION_TESTS=true environment variable.
#
# Setup:
#   1. Install Ollama: https://ollama.ai/
#   2. Start Ollama: ollama serve
#   3. Pull llama3.2: ollama pull llama3.2
#   4. Run tests: OLLAMA_INTEGRATION_TESTS=true bundle exec rspec spec/integration/ollama_integration_spec.rb
#
RSpec.describe RAAF::Models::OllamaProvider, :integration do
  # Skip all integration tests unless explicitly enabled
  before(:all) do
    unless ENV["OLLAMA_INTEGRATION_TESTS"] == "true"
      skip "Integration tests are disabled. Set OLLAMA_INTEGRATION_TESTS=true to run."
    end
  end

  let(:provider) { described_class.new }
  let(:model) { "llama3.2" }
  let(:messages) { [{ role: "user", content: "Say 'Hello from Ollama!' and nothing else." }] }

  describe "chat completion" do
    it "successfully completes a chat request" do
      result = provider.perform_chat_completion(messages: messages, model: model)

      expect(result).to be_a(Hash)
      expect(result[:id]).to be_a(String)
      expect(result[:object]).to eq("chat.completion")
      expect(result[:model]).to eq(model)
      expect(result[:choices]).to be_an(Array)
      expect(result[:choices].first[:message][:content]).to include("Hello")
      expect(result[:usage]).to be_a(Hash)
      expect(result[:usage][:input_tokens]).to be > 0
      expect(result[:usage][:output_tokens]).to be > 0
    end

    it "respects temperature parameter" do
      result = provider.perform_chat_completion(
        messages: [{ role: "user", content: "Generate a random number between 1 and 10." }],
        model: model,
        temperature: 0.0 # Very deterministic
      )

      expect(result[:choices].first[:message][:content]).to match(/\d+/)
    end

    it "respects max_tokens parameter" do
      result = provider.perform_chat_completion(
        messages: [{ role: "user", content: "Write a long story." }],
        model: model,
        max_tokens: 10
      )

      # Should have fewer tokens due to max_tokens limit
      expect(result[:usage][:output_tokens]).to be <= 15
    end
  end

  describe "streaming" do
    it "successfully streams a chat response" do
      chunks = []
      accumulated_content = ""

      provider.perform_stream_completion(messages: messages, model: model) do |chunk|
        chunks << chunk
        accumulated_content += chunk[:content] if chunk[:type] == "content"
      end

      expect(chunks).not_to be_empty
      expect(accumulated_content).to include("Hello")

      # Check final chunk has metadata
      final_chunk = chunks.last
      expect(final_chunk[:type]).to eq("finish")
      expect(final_chunk[:finish_reason]).to eq("stop")
      expect(final_chunk[:usage]).to be_a(Hash)
      expect(final_chunk[:usage][:input_tokens]).to be > 0
    end

    it "yields progressive content chunks" do
      content_chunks = []

      provider.perform_stream_completion(messages: messages, model: model) do |chunk|
        content_chunks << chunk[:content] if chunk[:type] == "content"
      end

      # Should have multiple progressive chunks
      expect(content_chunks.count).to be > 1
    end
  end

  describe "tool calling" do
    let(:get_weather_tool) do
      {
        type: "function",
        function: {
          name: "get_weather",
          description: "Get current weather for a location",
          parameters: {
            type: "object",
            properties: {
              location: {
                type: "string",
                description: "City name"
              }
            },
            required: ["location"]
          }
        }
      }
    end

    let(:tool_messages) do
      [
        {
          role: "user",
          content: "What's the weather in Tokyo?"
        }
      ]
    end

    it "successfully calls tools" do
      result = provider.perform_chat_completion(
        messages: tool_messages,
        model: model,
        tools: [get_weather_tool]
      )

      expect(result[:choices]).to be_an(Array)
      choice = result[:choices].first

      # Should either call the tool or respond with text
      if choice[:message][:tool_calls]
        tool_call = choice[:message][:tool_calls].first
        expect(tool_call[:function][:name]).to eq("get_weather")
        expect(tool_call[:function][:arguments]).to be_a(String)

        # Parse arguments
        args = JSON.parse(tool_call[:function][:arguments])
        expect(args["location"]).to include("Tokyo")
      else
        # If no tool call, should mention weather
        expect(choice[:message][:content]).to match(/weather|temperature/i)
      end
    end
  end

  describe "multi-turn conversation" do
    it "maintains conversation context" do
      # First message
      first_messages = [
        { role: "user", content: "My name is Alice. Remember this." }
      ]

      first_result = provider.perform_chat_completion(
        messages: first_messages,
        model: model
      )

      # Second message - should remember the name
      second_messages = first_messages + [
        { role: "assistant", content: first_result[:choices].first[:message][:content] },
        { role: "user", content: "What is my name?" }
      ]

      second_result = provider.perform_chat_completion(
        messages: second_messages,
        model: model
      )

      # Response should mention Alice
      response = second_result[:choices].first[:message][:content]
      expect(response).to match(/Alice/i)
    end
  end

  describe "error handling" do
    it "raises ModelNotFoundError for non-existent model" do
      expect {
        provider.perform_chat_completion(
          messages: messages,
          model: "nonexistent-model-12345"
        )
      }.to raise_error(RAAF::Models::ModelNotFoundError, /Model not found/)
    end

    it "handles connection errors gracefully when Ollama is not running" do
      # Create provider with invalid host
      invalid_provider = described_class.new(host: "http://localhost:99999")

      expect {
        invalid_provider.perform_chat_completion(
          messages: messages,
          model: model
        )
      }.to raise_error(RAAF::Models::ConnectionError, /Ollama not running/)
    end
  end
end
