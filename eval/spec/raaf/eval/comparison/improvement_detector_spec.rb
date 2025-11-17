# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Eval::Comparison::ImprovementDetector do
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
      },
      latency: {
        baseline_score: 500,
        configurations: {
          medium_temp: { score: 480, delta: -20, delta_pct: -4.0, label: "good" },
          high_temp: { score: 450, delta: -50, delta_pct: -10.0, label: "good" },
          low_temp: { score: 520, delta: 20, delta_pct: 4.0, label: "good" }
        }
      }
    }
  end

  describe ".detect_improvements" do
    it "detects fields with positive deltas" do
      result = described_class.detect_improvements(field_deltas)

      # medium_temp improved on output (+0.03) and tokens (+50)
      expect(result[:medium_temp]).to contain_exactly(:output, :tokens)

      # high_temp improved on latency (-50, negative is improvement for latency)
      # Wait, negative delta means score went down, not necessarily improvement
      # The spec says delta > 0 means improvement
      expect(result[:high_temp]).to eq([])

      # low_temp improved on output (+0.01) and latency (+20)
      expect(result[:low_temp]).to contain_exactly(:output, :latency)
    end

    it "returns hash with configuration names as keys" do
      result = described_class.detect_improvements(field_deltas)

      expect(result).to be_a(Hash)
      expect(result.keys).to all(be_a(Symbol))
    end

    it "returns arrays of field names as values" do
      result = described_class.detect_improvements(field_deltas)

      result.each_value do |fields|
        expect(fields).to be_an(Array)
        fields.each { |field| expect(field).to be_a(Symbol) }
      end
    end

    it "excludes configurations with no improvements" do
      result = described_class.detect_improvements(field_deltas)

      # high_temp has no positive deltas (all negative or zero)
      expect(result[:high_temp]).to eq([])
    end

    it "handles zero deltas as no improvement" do
      result = described_class.detect_improvements(field_deltas)

      # low_temp has 0 delta on tokens, should not be included
      expect(result[:low_temp]).not_to include(:tokens)
    end

    it "detects improvements across multiple fields" do
      result = described_class.detect_improvements(field_deltas)

      # medium_temp improved on 2 fields
      expect(result[:medium_temp].size).to eq(2)
    end
  end

  describe ".detect_regressions" do
    it "detects fields with negative deltas" do
      result = described_class.detect_regressions(field_deltas)

      # medium_temp regressed on latency (-20)
      expect(result[:medium_temp]).to contain_exactly(:latency)

      # high_temp regressed on output (-0.03), tokens (-50), latency (-50)
      expect(result[:high_temp]).to contain_exactly(:output, :tokens, :latency)

      # low_temp has no regressions
      expect(result[:low_temp]).to eq([])
    end

    it "returns hash with configuration names as keys" do
      result = described_class.detect_regressions(field_deltas)

      expect(result).to be_a(Hash)
      expect(result.keys).to all(be_a(Symbol))
    end

    it "returns arrays of field names as values" do
      result = described_class.detect_regressions(field_deltas)

      result.each_value do |fields|
        expect(fields).to be_an(Array)
        fields.each { |field| expect(field).to be_a(Symbol) }
      end
    end

    it "excludes configurations with no regressions" do
      result = described_class.detect_regressions(field_deltas)

      # low_temp has no negative deltas
      expect(result[:low_temp]).to eq([])
    end

    it "handles zero deltas as no regression" do
      result = described_class.detect_regressions(field_deltas)

      # low_temp has 0 delta on tokens, should not be included
      expect(result[:low_temp]).not_to include(:tokens)
    end

    it "detects regressions across multiple fields" do
      result = described_class.detect_regressions(field_deltas)

      # high_temp regressed on 3 fields
      expect(result[:high_temp].size).to eq(3)
    end
  end

  describe "improvement and regression interaction" do
    it "correctly categorizes mixed results" do
      improvements = described_class.detect_improvements(field_deltas)
      regressions = described_class.detect_regressions(field_deltas)

      # medium_temp: 2 improvements, 1 regression
      expect(improvements[:medium_temp].size).to eq(2)
      expect(regressions[:medium_temp].size).to eq(1)

      # high_temp: 0 improvements, 3 regressions
      expect(improvements[:high_temp].size).to eq(0)
      expect(regressions[:high_temp].size).to eq(3)

      # low_temp: 2 improvements, 0 regressions
      expect(improvements[:low_temp].size).to eq(2)
      expect(regressions[:low_temp].size).to eq(0)
    end

    it "ensures no overlap between improvements and regressions" do
      improvements = described_class.detect_improvements(field_deltas)
      regressions = described_class.detect_regressions(field_deltas)

      # No field should appear in both improvements and regressions for same config
      improvements.each do |config_name, improved_fields|
        regressed_fields = regressions[config_name] || []
        overlap = improved_fields & regressed_fields
        expect(overlap).to be_empty, "Config #{config_name} has fields in both improvements and regressions: #{overlap}"
      end
    end
  end
end
