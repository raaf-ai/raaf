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
