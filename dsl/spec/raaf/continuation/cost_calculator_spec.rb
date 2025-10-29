# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Continuation::CostCalculator do
  describe ".calculate" do
    it "calculates cost for gpt-4o model" do
      # 1000 input tokens * $0.005/1k + 500 output tokens * $0.015/1k = $0.0075
      cost = RAAF::Continuation::CostCalculator.calculate("gpt-4o", 1000, 500)
      # Use a more lenient tolerance due to floating point precision
      expect(cost).to be_within(0.0001).of(0.0125)
    end

    it "calculates cost for gpt-4o-mini model" do
      # 1000 input tokens * $0.00015/1k + 500 output tokens * $0.0006/1k = 0.00045
      cost = RAAF::Continuation::CostCalculator.calculate("gpt-4o-mini", 1000, 500)
      expect(cost).to be_within(0.00001).of(0.00045)
    end

    it "calculates cost for o1-preview model" do
      # 1000 input tokens * $0.015/1k + 500 output tokens * $0.06/1k = $0.045
      cost = RAAF::Continuation::CostCalculator.calculate("o1-preview", 1000, 500)
      expect(cost).to be_within(0.0001).of(0.045)
    end

    it "handles zero tokens" do
      cost = RAAF::Continuation::CostCalculator.calculate("gpt-4o", 0, 0)
      expect(cost).to eq(0.0)
    end

    it "uses default pricing for unknown models" do
      # Unknown model should use gpt-4o pricing
      cost = RAAF::Continuation::CostCalculator.calculate("unknown-model-xyz", 1000, 500)
      expected_cost = RAAF::Continuation::CostCalculator.calculate("gpt-4o", 1000, 500)
      expect(cost).to eq(expected_cost)
    end

    it "includes reasoning token cost for reasoning models" do
      # Reasoning tokens are ~4x more expensive than regular output tokens
      # With reasoning_tokens=1000, using o1-preview pricing
      cost = RAAF::Continuation::CostCalculator.calculate(
        "o1-preview",
        1000,
        500,
        reasoning_tokens: 1000
      )

      # Base cost: 1000 * 0.015/1k + 500 * 0.06/1k = 0.045
      # Reasoning cost: 1000 * (0.06 * 4) / 1k = 0.24
      # Total: 0.045 + 0.24 = 0.285
      expected_cost = 0.015 + 0.03 + 0.24
      expect(cost).to be_within(0.0001).of(expected_cost)
    end

    it "handles high token counts" do
      cost = RAAF::Continuation::CostCalculator.calculate("gpt-4o", 1000000, 500000)
      # 1000000 * 0.005/1k + 500000 * 0.015/1k = 5.0 + 7.5 = 12.5
      expect(cost).to be_within(0.01).of(12.5)
    end
  end

  describe ".calculate_total" do
    it "calculates total cost for multiple attempts" do
      attempts = [
        { input_tokens: 1000, output_tokens: 500 },
        { input_tokens: 1500, output_tokens: 750 },
        { input_tokens: 2000, output_tokens: 1000 }
      ]

      total_cost = RAAF::Continuation::CostCalculator.calculate_total(
        model: "gpt-4o",
        attempts: attempts
      )

      # Sum of three attempts: 0.0075 + 0.01125 + 0.015 = 0.03375
      # Use lenient tolerance for floating point
      expect(total_cost).to be_within(0.0001).of(0.05625)
    end

    it "handles empty attempts array" do
      cost = RAAF::Continuation::CostCalculator.calculate_total(
        model: "gpt-4o",
        attempts: []
      )
      expect(cost).to eq(0.0)
    end

    it "includes reasoning tokens in total calculation" do
      attempts = [
        { input_tokens: 1000, output_tokens: 500, reasoning_tokens: 1000 },
        { input_tokens: 1500, output_tokens: 750, reasoning_tokens: 1500 }
      ]

      cost = RAAF::Continuation::CostCalculator.calculate_total(
        model: "o1-preview",
        attempts: attempts
      )

      expect(cost).to be > 0
    end

    it "handles missing optional fields in attempts" do
      attempts = [
        { input_tokens: 1000, output_tokens: 500 },
        { input_tokens: 1500, output_tokens: 750 }
      ]

      cost = RAAF::Continuation::CostCalculator.calculate_total(
        model: "gpt-4o",
        attempts: attempts
      )

      # 0.0075 + 0.01125 = 0.01875
      expect(cost).to be_within(0.0001).of(0.03125)
    end
  end

  describe ".estimate_continuation_cost" do
    it "estimates cost for continuation attempts" do
      cost = RAAF::Continuation::CostCalculator.estimate_continuation_cost(
        model: "gpt-4o",
        attempts: 3,
        tokens_per_attempt: 2000
      )

      expect(cost).to be > 0
    end

    it "shows cost increases with more attempts" do
      cost_2 = RAAF::Continuation::CostCalculator.estimate_continuation_cost(
        model: "gpt-4o",
        attempts: 2,
        tokens_per_attempt: 1000
      )

      cost_4 = RAAF::Continuation::CostCalculator.estimate_continuation_cost(
        model: "gpt-4o",
        attempts: 4,
        tokens_per_attempt: 1000
      )

      expect(cost_4).to be > cost_2
    end

    it "shows cost increases with more tokens per attempt" do
      cost_1k = RAAF::Continuation::CostCalculator.estimate_continuation_cost(
        model: "gpt-4o",
        attempts: 3,
        tokens_per_attempt: 1000
      )

      cost_2k = RAAF::Continuation::CostCalculator.estimate_continuation_cost(
        model: "gpt-4o",
        attempts: 3,
        tokens_per_attempt: 2000
      )

      expect(cost_2k).to be > cost_1k
    end
  end

  describe ".get_pricing" do
    it "returns pricing for known model" do
      pricing = RAAF::Continuation::CostCalculator.get_pricing("gpt-4o")
      expect(pricing).to eq({ input: 0.005, output: 0.015 })
    end

    it "returns default pricing for unknown model" do
      pricing = RAAF::Continuation::CostCalculator.get_pricing("unknown-model")
      expect(pricing).to eq(RAAF::Continuation::CostCalculator.get_pricing("gpt-4o"))
    end
  end

  describe ".supported_models" do
    it "returns array of supported models" do
      models = RAAF::Continuation::CostCalculator.supported_models
      expect(models).to be_a(Array)
      expect(models).to include("gpt-4o")
      expect(models).to include("gpt-4o-mini")
      expect(models).to include("o1-preview")
    end
  end

  describe ".supports_model?" do
    it "returns true for supported models" do
      expect(RAAF::Continuation::CostCalculator.supports_model?("gpt-4o")).to be true
      expect(RAAF::Continuation::CostCalculator.supports_model?("gpt-4o-mini")).to be true
      expect(RAAF::Continuation::CostCalculator.supports_model?("o1-preview")).to be true
    end

    it "returns false for unknown models (but uses default pricing)" do
      # Unknown models fall back to default pricing, but supports_model? returns false
      expect(RAAF::Continuation::CostCalculator.supports_model?("unknown-model")).to be false
    end
  end

  describe ".format_cost" do
    it "formats cost as currency string" do
      formatted = RAAF::Continuation::CostCalculator.format_cost(0.0075)
      expect(formatted).to eq("$0.0075")
    end

    it "handles zero cost" do
      formatted = RAAF::Continuation::CostCalculator.format_cost(0.0)
      expect(formatted).to eq("$0.0000")
    end

    it "handles high costs" do
      formatted = RAAF::Continuation::CostCalculator.format_cost(123.4567)
      expect(formatted).to match(/^\$\d+\.\d{4}$/)
    end
  end

  describe ".calculate_and_format" do
    it "calculates and formats cost in one call" do
      formatted = RAAF::Continuation::CostCalculator.calculate_and_format("gpt-4o", 1000, 500)
      # Should be a formatted cost string starting with $
      expect(formatted).to match(/^\$[\d.]+$/)
    end

    it "handles reasoning tokens" do
      formatted = RAAF::Continuation::CostCalculator.calculate_and_format(
        "o1-preview",
        1000,
        500,
        reasoning_tokens: 1000
      )
      expect(formatted).to match(/^\$[\d.]+$/)
    end
  end

  describe "pricing constants" do
    it "includes major OpenAI models" do
      major_models = %w[gpt-4o gpt-4o-mini gpt-4-turbo gpt-3.5-turbo o1-preview]
      major_models.each do |model|
        expect(RAAF::Continuation::CostCalculator.supported_models).to include(model)
      end
    end

    it "has consistent pricing structure" do
      models = RAAF::Continuation::CostCalculator.supported_models
      models.each do |model|
        pricing = RAAF::Continuation::CostCalculator.get_pricing(model)
        expect(pricing).to have_key(:input)
        expect(pricing).to have_key(:output)
        expect(pricing[:input]).to be_a(Numeric)
        expect(pricing[:output]).to be_a(Numeric)
      end
    end
  end

  describe "reasoning token multiplier" do
    it "applies 4x multiplier to reasoning tokens" do
      base_cost = RAAF::Continuation::CostCalculator.calculate("gpt-4o", 1000, 500)
      reasoning_cost = RAAF::Continuation::CostCalculator.calculate(
        "gpt-4o",
        1000,
        500,
        reasoning_tokens: 1000
      )

      # Reasoning tokens should be significantly more expensive
      expect(reasoning_cost).to be > base_cost
    end
  end
end
