# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../../lib/raaf/eval/evaluators/llm/base_evaluator"
require_relative "../../../../../lib/raaf/eval/evaluators/llm/g_eval"

RSpec.describe RAAF::Eval::Evaluators::LLM::GEval do
  let(:field_context) do
    RAAF::Eval::DSL::FieldContext.new(:output, { output: "Paris is the capital of France." })
  end

  describe "initialization" do
    it "requires at least one evaluation criterion" do
      expect {
        described_class.new(criteria: [])
      }.to raise_error(ArgumentError, /At least one evaluation criterion is required/)
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

      expected_score = (accuracy_score * 2.0 + grammar_score * 1.0) / 3.0

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
      expect {
        RAAF::Eval::DSL::FieldContext.new(:output, nil)
      }.to raise_error(RAAF::Eval::DSL::FieldNotFoundError)
    end

    it "handles empty output gracefully" do
      empty_context = RAAF::Eval::DSL::FieldContext.new(:output, { output: "" })

      expect {
        evaluator.evaluate(empty_context)
      }.not_to raise_error
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

      expect(result[:label]).to satisfy { |label| ["good", "average", "bad"].include?(label) }
    end

    it "result works with threshold matchers" do
      result = evaluator.evaluate(field_context)

      if result[:score] >= 0.85
        expect(result).to meet_quality_threshold(0.85)
      end
    end
  end
end
