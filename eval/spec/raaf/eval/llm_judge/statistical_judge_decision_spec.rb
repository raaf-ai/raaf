# frozen_string_literal: true

require "spec_helper"
require "raaf/eval/llm_judge"

RSpec.describe RAAF::Eval::LLMJudge::StatisticalJudge do
  # A decision provider that answers every noul with a fixed probability and
  # records what it was asked, so the judge can be tested without a model call.
  let(:decision_provider) do
    Class.new(RAAF::Models::DecisionInterface) do
      attr_reader :asked

      def initialize(probability:)
        super()
        @probability = probability
        @asked = []
      end

      def provider_name = "Fake"

      def perform_decision(state:, questions:, model:, **)
        @asked << { state: state, questions: questions }

        RAAF::Models::Decision::Result.new(
          answers: questions.transform_values { |question| question.parse("noul" => @probability) },
          provider: provider_name
        )
      end
    end
  end

  let(:provider) { decision_provider.new(probability: 0.93) }
  let(:judge) { described_class.new(decision_provider: provider, cache: false) }

  describe "#evaluate" do
    it "judges through the decision model instead of a chat completion" do
      expect(judge).not_to receive(:call_judge_model)

      result = judge.evaluate(input: "2+2=?", output: "4", criteria: "The answer is correct")

      expect(result[:passed]).to be(true)
      expect(result[:probability]).to eq(0.93)
    end

    it "asks about the input and the output as one state" do
      judge.evaluate(input: "2+2=?", output: "4", criteria: "The answer is correct")

      expect(provider.asked.first[:state]).to eq(input: "2+2=?", output: "4")
    end

    it "puts the criteria into the noul instructions" do
      judge.evaluate(input: "2+2=?", output: "4", criteria: "The answer is correct")

      question = provider.asked.first[:questions]["answer"]
      expect(question).to be_a(RAAF::Models::Decision::Noul)
      expect(question.instructions).to eq("The output satisfies this criterion: The answer is correct")
    end

    it "reports the probability rather than inventing reasoning" do
      result = judge.evaluate(input: "2+2=?", output: "4", criteria: "The answer is correct")

      expect(result[:reasoning]).to eq("Fake noul p=0.93 (threshold 0.5)")
    end

    it "carries the answer's confidence through" do
      result = judge.evaluate(input: "2+2=?", output: "4", criteria: "The answer is correct")

      # A noul with no vendor confidence reports its distance from a coin flip.
      expect(result[:confidence]).to be_within(1e-9).of(0.86)
    end
  end

  describe "the decision threshold" do
    let(:provider) { decision_provider.new(probability: 0.6) }

    it "passes at the default threshold" do
      expect(judge.evaluate(input: "x", output: "y", criteria: "c")[:passed]).to be(true)
    end

    it "fails under a stricter threshold" do
      strict = described_class.new(decision_provider: provider, decision_threshold: 0.9, cache: false)

      expect(strict.evaluate(input: "x", output: "y", criteria: "c")[:passed]).to be(false)
    end
  end

  describe "batch evaluation" do
    it "feeds bias correction the same way the chat path does" do
      samples = [{ input: "2+2=?", output: "4" }, { input: "2+3=?", output: "5" }]

      results = judge.evaluate_batch(samples, criteria: "The answer is correct")

      expect(results[:raw_accuracy]).to eq(1.0)
      expect(provider.asked.size).to eq(2)
    end
  end

  describe "resolving the provider" do
    it "takes a provider instance" do
      expect(described_class.new(decision_provider: provider).decision_provider).to be(provider)
    end

    it "takes a registry name" do
      judge = described_class.new(decision_provider: :llm)

      expect(judge.decision_provider).to be_a(RAAF::Models::Decision::LLMBackedProvider)
    end

    it "uses no decision model by default" do
      expect(described_class.new.decision_provider).to be_nil
    end

    it "uses no decision model when passed nil" do
      expect(described_class.new(decision_provider: nil).decision_provider).to be_nil
    end

    it "reads RAAF_EVAL_DECISION_PROVIDER" do
      original = ENV.fetch("RAAF_EVAL_DECISION_PROVIDER", nil)
      ENV["RAAF_EVAL_DECISION_PROVIDER"] = "llm"

      expect(described_class.new.decision_provider).to be_a(RAAF::Models::Decision::LLMBackedProvider)
    ensure
      ENV["RAAF_EVAL_DECISION_PROVIDER"] = original
    end

    it "ignores a blank RAAF_EVAL_DECISION_PROVIDER" do
      original = ENV.fetch("RAAF_EVAL_DECISION_PROVIDER", nil)
      ENV["RAAF_EVAL_DECISION_PROVIDER"] = ""

      expect(described_class.new.decision_provider).to be_nil
    ensure
      ENV["RAAF_EVAL_DECISION_PROVIDER"] = original
    end
  end

  describe "#summary" do
    it "names the decision provider in use" do
      expect(judge.summary[:decision_provider]).to eq("Fake")
    end

    it "reports none when judging through a chat model" do
      expect(described_class.new.summary[:decision_provider]).to be_nil
    end
  end

  describe "the chat path" do
    it "is unchanged when no decision provider is configured" do
      chat_judge = described_class.new(cache: false)
      allow(chat_judge).to receive(:call_judge_model)
        .and_return('{"passed": true, "confidence": 0.8, "reasoning": "looks right"}')

      result = chat_judge.evaluate(input: "2+2=?", output: "4", criteria: "The answer is correct")

      expect(result).to eq(passed: true, confidence: 0.8, reasoning: "looks right")
    end
  end
end
