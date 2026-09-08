# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/raaf/eval/evaluators/llm/llm_judge"
require_relative "../../../../lib/raaf/eval/evaluators/llm/quality_score"
require_relative "../../../../lib/raaf/eval/evaluators/llm/rubric_evaluation"

RSpec.describe "LLM Evaluators" do
  let(:result) { {} }
  let(:field_context) { RAAF::Eval::DSL::FieldContext.new(:output, result) }

  # The judge is the one evaluator whose answer cannot be re-derived from the
  # payload and a rule, so what is asserted here is that a score exists only
  # because a model produced it — and that when no model could be reached, the
  # result says so rather than passing a heuristic off as a judgement.
  describe RAAF::Eval::Evaluators::LLM::LlmJudge do
    let(:evaluator) { described_class.new }
    let(:result) { { output: "The capital of France is Paris. It is known for the Eiffel Tower." } }
    let(:criteria) { "accuracy, clarity, relevance" }

    # Never a real call: without a stub this reaches OpenAI on any machine that
    # has the key in its environment.
    def judge_answers(scores)
      answer = { criteria: scores.map.with_index { |score, i| { criterion: "criterion_#{i + 1}", score: score } },
                 overall_chain_of_thought: "judged" }.to_json
      allow_any_instance_of(RAAF::Eval::Evaluators::LLM::GEval).to receive(:call_llm).and_return(answer)
    end

    it "scores from the judge's answer" do
      judge_answers([0.4])

      expect(evaluator.evaluate(field_context, criteria: criteria)[:score]).to be_within(0.001).of(0.4)
    end

    it "names the criteria it was asked to judge against" do
      judge_answers([1.0])

      expect(evaluator.evaluate(field_context, criteria: criteria)[:details][:criteria]).to eq(criteria)
    end

    it "explains itself in the judge's own words" do
      judge_answers([1.0])

      expect(evaluator.evaluate(field_context, criteria: criteria)[:details][:reasoning]).to eq("judged")
    end

    it "carries the judge's model and exchange, which is what the score can be checked against" do
      judge_answers([1.0])

      details = evaluator.evaluate(field_context, criteria: criteria)[:details]

      expect(details[:judge_model]).to be_a(String)
      expect(details[:judge_prompt]).to include("accuracy, clarity, relevance")
      expect(details[:judge_response]).to include("overall_chain_of_thought")
    end

    it "raises when the judge was not reached rather than scoring the field anyway" do
      allow_any_instance_of(RAAF::Eval::Evaluators::LLM::GEval).to receive(:call_llm).and_return(nil)

      expect { evaluator.evaluate(field_context, criteria: criteria) }
        .to raise_error(RAAF::Eval::JudgeUnavailableError, /could not be reached/)
    end

    it "raises when the judge answered something that cannot be read as criteria" do
      allow_any_instance_of(RAAF::Eval::Evaluators::LLM::GEval)
        .to receive(:call_llm).and_return("not json at all")

      expect { evaluator.evaluate(field_context, criteria: criteria) }
        .to raise_error(RAAF::Eval::JudgeUnavailableError, /could not be read/)
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

    context "with nothing to judge" do
      let(:result) { { output: nil } }

      it "scores an empty field without asking anybody" do
        expect_any_instance_of(RAAF::Eval::Evaluators::LLM::GEval).not_to receive(:call_llm)

        result = evaluator.evaluate(field_context, criteria: criteria)

        expect(result[:label]).to eq("bad")
        expect(result[:score]).to eq(0.0)
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
              required_elements: %w[clear understanding]
            },
            evidence: {
              weight: 1.0,
              required_elements: %w[evidence supporting]
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
              required_elements: %w[introduction body conclusion]
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
