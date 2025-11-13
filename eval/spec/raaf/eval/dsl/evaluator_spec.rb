# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Eval::DSL::Evaluator do
  # Test class implementing evaluator interface
  class TestEvaluator
    include RAAF::Eval::DSL::Evaluator

    evaluator_name :test_evaluator

    def evaluate(field_context, **options)
      threshold = options[:threshold] || 0.5
      value = field_context.value.to_f if field_context.value.respond_to?(:to_f)

      {
        passed: value && value > threshold,
        score: value ? [value, 1.0].min : 0.0,
        details: { threshold: threshold, actual: value },
        message: "Test evaluator: #{value > threshold ? 'PASS' : 'FAIL'}"
      }
    end
  end

  describe "evaluator interface" do
    let(:evaluator) { TestEvaluator.new }
    let(:result) { { output: "test output", tokens: 100 } }
    let(:field_context) { RAAF::Eval::DSL::FieldContext.new(:tokens, result) }

    it "requires evaluator_name class method" do
      expect(TestEvaluator).to respond_to(:evaluator_name)
      expect(TestEvaluator.evaluator_name).to eq(:test_evaluator)
    end

    it "requires evaluate instance method with correct signature" do
      expect(evaluator).to respond_to(:evaluate)
      expect(evaluator.method(:evaluate).arity).to eq(-2) # field_context + keyword args
    end

    it "returns result with required structure" do
      result = evaluator.evaluate(field_context, threshold: 50)

      expect(result).to be_a(Hash)
      expect(result).to include(:passed, :score, :details, :message)
      expect(result[:passed]).to be_in([true, false])
      expect(result[:score]).to be_a(Numeric).and be_between(0.0, 1.0)
    end

    it "passes parameters through options hash" do
      custom_threshold = 75
      result = evaluator.evaluate(field_context, threshold: custom_threshold)

      expect(result[:details][:threshold]).to eq(custom_threshold)
    end

    it "validates result structure on evaluation" do
      # Invalid evaluator that returns incomplete result
      invalid_evaluator = Class.new do
        include RAAF::Eval::DSL::Evaluator
        evaluator_name :invalid
        def evaluate(field_context, **options)
          { passed: true } # Missing required fields
        end
      end.new

      expect {
        result = invalid_evaluator.evaluate(field_context)
        invalid_evaluator.validate_result!(result)
      }.to raise_error(RAAF::Eval::DSL::InvalidEvaluatorResultError)
    end

    it "provides access to field context in evaluate method" do
      result_with_baseline = {
        tokens: 100,
        baseline_tokens: 80,
        output: "test"
      }
      context = RAAF::Eval::DSL::FieldContext.new(:tokens, result_with_baseline)

      eval_result = evaluator.evaluate(context)

      # Evaluator should have access to field value and baseline
      expect(context.value).to eq(100)
      expect(context.baseline_value).to eq(80)
      expect(context.delta).to eq(20)
    end
  end
end