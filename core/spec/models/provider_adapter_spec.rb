# frozen_string_literal: true

require "spec_helper"
require_relative "../../lib/raaf/models/provider_adapter"
require_relative "../../lib/raaf/models/interface"

RSpec.describe RAAF::Models::ProviderAdapter do
  # Mock providers for testing
  let(:function_calling_provider) do
    Class.new(RAAF::Models::ModelInterface) do
      def chat_completion(messages:, model:, tools: nil, stream: false, **kwargs)
        {
          "choices" => [{
            "message" => {
              "role" => "assistant",
              "content" => "Test response",
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
          "usage" => { "prompt_tokens" => 10, "completion_tokens" => 5, "total_tokens" => 15 }
        }
      end

      def responses_completion(messages:, model:, tools: nil, **kwargs)
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
      def chat_completion(messages:, model:, stream: false, **kwargs)
        # Note: No tools parameter
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
      def chat_completion(messages:, model:, tools: nil, stream: false, **kwargs)
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

  let(:available_agents) { ["SupportAgent", "BillingAgent", "TechnicalAgent"] }

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
        expect(non_function_calling_provider).to receive(:chat_completion).and_call_original
        
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

      subject { described_class.new(incompatible_provider) }

      it "raises appropriate error" do
        expect {
          subject.universal_completion(
            messages: test_messages,
            model: test_model
          )
        }.to raise_error(RAAF::ProviderError, /doesn't support any known completion API/)
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
      let(:incompatible_provider) do
        Class.new(RAAF::Models::ModelInterface) do
          def supported_models; []; end
          def provider_name; "Incompatible"; end
        end.new
      end

      subject { described_class.new(incompatible_provider) }

      it "returns false" do
        expect(subject.supports_handoffs?).to be false
      end
    end
  end

  describe "#update_available_agents" do
    subject { described_class.new(non_function_calling_provider, ["Agent1"]) }

    it "updates the fallback system with new agents" do
      new_agents = ["Agent2", "Agent3"]
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

      it "adds handoff instructions" do
        result = subject.get_enhanced_system_instructions(base_instructions, available_agents)
        expect(result).to include(base_instructions)
        expect(result).to include("Handoff Instructions")
        expect(result).to include("SupportAgent")
        expect(result).to include("BillingAgent")
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

      it "detects JSON handoff format" do
        content = 'I need to transfer you. {"handoff_to": "SupportAgent"}'
        result = subject.detect_content_based_handoff(content)
        expect(result).to eq("SupportAgent")
      end

      it "detects structured handoff format" do
        content = "Let me transfer you. [HANDOFF:BillingAgent]"
        result = subject.detect_content_based_handoff(content)
        expect(result).to eq("BillingAgent")
      end

      it "detects natural language handoff" do
        content = "Transfer to TechnicalAgent for help."
        result = subject.detect_content_based_handoff(content)
        expect(result).to eq("TechnicalAgent")
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
    let(:error_provider) do
      Class.new(RAAF::Models::ModelInterface) do
        def chat_completion(messages:, model:, **kwargs)
          raise StandardError, "Provider error"
        end

        def supported_models; ["error-model"]; end
        def provider_name; "ErrorProvider"; end
      end.new
    end

    subject { described_class.new(error_provider) }

    it "propagates provider errors" do
      expect {
        subject.universal_completion(
          messages: [{ role: "user", content: "test" }],
          model: "test-model"
        )
      }.to raise_error(StandardError, "Provider error")
    end
  end
end