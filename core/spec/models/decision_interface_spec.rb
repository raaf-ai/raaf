# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Models::DecisionInterface do
  let(:recording_provider) do
    Class.new(described_class) do
      attr_reader :calls

      def provider_name = "Recording"

      def default_model = "recording-1"

      def perform_decision(state:, questions:, model:, **kwargs)
        (@calls ||= []) << { state: state, questions: questions, model: model, kwargs: kwargs }

        RAAF::Models::Decision::Result.new(
          answers: questions.transform_values { |question| question.parse("noul" => 0.75) },
          model: model,
          provider: provider_name
        )
      end
    end
  end

  describe "the abstract contract" do
    subject(:provider) { Class.new(described_class).new }

    it "requires #perform_decision" do
      expect { provider.decide(state: "x", questions: { a: { type: :noul, instructions: "y" } }) }
        .to raise_error(NotImplementedError, /must implement #perform_decision/)
    end

    it "requires #provider_name" do
      expect { provider.provider_name }.to raise_error(NotImplementedError, /must implement #provider_name/)
    end

    it "does not restrict models by default" do
      expect(provider.supported_models).to eq([])
    end
  end

  describe "#decide" do
    subject(:provider) { recording_provider.new }

    it "builds Hash questions into Question objects" do
      provider.decide(state: "x", questions: { urgent: { type: :noul, instructions: "y" } })

      question = provider.calls.first[:questions]["urgent"]
      expect(question).to be_a(RAAF::Models::Decision::Noul)
      expect(question.instructions).to eq("y")
    end

    it "keys questions by String" do
      provider.decide(state: "x", questions: { urgent: { type: :noul, instructions: "y" } })

      expect(provider.calls.first[:questions].keys).to eq(["urgent"])
    end

    it "uses the provider default model" do
      provider.decide(state: "x", questions: { a: { type: :noul, instructions: "y" } })

      expect(provider.calls.first[:model]).to eq("recording-1")
    end

    it "lets the caller override the model per call" do
      provider.decide(state: "x", questions: { a: { type: :noul, instructions: "y" } }, model: "recording-2")

      expect(provider.calls.first[:model]).to eq("recording-2")
    end

    it "lets the constructor override the default model" do
      other = recording_provider.new(model: "recording-9")
      other.decide(state: "x", questions: { a: { type: :noul, instructions: "y" } })

      expect(other.calls.first[:model]).to eq("recording-9")
    end

    it "passes extra parameters through to the provider" do
      provider.decide(state: "x", questions: { a: { type: :noul, instructions: "y" } }, priority: "high")

      expect(provider.calls.first[:kwargs]).to eq(priority: "high")
    end

    it "accepts a structured state" do
      provider.decide(state: { input: "a", output: "b" }, questions: { a: { type: :noul, instructions: "y" } })

      expect(provider.calls.first[:state]).to eq(input: "a", output: "b")
    end

    it "rejects questions that are not a Hash" do
      expect { provider.decide(state: "x", questions: []) }
        .to raise_error(ArgumentError, /must be a Hash/)
    end
  end

  describe "#noul" do
    subject(:provider) { recording_provider.new }

    it "asks a single noul and returns its answer" do
      answer = provider.noul(state: "x", instructions: "The output is correct")

      expect(answer).to be_a(RAAF::Models::Decision::Answers::Noul)
      expect(answer.probability).to eq(0.75)
      expect(provider.calls.first[:questions]["answer"].instructions).to eq("The output is correct")
    end
  end

  describe "model validation" do
    let(:restricted_provider) do
      Class.new(described_class) do
        def provider_name = "Restricted"

        def supported_models = ["only-1"]

        def perform_decision(state:, questions:, model:, **)
          validate_model!(model)
          RAAF::Models::Decision::Result.new(answers: {}, model: model)
        end
      end
    end

    it "accepts a supported model" do
      expect do
        restricted_provider.new.decide(
          state: "x", questions: { a: { type: :noul, instructions: "y" } }, model: "only-1"
        )
      end.not_to raise_error
    end

    it "rejects an unsupported model" do
      expect do
        restricted_provider.new.decide(
          state: "x", questions: { a: { type: :noul, instructions: "y" } }, model: "other"
        )
      end.to raise_error(ArgumentError, /is not supported by Restricted/)
    end
  end
end
