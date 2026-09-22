# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../../lib/raaf/eval/evaluators/llm/base_evaluator"
require_relative "../../../../../lib/raaf/eval/evaluators/llm/g_eval"

RSpec.describe RAAF::Eval::Evaluators::LLM::GEval do
  let(:field_context) do
    RAAF::Eval::DSL::FieldContext.new(:output, { output: "Paris is the capital of France." })
  end

  # Every example below used to call evaluate with nothing stubbed, and passed
  # because a missing API key sent GEval into a word-count heuristic that always
  # answered. The suite was therefore asserting the behaviour of the stand-in
  # rather than of the judge, which is how a judge that had never run stayed
  # green. There is no stand-in any more, so the judge's answer is stated here.
  #
  # Three criteria are returned regardless of how many were asked for: extras go
  # unread, and the scores are distinct so the average and weighted-average
  # examples are checking arithmetic rather than comparing a number to itself.
  def judge_answers(scores = [0.9, 0.6, 0.75])
    answer = {
      criteria: scores.map.with_index do |score, i|
        { criterion: "criterion_#{i + 1}", score: score,
          reasoning: "criterion #{i + 1} reasoning" }
      end,
      overall_chain_of_thought: "The output was read against each criterion in turn, and the " \
                                "reasoning for each is recorded beside its score above."
    }.to_json
    allow_any_instance_of(described_class).to receive(:call_llm).and_return(answer)
  end

  before { judge_answers }

  describe "provider routing" do
    it "reaches Gemini for a gemini model, and OpenAI for anything else" do
      evaluator = described_class.new(criteria: ["Output is clear"])

      expect(evaluator.send(:provider_for, "gemini-2.5-flash")[:key_env]).to eq("GEMINI_API_KEY")
      expect(evaluator.send(:provider_for, "gpt-4o-mini")[:key_env]).to eq("OPENAI_API_KEY")
      expect(evaluator.send(:provider_for, "some-future-model")[:label]).to eq("OpenAI")
    end
  end

  describe "judge usage" do
    it "bills tokens the provider did not report as completion" do
      evaluator = described_class.new(criteria: ["Output is clear"])

      # gemini-2.5-pro reports thinking tokens only inside the total, and bills
      # them at the output rate; reading completion_tokens alone understated a
      # measured call by about four times.
      usage = evaluator.send(:extract_usage,
                             { "prompt_tokens" => 146, "completion_tokens" => 365, "total_tokens" => 1349 })

      expect(usage[:output_tokens]).to eq(1203)
      expect(usage[:total_tokens]).to eq(1349)
    end

    it "leaves a provider that reports everything alone" do
      evaluator = described_class.new(criteria: ["Output is clear"])

      usage = evaluator.send(:extract_usage,
                             { "prompt_tokens" => 100, "completion_tokens" => 50, "total_tokens" => 150 })

      expect(usage[:output_tokens]).to eq(50)
    end
  end

  describe "initialization" do
    it "requires at least one evaluation criterion" do
      expect do
        described_class.new(criteria: [])
      end.to raise_error(ArgumentError, /At least one evaluation criterion is required/)
    end

    it "accepts array of criterion descriptions" do
      evaluator = described_class.new(
        criteria: ["Output is factually accurate", "Output is grammatically correct"]
      )

      expect(evaluator).to be_a(described_class)
    end

    it "accepts hash of criteria with weights" do
      evaluator = described_class.new(
        criteria: {
          accuracy: { description: "Output is factually accurate", weight: 1.0 },
          grammar: { description: "Output is grammatically correct", weight: 0.5 }
        }
      )

      expect(evaluator).to be_a(described_class)
    end

    it "supports custom thresholds" do
      evaluator = described_class.new(
        criteria: ["Output is clear"],
        good_threshold: 0.85,
        average_threshold: 0.70
      )

      expect(evaluator).to be_a(described_class)
    end
  end

  describe "evaluation with single criterion" do
    let(:evaluator) do
      described_class.new(
        criteria: ["Output is factually accurate"]
      )
    end

    it "returns structured result with score and label" do
      result = evaluator.evaluate(field_context)

      expect(result).to include(
        :label,
        :score,
        :message,
        :details
      )
      expect(result[:label]).to be_a(String)
      expect(result[:score]).to be_a(Float)
      expect(result[:score]).to be_between(0.0, 1.0)
    end

    it "includes chain-of-thought reasoning in details" do
      result = evaluator.evaluate(field_context)

      expect(result[:details]).to include(:chain_of_thought)
      expect(result[:details][:chain_of_thought]).to be_a(String)
      expect(result[:details][:chain_of_thought]).not_to be_empty
    end

    it "includes criterion evaluation in details" do
      result = evaluator.evaluate(field_context)

      expect(result[:details]).to include(:criteria_evaluation)
      expect(result[:details][:criteria_evaluation]).to be_an(Array)
      expect(result[:details][:criteria_evaluation].first).to include(
        :criterion,
        :score,
        :reasoning
      )
    end

    it "evaluates field_context value" do
      result = evaluator.evaluate(field_context)

      expect(result[:details][:evaluated_field]).to eq(:output)
    end
  end

  describe "evaluation with multiple criteria" do
    let(:evaluator) do
      described_class.new(
        criteria: [
          "Output is factually accurate",
          "Output is grammatically correct",
          "Output is concise"
        ]
      )
    end

    it "evaluates all criteria" do
      result = evaluator.evaluate(field_context)

      criteria_eval = result[:details][:criteria_evaluation]
      expect(criteria_eval.size).to eq(3)

      criteria_eval.each do |criterion_result|
        expect(criterion_result).to include(:criterion, :score, :reasoning)
        expect(criterion_result[:score]).to be_between(0.0, 1.0)
      end
    end

    it "calculates overall score as average of criteria scores" do
      result = evaluator.evaluate(field_context)

      criteria_scores = result[:details][:criteria_evaluation].map { |c| c[:score] }
      expected_score = criteria_scores.sum / criteria_scores.size.to_f

      expect(result[:score]).to be_within(0.01).of(expected_score)
    end

    it "includes aggregated chain-of-thought" do
      result = evaluator.evaluate(field_context)

      expect(result[:details][:chain_of_thought]).to be_a(String)
      expect(result[:details][:chain_of_thought].length).to be > 50
    end
  end

  describe "evaluation with weighted criteria" do
    let(:evaluator) do
      described_class.new(
        criteria: {
          accuracy: { description: "Output is factually accurate", weight: 2.0 },
          grammar: { description: "Output is grammatically correct", weight: 1.0 }
        }
      )
    end

    it "calculates weighted average score" do
      result = evaluator.evaluate(field_context)

      criteria_eval = result[:details][:criteria_evaluation]
      expect(criteria_eval.size).to eq(2)

      # Weighted average calculation
      accuracy_score = criteria_eval.find { |c| c[:criterion] == :accuracy }[:score]
      grammar_score = criteria_eval.find { |c| c[:criterion] == :grammar }[:score]

      expected_score = ((accuracy_score * 2.0) + (grammar_score * 1.0)) / 3.0

      expect(result[:score]).to be_within(0.01).of(expected_score)
    end

    it "includes weight information in criteria evaluation" do
      result = evaluator.evaluate(field_context)

      accuracy_eval = result[:details][:criteria_evaluation].find { |c| c[:criterion] == :accuracy }
      expect(accuracy_eval[:weight]).to eq(2.0)

      grammar_eval = result[:details][:criteria_evaluation].find { |c| c[:criterion] == :grammar }
      expect(grammar_eval[:weight]).to eq(1.0)
    end
  end

  describe "threshold application" do
    let(:evaluator) do
      described_class.new(
        criteria: ["Output is clear"],
        good_threshold: 0.90,
        average_threshold: 0.70
      )
    end

    it "applies custom thresholds to determine label" do
      result = evaluator.evaluate(field_context)

      # Mock score should be between 0.7 and 0.9 for "average"
      if result[:score] >= 0.90
        expect(result[:label]).to eq("good")
      elsif result[:score] >= 0.70
        expect(result[:label]).to eq("average")
      else
        expect(result[:label]).to eq("bad")
      end
    end

    it "includes threshold metadata in result" do
      result = evaluator.evaluate(field_context)

      expect(result[:details][:thresholds]).to include(
        good: 0.90,
        average: 0.70
      )
    end
  end

  describe "error handling" do
    let(:evaluator) do
      described_class.new(criteria: ["Output is clear"])
    end

    it "raises error when field_context value is nil" do
      # FieldContext with nil data will raise FieldNotFoundError
      expect do
        RAAF::Eval::DSL::FieldContext.new(:output, nil)
      end.to raise_error(RAAF::Eval::DSL::FieldNotFoundError)
    end

    it "handles empty output gracefully" do
      empty_context = RAAF::Eval::DSL::FieldContext.new(:output, { output: "" })

      expect do
        evaluator.evaluate(empty_context)
      end.not_to raise_error
    end
  end

  describe "result structure" do
    let(:evaluator) do
      described_class.new(
        criteria: ["Output is factually accurate"]
      )
    end

    it "includes all required result fields" do
      result = evaluator.evaluate(field_context)

      expect(result).to include(
        label: be_a(String),
        score: be_a(Float),
        message: be_a(String),
        details: be_a(Hash)
      )
    end

    it "includes G-Eval specific details" do
      result = evaluator.evaluate(field_context)

      expect(result[:details]).to include(
        evaluated_field: :output,
        method: "g_eval",
        criteria_count: 1,
        chain_of_thought: be_a(String),
        criteria_evaluation: be_an(Array)
      )
    end

    it "includes threshold metadata" do
      result = evaluator.evaluate(field_context)

      expect(result[:details][:thresholds]).to include(
        :good,
        :average,
        :used
      )
    end
  end

  describe "RSpec matcher integration" do
    let(:evaluator) do
      described_class.new(
        criteria: ["Output is factually accurate"],
        good_threshold: 0.85,
        average_threshold: 0.65
      )
    end

    it "result works with standard label matchers" do
      result = evaluator.evaluate(field_context)

      expect(result[:label]).to(satisfy { |label| %w[good average bad].include?(label) })
    end

    it "result works with threshold matchers" do
      result = evaluator.evaluate(field_context)

      expect(result).to meet_quality_threshold(0.85) if result[:score] >= 0.85
    end
  end
end
