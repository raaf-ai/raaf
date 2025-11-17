# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Eval::Comparison::RankingEngine do
  describe ".rank_all_fields" do
    let(:field_deltas) do
      {
        output: {
          baseline_score: 0.85,
          configurations: {
            medium_temp: { score: 0.88, delta: 0.03, delta_pct: 3.53, label: "good" },
            high_temp: { score: 0.82, delta: -0.03, delta_pct: -3.53, label: "good" },
            low_temp: { score: 0.86, delta: 0.01, delta_pct: 1.18, label: "good" }
          }
        },
        tokens: {
          baseline_score: 1200,
          configurations: {
            medium_temp: { score: 1250, delta: 50, delta_pct: 4.17, label: "good" },
            high_temp: { score: 1150, delta: -50, delta_pct: -4.17, label: "good" },
            low_temp: { score: 1200, delta: 0, delta_pct: 0.0, label: "good" }
          }
        }
      }
    end

    it "ranks all fields" do
      result = described_class.rank_all_fields(field_deltas)

      expect(result).to have_key(:output)
      expect(result).to have_key(:tokens)
    end

    it "ranks configurations by score descending" do
      result = described_class.rank_all_fields(field_deltas)

      # Output: 0.88 > 0.86 > 0.82
      expect(result[:output]).to eq([:medium_temp, :low_temp, :high_temp])

      # Tokens: 1250 > 1200 > 1150
      expect(result[:tokens]).to eq([:medium_temp, :low_temp, :high_temp])
    end

    it "uses alphabetical order for tie-breaking" do
      tied_field_deltas = {
        output: {
          baseline_score: 0.85,
          configurations: {
            zebra: { score: 0.90, delta: 0.05, delta_pct: 5.88, label: "good" },
            apple: { score: 0.90, delta: 0.05, delta_pct: 5.88, label: "good" },
            banana: { score: 0.90, delta: 0.05, delta_pct: 5.88, label: "good" }
          }
        }
      }

      result = described_class.rank_all_fields(tied_field_deltas)

      # Same score, alphabetical order
      expect(result[:output]).to eq([:apple, :banana, :zebra])
    end

    it "handles single configuration" do
      single_config_deltas = {
        output: {
          baseline_score: 0.85,
          configurations: {
            only_config: { score: 0.90, delta: 0.05, delta_pct: 5.88, label: "good" }
          }
        }
      }

      result = described_class.rank_all_fields(single_config_deltas)

      expect(result[:output]).to eq([:only_config])
    end

    it "handles multiple configurations with different scores" do
      result = described_class.rank_all_fields(field_deltas)

      # Should have 3 configurations per field
      expect(result[:output].size).to eq(3)
      expect(result[:tokens].size).to eq(3)
    end
  end

  describe ".rank_field" do
    let(:configurations) do
      {
        medium_temp: { score: 0.88, delta: 0.03, delta_pct: 3.53, label: "good" },
        high_temp: { score: 0.82, delta: -0.03, delta_pct: -3.53, label: "good" },
        low_temp: { score: 0.86, delta: 0.01, delta_pct: 1.18, label: "good" }
      }
    end

    it "ranks configurations by score descending" do
      result = described_class.rank_field(configurations)

      expect(result).to eq([:medium_temp, :low_temp, :high_temp])
    end

    it "returns configuration names only" do
      result = described_class.rank_field(configurations)

      result.each do |config_name|
        expect(config_name).to be_a(Symbol)
        expect(configurations).to have_key(config_name)
      end
    end

    it "uses alphabetical tie-breaking" do
      tied_configurations = {
        zebra: { score: 0.90, delta: 0.05, delta_pct: 5.88, label: "good" },
        apple: { score: 0.90, delta: 0.05, delta_pct: 5.88, label: "good" }
      }

      result = described_class.rank_field(tied_configurations)

      expect(result).to eq([:apple, :zebra])
    end
  end
end
