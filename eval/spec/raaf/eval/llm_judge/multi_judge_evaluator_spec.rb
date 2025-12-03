# frozen_string_literal: true

require "spec_helper"
require "raaf/eval/llm_judge"

RSpec.describe RAAF::Eval::LLMJudge::MultiJudgeEvaluator do
  let(:models) { ["gpt-4o", "gpt-4o-mini"] }

  subject(:evaluator) do
    described_class.new(models: models, temperature: 0.0)
  end

  describe "#initialize" do
    it "creates judges from model names" do
      expect(evaluator.judges.size).to eq(2)
      expect(evaluator.judges).to all(be_a(RAAF::Eval::LLMJudge::StatisticalJudge))
    end

    it "accepts pre-configured judges" do
      judges = [
        RAAF::Eval::LLMJudge::StatisticalJudge.new(model: "gpt-4o"),
        RAAF::Eval::LLMJudge::StatisticalJudge.new(model: "gpt-4o-mini")
      ]

      eval = described_class.new(judges: judges)
      expect(eval.judges).to eq(judges)
    end

    it "raises error without judges or models" do
      expect { described_class.new }.to raise_error(ArgumentError, /Must provide either judges or models/)
    end

    it "raises error with fewer than 2 judges" do
      expect { described_class.new(models: ["gpt-4o"]) }.to raise_error(
        ArgumentError, /at least 2 judges/
      )
    end

    it "sets default strategy to majority" do
      expect(evaluator.default_strategy).to eq(:majority)
    end
  end

  describe "#evaluate", :vcr do
    let(:input) { "What is 2 + 2?" }
    let(:output) { "4" }
    let(:criteria) { "Is the answer mathematically correct?" }

    it "returns consensus result" do
      result = evaluator.evaluate(input: input, output: output, criteria: criteria)

      expect(result).to have_key(:consensus)
      expect(result).to have_key(:agreement_rate)
      expect(result).to have_key(:positive_votes)
      expect(result).to have_key(:negative_votes)
      expect(result).to have_key(:total_judges)
      expect(result).to have_key(:individual_votes)
    end

    it "includes individual votes with details" do
      result = evaluator.evaluate(input: input, output: output, criteria: criteria)

      expect(result[:individual_votes].size).to eq(2)
      result[:individual_votes].each do |vote|
        expect(vote).to have_key(:judge)
        expect(vote).to have_key(:passed)
        expect(vote).to have_key(:confidence)
        expect(vote).to have_key(:reasoning)
      end
    end

    it "computes agreement rate correctly" do
      result = evaluator.evaluate(input: input, output: output, criteria: criteria)

      expected_rate = [result[:positive_votes], result[:negative_votes]].max.to_f / result[:total_judges]
      expect(result[:agreement_rate]).to eq(expected_rate)
    end
  end

  describe "#evaluate_weighted", :vcr do
    let(:input) { "What is 2 + 2?" }
    let(:output) { "4" }
    let(:criteria) { "Is the answer mathematically correct?" }

    it "returns weighted voting result" do
      result = evaluator.evaluate_weighted(input: input, output: output, criteria: criteria)

      expect(result).to have_key(:consensus)
      expect(result).to have_key(:weighted_positive_score)
      expect(result).to have_key(:weighted_negative_score)
      expect(result).to have_key(:weights)
      expect(result[:strategy]).to eq(:weighted)
    end

    it "includes weights for each judge" do
      result = evaluator.evaluate_weighted(input: input, output: output, criteria: criteria)

      expect(result[:weights].size).to eq(2)
      result[:weights].each do |w|
        expect(w).to have_key(:model)
        expect(w).to have_key(:weight)
        expect(w[:weight]).to be_between(0.0, 1.0)
      end
    end

    it "normalizes weights to sum to 1" do
      result = evaluator.evaluate_weighted(input: input, output: output, criteria: criteria)

      total_weight = result[:weights].sum { |w| w[:weight] }
      expect(total_weight).to be_within(0.001).of(1.0)
    end
  end

  describe "#evaluate_unanimous", :vcr do
    let(:criteria) { "Is the answer correct?" }

    it "requires all judges to agree for positive consensus" do
      result = evaluator.evaluate_unanimous(
        input: "What is 2 + 2?",
        output: "4",
        criteria: criteria
      )

      if result[:positive_votes] == result[:total_judges]
        expect(result[:consensus]).to be true
      else
        expect(result[:consensus]).to be false
      end
    end
  end

  describe "#evaluate_threshold", :vcr do
    let(:criteria) { "Is the answer correct?" }

    it "uses custom threshold for consensus" do
      result = evaluator.evaluate_threshold(
        input: "What is 2 + 2?",
        output: "4",
        criteria: criteria,
        threshold: 0.5
      )

      expected_consensus = result[:positive_votes].to_f / result[:total_judges] >= 0.5
      expect(result[:consensus]).to eq(expected_consensus)
    end
  end

  describe "#evaluate_batch", :vcr do
    let(:samples) do
      [
        { input: "What is 1 + 1?", output: "2" },
        { input: "What is 2 + 2?", output: "4" },
        { input: "What is 3 + 3?", output: "7" }  # Incorrect
      ]
    end
    let(:criteria) { "Is the answer correct?" }

    it "evaluates all samples" do
      results = evaluator.evaluate_batch(samples, criteria: criteria)

      expect(results[:results].size).to eq(3)
      expect(results).to have_key(:consensus_rate)
      expect(results).to have_key(:average_agreement)
      expect(results).to have_key(:high_disagreement_count)
      expect(results).to have_key(:unanimous_count)
    end

    it "computes aggregate statistics" do
      results = evaluator.evaluate_batch(samples, criteria: criteria)

      expect(results[:consensus_rate]).to be_between(0.0, 1.0)
      expect(results[:average_agreement]).to be_between(0.0, 1.0)
      expect(results[:high_disagreement_count]).to be >= 0
      expect(results[:unanimous_count]).to be >= 0
    end
  end

  describe "#flag_for_human_review", :vcr do
    let(:samples) do
      [
        { input: "What is 1 + 1?", output: "2" },
        { input: "Explain quantum physics in detail", output: "Complex topic..." }
      ]
    end
    let(:criteria) { "Is the answer complete and accurate?" }

    it "flags samples with low agreement" do
      flagged = evaluator.flag_for_human_review(
        samples,
        criteria: criteria,
        disagreement_threshold: 0.9  # High threshold to catch most samples
      )

      expect(flagged).to be_an(Array)
      flagged.each do |item|
        expect(item).to have_key(:sample)
        expect(item).to have_key(:result)
        expect(item).to have_key(:reason)
      end
    end
  end

  describe "#inter_rater_reliability", :vcr do
    let(:samples) do
      5.times.map { |i| { input: "Q#{i}", output: "A#{i}" } }
    end
    let(:criteria) { "Is this correct?" }

    it "computes reliability statistics" do
      reliability = evaluator.inter_rater_reliability(samples, criteria: criteria)

      expect(reliability).to have_key(:mean_pairwise_agreement)
      expect(reliability).to have_key(:min_pairwise_agreement)
      expect(reliability).to have_key(:max_pairwise_agreement)
      expect(reliability).to have_key(:fleiss_kappa)
      expect(reliability).to have_key(:num_judges)
      expect(reliability).to have_key(:num_samples)
    end

    it "returns valid agreement values" do
      reliability = evaluator.inter_rater_reliability(samples, criteria: criteria)

      expect(reliability[:mean_pairwise_agreement]).to be_between(0.0, 1.0)
      expect(reliability[:fleiss_kappa]).to be_between(-1.0, 1.0)
    end
  end

  describe "#judges_summary" do
    it "returns summary for all judges" do
      summaries = evaluator.judges_summary

      expect(summaries.size).to eq(2)
      summaries.each do |summary|
        expect(summary).to have_key(:model)
        expect(summary).to have_key(:calibrated)
        expect(summary).to have_key(:index)
      end
    end
  end

  describe "#calibrate_all", :vcr do
    let(:calibration_set) do
      set = RAAF::Eval::LLMJudge::CalibrationSet.new
      15.times { |i| set.add(input: "P#{i}", output: "A#{i}", ground_truth: true) }
      15.times { |i| set.add(input: "N#{i}", output: "A#{i}", ground_truth: false) }
      set
    end

    it "calibrates all judges" do
      results = evaluator.calibrate_all(calibration_set, criteria: "Is correct?")

      expect(results.keys.size).to eq(2)
      results.each_value do |result|
        expect(result).to have_key(:sensitivity)
        expect(result).to have_key(:specificity)
      end
    end

    it "marks all judges as calibrated" do
      evaluator.calibrate_all(calibration_set, criteria: "Is correct?")

      evaluator.judges.each do |judge|
        expect(judge.calibrated?).to be true
      end
    end
  end
end
