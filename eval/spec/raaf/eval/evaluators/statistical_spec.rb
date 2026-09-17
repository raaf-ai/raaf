# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/raaf/eval/evaluators/statistical/consistency"
require_relative "../../../../lib/raaf/eval/evaluators/statistical/statistical_significance"
require_relative "../../../../lib/raaf/eval/evaluators/statistical/effect_size"

RSpec.describe "Statistical Evaluators" do
  let(:result) { {} }
  let(:field_context) { RAAF::Eval::DSL::FieldContext.new(:data, result) }

  describe RAAF::Eval::Evaluators::Statistical::Consistency do
    let(:evaluator) { described_class.new }

    context "with consistent values" do
      let(:result) { { data: [10, 11, 10, 11, 10] } }

      it "passes with low variation" do
        result = evaluator.evaluate(field_context, std_dev: 0.1)

        expect(result[:label]).to eq("good")
        expect(result[:score]).to be > 0.5
        expect(result[:details][:coefficient_of_variation]).to be < 0.1
      end
    end

    context "with inconsistent values" do
      let(:result) { { data: [5, 10, 20, 3, 25] } }

      it "fails with high variation" do
        result = evaluator.evaluate(field_context, std_dev: 0.1)

        expect(result[:label]).to eq("bad")
        expect(result[:score]).to be < 1.0
      end
    end

    context "with a tolerance on a coarse scale" do
      let(:result) { { data: [1, 1, 2] } }

      it "accepts a one-point wobble that the coefficient of variation rejects" do
        by_cv = evaluator.evaluate(field_context, std_dev: 0.1)
        by_spread = evaluator.evaluate(field_context, tolerance: 1)

        expect(by_cv[:label]).to eq("bad")
        expect(by_spread[:label]).to eq("good")
        expect(by_spread[:score]).to eq(1.0)
        expect(by_spread[:details]).to include(spread: 1, tolerance: 1)
        expect(by_spread[:message]).to eq("[GOOD] Consistency spread: 1 (tolerance: 1)")
      end
    end

    context "with a tolerance and a spread past it" do
      let(:result) { { data: [45, 10, 15] } }

      it "still fails a real disagreement" do
        result = evaluator.evaluate(field_context, tolerance: 10)

        expect(result[:label]).to eq("bad")
        expect(result[:score]).to eq(0.0)
        expect(result[:details][:spread]).to eq(35)
      end
    end

    context "with a tolerance and a spread between one and three times it" do
      let(:result) { { data: [7, 5, 7] } }

      it "scores linearly down from the tolerance" do
        result = evaluator.evaluate(field_context, tolerance: 1)

        expect(result[:score]).to eq(0.5)
        expect(result[:label]).to eq("bad")
      end
    end

    context "with runs keyed by item, listed in a different order each run" do
      # The same three events, reordered: read positionally the first item
      # would compare 7, 2 and 5, which are three different events.
      let(:result) do
        { data: [ { "e1" => 7, "e2" => 2, "e3" => 5 },
                  { "e2" => 2, "e3" => 5, "e1" => 7 },
                  { "e3" => 5, "e1" => 8, "e2" => 2 } ] }
      end

      it "compares each item with itself" do
        result = evaluator.evaluate(field_context, tolerance: 1)

        expect(result[:label]).to eq("good")
        expect(result[:score]).to eq(1.0)
        expect(result[:details]).to include(items_compared: 3, items_consistent: 3, worst_items: [])
        expect(result[:message]).to eq("[GOOD] 3 of 3 items consistent across 3 runs (tolerance: 1)")
      end
    end

    context "with one item that disagrees with itself" do
      let(:result) do
        { data: [ { "funding" => 100, "hiring" => 40 },
                  { "hiring" => 40, "funding" => 55 },
                  { "funding" => 55, "hiring" => 45 } ] }
      end

      it "scores the mean of the items and names the worst" do
        result = evaluator.evaluate(field_context, tolerance: 10)

        expect(result[:score]).to eq(0.5)
        expect(result[:label]).to eq("bad")
        expect(result[:details][:worst_items])
          .to eq([ { key: "funding", values: [ 100, 55, 55 ], score: 0.0 } ])
        expect(result[:message]).to end_with("; worst funding [100, 55, 55]")
      end
    end

    context "with an item one run left out" do
      let(:result) { { data: [ { "e1" => 3, "e2" => 4 }, { "e1" => 3 } ] } }

      it "counts the omission as a different answer" do
        result = evaluator.evaluate(field_context, tolerance: 1)

        expect(result[:score]).to eq(0.5)
        expect(result[:details][:items_missing_from_a_run]).to eq(1)
        expect(described_class.format_result(result)).to include("| e2 | 4, missing | 0.0 |")
      end
    end

    context "with invalid input" do
      let(:result) { { data: "not an array" } }

      it "fails with invalid data" do
        result = evaluator.evaluate(field_context)

        expect(result[:label]).to eq("bad")
        expect(result[:score]).to eq(0.0)
        expect(result[:message]).to include("Invalid input")
      end
    end
  end

  describe RAAF::Eval::Evaluators::Statistical::StatisticalSignificance do
    let(:evaluator) { described_class.new }

    context "with p-value provided" do
      let(:result) { { data: { p_value: 0.03, sample_size: 100 } } }

      it "returns label 'good' when significant" do
        result = evaluator.evaluate(field_context, p_value: 0.05)

        expect(result[:label]).to eq("good")
        expect(result[:score]).to be > 0.5
        expect(result[:details][:p_value]).to eq(0.03)
      end

      it "returns label 'bad' when not significant" do
        result_high_p = { data: { p_value: 0.08, sample_size: 100 } }
        context_high_p = RAAF::Eval::DSL::FieldContext.new(:data, result_high_p)

        result = evaluator.evaluate(context_high_p, p_value: 0.05)

        expect(result[:label]).to eq("bad")
        expect(result[:score]).to be < 1.0
      end
    end

    context "with control and treatment groups" do
      let(:result) do
        {
          data: {
            control: [10, 11, 9, 10, 11],
            treatment: [15, 16, 14, 15, 16]
          }
        }
      end

      it "calculates p-value from groups" do
        result = evaluator.evaluate(field_context)

        expect(result[:details][:p_value]).not_to be_nil
      end
    end
  end

  describe RAAF::Eval::Evaluators::Statistical::EffectSize do
    let(:evaluator) { described_class.new }

    context "with cohen_d provided" do
      let(:result) { { data: { cohen_d: 0.8 } } }

      it "passes with large effect" do
        result = evaluator.evaluate(field_context, cohen_d: 0.5)

        expect(result[:label]).to eq("good")
        expect(result[:score]).to be > 0.5
        expect(result[:details][:effect_size_interpretation]).to eq("large")
      end

      it "fails with small effect" do
        result_small = { data: { cohen_d: 0.2 } }
        context_small = RAAF::Eval::DSL::FieldContext.new(:data, result_small)

        result = evaluator.evaluate(context_small, cohen_d: 0.5)

        expect(result[:label]).to eq("bad")
        expect(result[:details][:effect_size_interpretation]).to eq("small")
      end
    end

    context "with control and treatment groups" do
      let(:result) do
        {
          data: {
            control: [10, 11, 9, 10, 11],
            treatment: [15, 16, 14, 15, 16]
          }
        }
      end

      it "calculates Cohen's d from groups" do
        result = evaluator.evaluate(field_context)

        expect(result[:details][:cohen_d]).not_to be_nil
        expect(result[:details][:effect_size_interpretation]).not_to be_nil
      end
    end
  end
end
