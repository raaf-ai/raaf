# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Eval::Comparison::FieldDeltaCalculator do
  describe ".calculate" do
    let(:baseline_result) do
      double(
        "baseline_result",
        field_results: {
          output: { score: 0.85, label: "good" },
          tokens: { score: 1200, label: "good" }
        }
      )
    end

    let(:medium_temp_result) do
      double(
        "medium_temp_result",
        field_results: {
          output: { score: 0.88, label: "good" },
          tokens: { score: 1250, label: "good" }
        }
      )
    end

    let(:high_temp_result) do
      double(
        "high_temp_result",
        field_results: {
          output: { score: 0.82, label: "good" },
          tokens: { score: 1150, label: "good" }
        }
      )
    end

    let(:other_results) do
      {
        medium_temp: medium_temp_result,
        high_temp: high_temp_result
      }
    end

    it "calculates field deltas for all configurations" do
      result = described_class.calculate(baseline_result, other_results)

      expect(result).to have_key(:output)
      expect(result).to have_key(:tokens)
      expect(result[:output][:baseline_score]).to eq(0.85)
      expect(result[:tokens][:baseline_score]).to eq(1200)
    end

    it "calculates absolute delta correctly" do
      result = described_class.calculate(baseline_result, other_results)

      # Medium temp: 0.88 - 0.85 = 0.03
      expect(result[:output][:configurations][:medium_temp][:delta]).to eq(0.03)

      # High temp: 0.82 - 0.85 = -0.03
      expect(result[:output][:configurations][:high_temp][:delta]).to eq(-0.03)
    end

    it "calculates percentage delta correctly" do
      result = described_class.calculate(baseline_result, other_results)

      # Medium temp: ((0.88 - 0.85) / 0.85) * 100 = 3.53%
      expect(result[:output][:configurations][:medium_temp][:delta_pct]).to eq(3.53)

      # High temp: ((0.82 - 0.85) / 0.85) * 100 = -3.53%
      expect(result[:output][:configurations][:high_temp][:delta_pct]).to eq(-3.53)
    end

    it "handles baseline_score = 0 edge case" do
      baseline_result_zero = double(
        "baseline_result_zero",
        field_results: {
          output: { score: 0.0, label: "good" }
        }
      )

      other_result = double(
        "other_result",
        field_results: {
          output: { score: 0.5, label: "good" }
        }
      )

      result = described_class.calculate(baseline_result_zero, { other: other_result })

      # Absolute delta should still work
      expect(result[:output][:configurations][:other][:delta]).to eq(0.5)

      # Percentage delta should be 0.0 (avoid division by zero)
      expect(result[:output][:configurations][:other][:delta_pct]).to eq(0.0)
    end

    it "includes passed status from field results" do
      result = described_class.calculate(baseline_result, other_results)

      expect(result[:output][:configurations][:medium_temp][:label]).to eq("good")
      expect(result[:output][:configurations][:high_temp][:label]).to eq("good")
    end

    it "handles negative deltas" do
      result = described_class.calculate(baseline_result, other_results)

      # Tokens: 1150 - 1200 = -50
      expect(result[:tokens][:configurations][:high_temp][:delta]).to eq(-50)

      # Percentage: ((1150 - 1200) / 1200) * 100 = -4.17%
      expect(result[:tokens][:configurations][:high_temp][:delta_pct]).to eq(-4.17)
    end

    it "handles multiple configurations" do
      result = described_class.calculate(baseline_result, other_results)

      expect(result[:output][:configurations]).to have_key(:medium_temp)
      expect(result[:output][:configurations]).to have_key(:high_temp)
      expect(result[:output][:configurations].size).to eq(2)
    end

    it "handles multiple fields" do
      result = described_class.calculate(baseline_result, other_results)

      expect(result.keys).to contain_exactly(:output, :tokens)
    end

    it "rounds absolute delta to 4 decimal places" do
      baseline_result_precise = double(
        "baseline_result_precise",
        field_results: {
          output: { score: 0.123456789, label: "good" }
        }
      )

      other_result_precise = double(
        "other_result_precise",
        field_results: {
          output: { score: 0.987654321, label: "good" }
        }
      )

      result = described_class.calculate(baseline_result_precise, { other: other_result_precise })

      # 0.987654321 - 0.123456789 = 0.864197532 → rounded to 0.8642
      expect(result[:output][:configurations][:other][:delta]).to eq(0.8642)
    end

    it "rounds percentage delta to 2 decimal places" do
      result = described_class.calculate(baseline_result, other_results)

      # All percentage deltas should have at most 2 decimal places
      result.each_value do |field_delta|
        field_delta[:configurations].each_value do |config_data|
          # Check that percentage delta has at most 2 decimal places
          expect(config_data[:delta_pct].to_s.split('.').last.length).to be <= 2
        end
      end
    end
  end
end
