# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/raaf/eval/evaluators/performance/token_efficiency"
require_relative "../../../../lib/raaf/eval/evaluators/performance/latency"
require_relative "../../../../lib/raaf/eval/evaluators/performance/throughput"

RSpec.describe "Performance Evaluators" do
  let(:result) { {} }
  let(:field_context) { RAAF::Eval::DSL::FieldContext.new(field_name, result) }

  describe RAAF::Eval::Evaluators::Performance::TokenEfficiency do
    let(:evaluator) { described_class.new }
    let(:field_name) { :tokens }

    context "with baseline comparison" do
      let(:result) { { tokens: 110, baseline_tokens: 100 } }

      it "returns label 'good' when under threshold" do
        result = evaluator.evaluate(field_context, max_increase_pct: 15)
        
        expect(result[:label]).to eq("good")
        expect(result[:score]).to be > 0.5
        expect(result[:details][:percentage_change]).to eq(10.0)
        expect(result[:message]).to include("10.0%")
      end

      it "returns label 'bad' when over threshold" do
        result = evaluator.evaluate(field_context, max_increase_pct: 5)
        
        expect(result[:label]).to eq("bad")
        expect(result[:score]).to be < 1.0
      end
    end

    context "without baseline" do
      let(:result) { { tokens: 100 } }

      it "returns passing result with no baseline" do
        result = evaluator.evaluate(field_context)
        
        expect(result[:label]).to eq("good")
        expect(result[:score]).to eq(1.0)
        expect(result[:message]).to include("No baseline")
      end
    end
  end

  describe RAAF::Eval::Evaluators::Performance::Latency do
    let(:evaluator) { described_class.new }
    let(:field_name) { :latency_ms }

    context "with valid latency" do
      let(:result) { { latency_ms: 1500 } }

      it "returns label 'good' when under threshold" do
        result = evaluator.evaluate(field_context, max_ms: 2000)
        
        expect(result[:label]).to eq("good")
        expect(result[:score]).to be > 0.5
        expect(result[:message]).to include("1500ms")
      end

      it "returns label 'bad' when over threshold" do
        result = evaluator.evaluate(field_context, max_ms: 1000)
        
        expect(result[:label]).to eq("bad")
        expect(result[:score]).to be < 1.0
      end
    end

    context "with invalid latency" do
      let(:result) { { latency_ms: -100 } }

      it "fails with invalid value" do
        result = evaluator.evaluate(field_context)
        
        expect(result[:label]).to eq("bad")
        expect(result[:score]).to eq(0.0)
        expect(result[:message]).to include("Invalid")
      end
    end
  end

  describe RAAF::Eval::Evaluators::Performance::Throughput do
    let(:evaluator) { described_class.new }
    let(:field_name) { :tokens_per_second }

    context "with valid throughput" do
      let(:result) { { tokens_per_second: 15.5 } }

      it "returns label 'good' when above minimum" do
        result = evaluator.evaluate(field_context, min_tps: 10)
        
        expect(result[:label]).to eq("good")
        expect(result[:score]).to be > 0.7
        expect(result[:message]).to include("15.5")
      end

      it "returns label 'bad' when below minimum" do
        result = evaluator.evaluate(field_context, min_tps: 20)
        
        expect(result[:label]).to eq("bad")
        expect(result[:score]).to be < 1.0
      end
    end

    context "with zero throughput" do
      let(:result) { { tokens_per_second: 0 } }

      it "fails with zero value" do
        result = evaluator.evaluate(field_context)
        
        expect(result[:label]).to eq("bad")
        expect(result[:score]).to eq(0.0)
      end
    end
  end
end
