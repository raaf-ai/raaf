# frozen_string_literal: true

require "spec_helper"
require "raaf/eval/llm_judge"

RSpec.describe RAAF::Eval::LLMJudge::CalibrationSet do
  subject(:calibration) { described_class.new }

  describe "#initialize" do
    it "creates an empty calibration set" do
      expect(calibration.samples).to be_empty
      expect(calibration.size).to eq(0)
    end

    it "accepts initial samples" do
      samples = [
        { input: "Q1", output: "A1", ground_truth: true },
        { input: "Q2", output: "A2", ground_truth: false }
      ]
      set = described_class.new(samples: samples)
      expect(set.size).to eq(2)
    end

    it "accepts metadata" do
      set = described_class.new(metadata: { version: "1.0", domain: "test" })
      expect(set.metadata[:version]).to eq("1.0")
      expect(set.metadata[:domain]).to eq("test")
    end
  end

  describe "#add" do
    it "adds a sample to the set" do
      calibration.add(input: "Q1", output: "A1", ground_truth: true)
      expect(calibration.size).to eq(1)
    end

    it "supports chaining" do
      result = calibration
               .add(input: "Q1", output: "A1", ground_truth: true)
               .add(input: "Q2", output: "A2", ground_truth: false)

      expect(result).to eq(calibration)
      expect(calibration.size).to eq(2)
    end

    it "adds context to samples" do
      calibration.add(
        input: "Q1",
        output: "A1",
        ground_truth: true,
        context: { domain: "math", difficulty: "easy" }
      )

      expect(calibration.samples.first[:context][:domain]).to eq("math")
      expect(calibration.samples.first[:context][:difficulty]).to eq("easy")
    end

    it "adds timestamp to samples" do
      calibration.add(input: "Q1", output: "A1", ground_truth: true)
      expect(calibration.samples.first[:added_at]).to be_a(String)
    end
  end

  describe "#positive_samples and #negative_samples" do
    before do
      calibration.add(input: "Q1", output: "A1", ground_truth: true)
      calibration.add(input: "Q2", output: "A2", ground_truth: true)
      calibration.add(input: "Q3", output: "A3", ground_truth: false)
    end

    it "returns positive samples" do
      expect(calibration.positive_samples.size).to eq(2)
      expect(calibration.positive_samples.all? { |s| s[:ground_truth] }).to be true
    end

    it "returns negative samples" do
      expect(calibration.negative_samples.size).to eq(1)
      expect(calibration.negative_samples.all? { |s| !s[:ground_truth] }).to be true
    end
  end

  describe "#m0 and #m1" do
    before do
      3.times { |i| calibration.add(input: "P#{i}", output: "A#{i}", ground_truth: true) }
      2.times { |i| calibration.add(input: "N#{i}", output: "A#{i}", ground_truth: false) }
    end

    it "returns count of positive samples (m1)" do
      expect(calibration.m1).to eq(3)
    end

    it "returns count of negative samples (m0)" do
      expect(calibration.m0).to eq(2)
    end
  end

  describe "#valid? and #validate!" do
    context "with sufficient samples" do
      before do
        15.times { |i| calibration.add(input: "P#{i}", output: "A#{i}", ground_truth: true) }
        15.times { |i| calibration.add(input: "N#{i}", output: "A#{i}", ground_truth: false) }
      end

      it "returns true for valid?" do
        expect(calibration.valid?).to be true
      end

      it "returns self for validate!" do
        expect(calibration.validate!).to eq(calibration)
      end
    end

    context "with insufficient samples" do
      before do
        5.times { |i| calibration.add(input: "P#{i}", output: "A#{i}", ground_truth: true) }
        5.times { |i| calibration.add(input: "N#{i}", output: "A#{i}", ground_truth: false) }
      end

      it "returns false for valid?" do
        expect(calibration.valid?).to be false
      end

      it "raises InsufficientCalibrationDataError for validate!" do
        expect { calibration.validate! }.to raise_error(
          RAAF::Eval::LLMJudge::InsufficientCalibrationDataError
        )
      end

      it "allows custom minimum requirements" do
        expect(calibration.valid?(min_positive: 5, min_negative: 5)).to be true
      end
    end
  end

  describe "#split" do
    before do
      20.times { |i| calibration.add(input: "Q#{i}", output: "A#{i}", ground_truth: i.even?) }
    end

    it "splits into train and test sets" do
      train, test = calibration.split(ratio: 0.8)

      expect(train.size).to eq(16)
      expect(test.size).to eq(4)
    end

    it "is reproducible with seed" do
      train1, = calibration.split(ratio: 0.8, seed: 42)
      train2, = calibration.split(ratio: 0.8, seed: 42)

      expect(train1.samples).to eq(train2.samples)
    end
  end

  describe "#stratified_split" do
    before do
      15.times { |i| calibration.add(input: "P#{i}", output: "A#{i}", ground_truth: true) }
      5.times { |i| calibration.add(input: "N#{i}", output: "A#{i}", ground_truth: false) }
    end

    it "maintains positive/negative ratio" do
      train, test = calibration.stratified_split(ratio: 0.8)

      # Original ratio is 15:5 = 3:1
      train_ratio = train.m1.to_f / train.m0
      test_ratio = test.m1.to_f / test.m0

      expect(train_ratio).to be_within(0.5).of(3.0)
      expect(test_ratio).to be_within(0.5).of(3.0)
    end
  end

  describe "#filter" do
    before do
      calibration.add(input: "Q1", output: "A1", ground_truth: true, context: { domain: "math" })
      calibration.add(input: "Q2", output: "A2", ground_truth: true, context: { domain: "science" })
      calibration.add(input: "Q3", output: "A3", ground_truth: false, context: { domain: "math" })
    end

    it "filters by context attributes" do
      filtered = calibration.filter(domain: "math")
      expect(filtered.size).to eq(2)
      expect(filtered.samples.all? { |s| s[:context][:domain] == "math" }).to be true
    end

    it "returns a new CalibrationSet" do
      filtered = calibration.filter(domain: "math")
      expect(filtered).to be_a(described_class)
      expect(filtered).not_to eq(calibration)
    end
  end

  describe "serialization" do
    before do
      calibration.add(input: "Q1", output: "A1", ground_truth: true, context: { domain: "test" })
      calibration.add(input: "Q2", output: "A2", ground_truth: false)
    end

    describe "#to_h" do
      it "converts to hash" do
        hash = calibration.to_h
        expect(hash).to have_key(:metadata)
        expect(hash).to have_key(:samples)
        expect(hash[:samples].size).to eq(2)
      end
    end

    describe "#to_json" do
      it "converts to JSON" do
        json = calibration.to_json
        expect(json).to be_a(String)
        parsed = JSON.parse(json)
        expect(parsed["samples"].size).to eq(2)
      end
    end

    describe ".from_json" do
      it "loads from JSON string" do
        json = calibration.to_json
        loaded = described_class.from_json(json)

        expect(loaded.size).to eq(2)
        expect(loaded.m1).to eq(1)
        expect(loaded.m0).to eq(1)
      end
    end

    describe "#save and .load" do
      let(:file_path) { "/tmp/test_calibration_#{Process.pid}.json" }

      after { FileUtils.rm_f(file_path) }

      it "saves and loads from file" do
        calibration.save(file_path)
        loaded = described_class.load(file_path)

        expect(loaded.size).to eq(2)
        expect(loaded.samples.first[:input]).to eq("Q1")
      end
    end
  end

  describe ".merge" do
    let(:set1) do
      s = described_class.new
      s.add(input: "Q1", output: "A1", ground_truth: true)
      s
    end

    let(:set2) do
      s = described_class.new
      s.add(input: "Q2", output: "A2", ground_truth: false)
      s
    end

    it "merges multiple calibration sets" do
      merged = described_class.merge(set1, set2)

      expect(merged.size).to eq(2)
      expect(merged.m1).to eq(1)
      expect(merged.m0).to eq(1)
    end

    it "records merge metadata" do
      merged = described_class.merge(set1, set2)

      expect(merged.metadata[:merged_from]).to eq(2)
      expect(merged.metadata[:merged_at]).to be_a(String)
    end
  end

  describe "#statistics" do
    before do
      6.times { |i| calibration.add(input: "P#{i}", output: "A#{i}", ground_truth: true) }
      4.times { |i| calibration.add(input: "N#{i}", output: "A#{i}", ground_truth: false) }
    end

    it "returns comprehensive statistics" do
      stats = calibration.statistics

      expect(stats[:total_samples]).to eq(10)
      expect(stats[:positive_samples]).to eq(6)
      expect(stats[:negative_samples]).to eq(4)
      expect(stats[:positive_ratio]).to eq(0.6)
      expect(stats[:negative_ratio]).to eq(0.4)
      expect(stats[:balance_ratio]).to eq(1.5)
    end
  end
end
