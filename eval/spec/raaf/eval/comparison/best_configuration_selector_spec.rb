# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Eval::Comparison::BestConfigurationSelector do
  describe ".select" do
    context "when configurations have different improvement counts" do
      let(:improvements) do
        {
          config_a: [:output, :tokens],
          config_b: [:output],
          config_c: [:output, :tokens, :latency]
        }
      end

      let(:regressions) do
        {
          config_a: [:latency],
          config_b: [:tokens, :latency],
          config_c: []
        }
      end

      it "selects configuration with most improvements" do
        result = described_class.select(improvements, regressions)

        # config_c has 3 improvements
        expect(result).to eq(:config_c)
      end
    end

    context "when improvements are tied" do
      let(:improvements) do
        {
          config_a: [:output, :tokens],
          config_b: [:output, :tokens]
        }
      end

      let(:regressions) do
        {
          config_a: [:latency],
          config_b: []
        }
      end

      it "selects configuration with fewest regressions" do
        result = described_class.select(improvements, regressions)

        # Both have 2 improvements, but config_b has 0 regressions vs 1
        expect(result).to eq(:config_b)
      end
    end

    context "when both improvements and regressions are tied" do
      let(:improvements) do
        {
          zebra: [:output],
          apple: [:output]
        }
      end

      let(:regressions) do
        {
          zebra: [:tokens],
          apple: [:tokens]
        }
      end

      it "uses alphabetical order as tie-breaker" do
        result = described_class.select(improvements, regressions)

        # Same improvements (1), same regressions (1), alphabetical
        expect(result).to eq(:apple)
      end
    end

    context "when using net score logic" do
      let(:improvements) do
        {
          config_a: [:output, :tokens, :latency],
          config_b: [:output, :tokens],
          config_c: [:output]
        }
      end

      let(:regressions) do
        {
          config_a: [:accuracy],
          config_b: [],
          config_c: []
        }
      end

      it "calculates net score (improvements - regressions)" do
        result = described_class.select(improvements, regressions)

        # config_a: 3 - 1 = 2
        # config_b: 2 - 0 = 2
        # config_c: 1 - 0 = 1
        # Tied at 2, config_b wins with fewer regressions
        expect(result).to eq(:config_b)
      end
    end

    context "with single configuration" do
      let(:improvements) do
        {
          only_config: [:output]
        }
      end

      let(:regressions) do
        {
          only_config: []
        }
      end

      it "returns the only configuration" do
        result = described_class.select(improvements, regressions)

        expect(result).to eq(:only_config)
      end
    end

    context "with no improvements" do
      let(:improvements) do
        {
          config_a: [],
          config_b: []
        }
      end

      let(:regressions) do
        {
          config_a: [:output],
          config_b: [:output, :tokens]
        }
      end

      it "selects configuration with fewest regressions" do
        result = described_class.select(improvements, regressions)

        # Both have 0 improvements, config_a has 1 regression vs 2
        expect(result).to eq(:config_a)
      end
    end

    context "with all configurations having equal net scores" do
      let(:improvements) do
        {
          config_a: [:output],
          config_b: [:tokens],
          config_c: [:latency]
        }
      end

      let(:regressions) do
        {
          config_a: [],
          config_b: [],
          config_c: []
        }
      end

      it "uses alphabetical order" do
        result = described_class.select(improvements, regressions)

        # All have net score of 1, alphabetical
        expect(result).to eq(:config_a)
      end
    end

    context "with negative net scores" do
      let(:improvements) do
        {
          config_a: [:output],
          config_b: []
        }
      end

      let(:regressions) do
        {
          config_a: [:tokens, :latency],
          config_b: [:output, :tokens, :latency]
        }
      end

      it "selects configuration with least negative net score" do
        result = described_class.select(improvements, regressions)

        # config_a: 1 - 2 = -1
        # config_b: 0 - 3 = -3
        # config_a has better (less negative) net score
        expect(result).to eq(:config_a)
      end
    end
  end
end
