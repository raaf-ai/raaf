# frozen_string_literal: true

require "spec_helper"
require_relative "../../lib/raaf/models/provider_adapter"
require_relative "../../lib/raaf/models/interface"

RSpec.describe RAAF::Models::ProviderAdapter do
  # Mock providers for testing
  let(:function_calling_provider) do
    Class.new(RAAF::Models::ModelInterface) do
      def chat_completion(messages:, model:, tools: nil, stream: false, **_kwargs)
        {
          "choices" => [{
            "message" => {
              "role" => "assistant",
              "content" => "Test response",
              "tool_calls" => if tools&.any?
                                [{
                                  "id" => "call_123",
                                  "type" => "function",
                                  "function" => {
                                    "name" => "transfer_to_support",
                                    "arguments" => "{}"
                                  }
                                }]
                              end
            }
          }],
          "usage" => { "prompt_tokens" => 10, "completion_tokens" => 5, "total_tokens" => 15 }
        }
      end

      def responses_completion(messages:, model:, tools: nil, **_kwargs)
        {
          output: [{
            type: "message",
            role: "assistant",
            content: "Test response"
          }],
          usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 }
        }
      end

      def supported_models
        ["test-model-v1"]
      end

      def provider_name
        "FunctionCallingProvider"
      end
    end.new
  end

  let(:non_function_calling_provider) do
    Class.new(RAAF::Models::ModelInterface) do
      def chat_completion(messages:, model:, stream: false, **_kwargs)
        # NOTE: No tools parameter
        {
          "choices" => [{
            "message" => {
              "role" => "assistant",
              "content" => 'I can help you. {"handoff_to": "SupportAgent"}'
            }
          }],
          "usage" => { "prompt_tokens" => 8, "completion_tokens" => 12, "total_tokens" => 20 }
        }
      end

      def supported_models
        ["non-function-model-v1"]
      end

      def provider_name
        "NonFunctionCallingProvider"
      end
    end.new
  end

  let(:limited_function_calling_provider) do
    Class.new(RAAF::Models::ModelInterface) do
      def chat_completion(messages:, model:, tools: nil, stream: false, **_kwargs)
        # Accepts tools but doesn't always use them correctly
        if tools && rand < 0.5
          {
            "choices" => [{
              "message" => {
                "role" => "assistant",
                "content" => "Using tools",
                "tool_calls" => [{
                  "id" => "call_456",
                  "type" => "function",
                  "function" => {
                    "name" => "transfer_to_billing",
                    "arguments" => "{}"
                  }
                }]
              }
            }],
            "usage" => { "prompt_tokens" => 15, "completion_tokens" => 8, "total_tokens" => 23 }
          }
        else
          {
            "choices" => [{
              "message" => {
                "role" => "assistant",
                "content" => "Transfer to BillingAgent for help."
              }
            }],
            "usage" => { "prompt_tokens" => 12, "completion_tokens" => 6, "total_tokens" => 18 }
          }
        end
      end

      def supported_models
        ["limited-function-model-v1"]
      end

      def provider_name
        "LimitedFunctionCallingProvider"
      end
    end.new
  end

  let(:available_agents) { %w[SupportAgent BillingAgent TechnicalAgent] }

  describe "#initialize" do
    context "with function calling provider" do
      subject { described_class.new(function_calling_provider, available_agents) }

      it "initializes with correct capabilities" do
        expect(subject.capabilities[:function_calling]).to be true
        expect(subject.capabilities[:responses_api]).to be true
        expect(subject.capabilities[:chat_completion]).to be true
      end

      it "sets up logging correctly" do
        expect { subject }.not_to raise_error
      end
    end

    context "with non-function calling provider" do
      subject { described_class.new(non_function_calling_provider, available_agents) }

      it "initializes with correct capabilities" do
        expect(subject.capabilities[:function_calling]).to be false
        expect(subject.capabilities[:chat_completion]).to be true
        expect(subject.capabilities[:responses_api]).to be false
      end

      it "initializes fallback system" do
        expect(subject.get_handoff_stats).to include(:available_agents)
        expect(subject.get_handoff_stats[:available_agents]).to eq(available_agents)
      end
    end

    context "without available agents" do
      subject { described_class.new(function_calling_provider) }

      it "initializes with empty agent list" do
        expect(subject.get_handoff_stats[:available_agents]).to eq([])
      end
    end
  end

  describe "#universal_completion" do
    let(:test_messages) { [{ role: "user", content: "Help me with billing" }] }
    let(:test_model) { "test-model" }

    context "with function calling provider" do
      subject { described_class.new(function_calling_provider, available_agents) }

      it "uses responses_completion when available" do
        expect(function_calling_provider).to receive(:responses_completion).and_call_original

        result = subject.universal_completion(
          messages: test_messages,
          model: test_model,
          tools: []
        )

        expect(result).to have_key(:output)
      end

      it "passes tools correctly" do
        test_tools = [{ type: "function", name: "test_tool" }]

        expect(function_calling_provider).to receive(:responses_completion)
          .with(hash_including(tools: test_tools))
          .and_call_original

        subject.universal_completion(
          messages: test_messages,
          model: test_model,
          tools: test_tools
        )
      end
    end

    context "with non-function calling provider" do
      subject { described_class.new(non_function_calling_provider, available_agents) }

      it "uses chat_completion when responses_completion not available" do
        expect(non_function_calling_provider).to receive(:chat_completion).at_least(:once).and_call_original

        result = subject.universal_completion(
          messages: test_messages,
          model: test_model
        )

        expect(result).to have_key(:output)
      end

      it "converts chat completion response to responses format" do
        result = subject.universal_completion(
          messages: test_messages,
          model: test_model
        )

        expect(result[:output]).to be_an(Array)
        expect(result[:output].first).to include(type: "message", role: "assistant")
      end
    end

    context "with provider that supports neither API" do
      subject { described_class.new(incompatible_provider) }

      let(:incompatible_provider) do
        Class.new(RAAF::Models::ModelInterface) do
          def supported_models
            ["incompatible-model"]
          end

          def provider_name
            "IncompatibleProvider"
          end
        end.new
      end

      it "raises appropriate error" do
        expect do
          subject.universal_completion(
            messages: test_messages,
            model: test_model
          )
        end.to raise_error(RAAF::ProviderError, /doesn't support any known completion API/)
      end
    end
  end

  describe "#supports_handoffs?" do
    context "with function calling provider" do
      subject { described_class.new(function_calling_provider) }

      it "returns true" do
        expect(subject.supports_handoffs?).to be true
      end
    end

    context "with non-function calling provider" do
      subject { described_class.new(non_function_calling_provider) }

      it "returns true (with fallback)" do
        expect(subject.supports_handoffs?).to be true
      end
    end

    context "with incompatible provider" do
      subject { described_class.new(incompatible_provider) }

      let(:incompatible_provider) do
        Class.new(RAAF::Models::ModelInterface) do
          def supported_models = []
          def provider_name = "Incompatible"
        end.new
      end

      it "returns false" do
        expect(subject.supports_handoffs?).to be false
      end
    end
  end

  describe "#update_available_agents" do
    subject { described_class.new(non_function_calling_provider, ["Agent1"]) }

    it "updates the fallback system with new agents" do
      new_agents = %w[Agent2 Agent3]
      subject.update_available_agents(new_agents)

      stats = subject.get_handoff_stats
      expect(stats[:available_agents]).to eq(new_agents)
    end
  end

  describe "#get_enhanced_system_instructions" do
    let(:base_instructions) { "You are a helpful assistant." }

    context "with function calling provider" do
      subject { described_class.new(function_calling_provider) }

      it "returns base instructions unchanged" do
        result = subject.get_enhanced_system_instructions(base_instructions, available_agents)
        expect(result).to eq(base_instructions)
      end
    end

    context "with non-function calling provider" do
      subject { described_class.new(non_function_calling_provider, available_agents) }

      it "no longer adds handoff instructions (deprecated)" do
        result = subject.get_enhanced_system_instructions(base_instructions, available_agents)
        expect(result).to eq(base_instructions)
      end
    end
  end

  describe "#detect_content_based_handoff" do
    context "with function calling provider" do
      subject { described_class.new(function_calling_provider) }

      it "returns nil (not applicable)" do
        result = subject.detect_content_based_handoff('{"handoff_to": "SupportAgent"}')
        expect(result).to be_nil
      end
    end

    context "with non-function calling provider" do
      subject { described_class.new(non_function_calling_provider, available_agents) }

      it "no longer detects JSON handoff format (deprecated)" do
        content = 'I need to transfer you. {"handoff_to": "SupportAgent"}'
        result = subject.detect_content_based_handoff(content)
        expect(result).to be_nil
      end

      it "no longer detects structured handoff format (deprecated)" do
        content = "Let me transfer you. [HANDOFF:BillingAgent]"
        result = subject.detect_content_based_handoff(content)
        expect(result).to be_nil
      end

      it "no longer detects natural language handoff (deprecated)" do
        content = "Transfer to TechnicalAgent for help."
        result = subject.detect_content_based_handoff(content)
        expect(result).to be_nil
      end

      it "returns nil for no handoff" do
        content = "This is just a regular response."
        result = subject.detect_content_based_handoff(content)
        expect(result).to be_nil
      end

      it "returns nil for unrecognized agent" do
        content = '{"handoff_to": "UnknownAgent"}'
        result = subject.detect_content_based_handoff(content)
        expect(result).to be_nil
      end
    end
  end

  describe "delegation methods" do
    subject { described_class.new(function_calling_provider) }

    it "delegates responses_completion" do
      expect(subject.responses_completion(
               messages: [{ role: "user", content: "test" }],
               model: "test-model"
             )).to be_a(Hash)
    end

    it "delegates chat_completion" do
      expect(subject.chat_completion(
               messages: [{ role: "user", content: "test" }],
               model: "test-model"
             )).to be_a(Hash)
    end

    it "delegates stream_completion" do
      expect(subject.stream_completion(
               messages: [{ role: "user", content: "test" }],
               model: "test-model"
             )).to be_a(Hash)
    end
  end

  describe "method delegation" do
    subject { described_class.new(function_calling_provider) }

    it "delegates supported_models" do
      expect(subject.supported_models).to eq(["test-model-v1"])
    end

    it "delegates provider_name" do
      expect(subject.provider_name).to eq("FunctionCallingProvider")
    end

    it "raises NoMethodError for unsupported methods" do
      expect { subject.non_existent_method }.to raise_error(NoMethodError)
    end
  end

  describe "#get_handoff_stats" do
    subject { described_class.new(non_function_calling_provider, available_agents) }

    it "returns statistics from fallback system" do
      stats = subject.get_handoff_stats
      expect(stats).to include(:total_attempts, :successful_detections, :success_rate, :available_agents)
      expect(stats[:available_agents]).to eq(available_agents)
    end
  end

  describe "error handling" do
    subject { described_class.new(error_provider) }

    let(:error_provider) do
      Class.new(RAAF::Models::ModelInterface) do
        def chat_completion(messages:, model:, **_kwargs)
          raise StandardError, "Provider error"
        end

        def supported_models = ["error-model"]
        def provider_name = "ErrorProvider"
      end.new
    end

    it "propagates provider errors" do
      expect do
        subject.universal_completion(
          messages: [{ role: "user", content: "test" }],
          model: "test-model"
        )
      end.to raise_error(StandardError, "Provider error")
    end
  end

  describe "message logging" do
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

    let(:adapter) { described_class.new(test_provider, ["TestAgent"]) }
    let(:logged_messages) { [] }

    before do
      # Capture log messages
      allow(adapter).to receive(:log_debug_api) do |message, **context|
        logged_messages << { message: message, context: context }
      end
    end

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

    describe "message inspection utilities" do
      let(:adapter_with_inspection) { described_class.new(test_provider) }

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
end
