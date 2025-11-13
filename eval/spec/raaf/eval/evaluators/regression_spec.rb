# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/raaf/eval/evaluators/regression/no_regression"
require_relative "../../../../lib/raaf/eval/evaluators/regression/token_regression"
require_relative "../../../../lib/raaf/eval/evaluators/regression/latency_regression"

RSpec.describe "Regression Evaluators" do
  let(:result) { {} }
  let(:field_context) { RAAF::Eval::DSL::FieldContext.new(field_name, result) }

  describe RAAF::Eval::Evaluators::Regression::NoRegression do
    let(:evaluator) { described_class.new }
    let(:field_name) { :score }

    context "with numeric values" do
      let(:result) { { score: 0.85, baseline_score: 0.80 } }

      it "passes when no regression" do
        result = evaluator.evaluate(field_context)
        
        expect(result[:passed]).to be true
        expect(result[:score]).to eq(1.0)
        expect(result[:message]).to include("No regression")
      end

      it "fails when regression detected" do
        result_with_regression = { score: 0.75, baseline_score: 0.80 }
        context_with_regression = RAAF::Eval::DSL::FieldContext.new(:score, result_with_regression)
        
        result = evaluator.evaluate(context_with_regression)
        
        expect(result[:passed]).to be false
        expect(result[:score]).to be < 1.0
        expect(result[:message]).to include("Regression detected")
      end
    end

    context "without baseline" do
      let(:result) { { score: 0.85 } }

      it "passes with no baseline" do
        result = evaluator.evaluate(field_context)
        
        expect(result[:passed]).to be true
        expect(result[:score]).to eq(1.0)
        expect(result[:message]).to include("No baseline")
      end
    end
  end

  describe RAAF::Eval::Evaluators::Regression::TokenRegression do
    let(:evaluator) { described_class.new }
    let(:field_name) { :tokens }

    context "with token increase" do
      let(:result) { { tokens: 105, baseline_tokens: 100 } }

      it "passes when under threshold" do
        result = evaluator.evaluate(field_context, max_pct: 10)
        
        expect(result[:passed]).to be true
        expect(result[:score]).to be > 0.5
        expect(result[:details][:increase_pct]).to eq(5.0)
      end

      it "fails when over threshold" do
        result_high = { tokens: 120, baseline_tokens: 100 }
        context_high = RAAF::Eval::DSL::FieldContext.new(:tokens, result_high)
        
        result = evaluator.evaluate(context_high, max_pct: 10)
        
        expect(result[:passed]).to be false
        expect(result[:score]).to be < 1.0
      end
    end

    context "with token decrease" do
      let(:result) { { tokens: 90, baseline_tokens: 100 } }

      it "passes with improvement" do
        result = evaluator.evaluate(field_context)
        
        expect(result[:passed]).to be true
        expect(result[:score]).to eq(1.0)
      end
    end
  end

  describe RAAF::Eval::Evaluators::Regression::LatencyRegression do
    let(:evaluator) { described_class.new }
    let(:field_name) { :latency_ms }

    context "with latency increase" do
      let(:result) { { latency_ms: 1100, baseline_latency_ms: 1000 } }

      it "passes when under threshold" do
        result = evaluator.evaluate(field_context, max_ms: 200)
        
        expect(result[:passed]).to be true
        expect(result[:score]).to be > 0.5
        expect(result[:details][:increase_ms]).to eq(100)
      end

      it "fails when over threshold" do
        result_high = { latency_ms: 1500, baseline_latency_ms: 1000 }
        context_high = RAAF::Eval::DSL::FieldContext.new(:latency_ms, result_high)
        
        result = evaluator.evaluate(context_high, max_ms: 200)
        
        expect(result[:passed]).to be false
        expect(result[:score]).to be < 1.0
      end
    end

    context "without baseline" do
      let(:result) { { latency_ms: 1000 } }

      it "passes with no baseline" do
        result = evaluator.evaluate(field_context)
        
        expect(result[:passed]).to be true
        expect(result[:score]).to eq(1.0)
      end
    end
  end
end
