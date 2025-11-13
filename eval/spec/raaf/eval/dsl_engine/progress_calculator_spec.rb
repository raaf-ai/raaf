# frozen_string_literal: true

require "spec_helper"
require "raaf/eval/dsl_engine/progress_calculator"

RSpec.describe RAAF::Eval::DslEngine::ProgressCalculator do
  describe "#config_start_progress" do
    it "returns 0% for first config" do
      calculator = described_class.new(3, 2, 5)
      expect(calculator.config_start_progress(0, 3)).to eq(0.0)
    end

    it "returns 33.33% for second config of 3" do
      calculator = described_class.new(3, 2, 5)
      expect(calculator.config_start_progress(1, 3)).to eq(33.33)
    end

    it "returns 66.67% for third config of 3" do
      calculator = described_class.new(3, 2, 5)
      expect(calculator.config_start_progress(2, 3)).to eq(66.67)
    end

    it "returns 50% for second config of 2" do
      calculator = described_class.new(2, 2, 5)
      expect(calculator.config_start_progress(1, 2)).to eq(50.0)
    end
  end

  describe "#evaluator_progress" do
    it "calculates progress within first configuration" do
      calculator = described_class.new(3, 2, 5)

      # First evaluator of 5 within first config
      progress = calculator.evaluator_progress(0, 5)
      expect(progress).to be_between(0.0, 33.33)
    end

    it "advances progress for each evaluator" do
      calculator = described_class.new(3, 2, 5)

      progress1 = calculator.evaluator_progress(0, 5)
      progress2 = calculator.evaluator_progress(1, 5)
      progress3 = calculator.evaluator_progress(2, 5)

      expect(progress2).to be > progress1
      expect(progress3).to be > progress2
    end

    it "stays within configuration boundaries" do
      calculator = described_class.new(3, 2, 5)

      # Last evaluator of first config should be < 33.33%
      progress = calculator.evaluator_progress(4, 5)
      expect(progress).to be < 33.33
    end
  end

  describe "#advance_config" do
    it "increments configuration index" do
      calculator = described_class.new(3, 2, 5)

      expect(calculator.current_progress).to eq(0.0)

      calculator.advance_config
      expect(calculator.current_progress).to eq(33.33)

      calculator.advance_config
      expect(calculator.current_progress).to eq(66.67)
    end
  end

  describe "#advance_evaluator" do
    it "increments evaluator index" do
      calculator = described_class.new(3, 2, 5)

      # advance_evaluator doesn't directly affect current_progress
      # but is tracked internally for evaluator_progress calculations
      expect { calculator.advance_evaluator }.not_to raise_error
    end
  end

  describe "#current_progress" do
    it "returns progress based on configuration index" do
      calculator = described_class.new(3, 2, 5)

      expect(calculator.current_progress).to eq(0.0)

      calculator.advance_config
      expect(calculator.current_progress).to eq(33.33)

      calculator.advance_config
      expect(calculator.current_progress).to eq(66.67)

      calculator.advance_config
      expect(calculator.current_progress).to eq(100.0)
    end

    it "handles single configuration" do
      calculator = described_class.new(1, 2, 5)

      expect(calculator.current_progress).to eq(0.0)

      calculator.advance_config
      expect(calculator.current_progress).to eq(100.0)
    end
  end

  describe "progress accuracy" do
    it "ensures total progress reaches 100% after all configs" do
      calculator = described_class.new(3, 2, 5)

      calculator.advance_config
      calculator.advance_config
      calculator.advance_config

      expect(calculator.current_progress).to eq(100.0)
    end

    it "ensures progress increments are reasonable" do
      calculator = described_class.new(5, 3, 4)

      previous_progress = 0.0
      5.times do
        calculator.advance_config
        current = calculator.current_progress

        # Each step should increase progress
        expect(current).to be > previous_progress
        previous_progress = current
      end

      expect(previous_progress).to eq(100.0)
    end
  end
end
