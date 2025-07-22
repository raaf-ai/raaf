# frozen_string_literal: true

require "spec_helper"
require_relative "../../lib/raaf/models/capability_detector"
require_relative "../../lib/raaf/models/interface"

RSpec.describe RAAF::Models::CapabilityDetector do
  # Mock providers for testing different capability combinations
  let(:full_featured_provider) do
    Class.new(RAAF::Models::ModelInterface) do
      def chat_completion(messages:, model:, tools: nil, stream: false, **_kwargs)
        {
          "choices" => [{ "message" => { "role" => "assistant", "content" => "Response" } }],
          "usage" => { "total_tokens" => 10 }
        }
      end

      def responses_completion(messages:, model:, tools: nil, **_kwargs)
        {
          output: [{ type: "message", role: "assistant", content: "Response" }],
          usage: { total_tokens: 10 }
        }
      end

      def stream_completion(messages:, model:, tools: nil, **_kwargs)
        { streaming: true }
      end

      def supported_models
        ["full-featured-model-v1"]
      end

      def provider_name
        "FullFeaturedProvider"
      end
    end.new
  end

  let(:basic_provider) do
    Class.new(RAAF::Models::ModelInterface) do
      def chat_completion(messages:, model:, tools: nil, **_kwargs)
        {
          "choices" => [{ "message" => { "role" => "assistant", "content" => "Response" } }],
          "usage" => { "total_tokens" => 10 }
        }
      end

      def supported_models
        ["basic-model-v1"]
      end

      def provider_name
        "BasicProvider"
      end
    end.new
  end

  let(:no_function_calling_provider) do
    Class.new(RAAF::Models::ModelInterface) do
      def chat_completion(messages:, model:, **_kwargs)
        # NOTE: No tools parameter
        {
          "choices" => [{ "message" => { "role" => "assistant", "content" => "Response" } }],
          "usage" => { "total_tokens" => 10 }
        }
      end

      def supported_models
        ["no-function-model-v1"]
      end

      def provider_name
        "NoFunctionCallingProvider"
      end
    end.new
  end

  let(:minimal_provider) do
    Class.new(RAAF::Models::ModelInterface) do
      def supported_models
        ["minimal-model-v1"]
      end

      def provider_name
        "MinimalProvider"
      end
    end.new
  end

  describe "#initialize" do
    subject { described_class.new(full_featured_provider) }

    it "initializes with provider" do
      expect(subject).to be_a(described_class)
    end

    it "starts with empty capabilities" do
      expect(subject.instance_variable_get(:@capabilities)).to be_empty
    end
  end

  describe "#detect_capabilities" do
    context "with full-featured provider" do
      subject { described_class.new(full_featured_provider) }

      it "detects all capabilities" do
        capabilities = subject.detect_capabilities

        expect(capabilities).to include(
          responses_api: true,
          chat_completion: true,
          streaming: true,
          function_calling: true,
          handoffs: true
        )
      end

      it "caches results on subsequent calls" do
        expect(full_featured_provider).to receive(:supported_models).once

        subject.detect_capabilities
        capabilities = subject.detect_capabilities

        expect(capabilities[:responses_api]).to be true
      end
    end

    context "with basic provider" do
      subject { described_class.new(basic_provider) }

      it "detects available capabilities" do
        capabilities = subject.detect_capabilities

        expect(capabilities).to include(
          responses_api: false,
          chat_completion: true,
          streaming: false,
          function_calling: true,
          handoffs: true
        )
      end
    end

    context "with no function calling provider" do
      subject { described_class.new(no_function_calling_provider) }

      it "detects limited capabilities" do
        capabilities = subject.detect_capabilities

        expect(capabilities).to include(
          responses_api: false,
          chat_completion: true,
          streaming: false,
          function_calling: false,
          handoffs: false
        )
      end
    end

    context "with minimal provider" do
      subject { described_class.new(minimal_provider) }

      it "detects minimal capabilities" do
        capabilities = subject.detect_capabilities

        expect(capabilities).to include(
          responses_api: false,
          chat_completion: false,
          streaming: false,
          function_calling: false,
          handoffs: false
        )
      end
    end
  end

  describe "#generate_report" do
    context "with full-featured provider" do
      subject { described_class.new(full_featured_provider) }

      it "generates comprehensive report" do
        report = subject.generate_report

        expect(report).to include(
          provider: "FullFeaturedProvider",
          capabilities: be_an(Array),
          recommendations: be_an(Array),
          handoff_support: "Full",
          optimal_usage: be_a(String)
        )
      end

      it "includes detailed capability descriptions" do
        report = subject.generate_report

        capabilities = report[:capabilities]
        expect(capabilities).to have(5).items

        first_capability = capabilities.first
        expect(first_capability).to include(
          name: be_a(String),
          description: be_a(String),
          supported: be_in([true, false]),
          priority: be_in(%i[high medium low])
        )
      end

      it "provides positive recommendations" do
        report = subject.generate_report

        recommendations = report[:recommendations]
        success_recommendations = recommendations.select { |r| r[:type] == :success }
        expect(success_recommendations).not_to be_empty
      end

      it "sets optimal usage for full-featured provider" do
        report = subject.generate_report
        expect(report[:optimal_usage]).to eq("Native Responses API - No adapter needed")
      end
    end

    context "with basic provider" do
      subject { described_class.new(basic_provider) }

      it "provides appropriate recommendations" do
        report = subject.generate_report

        expect(report[:handoff_support]).to eq("Full")
        expect(report[:optimal_usage]).to eq("Chat Completions with ProviderAdapter - Full handoff support")
      end
    end

    context "with no function calling provider" do
      subject { described_class.new(no_function_calling_provider) }

      it "identifies limited handoff support" do
        report = subject.generate_report

        expect(report[:handoff_support]).to eq("Limited")
        expect(report[:optimal_usage]).to eq("Chat Completions only - Limited handoff support")
      end

      it "provides warning recommendations" do
        report = subject.generate_report

        warnings = report[:recommendations].select { |r| r[:type] == :warning }
        expect(warnings).not_to be_empty
        expect(warnings.first[:message]).to include("function calling")
      end
    end

    context "with minimal provider" do
      subject { described_class.new(minimal_provider) }

      it "identifies incompatibility" do
        report = subject.generate_report

        expect(report[:handoff_support]).to eq("Limited")
        expect(report[:optimal_usage]).to eq("Not compatible - Implement required methods")
      end

      it "provides critical recommendations" do
        report = subject.generate_report

        critical = report[:recommendations].select { |r| r[:type] == :critical }
        expect(critical).not_to be_empty
        expect(critical.first[:message]).to include("completion API")
      end
    end
  end

  describe "#supports_handoffs?" do
    context "with function calling provider" do
      subject { described_class.new(basic_provider) }

      it "returns true" do
        expect(subject.supports_handoffs?).to be true
      end
    end

    context "with no function calling provider" do
      subject { described_class.new(no_function_calling_provider) }

      it "returns false" do
        expect(subject.supports_handoffs?).to be false
      end
    end

    it "caches detection results" do
      subject = described_class.new(basic_provider)

      # First call should detect capabilities
      expect(subject).to receive(:detect_capabilities).once.and_call_original

      result1 = subject.supports_handoffs?
      result2 = subject.supports_handoffs?

      expect(result1).to eq(result2)
    end
  end

  describe "capability testing methods" do
    subject { described_class.new(full_featured_provider) }

    describe "#test_responses_api" do
      it "detects responses_completion method" do
        result = subject.send(:test_responses_api)
        expect(result).to be true
      end
    end

    describe "#test_chat_completion" do
      it "detects chat_completion method" do
        result = subject.send(:test_chat_completion)
        expect(result).to be true
      end
    end

    describe "#test_streaming" do
      it "detects stream_completion method" do
        result = subject.send(:test_streaming)
        expect(result).to be true
      end
    end

    describe "#test_function_calling" do
      it "detects tools parameter in chat_completion" do
        result = subject.send(:test_function_calling)
        expect(result).to be true
      end

      context "with provider without tools parameter" do
        subject { described_class.new(no_function_calling_provider) }

        it "returns false" do
          result = subject.send(:test_function_calling)
          expect(result).to be false
        end
      end

      context "with provider without chat_completion" do
        subject { described_class.new(minimal_provider) }

        it "returns false" do
          result = subject.send(:test_function_calling)
          expect(result).to be false
        end
      end
    end

    describe "#test_handoffs" do
      it "delegates to function calling test" do
        expect(subject).to receive(:test_function_calling).and_return(true)
        result = subject.send(:test_handoffs)
        expect(result).to be true
      end
    end
  end

  describe "error handling" do
    subject { described_class.new(error_provider) }

    let(:error_provider) do
      Class.new(RAAF::Models::ModelInterface) do
        def chat_completion(messages:, model:, tools: nil, **_kwargs)
          raise StandardError, "Provider error"
        end

        def supported_models
          ["error-model-v1"]
        end

        def provider_name
          "ErrorProvider"
        end
      end.new
    end

    it "handles provider errors gracefully during function calling test" do
      expect { subject.detect_capabilities }.not_to raise_error

      capabilities = subject.detect_capabilities
      expect(capabilities[:function_calling]).to be false
    end

    it "logs errors appropriately" do
      expect(subject).to receive(:log_debug).with(
        "🔍 CAPABILITY DETECTOR: Function calling test failed",
        hash_including(:error)
      )

      subject.send(:test_function_calling)
    end
  end

  describe "recommendation generation" do
    context "with various provider types" do
      let(:providers_and_expected_recommendations) do
        [
          {
            provider: full_featured_provider,
            expected_types: [:success],
            description: "full-featured provider"
          },
          {
            provider: basic_provider,
            expected_types: [:success],
            description: "basic provider with function calling"
          },
          {
            provider: no_function_calling_provider,
            expected_types: %i[warning info],
            description: "provider without function calling"
          },
          {
            provider: minimal_provider,
            expected_types: %i[critical info],
            description: "minimal provider"
          }
        ]
      end

      it "generates appropriate recommendations for each provider type" do
        providers_and_expected_recommendations.each do |test_case|
          detector = described_class.new(test_case[:provider])
          report = detector.generate_report

          recommendation_types = report[:recommendations].map { |r| r[:type] }

          test_case[:expected_types].each do |expected_type|
            expect(recommendation_types).to include(expected_type),
                                            "Expected #{expected_type} recommendation for #{test_case[:description]}"
          end
        end
      end
    end
  end

  describe "integration scenarios" do
    context "real-world provider simulation" do
      let(:openai_like_provider) do
        Class.new(RAAF::Models::ModelInterface) do
          def chat_completion(messages:, model:, tools: nil, stream: false, **_kwargs)
            { "choices" => [{ "message" => { "role" => "assistant", "content" => "Response" } }] }
          end

          def responses_completion(messages:, model:, tools: nil, **_kwargs)
            { output: [{ type: "message", content: "Response" }] }
          end

          def stream_completion(messages:, model:, tools: nil, **_kwargs)
            { streaming: true }
          end

          def supported_models = ["gpt-4"]
          def provider_name = "OpenAI-like"
        end.new
      end

      let(:llama_like_provider) do
        Class.new(RAAF::Models::ModelInterface) do
          def chat_completion(messages:, model:, **_kwargs)
            # No tools parameter, no streaming, no responses API
            { "choices" => [{ "message" => { "role" => "assistant", "content" => "Response" } }] }
          end

          def supported_models = ["llama-2-7b"]
          def provider_name = "LLaMA-like"
        end.new
      end

      it "correctly identifies OpenAI-like provider capabilities" do
        detector = described_class.new(openai_like_provider)
        report = detector.generate_report

        expect(report[:handoff_support]).to eq("Full")
        expect(report[:optimal_usage]).to eq("Native Responses API - No adapter needed")
      end

      it "correctly identifies LLaMA-like provider limitations" do
        detector = described_class.new(llama_like_provider)
        report = detector.generate_report

        expect(report[:handoff_support]).to eq("Limited")
        expect(report[:optimal_usage]).to eq("Chat Completions only - Limited handoff support")
      end
    end
  end
end
