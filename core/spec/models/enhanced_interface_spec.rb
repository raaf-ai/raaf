# frozen_string_literal: true

require "spec_helper"
require_relative "../../lib/raaf/models/enhanced_interface"

RSpec.describe RAAF::Models::EnhancedModelInterface do
  let(:test_provider_class) do
    Class.new(described_class) do
      def chat_completion(messages:, model:, tools: nil, stream: false, **kwargs)
        {
          "choices" => [{
            "message" => {
              "role" => "assistant",
              "content" => "Test response from chat completion",
              "tool_calls" => tools&.any? ? [{
                "id" => "call_123",
                "type" => "function",
                "function" => {
                  "name" => "transfer_to_support",
                  "arguments" => "{}"
                }
              }] : nil
            }
          }],
          "usage" => {
            "prompt_tokens" => 20,
            "completion_tokens" => 10,
            "total_tokens" => 30
          },
          "model" => model,
          "id" => "chat_completion_123"
        }
      end

      def supported_models
        ["enhanced-test-model-v1"]
      end

      def provider_name
        "EnhancedTestProvider"
      end
    end
  end

  let(:test_provider) { test_provider_class.new }
  let(:test_messages) { [{ role: "user", content: "Hello, I need help" }] }
  let(:test_model) { "enhanced-test-model-v1" }
  let(:test_tools) do
    [
      {
        type: "function",
        name: "transfer_to_support",
        function: {
          name: "transfer_to_support",
          description: "Transfer to support agent",
          parameters: { type: "object", properties: {} }
        }
      }
    ]
  end

  describe "#responses_completion" do
    context "with basic message conversion" do
      it "converts chat completion to responses format" do
        result = test_provider.responses_completion(
          messages: test_messages,
          model: test_model
        )

        expect(result).to include(:output, :usage, :model, :id)
        expect(result[:output]).to be_an(Array)
        expect(result[:output].first).to include(
          type: "message",
          role: "assistant",
          content: "Test response from chat completion"
        )
      end

      it "preserves usage information" do
        result = test_provider.responses_completion(
          messages: test_messages,
          model: test_model
        )

        expect(result[:usage]).to eq({
          "prompt_tokens" => 20,
          "completion_tokens" => 10,
          "total_tokens" => 30
        })
      end

      it "preserves model information" do
        result = test_provider.responses_completion(
          messages: test_messages,
          model: test_model
        )

        expect(result[:model]).to eq(test_model)
      end

      it "includes response ID" do
        result = test_provider.responses_completion(
          messages: test_messages,
          model: test_model
        )

        expect(result[:id]).to eq("chat_completion_123")
      end
    end

    context "with tool calls" do
      it "converts tool calls to function call format" do
        result = test_provider.responses_completion(
          messages: test_messages,
          model: test_model,
          tools: test_tools
        )

        expect(result[:output]).to have(2).items
        
        # First item should be the text message
        expect(result[:output][0]).to include(
          type: "message",
          role: "assistant"
        )

        # Second item should be the function call
        expect(result[:output][1]).to include(
          type: "function_call",
          id: "call_123",
          name: "transfer_to_support",
          arguments: "{}"
        )
      end

      it "handles multiple tool calls" do
        # Modify provider to return multiple tool calls
        multi_tool_provider = Class.new(described_class) do
          def chat_completion(messages:, model:, tools: nil, **kwargs)
            {
              "choices" => [{
                "message" => {
                  "role" => "assistant",
                  "content" => "Multiple tools",
                  "tool_calls" => [
                    {
                      "id" => "call_1",
                      "type" => "function",
                      "function" => { "name" => "tool_1", "arguments" => "{}" }
                    },
                    {
                      "id" => "call_2",
                      "type" => "function", 
                      "function" => { "name" => "tool_2", "arguments" => "{}" }
                    }
                  ]
                }
              }],
              "usage" => { "total_tokens" => 25 }
            }
          end

          def supported_models; ["multi-tool-model"]; end
          def provider_name; "MultiToolProvider"; end
        end.new

        result = multi_tool_provider.responses_completion(
          messages: test_messages,
          model: "multi-tool-model",
          tools: test_tools
        )

        expect(result[:output]).to have(3).items # 1 message + 2 function calls
        
        function_calls = result[:output].select { |item| item[:type] == "function_call" }
        expect(function_calls).to have(2).items
        expect(function_calls[0][:name]).to eq("tool_1")
        expect(function_calls[1][:name]).to eq("tool_2")
      end
    end

    context "with input items (Responses API continuation)" do
      let(:input_items) do
        [
          {
            type: "message",
            role: "user",
            content: "Follow-up question"
          },
          {
            type: "function_call_output",
            call_id: "call_456",
            output: "Tool execution result"
          }
        ]
      end

      it "converts input items back to messages" do
        expect(test_provider).to receive(:chat_completion) do |args|
          messages = args[:messages]
          expect(messages).to have(3).items
          
          # Original messages
          expect(messages[0]).to eq({ role: "user", content: "Hello, I need help" })
          
          # Converted from input items
          expect(messages[1]).to eq({ role: "user", content: "Follow-up question" })
          expect(messages[2]).to eq({
            role: "tool",
            tool_call_id: "call_456",
            content: "Tool execution result"
          })

          # Return standard response
          {
            "choices" => [{ "message" => { "role" => "assistant", "content" => "Response" } }],
            "usage" => { "total_tokens" => 15 }
          }
        end

        test_provider.responses_completion(
          messages: test_messages,
          model: test_model,
          input: input_items
        )
      end
    end

    context "with streaming" do
      it "passes stream parameter to chat_completion" do
        expect(test_provider).to receive(:chat_completion)
          .with(hash_including(stream: true))
          .and_call_original

        test_provider.responses_completion(
          messages: test_messages,
          model: test_model,
          stream: true
        )
      end
    end

    context "with additional parameters" do
      it "passes through additional kwargs" do
        custom_params = {
          temperature: 0.7,
          max_tokens: 100,
          top_p: 0.9
        }

        expect(test_provider).to receive(:chat_completion)
          .with(hash_including(custom_params))
          .and_call_original

        test_provider.responses_completion(
          messages: test_messages,
          model: test_model,
          **custom_params
        )
      end
    end

    context "error handling" do
      let(:error_provider) do
        Class.new(described_class) do
          def chat_completion(messages:, model:, **kwargs)
            raise StandardError, "Provider error"
          end

          def supported_models; ["error-model"]; end
          def provider_name; "ErrorProvider"; end
        end.new
      end

      it "propagates errors from chat_completion" do
        expect {
          error_provider.responses_completion(
            messages: test_messages,
            model: "error-model"
          )
        }.to raise_error(StandardError, "Provider error")
      end
    end

    context "with edge cases" do
      let(:edge_case_provider) do
        Class.new(described_class) do
          def chat_completion(messages:, model:, **kwargs)
            {
              "choices" => [{
                "message" => {
                  "role" => "assistant",
                  "content" => nil # Nil content
                }
              }],
              "usage" => nil, # Nil usage
              "model" => nil  # Nil model
            }
          end

          def supported_models; ["edge-case-model"]; end
          def provider_name; "EdgeCaseProvider"; end
        end.new
      end

      it "handles nil content gracefully" do
        result = edge_case_provider.responses_completion(
          messages: test_messages,
          model: "edge-case-model"
        )

        expect(result[:output]).to be_empty
      end

      it "handles missing usage information" do
        result = edge_case_provider.responses_completion(
          messages: test_messages,
          model: "edge-case-model"
        )

        expect(result[:usage]).to be_nil
      end

      it "generates ID when missing" do
        result = edge_case_provider.responses_completion(
          messages: test_messages,
          model: "edge-case-model"
        )

        expect(result[:id]).to be_a(String)
        expect(result[:id]).not_to be_empty
      end
    end
  end

  describe "#supports_handoffs?" do
    it "returns true for providers with function calling" do
      expect(test_provider.supports_handoffs?).to be true
    end

    context "with provider without function calling" do
      let(:no_function_provider) do
        Class.new(described_class) do
          def chat_completion(messages:, model:, **kwargs)
            # Note: No tools parameter
            { "choices" => [{ "message" => { "role" => "assistant", "content" => "Response" } }] }
          end

          def supported_models; ["no-function-model"]; end
          def provider_name; "NoFunctionProvider"; end
        end.new
      end

      it "returns false" do
        expect(no_function_provider.supports_handoffs?).to be false
      end
    end
  end

  describe "#supports_function_calling?" do
    it "returns true when chat_completion accepts tools parameter" do
      expect(test_provider.supports_function_calling?).to be true
    end

    context "with provider without tools parameter" do
      let(:no_tools_provider) do
        Class.new(described_class) do
          def chat_completion(messages:, model:, **kwargs)
            { "choices" => [{ "message" => { "role" => "assistant", "content" => "Response" } }] }
          end

          def supported_models; ["no-tools-model"]; end
          def provider_name; "NoToolsProvider"; end
        end.new
      end

      it "returns false" do
        expect(no_tools_provider.supports_function_calling?).to be false
      end
    end
  end

  describe "#capabilities" do
    it "returns comprehensive capability information" do
      capabilities = test_provider.capabilities

      expect(capabilities).to include(
        responses_api: true,
        chat_completion: true,
        streaming: false, # Not implemented in test provider
        function_calling: true,
        handoffs: true
      )
    end

    context "with provider implementing streaming" do
      let(:streaming_provider) do
        Class.new(described_class) do
          def chat_completion(messages:, model:, tools: nil, **kwargs)
            { "choices" => [{ "message" => { "role" => "assistant", "content" => "Response" } }] }
          end

          def stream_completion(messages:, model:, tools: nil, **kwargs)
            { "streaming" => true }
          end

          def supported_models; ["streaming-model"]; end
          def provider_name; "StreamingProvider"; end
        end.new
      end

      it "detects streaming capability" do
        capabilities = streaming_provider.capabilities
        expect(capabilities[:streaming]).to be true
      end
    end
  end

  describe "method delegation" do
    it "delegates supported_models" do
      expect(test_provider.supported_models).to eq(["enhanced-test-model-v1"])
    end

    it "delegates provider_name" do
      expect(test_provider.provider_name).to eq("EnhancedTestProvider")
    end

    it "inherits other ModelInterface methods" do
      expect(test_provider).to respond_to(:validate_model)
    end
  end

  describe "integration with base interface" do
    it "maintains compatibility with ModelInterface" do
      expect(test_provider).to be_a(RAAF::Models::ModelInterface)
    end

    it "provides automatic responses_completion implementation" do
      expect(test_provider).to respond_to(:responses_completion)
    end

    it "supports all required interface methods" do
      expect(test_provider).to respond_to(:chat_completion)
      expect(test_provider).to respond_to(:supported_models)
      expect(test_provider).to respond_to(:provider_name)
    end
  end

  describe "real-world usage patterns" do
    context "with handoff scenario" do
      let(:handoff_tools) do
        [
          {
            type: "function",
            name: "transfer_to_billing",
            function: {
              name: "transfer_to_billing",
              description: "Transfer to billing agent",
              parameters: { type: "object", properties: {} }
            }
          }
        ]
      end

      it "provides seamless handoff support" do
        result = test_provider.responses_completion(
          messages: [{ role: "user", content: "I need billing help" }],
          model: test_model,
          tools: handoff_tools
        )

        # Should have both message and function call
        expect(result[:output]).to have(2).items
        
        function_call = result[:output].find { |item| item[:type] == "function_call" }
        expect(function_call[:name]).to eq("transfer_to_support")
      end
    end

    context "with conversation continuation" do
      let(:conversation_messages) do
        [
          { role: "user", content: "Hello" },
          { role: "assistant", content: "Hi there!" },
          { role: "user", content: "I need help" }
        ]
      end

      it "handles multi-turn conversations" do
        result = test_provider.responses_completion(
          messages: conversation_messages,
          model: test_model
        )

        expect(result[:output].first[:content]).to eq("Test response from chat completion")
      end
    end
  end
end