# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../../lib/raaf/eval/rspec/matchers/g_eval_matchers"

RSpec.describe "G-Eval RSpec Matchers" do
  # Mock G-Eval result for testing
  # Weighted average: (0.95*2.0 + 0.80*1.0 + 0.75*1.0) / (2.0 + 1.0 + 1.0) = 3.45 / 4.0 = 0.8625
  let(:g_eval_result) do
    {
      label: "good",
      score: 0.8625,
      message: "[GOOD] GEval: 86%",
      details: {
        evaluated_field: :output,
        method: "g_eval",
        criteria_count: 3,
        chain_of_thought: "Evaluation Summary:\nAnalyzed output: 'Paris is the capital of France.'\n\nCriterion 1 (Output is factually accurate): Score 95% - The output strongly satisfies the criterion 'Output is factually accurate'. It demonstrates clear alignment with the evaluation standard.\n\nOverall Assessment: The output performs well across most criteria.",
        criteria_evaluation: [
          {
            criterion: :accuracy,
            description: "Output is factually accurate",
            weight: 2.0,
            score: 0.95,
            reasoning: "The output strongly satisfies the criterion 'Output is factually accurate'."
          },
          {
            criterion: :grammar,
            description: "Output is grammatically correct",
            weight: 1.0,
            score: 0.80,
            reasoning: "The output adequately meets the criterion 'Output is grammatically correct'."
          },
          {
            criterion: :clarity,
            description: "Output is clear and concise",
            weight: 1.0,
            score: 0.75,
            reasoning: "The output adequately meets the criterion 'Output is clear and concise'."
          }
        ],
        thresholds: {
          good: 0.80,
          average: 0.60,
          used: "good (≥0.8)"
        }
      }
    }
  end

  describe "meet_all_criteria matcher" do
    it "passes when all criteria meet minimum score" do
      expect(g_eval_result).to meet_all_criteria(min_score: 0.70)
    end

    it "fails when any criterion is below minimum score" do
      expect(g_eval_result).not_to meet_all_criteria(min_score: 0.90)
    end

    it "provides detailed failure message" do
      expect {
        expect(g_eval_result).to meet_all_criteria(min_score: 0.90)
      }.to raise_error(::RSpec::Expectations::ExpectationNotMetError, /clarity.*75% < 90%/)
    end
  end

  describe "meet_criterion matcher" do
    it "passes when specific criterion meets minimum score by name" do
      expect(g_eval_result).to meet_criterion(:accuracy, min_score: 0.90)
    end

    it "passes when specific criterion meets minimum score by index" do
      expect(g_eval_result).to meet_criterion(0, min_score: 0.90)
    end

    it "fails when criterion is below minimum score" do
      expect(g_eval_result).not_to meet_criterion(:clarity, min_score: 0.80)
    end

    it "fails when criterion is not found" do
      expect(g_eval_result).not_to meet_criterion(:nonexistent, min_score: 0.70)
    end

    it "provides detailed failure message for low score" do
      expect {
        expect(g_eval_result).to meet_criterion(:clarity, min_score: 0.80)
      }.to raise_error(::RSpec::Expectations::ExpectationNotMetError, /clarity.*got 75%/)
    end

    it "provides detailed failure message for missing criterion" do
      expect {
        expect(g_eval_result).to meet_criterion(:nonexistent, min_score: 0.70)
      }.to raise_error(::RSpec::Expectations::ExpectationNotMetError, /not found/)
    end
  end

  describe "have_chain_of_thought matcher" do
    it "passes when chain_of_thought exists and meets minimum length" do
      expect(g_eval_result).to have_chain_of_thought(min_length: 50)
    end

    it "fails when chain_of_thought is too short" do
      expect(g_eval_result).not_to have_chain_of_thought(min_length: 1000)
    end

    it "fails when chain_of_thought is missing" do
      result_without_chain = g_eval_result.dup
      result_without_chain[:details] = result_without_chain[:details].dup
      result_without_chain[:details].delete(:chain_of_thought)

      expect(result_without_chain).not_to have_chain_of_thought
    end

    it "fails when chain_of_thought is empty" do
      result_with_empty_chain = g_eval_result.dup
      result_with_empty_chain[:details] = result_with_empty_chain[:details].dup
      result_with_empty_chain[:details][:chain_of_thought] = ""

      expect(result_with_empty_chain).not_to have_chain_of_thought
    end

    it "provides detailed failure message for short chain" do
      expect {
        expect(g_eval_result).to have_chain_of_thought(min_length: 1000)
      }.to raise_error(::RSpec::Expectations::ExpectationNotMetError, /at least 1000 characters/)
    end
  end

  describe "respect_criteria_weights matcher" do
    it "passes when overall score matches weighted average" do
      expect(g_eval_result).to respect_criteria_weights
    end

    it "fails when overall score doesn't match weighted average" do
      result_with_wrong_score = g_eval_result.dup
      result_with_wrong_score[:score] = 0.50

      expect(result_with_wrong_score).not_to respect_criteria_weights
    end

    it "provides detailed failure message with expected vs actual scores" do
      result_with_wrong_score = g_eval_result.dup
      result_with_wrong_score[:score] = 0.50

      expect {
        expect(result_with_wrong_score).to respect_criteria_weights
      }.to raise_error(::RSpec::Expectations::ExpectationNotMetError, /weighted average/)
    end
  end

  describe "evaluate_criteria_count matcher" do
    it "passes when criteria count matches expectation" do
      expect(g_eval_result).to evaluate_criteria_count(3)
    end

    it "fails when criteria count doesn't match" do
      expect(g_eval_result).not_to evaluate_criteria_count(5)
    end

    it "provides detailed failure message" do
      expect {
        expect(g_eval_result).to evaluate_criteria_count(5)
      }.to raise_error(::RSpec::Expectations::ExpectationNotMetError, /Expected 5 criteria.*but got 3/)
    end
  end

  describe "be_valid_g_eval_result matcher" do
    it "passes when result has complete G-Eval structure" do
      expect(g_eval_result).to be_valid_g_eval_result
    end

    it "fails when label is missing" do
      invalid_result = g_eval_result.dup
      invalid_result.delete(:label)

      expect(invalid_result).not_to be_valid_g_eval_result
    end

    it "fails when details are missing" do
      invalid_result = g_eval_result.dup
      invalid_result.delete(:details)

      expect(invalid_result).not_to be_valid_g_eval_result
    end

    it "fails when method is not 'g_eval'" do
      invalid_result = g_eval_result.dup
      invalid_result[:details] = invalid_result[:details].dup
      invalid_result[:details][:method] = "other"

      expect(invalid_result).not_to be_valid_g_eval_result
    end

    it "fails when chain_of_thought is missing" do
      invalid_result = g_eval_result.dup
      invalid_result[:details] = invalid_result[:details].dup
      invalid_result[:details].delete(:chain_of_thought)

      expect(invalid_result).not_to be_valid_g_eval_result
    end

    it "fails when criteria_evaluation is not an array" do
      invalid_result = g_eval_result.dup
      invalid_result[:details] = invalid_result[:details].dup
      invalid_result[:details][:criteria_evaluation] = "not an array"

      expect(invalid_result).not_to be_valid_g_eval_result
    end

    it "fails when criterion structure is invalid" do
      invalid_result = g_eval_result.dup
      invalid_result[:details] = invalid_result[:details].dup
      invalid_result[:details][:criteria_evaluation] = [
        { criterion: :test, score: "not a number" }
      ]

      expect(invalid_result).not_to be_valid_g_eval_result
    end

    it "provides detailed failure message listing all issues" do
      invalid_result = {
        label: nil,
        score: 0.85,
        message: "test",
        details: {
          evaluated_field: :output,
          method: "wrong",
          criteria_count: 1,
          chain_of_thought: nil,
          criteria_evaluation: "not an array"
        }
      }

      expect {
        expect(invalid_result).to be_valid_g_eval_result
      }.to raise_error(::RSpec::Expectations::ExpectationNotMetError, /Missing label/)
    end
  end

  describe "integration with other matchers" do
    it "can be combined with standard label matchers" do
      expect(g_eval_result).to be_valid_g_eval_result
      expect(g_eval_result[:label]).to eq("good")
    end

    it "can be combined with meet_quality_threshold matcher" do
      expect(g_eval_result).to be_valid_g_eval_result
      expect(g_eval_result).to meet_quality_threshold(0.80)
    end

    it "supports chaining multiple G-Eval specific matchers" do
      expect(g_eval_result).to be_valid_g_eval_result
        .and meet_all_criteria(min_score: 0.70)
        .and have_chain_of_thought
        .and respect_criteria_weights
        .and evaluate_criteria_count(3)
    end
  end
end
