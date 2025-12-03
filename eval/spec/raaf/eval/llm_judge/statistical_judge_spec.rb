# frozen_string_literal: true

require "spec_helper"
require "raaf/eval/llm_judge"

RSpec.describe RAAF::Eval::LLMJudge::StatisticalJudge do
  subject(:judge) { described_class.new(model: "gpt-4o", temperature: 0.0) }

  let(:calibration_set) do
    set = RAAF::Eval::LLMJudge::CalibrationSet.new

    # Add positive samples
    15.times do |i|
      set.add(
        input: "What is #{i} + #{i}?",
        output: (i + i).to_s,
        ground_truth: true
      )
    end

    # Add negative samples
    15.times do |i|
      set.add(
        input: "What is #{i} + #{i}?",
        output: (i + i + 1).to_s,
        ground_truth: false
      )
    end

    set
  end

  describe "#initialize" do
    it "sets default values" do
      expect(judge.model).to eq("gpt-4o")
      expect(judge.temperature).to eq(0.0)
      expect(judge.calibrated?).to be false
      expect(judge.sensitivity).to be_nil
      expect(judge.specificity).to be_nil
    end

    it "accepts custom configuration" do
      custom = described_class.new(
        model: "claude-3-5-sonnet",
        temperature: 0.2,
        cache: false,
        timeout: 60
      )

      expect(custom.model).to eq("claude-3-5-sonnet")
      expect(custom.temperature).to eq(0.2)
    end
  end

  describe "#calibrate", :vcr do
    let(:criteria) { "Is the mathematical answer correct?" }

    it "computes sensitivity and specificity" do
      result = judge.calibrate(calibration_set, criteria: criteria)

      expect(result[:sensitivity]).to be_between(0.0, 1.0)
      expect(result[:specificity]).to be_between(0.0, 1.0)
    end

    it "stores calibration metadata" do
      result = judge.calibrate(calibration_set, criteria: criteria)

      expect(result[:calibrated_at]).to be_a(String)
      expect(result[:criteria]).to eq(criteria)
      expect(result[:m0]).to eq(15)
      expect(result[:m1]).to eq(15)
      expect(result[:true_positives]).to be >= 0
      expect(result[:true_negatives]).to be >= 0
    end

    it "marks judge as calibrated" do
      judge.calibrate(calibration_set, criteria: criteria)

      expect(judge.calibrated?).to be true
      expect(judge.sensitivity).to be_a(Float)
      expect(judge.specificity).to be_a(Float)
    end

    it "raises error for insufficient calibration data" do
      small_set = RAAF::Eval::LLMJudge::CalibrationSet.new
      3.times { |i| small_set.add(input: "Q#{i}", output: "A#{i}", ground_truth: true) }
      3.times { |i| small_set.add(input: "Q#{i}", output: "A#{i}", ground_truth: false) }

      expect { judge.calibrate(small_set, criteria: criteria) }.to raise_error(
        RAAF::Eval::LLMJudge::InsufficientCalibrationDataError
      )
    end
  end

  describe "#calibrated?" do
    it "returns false before calibration" do
      expect(judge.calibrated?).to be false
    end

    it "returns true after calibration", :vcr do
      judge.calibrate(calibration_set, criteria: "Is correct?")
      expect(judge.calibrated?).to be true
    end
  end

  describe "#better_than_random?" do
    it "returns false when not calibrated" do
      expect(judge.better_than_random?).to be false
    end

    context "when calibrated", :vcr do
      before do
        judge.calibrate(calibration_set, criteria: "Is correct?")
      end

      it "returns true when sensitivity + specificity > 1" do
        # Assuming a good judge, it should be better than random
        expect(judge.better_than_random?).to be true
      end
    end
  end

  describe "#bias_corrected_accuracy" do
    it "raises error when not calibrated" do
      expect { judge.bias_corrected_accuracy(0.7) }.to raise_error(
        RAAF::Eval::LLMJudge::JudgeNotCalibratedError
      )
    end

    context "when calibrated" do
      before do
        # Manually set calibration values for testing
        judge.instance_variable_set(:@sensitivity, 0.9)
        judge.instance_variable_set(:@specificity, 0.8)
      end

      it "applies bias correction formula" do
        # Formula: theta = (p + q0 - 1) / (q0 + q1 - 1)
        # With p=0.75, q0=0.8, q1=0.9:
        # theta = (0.75 + 0.8 - 1) / (0.8 + 0.9 - 1) = 0.55 / 0.7 ≈ 0.786

        raw_proportion = 0.75
        corrected = judge.bias_corrected_accuracy(raw_proportion)

        expected = (0.75 + 0.8 - 1) / (0.8 + 0.9 - 1)
        expect(corrected).to be_within(0.001).of(expected)
      end

      it "clamps result to valid probability range" do
        # Test extreme values
        expect(judge.bias_corrected_accuracy(0.0)).to be >= 0.0
        expect(judge.bias_corrected_accuracy(1.0)).to be <= 1.0
      end
    end
  end

  describe "#confidence_interval" do
    before do
      # Set up calibrated state
      judge.instance_variable_set(:@sensitivity, 0.9)
      judge.instance_variable_set(:@specificity, 0.8)

      mock_calibration = RAAF::Eval::LLMJudge::CalibrationSet.new
      50.times { |i| mock_calibration.add(input: "P#{i}", output: "A#{i}", ground_truth: true) }
      50.times { |i| mock_calibration.add(input: "N#{i}", output: "A#{i}", ground_truth: false) }
      judge.instance_variable_set(:@calibration_set, mock_calibration)
    end

    it "returns confidence interval structure" do
      ci = judge.confidence_interval(0.75, 100, alpha: 0.05)

      expect(ci).to have_key(:point_estimate)
      expect(ci).to have_key(:lower)
      expect(ci).to have_key(:upper)
      expect(ci).to have_key(:confidence_level)
      expect(ci).to have_key(:standard_error)
      expect(ci).to have_key(:variance_decomposition)
      expect(ci).to have_key(:sample_sizes)
    end

    it "computes valid confidence bounds" do
      ci = judge.confidence_interval(0.75, 100, alpha: 0.05)

      expect(ci[:confidence_level]).to eq(0.95)
      expect(ci[:lower]).to be < ci[:point_estimate]
      expect(ci[:upper]).to be > ci[:point_estimate]
      expect(ci[:lower]).to be >= 0.0
      expect(ci[:upper]).to be <= 1.0
    end

    it "decomposes variance into sources" do
      ci = judge.confidence_interval(0.75, 100)

      expect(ci[:variance_decomposition]).to have_key(:test_variance)
      expect(ci[:variance_decomposition]).to have_key(:calibration_variance)
    end

    it "includes sample sizes" do
      ci = judge.confidence_interval(0.75, 100)

      expect(ci[:sample_sizes][:test_n]).to eq(100)
      expect(ci[:sample_sizes][:calibration_m0]).to eq(50)
      expect(ci[:sample_sizes][:calibration_m1]).to eq(50)
    end

    it "produces narrower intervals with more samples" do
      ci_small = judge.confidence_interval(0.75, 50)
      ci_large = judge.confidence_interval(0.75, 500)

      width_small = ci_small[:upper] - ci_small[:lower]
      width_large = ci_large[:upper] - ci_large[:lower]

      expect(width_large).to be < width_small
    end
  end

  describe "#evaluate", :vcr do
    let(:criteria) { "Is the mathematical answer correct?" }

    before do
      judge.calibrate(calibration_set, criteria: criteria)
    end

    it "returns judgment result" do
      result = judge.evaluate(
        input: "What is 5 + 5?",
        output: "10",
        criteria: criteria
      )

      expect(result).to have_key(:passed)
      expect(result).to have_key(:confidence)
      expect(result).to have_key(:reasoning)
    end

    it "raises error without criteria" do
      expect do
        judge.evaluate(input: "Q", output: "A", criteria: nil)
      end.to raise_error(ArgumentError)
    end
  end

  describe "#evaluate_batch", :vcr do
    let(:criteria) { "Is the mathematical answer correct?" }
    let(:test_samples) do
      [
        { input: "What is 1 + 1?", output: "2" },
        { input: "What is 2 + 2?", output: "4" },
        { input: "What is 3 + 3?", output: "7" }  # Incorrect
      ]
    end

    before do
      judge.calibrate(calibration_set, criteria: criteria)
    end

    it "returns comprehensive batch results" do
      results = judge.evaluate_batch(test_samples, criteria: criteria)

      expect(results).to have_key(:raw_accuracy)
      expect(results).to have_key(:bias_corrected_accuracy)
      expect(results).to have_key(:confidence_interval)
      expect(results).to have_key(:passed_count)
      expect(results).to have_key(:total_count)
      expect(results).to have_key(:individual_results)
      expect(results).to have_key(:calibration)
    end

    it "includes calibration parameters" do
      results = judge.evaluate_batch(test_samples, criteria: criteria)

      expect(results[:calibration][:sensitivity]).to eq(judge.sensitivity)
      expect(results[:calibration][:specificity]).to eq(judge.specificity)
    end

    it "includes individual results" do
      results = judge.evaluate_batch(test_samples, criteria: criteria)

      expect(results[:individual_results].size).to eq(3)
      results[:individual_results].each do |r|
        expect(r).to have_key(:passed)
        expect(r).to have_key(:confidence)
      end
    end
  end

  describe "#reset_calibration!" do
    before do
      judge.instance_variable_set(:@sensitivity, 0.9)
      judge.instance_variable_set(:@specificity, 0.8)
    end

    it "clears calibration state" do
      judge.reset_calibration!

      expect(judge.calibrated?).to be false
      expect(judge.sensitivity).to be_nil
      expect(judge.specificity).to be_nil
    end

    it "returns self for chaining" do
      expect(judge.reset_calibration!).to eq(judge)
    end
  end

  describe "#summary" do
    it "returns judge state summary" do
      summary = judge.summary

      expect(summary[:model]).to eq("gpt-4o")
      expect(summary[:temperature]).to eq(0.0)
      expect(summary[:calibrated]).to be false
    end

    context "when calibrated" do
      before do
        judge.instance_variable_set(:@sensitivity, 0.9)
        judge.instance_variable_set(:@specificity, 0.8)
      end

      it "includes calibration details" do
        summary = judge.summary

        expect(summary[:calibrated]).to be true
        expect(summary[:sensitivity]).to eq(0.9)
        expect(summary[:specificity]).to eq(0.8)
        expect(summary[:better_than_random]).to be true
      end
    end
  end
end
