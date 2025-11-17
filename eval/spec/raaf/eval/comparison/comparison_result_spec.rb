# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Eval::Comparison::ComparisonResult do
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

  let(:field_results) do
    {
      low_temp: baseline_result,
      medium_temp: medium_temp_result,
      high_temp: high_temp_result
    }
  end

  describe "#initialize" do
    it "accepts baseline_name and field_results" do
      expect do
        described_class.new(
          baseline_name: :low_temp,
          field_results: field_results
        )
      end.not_to raise_error
    end

    it "sets default timestamp to current time" do
      result = described_class.new(
        baseline_name: :low_temp,
        field_results: field_results
      )

      expect(result.timestamp).to be_a(Time)
      expect(result.timestamp).to be_within(1).of(Time.now)
    end

    it "accepts custom timestamp" do
      custom_time = Time.new(2025, 1, 13, 12, 0, 0)
      result = described_class.new(
        baseline_name: :low_temp,
        field_results: field_results,
        timestamp: custom_time
      )

      expect(result.timestamp).to eq(custom_time)
    end

    it "calculates comparison data on initialization" do
      result = described_class.new(
        baseline_name: :low_temp,
        field_results: field_results
      )

      expect(result.field_deltas).not_to be_nil
      expect(result.rankings).not_to be_nil
      expect(result.improvements).not_to be_nil
      expect(result.regressions).not_to be_nil
      expect(result.best_configuration).not_to be_nil
      expect(result.metadata).not_to be_nil
    end
  end

  describe "#field_deltas" do
    it "contains baseline scores" do
      result = described_class.new(
        baseline_name: :low_temp,
        field_results: field_results
      )

      expect(result.field_deltas[:output][:baseline_score]).to eq(0.85)
      expect(result.field_deltas[:tokens][:baseline_score]).to eq(1200)
    end

    it "contains configuration deltas" do
      result = described_class.new(
        baseline_name: :low_temp,
        field_results: field_results
      )

      expect(result.field_deltas[:output][:configurations]).to have_key(:medium_temp)
      expect(result.field_deltas[:output][:configurations]).to have_key(:high_temp)
    end

    it "excludes baseline from configurations" do
      result = described_class.new(
        baseline_name: :low_temp,
        field_results: field_results
      )

      expect(result.field_deltas[:output][:configurations]).not_to have_key(:low_temp)
    end
  end

  describe "#rankings" do
    it "contains rankings for all fields" do
      result = described_class.new(
        baseline_name: :low_temp,
        field_results: field_results
      )

      expect(result.rankings).to have_key(:output)
      expect(result.rankings).to have_key(:tokens)
    end

    it "excludes baseline from rankings" do
      result = described_class.new(
        baseline_name: :low_temp,
        field_results: field_results
      )

      expect(result.rankings[:output]).not_to include(:low_temp)
      expect(result.rankings[:tokens]).not_to include(:low_temp)
    end
  end

  describe "#improvements" do
    it "identifies improved configurations" do
      result = described_class.new(
        baseline_name: :low_temp,
        field_results: field_results
      )

      # medium_temp improved on both fields
      expect(result.improvements[:medium_temp]).to include(:output, :tokens)
    end

    it "excludes configurations with no improvements" do
      result = described_class.new(
        baseline_name: :low_temp,
        field_results: field_results
      )

      # high_temp has no improvements (both negative deltas)
      expect(result.improvements[:high_temp]).to eq([])
    end
  end

  describe "#regressions" do
    it "identifies regressed configurations" do
      result = described_class.new(
        baseline_name: :low_temp,
        field_results: field_results
      )

      # high_temp regressed on both fields
      expect(result.regressions[:high_temp]).to include(:output, :tokens)
    end

    it "excludes configurations with no regressions" do
      result = described_class.new(
        baseline_name: :low_temp,
        field_results: field_results
      )

      # medium_temp has no regressions (both positive deltas)
      expect(result.regressions[:medium_temp]).to eq([])
    end
  end

  describe "#best_configuration" do
    it "selects configuration with most improvements" do
      result = described_class.new(
        baseline_name: :low_temp,
        field_results: field_results
      )

      # medium_temp has 2 improvements, high_temp has 0
      expect(result.best_configuration).to eq(:medium_temp)
    end
  end

  describe "#metadata" do
    it "includes total_configurations" do
      result = described_class.new(
        baseline_name: :low_temp,
        field_results: field_results
      )

      # 3 total configurations (low, medium, high)
      expect(result.metadata[:total_configurations]).to eq(3)
    end

    it "includes total_fields" do
      result = described_class.new(
        baseline_name: :low_temp,
        field_results: field_results
      )

      # 2 fields (output, tokens)
      expect(result.metadata[:total_fields]).to eq(2)
    end

    it "includes comparison_timestamp" do
      result = described_class.new(
        baseline_name: :low_temp,
        field_results: field_results
      )

      expect(result.metadata[:comparison_timestamp]).to be_a(Time)
    end
  end

  describe "#to_h" do
    it "returns complete comparison data as hash" do
      result = described_class.new(
        baseline_name: :low_temp,
        field_results: field_results
      )

      hash = result.to_h

      expect(hash).to have_key(:baseline_name)
      expect(hash).to have_key(:timestamp)
      expect(hash).to have_key(:field_deltas)
      expect(hash).to have_key(:rankings)
      expect(hash).to have_key(:improvements)
      expect(hash).to have_key(:regressions)
      expect(hash).to have_key(:best_configuration)
      expect(hash).to have_key(:metadata)
    end

    it "returns serializable data" do
      result = described_class.new(
        baseline_name: :low_temp,
        field_results: field_results
      )

      hash = result.to_h

      # Should be convertible to JSON
      expect { JSON.generate(hash) }.not_to raise_error
    end
  end

  describe "#rank_by_field" do
    it "returns ranking for specified field" do
      result = described_class.new(
        baseline_name: :low_temp,
        field_results: field_results
      )

      ranking = result.rank_by_field(:output)

      expect(ranking).to be_an(Array)
      expect(ranking).to include(:medium_temp, :high_temp)
    end

    it "returns nil for non-existent field" do
      result = described_class.new(
        baseline_name: :low_temp,
        field_results: field_results
      )

      ranking = result.rank_by_field(:nonexistent)

      expect(ranking).to be_nil
    end
  end
end
