# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Models::ModelInterface do
  let(:interface) { described_class.new }

  describe "abstract methods" do
    it "raises NotImplementedError for perform_chat_completion" do
      expect { interface.send(:perform_chat_completion, messages: [], model: "test") }.to raise_error(NotImplementedError)
    end

    it "raises NotImplementedError for perform_stream_completion" do
      expect { interface.send(:perform_stream_completion, messages: [], model: "test") }.to raise_error(NotImplementedError)
    end

    it "raises NotImplementedError for supported_models" do
      expect { interface.supported_models }.to raise_error(NotImplementedError)
    end

    it "raises NotImplementedError for provider_name" do
      expect { interface.provider_name }.to raise_error(NotImplementedError)
    end
  end

  describe "#prepare_tools" do
    it "returns nil for nil tools" do
      expect(interface.send(:prepare_tools, nil)).to be_nil
    end

    it "returns nil for empty tools" do
      expect(interface.send(:prepare_tools, [])).to be_nil
    end

    it "handles hash tools" do
      tools = [{ type: "function", function: { name: "test" } }]
      result = interface.send(:prepare_tools, tools)

      expect(result).to eq(tools)
    end

    it "handles FunctionTool objects" do
      tool = RAAF::FunctionTool.new(proc { |value| value }, name: "test_tool")
      tools = [tool]

      result = interface.send(:prepare_tools, tools)

      expect(result).to be_an(Array)
      expect(result.first).to be_a(Hash)
      expect(result.first).to have_key(:type)
      expect(result.first).to have_key(:function)
    end

    it "raises error for invalid tool types" do
      tools = ["invalid_tool"]

      expect { interface.send(:prepare_tools, tools) }.to raise_error(ArgumentError, /Invalid tool type/)
    end

    it "handles mixed tool types" do
      tool_hash = { type: "function", function: { name: "hash_tool" } }
      tool_object = RAAF::FunctionTool.new(proc { |value| value }, name: "object_tool")
      tools = [tool_hash, tool_object]

      result = interface.send(:prepare_tools, tools)

      expect(result.size).to eq(2)
      expect(result.all? { |t| t.is_a?(Hash) }).to be true
    end
  end

  describe "#handle_api_error" do
    it "raises AuthenticationError for 401" do
      mock_response = double("response", code: "401", body: "Unauthorized")

      expect do
        interface.send(:handle_api_error, mock_response, "TestProvider")
      end.to raise_error(RAAF::Models::AuthenticationError, /Invalid API key/)
    end

    it "raises RateLimitError for 429" do
      mock_response = double("response", code: "429", body: "Rate limit exceeded")

      expect do
        interface.send(:handle_api_error, mock_response, "TestProvider")
      end.to raise_error(RAAF::Models::RateLimitError, /Rate limit exceeded/)
    end

    it "raises ServerError for 5xx codes" do
      mock_response = double("response", code: "500", body: "Internal server error")

      expect do
        interface.send(:handle_api_error, mock_response, "TestProvider")
      end.to raise_error(RAAF::Models::ServerError, /Server error/)
    end

    it "raises APIError for other error codes" do
      mock_response = double("response", code: "400", body: "Bad request")

      expect do
        interface.send(:handle_api_error, mock_response, "TestProvider")
      end.to raise_error(RAAF::Models::APIError, /API error/)
    end
  end

  # Enhanced functionality tests (merged from EnhancedModelInterface)
  describe "enhanced functionality" do
    let(:test_provider_class) do
      Class.new(described_class) do
        def perform_chat_completion(messages:, model:, tools: nil, stream: false, **_kwargs)
          {
            "choices" => [{
              "message" => {
                "role" => "assistant",
                "content" => "Test response from chat completion",
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
      context "basic functionality" do
        it "converts chat_completion response to responses format" do
          result = test_provider.responses_completion(
            messages: test_messages,
            model: test_model
          )

          expect(result).to be_a(Hash)
          expect(result).to have_key(:output)
          expect(result).to have_key(:usage)
          expect(result).to have_key(:model)
          expect(result).to have_key(:id)
        end

        it "creates message output" do
          result = test_provider.responses_completion(
            messages: test_messages,
            model: test_model
          )

          expect(result[:output]).to have(1).item
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
      end
    end

    describe "#supports_handoffs?" do
      it "returns true for providers with function calling" do
        expect(test_provider.supports_handoffs?).to be true
      end

      context "with provider without function calling" do
        let(:no_function_provider) do
          Class.new(described_class) do
            def perform_chat_completion(messages:, model:, **_kwargs)
              # NOTE: No tools parameter
              { "choices" => [{ "message" => { "role" => "assistant", "content" => "Response" } }] }
            end

            def supported_models
              ["no-function-model"]
            end

            def provider_name
              "NoFunctionProvider"
            end
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
            def perform_chat_completion(messages:, model:, **_kwargs)
              { "choices" => [{ "message" => { "role" => "assistant", "content" => "Response" } }] }
            end

            def supported_models
              ["no-tools-model"]
            end

            def provider_name
              "NoToolsProvider"
            end
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
          streaming: true, # Method exists in ModelInterface even if not implemented
          function_calling: true,
          handoffs: true
        )
      end
    end

    describe "#convert_input_to_messages" do
      let(:base_messages) { [{ role: "user", content: "Hello" }] }
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
        result = test_provider.send(:convert_input_to_messages, input_items, base_messages)

        expect(result).to have(3).items

        # Original messages
        expect(result[0]).to eq({ role: "user", content: "Hello" })

        # Converted from input items
        expect(result[1]).to eq({ role: "user", content: "Follow-up question" })
        expect(result[2]).to eq({
                                  role: "tool",
                                  tool_call_id: "call_456",
                                  content: "Tool execution result"
                                })
      end
    end

    describe "#convert_chat_to_responses_format" do
      let(:chat_response) do
        {
          "choices" => [{
            "message" => {
              "role" => "assistant",
              "content" => "I'll help you",
              "tool_calls" => [{
                "id" => "call_123",
                "type" => "function",
                "function" => { "name" => "transfer_to_billing", "arguments" => "{}" }
              }]
            }
          }],
          "usage" => { "total_tokens" => 25 },
          "model" => "gpt-4"
        }
      end

      it "converts chat completion response to responses format" do
        result = test_provider.send(:convert_chat_to_responses_format, chat_response)

        expect(result[:output]).to have(2).items

        # Text message
        expect(result[:output][0]).to eq({
                                           type: "message",
                                           role: "assistant",
                                           content: "I'll help you"
                                         })

        # Function call
        expect(result[:output][1]).to eq({
                                           type: "function_call",
                                           id: "call_123",
                                           name: "transfer_to_billing",
                                           arguments: "{}"
                                         })

        expect(result[:usage]).to eq({ "total_tokens" => 25 })
        expect(result[:model]).to eq("gpt-4")
        expect(result[:id]).to be_a(String)
      end
    end
  end

  # Error classes tests (merged from errors_spec.rb)
  describe "error classes" do
    it "defines model-specific error hierarchy" do
      expect(RAAF::Models::AuthenticationError).to be < RAAF::Error
      expect(RAAF::Models::RateLimitError).to be < RAAF::Error
      expect(RAAF::Models::ServerError).to be < RAAF::Error
      expect(RAAF::Models::APIError).to be < RAAF::Error
    end
  end
end
