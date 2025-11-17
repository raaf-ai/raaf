# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/raaf/eval/evaluators/llm/llm_judge"
require_relative "../../../../lib/raaf/eval/evaluators/llm/quality_score"
require_relative "../../../../lib/raaf/eval/evaluators/llm/rubric_evaluation"

RSpec.describe "LLM Evaluators" do
  let(:result) { {} }
  let(:field_context) { RAAF::Eval::DSL::FieldContext.new(:output, result) }

  describe RAAF::Eval::Evaluators::LLM::LlmJudge do
    let(:evaluator) { described_class.new }

    context "with valid criteria" do
      let(:result) { { output: "The capital of France is Paris. It is known for the Eiffel Tower." } }
      let(:criteria) { "accuracy, clarity, relevance" }

      it "evaluates against criteria" do
        result = evaluator.evaluate(field_context, criteria: criteria)
        
        expect(result).to have_key(:label)
        expect(result).to have_key(:score)
        expect(result[:details][:criteria]).to eq(criteria)
        expect(result[:details][:reasoning]).not_to be_empty
        expect(result[:details][:confidence]).to be > 0
      end
    end

    context "without criteria" do
      let(:result) { { output: "Some text" } }

      it "fails without criteria parameter" do
        result = evaluator.evaluate(field_context)
        
        expect(result[:label]).to eq("bad")
        expect(result[:score]).to eq(0.0)
        expect(result[:message]).to include("requires :criteria")
      end
    end

    context "with short response" do
      let(:result) { { output: "Yes" } }
      let(:criteria) { "clarity" }

      it "penalizes brevity" do
        result = evaluator.evaluate(field_context, criteria: criteria)
        
        expect(result[:score]).to be < 0.7
        expect(result[:details][:reasoning]).to include("brief")
      end
    end
  end

  describe RAAF::Eval::Evaluators::LLM::QualityScore do
    let(:evaluator) { described_class.new }

    context "with high-quality content" do
      let(:result) do 
        { 
          output: "The solution involves multiple steps. First, we analyze the problem. 
                   Second, we develop a strategy. Third, we implement the solution.
                   Finally, we verify the results. This approach ensures completeness." 
        }
      end

      it "passes quality threshold" do
        result = evaluator.evaluate(field_context, min_score: 0.6)
        
        expect(result[:label]).to eq("good")
        expect(result[:score]).to be > 0.6
        expect(result[:details][:dimensions]).to include(:accuracy, :completeness, :coherence)
      end

      it "identifies strengths" do
        result = evaluator.evaluate(field_context)
        
        expect(result[:details][:strengths]).not_to be_empty
      end
    end

    context "with low-quality content" do
      let(:result) { { output: "Maybe" } }

      it "fails quality threshold" do
        result = evaluator.evaluate(field_context, min_score: 0.7)
        
        expect(result[:label]).to eq("bad")
        expect(result[:score]).to be < 0.7
      end

      it "identifies weaknesses" do
        result = evaluator.evaluate(field_context)
        
        expect(result[:details][:weaknesses]).not_to be_empty
      end
    end

    context "with empty content" do
      let(:result) { { output: "" } }

      it "scores zero for empty content" do
        result = evaluator.evaluate(field_context)
        
        expect(result[:score]).to eq(0.0)
        expect(result[:label]).to eq("bad")
      end
    end
  end

  describe RAAF::Eval::Evaluators::LLM::RubricEvaluation do
    let(:evaluator) { described_class.new }

    context "with comprehensive rubric" do
      let(:result) { { output: "The analysis shows clear understanding with supporting evidence." } }
      let(:rubric) do
        {
          passing_score: 0.7,
          criteria: {
            clarity: {
              weight: 2.0,
              required_elements: ["clear", "understanding"]
            },
            evidence: {
              weight: 1.0,
              required_elements: ["evidence", "supporting"]
            }
          }
        }
      end

      it "evaluates against rubric criteria" do
        result = evaluator.evaluate(field_context, rubric: rubric)
        
        expect(result[:label]).to eq("good")
        expect(result[:score]).to be > 0.7
        expect(result[:details][:rubric_scores]).to have_key(:clarity)
        expect(result[:details][:rubric_scores]).to have_key(:evidence)
      end

      it "applies weights correctly" do
        result = evaluator.evaluate(field_context, rubric: rubric)
        
        expect(result[:details][:rubric_criteria]).to include(:clarity, :evidence)
      end
    end

    context "with failing rubric score" do
      let(:result) { { output: "Brief response" } }
      let(:rubric) do
        {
          passing_score: 0.8,
          criteria: {
            completeness: {
              required_elements: ["introduction", "body", "conclusion"]
            }
          }
        }
      end

      it "returns label 'bad' when below passing score" do
        result = evaluator.evaluate(field_context, rubric: rubric)
        
        expect(result[:label]).to eq("bad")
        expect(result[:score]).to be < 0.8
      end
    end

    context "without rubric" do
      let(:result) { { output: "Some text" } }

      it "fails without rubric parameter" do
        result = evaluator.evaluate(field_context)
        
        expect(result[:label]).to eq("bad")
        expect(result[:score]).to eq(0.0)
        expect(result[:message]).to include("requires :rubric")
      end
    end

    context "with levels-based rubric" do
      let(:result) { { output: "This is a comprehensive response with multiple paragraphs." * 10 } }
      let(:rubric) do
        {
          criteria: {
            depth: {
              levels: {
                excellent: 4,
                good: 3,
                adequate: 2,
                poor: 1
              }
            }
          }
        }
      end

      it "determines appropriate level" do
        result = evaluator.evaluate(field_context, rubric: rubric)
        
        expect(result[:details][:rubric_scores][:depth]).to be > 0.5
      end
    end
  end
end
