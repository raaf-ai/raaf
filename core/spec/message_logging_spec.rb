# frozen_string_literal: true

require "spec_helper"
require_relative "../lib/raaf/models/provider_adapter"
require_relative "../lib/raaf/models/interface"

RSpec.describe "Message Logging" do
  let(:test_provider) do
    Class.new(RAAF::Models::ModelInterface) do
      def chat_completion(messages:, model:, tools: nil, stream: false, **_kwargs)
        {
          "choices" => [{
            "message" => {
              "role" => "assistant",
              "content" => "Test response from provider",
              "tool_calls" => if tools&.any?
                                [{
                                  "id" => "call_123",
                                  "type" => "function",
                                  "function" => {
                                    "name" => "test_function",
                                    "arguments" => "{\"param\": \"value\"}"
                                  }
                                }]
                              end
            }
          }],
          "usage" => {
            "prompt_tokens" => 10,
            "completion_tokens" => 15,
            "total_tokens" => 25
          },
          "model" => model,
          "id" => "test_response_123"
        }
      end

      def supported_models
        ["test-model-v1"]
      end

      def provider_name
        "TestProvider"
      end
    end.new
  end

  let(:test_tools) do
    [{
      type: "function",
      name: "test_function",
      function: {
        name: "test_function",
        description: "A test function",
        parameters: {
          type: "object",
          properties: {
            param: { type: "string" }
          }
        }
      }
    }]
  end

  let(:test_messages) do
    [
      { role: "system", content: "You are a test assistant" },
      { role: "user", content: "Hello, can you help me?" }
    ]
  end

  let(:adapter) { RAAF::Models::ProviderAdapter.new(test_provider, ["TestAgent"]) }
  let(:logged_messages) { [] }

  before do
    # Capture log messages
    allow(adapter).to receive(:log_debug_api) do |message, **context|
      logged_messages << { message: message, context: context }
    end
  end

  describe "Provider-independent message logging" do
    context "when making API calls" do
      it "logs outgoing request details" do
        adapter.universal_completion(
          messages: test_messages,
          model: "test-model-v1",
          tools: test_tools
        )

        # Check for request logging
        request_logs = logged_messages.select { |log| log[:message].include?("PROVIDER REQUEST") }
        expect(request_logs).not_to be_empty

        # Check main request log
        main_request_log = request_logs.find { |log| log[:message].include?("Sending to TestProvider endpoint") }
        expect(main_request_log).not_to be_nil
        expect(main_request_log[:context][:model]).to eq("test-model-v1")
        expect(main_request_log[:context][:message_count]).to eq(2)
        expect(main_request_log[:context][:tools_count]).to eq(1)
        expect(main_request_log[:context][:api_type]).to eq("Chat Completions")
      end

      it "logs message details" do
        adapter.universal_completion(
          messages: test_messages,
          model: "test-model-v1"
        )

        # Check for message details logging
        message_logs = logged_messages.select { |log| log[:message].include?("Message details") }
        expect(message_logs).not_to be_empty

        message_log = message_logs.first
        expect(message_log[:context][:messages]).to be_an(Array)
        expect(message_log[:context][:messages].size).to eq(2)

        # Check message structure
        first_message = message_log[:context][:messages][0]
        expect(first_message[:role]).to eq("system")
        expect(first_message[:content_length]).to eq("You are a test assistant".length)
        expect(first_message[:content_preview]).to include("You are a test assistant")
      end

      it "logs tool details when tools are provided" do
        adapter.universal_completion(
          messages: test_messages,
          model: "test-model-v1",
          tools: test_tools
        )

        # Check for tool details logging
        tool_logs = logged_messages.select { |log| log[:message].include?("Tool details") }
        expect(tool_logs).not_to be_empty

        tool_log = tool_logs.first
        expect(tool_log[:context][:tools]).to be_an(Array)
        expect(tool_log[:context][:tools].size).to eq(1)

        # Check tool structure
        first_tool = tool_log[:context][:tools][0]
        expect(first_tool[:name]).to eq("test_function")
        expect(first_tool[:type]).to eq("function")
        expect(first_tool[:description]).to eq("A test function")
        expect(first_tool[:properties_count]).to eq(1)
      end

      it "logs incoming response details" do
        adapter.universal_completion(
          messages: test_messages,
          model: "test-model-v1",
          tools: test_tools
        )

        # Check for response logging
        response_logs = logged_messages.select { |log| log[:message].include?("PROVIDER RESPONSE") }
        expect(response_logs).not_to be_empty

        # Check main response log
        main_response_log = response_logs.find { |log| log[:message].include?("Received from TestProvider endpoint") }
        expect(main_response_log).not_to be_nil
        expect(main_response_log[:context][:api_type]).to eq("Chat Completions")
        expect(main_response_log[:context][:raw_response_keys]).to include("choices", "usage", "model", "id")
        expect(main_response_log[:context][:normalized_response_keys]).to include(:output, :usage, :model)
      end

      it "logs raw response details" do
        adapter.universal_completion(
          messages: test_messages,
          model: "test-model-v1",
          tools: test_tools
        )

        # Check for raw response details
        raw_response_logs = logged_messages.select { |log| log[:message].include?("Raw response details") }
        expect(raw_response_logs).not_to be_empty

        raw_log = raw_response_logs.first
        expect(raw_log[:context][:raw_response][:type]).to eq("chat_completions")
        expect(raw_log[:context][:raw_response][:choices_count]).to eq(1)
        expect(raw_log[:context][:raw_response][:first_choice]).to include(
          role: "assistant",
          has_tool_calls: true,
          tool_calls_count: 1
        )
      end

      it "logs normalized response details" do
        adapter.universal_completion(
          messages: test_messages,
          model: "test-model-v1",
          tools: test_tools
        )

        # Check for normalized response details
        normalized_logs = logged_messages.select { |log| log[:message].include?("Normalized response details") }
        expect(normalized_logs).not_to be_empty

        normalized_log = normalized_logs.first
        expect(normalized_log[:context][:normalized_response][:type]).to eq("responses_api")
        expect(normalized_log[:context][:normalized_response][:output_count]).to eq(2) # message + function_call
        expect(normalized_log[:context][:normalized_response][:output_types]).to include("message", "function_call")
        expect(normalized_log[:context][:normalized_response][:output_type_counts]).to eq({
                                                                                            "message" => 1,
                                                                                            "function_call" => 1
                                                                                          })
      end

      it "logs output details" do
        adapter.universal_completion(
          messages: test_messages,
          model: "test-model-v1",
          tools: test_tools
        )

        # Check for output details logging
        output_logs = logged_messages.select { |log| log[:message].include?("Output details") }
        expect(output_logs).not_to be_empty

        output_log = output_logs.first
        expect(output_log[:context][:output]).to be_an(Array)
        expect(output_log[:context][:output].size).to eq(2)

        # Check message output
        message_output = output_log[:context][:output][0]
        expect(message_output[:type]).to eq("message")
        expect(message_output[:role]).to eq("assistant")
        expect(message_output[:content_length]).to eq("Test response from provider".length)

        # Check function call output
        function_output = output_log[:context][:output][1]
        expect(function_output[:type]).to eq("function_call")
        expect(function_output[:function_name]).to eq("test_function")
        expect(function_output[:function_id]).to eq("call_123")
        expect(function_output[:has_arguments]).to be true
      end

      it "logs usage details" do
        adapter.universal_completion(
          messages: test_messages,
          model: "test-model-v1"
        )

        # Check for usage details logging
        usage_logs = logged_messages.select { |log| log[:message].include?("Usage details") }
        expect(usage_logs).not_to be_empty

        usage_log = usage_logs.first
        expect(usage_log[:context][:usage]).to include(
          prompt_tokens: 10,
          completion_tokens: 15,
          total_tokens: 25,
          all_keys: %w[prompt_tokens completion_tokens total_tokens]
        )
      end

      it "logs API format conversion" do
        adapter.universal_completion(
          messages: test_messages,
          model: "test-model-v1",
          tools: test_tools
        )

        # Check for conversion logging
        conversion_logs = logged_messages.select { |log| log[:message].include?("Normalizing Chat Completions") }
        expect(conversion_logs).not_to be_empty

        # Check completion logging
        completion_logs = logged_messages.select { |log| log[:message].include?("Completed normalization") }
        expect(completion_logs).not_to be_empty

        completion_log = completion_logs.first
        expect(completion_log[:context][:output_items]).to eq(2)
        expect(completion_log[:context][:has_usage]).to be true
        expect(completion_log[:context][:model]).to eq("test-model-v1")
      end

      it "logs additional parameters when provided" do
        adapter.universal_completion(
          messages: test_messages,
          model: "test-model-v1",
          temperature: 0.7,
          max_tokens: 100
        )

        # Check for additional parameters logging
        param_logs = logged_messages.select { |log| log[:message].include?("Additional parameters") }
        expect(param_logs).not_to be_empty

        param_log = param_logs.first
        expect(param_log[:context][:parameters]).to include(
          temperature: 0.7,
          max_tokens: 100
        )
      end
    end

    context "with different provider types" do
      it "works with any provider that implements the interface" do
        # The adapter automatically detects capabilities and logs accordingly
        expect(adapter.capabilities[:chat_completion]).to be true
        expect(adapter.capabilities[:function_calling]).to be true
        expect(adapter.capabilities[:responses_api]).to be false

        adapter.universal_completion(
          messages: test_messages,
          model: "test-model-v1"
        )

        # Should have logged the API type correctly
        api_logs = logged_messages.select { |log| log[:message].include?("endpoint") }
        expect(api_logs).not_to be_empty
        expect(api_logs.first[:context][:api_type]).to eq("Chat Completions")
      end
    end
  end

  describe "Message inspection utilities" do
    let(:adapter_with_inspection) { RAAF::Models::ProviderAdapter.new(test_provider) }

    it "properly determines content types" do
      messages = [
        { role: "user", content: "string content" },
        { role: "user", content: %w[array content] },
        { role: "user", content: { type: "hash" } },
        { role: "user", content: nil },
        { role: "user", content: "" }
      ]

      # Use send to access private method for testing
      result = adapter_with_inspection.send(:inspect_messages, messages)

      expect(result[0][:content_type]).to eq("string")
      expect(result[1][:content_type]).to eq("array")
      expect(result[2][:content_type]).to eq("hash")
      expect(result[3][:content_type]).to eq("nil")
      expect(result[4][:content_type]).to eq("empty")
    end

    it "properly truncates long content" do
      long_content = "a" * 150
      message = { role: "user", content: long_content }

      result = adapter_with_inspection.send(:inspect_messages, [message])

      expect(result[0][:content_length]).to eq(150)
      expect(result[0][:content_preview]).to end_with("...")
      expect(result[0][:content_preview].length).to eq(101) # 100 chars + "..." (but actual length is 101)
    end

    it "properly counts tool properties" do
      tool_with_properties = {
        type: "function",
        name: "test_tool",
        function: {
          name: "test_tool",
          description: "Test tool",
          parameters: {
            type: "object",
            properties: {
              param1: { type: "string" },
              param2: { type: "number" },
              param3: { type: "boolean" }
            }
          }
        }
      }

      result = adapter_with_inspection.send(:inspect_tools, [tool_with_properties])

      expect(result[0][:properties_count]).to eq(3)
      expect(result[0][:name]).to eq("test_tool")
      expect(result[0][:description]).to eq("Test tool")
    end
  end
end
