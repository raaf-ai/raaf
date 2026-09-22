# frozen_string_literal: true

require "spec_helper"
require "raaf/eval/llm_judge"

RSpec.describe RAAF::Eval::LLMJudge::MultiJudgeEvaluator do
  subject(:evaluator) do
    described_class.new(models: models, temperature: 0.0)
  end

  let(:models) { %w[gpt-4o gpt-4o-mini] }

  # A judge reaches the network in exactly one place, and every consensus method
  # here is built on what comes back from it. Stubbing that one call keeps prompt
  # construction, JSON parsing and the aggregation arithmetic under test while
  # deciding the votes from the spec. Without it there is no API key, every
  # judgement raises into `judge_output`'s rescue, and each method is measured on
  # two "did not pass" votes it never chose.
  #
  # +verdicts+ maps a model name to what that judge says: a fixed boolean, or a
  # callable handed the output under evaluation.
  def judges_answer(verdicts, confidence: 0.9)
    evaluator.judges.each do |judge|
      answer = verdicts.fetch(judge.model)

      allow(judge).to receive(:call_judge_model) do |prompt|
        passed = answer.respond_to?(:call) ? answer.call(judged_output(prompt)) : answer

        { passed: passed, confidence: confidence, reasoning: "#{judge.model} says #{passed}" }.to_json
      end
    end
  end

  # The output the judging prompt is asking about. Reading it back out of the
  # prompt is also what proves the prompt carried it.
  def judged_output(prompt)
    prompt[/## Output to Evaluate\n(.+?)\n\n## Instructions/m, 1].to_s.strip
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

  describe "#evaluate" do
    let(:input) { "What is 2 + 2?" }
    let(:criteria) { "Is the answer mathematically correct?" }

    it "reaches consensus when the judges agree" do
      judges_answer({ "gpt-4o" => true, "gpt-4o-mini" => true })

      result = evaluator.evaluate(input: input, output: "4", criteria: criteria)

      expect(result).to include(
        consensus: true,
        positive_votes: 2,
        negative_votes: 0,
        total_judges: 2,
        agreement_rate: 1.0,
        strategy: :majority
      )
    end

    # Two judges cannot produce a majority out of a split, so the tie reads as
    # "no consensus" rather than as the positive vote winning.
    it "withholds consensus on a split, and still reports full disagreement" do
      judges_answer({ "gpt-4o" => true, "gpt-4o-mini" => false })

      result = evaluator.evaluate(input: input, output: "4", criteria: criteria)

      expect(result).to include(consensus: false, positive_votes: 1, negative_votes: 1, agreement_rate: 0.5)
    end

    it "attributes every vote to the judge that cast it" do
      judges_answer({ "gpt-4o" => true, "gpt-4o-mini" => false })

      votes = evaluator.evaluate(input: input, output: "4", criteria: criteria)[:individual_votes]

      expect(votes).to eq(
        [
          { judge: "gpt-4o", passed: true, confidence: 0.9, reasoning: "gpt-4o says true" },
          { judge: "gpt-4o-mini", passed: false, confidence: 0.9, reasoning: "gpt-4o-mini says false" }
        ]
      )
    end

    # The judgement has to be about the output it was handed, which is only true
    # if the prompt carried it; the stub reads its verdict back out of the prompt.
    it "asks about the output it was given" do
      judges_answer(
        {
          "gpt-4o" => ->(output) { output == "4" },
          "gpt-4o-mini" => ->(output) { output == "4" }
        }
      )

      expect(evaluator.evaluate(input: input, output: "4", criteria: criteria)).to include(consensus: true)
      expect(evaluator.evaluate(input: input, output: "5", criteria: criteria)).to include(consensus: false)
    end
  end

  describe "#evaluate_weighted" do
    let(:input) { "What is 2 + 2?" }
    let(:criteria) { "Is the answer mathematically correct?" }

    it "splits the weight evenly between uncalibrated judges" do
      judges_answer({ "gpt-4o" => true, "gpt-4o-mini" => false })

      result = evaluator.evaluate_weighted(input: input, output: "4", criteria: criteria)

      expect(result[:weights]).to eq(
        [{ model: "gpt-4o", weight: 0.5 }, { model: "gpt-4o-mini", weight: 0.5 }]
      )
      expect(result).to include(
        weighted_positive_score: 0.5,
        weighted_negative_score: 0.5,
        consensus: false, # a tie is not a positive consensus
        strategy: :weighted
      )
    end

    # The point of weighting: a judge measured against ground truth outvotes one
    # that is barely better than a coin toss, even though it is one vote each.
    it "lets the better-calibrated judge carry the vote" do
      sharp, blunt = evaluator.judges
      allow(sharp).to receive_messages(calibrated?: true, sensitivity: 0.95, specificity: 0.95)
      allow(blunt).to receive_messages(calibrated?: true, sensitivity: 0.6, specificity: 0.6)
      judges_answer({ "gpt-4o" => true, "gpt-4o-mini" => false })

      result = evaluator.evaluate_weighted(input: input, output: "4", criteria: criteria)

      expect(result[:weights].map { |w| w[:weight] }).to all(be_between(0.0, 1.0))
      expect(result[:weights].sum { |w| w[:weight] }).to be_within(0.001).of(1.0)
      expect(result[:weights].first[:weight]).to be_within(0.001).of(0.9 / 1.1)
      expect(result[:consensus]).to be true
      expect(result[:positive_votes]).to eq(1) # still one vote each; only the weight differs
    end
  end

  describe "#evaluate_unanimous" do
    let(:criteria) { "Is the answer correct?" }

    it "reaches consensus only when every judge passes the output" do
      judges_answer({ "gpt-4o" => true, "gpt-4o-mini" => true })

      result = evaluator.evaluate_unanimous(input: "What is 2 + 2?", output: "4", criteria: criteria)

      expect(result).to include(consensus: true, positive_votes: 2, strategy: :unanimous)
    end

    # Unanimity is about the positive verdict: judges agreeing that the output
    # fails is full agreement, and still not a consensus that it passed.
    it "denies consensus when the judges unanimously fail the output" do
      judges_answer({ "gpt-4o" => false, "gpt-4o-mini" => false })

      result = evaluator.evaluate_unanimous(input: "What is 2 + 2?", output: "5", criteria: criteria)

      expect(result).to include(consensus: false, positive_votes: 0, agreement_rate: 1.0)
    end

    it "denies consensus on a single dissent" do
      judges_answer({ "gpt-4o" => true, "gpt-4o-mini" => false })

      result = evaluator.evaluate_unanimous(input: "What is 2 + 2?", output: "4", criteria: criteria)

      expect(result).to include(consensus: false)
    end
  end

  describe "#evaluate_threshold" do
    let(:criteria) { "Is the answer correct?" }

    def consensus_at(threshold, verdicts)
      judges_answer(verdicts)
      evaluator.evaluate_threshold(
        input: "What is 2 + 2?", output: "4", criteria: criteria, threshold: threshold
      )
    end

    it "passes a split at a threshold the split meets" do
      expect(consensus_at(0.5, { "gpt-4o" => true, "gpt-4o-mini" => false }))
        .to include(consensus: true, positive_votes: 1, strategy: :threshold)
    end

    it "fails the same split at a threshold above it" do
      expect(consensus_at(0.75, { "gpt-4o" => true, "gpt-4o-mini" => false }))
        .to include(consensus: false)
    end

    it "passes a unanimous vote at any threshold" do
      expect(consensus_at(1.0, { "gpt-4o" => true, "gpt-4o-mini" => true })).to include(consensus: true)
    end
  end

  describe "#evaluate_batch" do
    let(:samples) do
      [
        { input: "What is 1 + 1?", output: "2" },
        { input: "What is 2 + 2?", output: "4" },
        { input: "What is 3 + 3?", output: "7" } # wrong, and the judges split over it
      ]
    end
    let(:criteria) { "Is the answer correct?" }

    before do
      judges_answer(
        {
          "gpt-4o" => ->(output) { %w[2 4].include?(output) },
          "gpt-4o-mini" => ->(output) { %w[2 7].include?(output) }
        }
      )
    end

    it "returns one result per sample, in order" do
      results = evaluator.evaluate_batch(samples, criteria: criteria)[:results]

      expect(results.map { |r| r[:positive_votes] }).to eq([2, 1, 1])
      expect(results.map { |r| r[:consensus] }).to eq([true, false, false])
    end

    it "computes the aggregates from those results" do
      results = evaluator.evaluate_batch(samples, criteria: criteria)

      expect(results[:consensus_rate]).to be_within(0.001).of(1.0 / 3)
      expect(results[:average_agreement]).to be_within(0.001).of((1.0 + 0.5 + 0.5) / 3)
      expect(results[:unanimous_count]).to eq(1)
    end

    # `agreement_rate` is the larger side over the total, so it never drops below
    # 0.5 and this counter, which asks for less than 0.5, never fires. Asserted so
    # the day the metric is fixed, this says so.
    it "reports no high-disagreement samples, which it cannot" do
      results = evaluator.evaluate_batch(samples, criteria: criteria)

      expect(results[:high_disagreement_count]).to eq(0)
    end

    it "honours a strategy passed in place of the default" do
      results = evaluator.evaluate_batch(samples, criteria: criteria, strategy: :unanimous)

      expect(results[:results].map { |r| r[:strategy] }).to all(eq(:unanimous))
      expect(results[:results].map { |r| r[:consensus] }).to eq([true, false, false])
    end
  end

  describe "#flag_for_human_review" do
    let(:samples) do
      [
        { input: "What is 1 + 1?", output: "2" }, # both judges agree
        { input: "Explain quantum physics", output: "Complex topic..." } # they split
      ]
    end
    let(:criteria) { "Is the answer complete and accurate?" }

    before do
      judges_answer(
        {
          "gpt-4o" => true,
          "gpt-4o-mini" => ->(output) { output == "2" }
        }
      )
    end

    it "flags only the sample the judges disagreed over" do
      flagged = evaluator.flag_for_human_review(samples, criteria: criteria, disagreement_threshold: 0.6)

      expect(flagged.map { |f| f[:sample] }).to eq([samples.last])
      expect(flagged.first[:reason]).to eq("Low agreement: 50.0%")
      expect(flagged.first[:result]).to include(positive_votes: 1, negative_votes: 1)
    end

    it "flags nothing when the threshold sits at or below the agreement" do
      expect(evaluator.flag_for_human_review(samples, criteria: criteria, disagreement_threshold: 0.5))
        .to be_empty
    end

    # The default threshold is 0.5 and `agreement_rate` never goes below it, so
    # calling this without one can only ever return nothing.
    it "flags nothing at the default threshold" do
      expect(evaluator.flag_for_human_review(samples, criteria: criteria)).to be_empty
    end
  end

  describe "#inter_rater_reliability" do
    let(:criteria) { "Is this correct?" }
    let(:samples) { 4.times.map { |i| { input: "Q#{i}", output: "A#{i}" } } }

    it "measures how often the judges landed on the same verdict" do
      judges_answer(
        {
          "gpt-4o" => true,
          "gpt-4o-mini" => ->(output) { %w[A0 A1].include?(output) }
        }
      )

      reliability = evaluator.inter_rater_reliability(samples, criteria: criteria)

      expect(reliability).to include(
        mean_pairwise_agreement: 0.5,
        min_pairwise_agreement: 0.5,
        max_pairwise_agreement: 0.5,
        num_judges: 2,
        num_samples: 4
      )
      # Agreement half the time, while both judges lean positive, is worse than
      # the chance agreement that lean already buys: p_bar 0.5 against p_e 0.625.
      expect(reliability[:fleiss_kappa]).to be_within(0.001).of(-1.0 / 3)
    end

    it "reports perfect reliability when the judges never differ" do
      judges_answer({ "gpt-4o" => true, "gpt-4o-mini" => true })

      reliability = evaluator.inter_rater_reliability(samples, criteria: criteria)

      expect(reliability[:mean_pairwise_agreement]).to eq(1.0)
      expect(reliability[:fleiss_kappa]).to eq(1.0)
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

    # Without a model to ask, every judgement comes back as "did not pass" and the
    # judges calibrate to no better than a coin toss. These read the sample's own
    # prefix instead, so calibration measures the code rather than the network.
    before do
      evaluator.judges.each do |judge|
        allow(judge).to receive(:judge_output) do |input, _output, _criteria|
          { passed: input.to_s.start_with?("P"), confidence: 0.9, reasoning: "Stubbed" }
        end
      end
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
