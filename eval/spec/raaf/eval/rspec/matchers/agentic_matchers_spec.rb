# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../../lib/raaf/eval/rspec/matchers/agentic_matchers"

RSpec.describe "Agentic Matchers" do
  include RAAF::Eval::RSpec::Matchers::AgenticMatchers

  # Helper to create mock task completion evaluation results
  def mock_task_completion_result(score:, goal_achieved: true, task_description: "Complete the analysis")
    {
      label: score >= 0.85 ? "good" : (score >= 0.65 ? "average" : "bad"),
      score: score,
      message: "[#{score >= 0.85 ? 'GOOD' : (score >= 0.65 ? 'AVERAGE' : 'BAD')}] Task Completion: #{(score * 100).round}%",
      details: {
        evaluated_field: :output,
        method: "llm_judge",
        task_description: task_description,
        expected_output: "Comprehensive analysis with insights",
        actual_output: "Analysis complete with findings...",
        required_steps_provided: true,
        required_steps_count: 4,
        execution_trace_provided: false,
        completion_analysis: {
          goal_achieved: goal_achieved,
          output_quality: score >= 0.85 ? "high" : (score >= 0.65 ? "medium" : "low"),
          completeness: "#{(score * 100).round}% of expected elements present",
          steps_completed: "4/4 steps addressed",
          issues_found: goal_achieved ? [] : ["some expected elements missing"],
          reasoning: "Task completion evaluated based on output coverage"
        },
        completion_percentage: (score * 100).round,
        evaluation_note: "Task completed successfully"
      }
    }
  end

  # Helper to create mock tool correctness evaluation results
  def mock_tool_correctness_result(score:, appropriate_selection: true, task_context: "Search for information")
    {
      label: score >= 0.85 ? "good" : (score >= 0.65 ? "average" : "bad"),
      score: score,
      message: "[#{score >= 0.85 ? 'GOOD' : (score >= 0.65 ? 'AVERAGE' : 'BAD')}] Tool Correctness: #{(score * 100).round}%",
      details: {
        evaluated_field: :tools,
        method: "llm_judge",
        task_context: task_context,
        available_tools_count: 5,
        tools_used_count: 3,
        expected_tools_provided: true,
        tool_sequence_matters: false,
        tool_selection_analysis: appropriate_selection ? "appropriate tools from available set" : "some invalid tool selections",
        parameter_correctness_analysis: "parameters provided for all tools",
        sequence_analysis: "sequence not critical",
        output_handling_analysis: "all tools produced results",
        overall_reasoning: "Tool usage evaluated based on selection appropriateness",
        correctness_percentage: (score * 100).round,
        evaluation_note: "Tools used correctly",
        issues_found: appropriate_selection ? [] : ["invalid tool selection"]
      }
    }
  end

  describe "have_high_task_completion" do
    context "when task completion score meets threshold" do
      it "passes with default threshold (0.85)" do
        result = mock_task_completion_result(score: 0.90)
        expect(result).to have_high_task_completion
      end

      it "passes with custom threshold" do
        result = mock_task_completion_result(score: 0.75)
        expect(result).to have_high_task_completion(min_score: 0.70)
      end

      it "passes with score exactly at threshold" do
        result = mock_task_completion_result(score: 0.85)
        expect(result).to have_high_task_completion(min_score: 0.85)
      end
    end

    context "when task completion score below threshold" do
      it "fails with default threshold" do
        result = mock_task_completion_result(score: 0.60)
        expect(result).not_to have_high_task_completion
      end

      it "fails with custom threshold" do
        result = mock_task_completion_result(score: 0.70)
        expect(result).not_to have_high_task_completion(min_score: 0.75)
      end

      it "provides helpful failure message" do
        result = mock_task_completion_result(score: 0.60)
        expect {
          expect(result).to have_high_task_completion
        }.to raise_error(RSpec::Expectations::ExpectationNotMetError, /Expected task completion score to be at least 85%, but got 60%/)
      end
    end

    context "when result is invalid" do
      it "fails when missing method field" do
        result = mock_task_completion_result(score: 0.90)
        result[:details].delete(:method)
        expect(result).not_to have_high_task_completion
      end

      it "fails when missing task_description" do
        result = mock_task_completion_result(score: 0.90)
        result[:details].delete(:task_description)
        expect(result).not_to have_high_task_completion
      end
    end
  end

  describe "complete_task_successfully" do
    context "when task goal was achieved" do
      it "passes when goal_achieved is true" do
        result = mock_task_completion_result(score: 0.90, goal_achieved: true)
        expect(result).to complete_task_successfully
      end

      it "passes with high score and goal achieved" do
        result = mock_task_completion_result(score: 0.95, goal_achieved: true)
        expect(result).to complete_task_successfully
      end
    end

    context "when task goal was not achieved" do
      it "fails when goal_achieved is false" do
        result = mock_task_completion_result(score: 0.60, goal_achieved: false)
        expect(result).not_to complete_task_successfully
      end

      it "provides helpful failure message with issues" do
        result = mock_task_completion_result(score: 0.60, goal_achieved: false)
        expect {
          expect(result).to complete_task_successfully
        }.to raise_error(RSpec::Expectations::ExpectationNotMetError, /Expected task to be completed successfully.*some expected elements missing/)
      end
    end

    context "when result structure is invalid" do
      it "fails when missing completion_analysis" do
        result = mock_task_completion_result(score: 0.90)
        result[:details].delete(:completion_analysis)
        expect(result).not_to complete_task_successfully
      end
    end
  end

  describe "meet_task_requirements" do
    context "when all required steps completed" do
      it "passes when all steps addressed" do
        result = mock_task_completion_result(score: 0.90)
        result[:details][:completion_analysis][:steps_completed] = "4/4 steps addressed"
        expect(result).to meet_task_requirements
      end

      it "passes with different step counts" do
        result = mock_task_completion_result(score: 0.90)
        result[:details][:completion_analysis][:steps_completed] = "10/10 steps addressed"
        expect(result).to meet_task_requirements
      end
    end

    context "when some required steps incomplete" do
      it "fails when not all steps completed" do
        result = mock_task_completion_result(score: 0.70)
        result[:details][:completion_analysis][:steps_completed] = "3/4 steps addressed"
        expect(result).not_to meet_task_requirements
      end

      it "provides helpful failure message" do
        result = mock_task_completion_result(score: 0.70)
        result[:details][:completion_analysis][:steps_completed] = "2/5 steps addressed"
        expect {
          expect(result).to meet_task_requirements
        }.to raise_error(RSpec::Expectations::ExpectationNotMetError, /Expected all required steps to be completed, but got: 2\/5 steps addressed/)
      end
    end

    context "when required steps not provided" do
      it "fails when required_steps_provided is false" do
        result = mock_task_completion_result(score: 0.90)
        result[:details][:required_steps_provided] = false
        expect(result).not_to meet_task_requirements
      end
    end
  end

  describe "be_valid_task_completion_result" do
    context "with valid result structure" do
      it "passes with complete valid result" do
        result = mock_task_completion_result(score: 0.90)
        expect(result).to be_valid_task_completion_result
      end

      it "passes with all required fields present" do
        result = mock_task_completion_result(score: 0.75, goal_achieved: false)
        expect(result).to be_valid_task_completion_result
      end
    end

    context "with invalid result structure" do
      it "fails when missing label" do
        result = mock_task_completion_result(score: 0.90)
        result.delete(:label)
        expect(result).not_to be_valid_task_completion_result
      end

      it "fails when missing score" do
        result = mock_task_completion_result(score: 0.90)
        result.delete(:score)
        expect(result).not_to be_valid_task_completion_result
      end

      it "fails when missing details" do
        result = mock_task_completion_result(score: 0.90)
        result.delete(:details)
        expect(result).not_to be_valid_task_completion_result
      end

      it "fails when method is not llm_judge" do
        result = mock_task_completion_result(score: 0.90)
        result[:details][:method] = "heuristic"
        expect(result).not_to be_valid_task_completion_result
      end

      it "fails when missing completion_analysis" do
        result = mock_task_completion_result(score: 0.90)
        result[:details].delete(:completion_analysis)
        expect(result).not_to be_valid_task_completion_result
      end

      it "fails when goal_achieved is not boolean" do
        result = mock_task_completion_result(score: 0.90)
        result[:details][:completion_analysis][:goal_achieved] = "yes"
        expect(result).not_to be_valid_task_completion_result
      end

      it "fails when output_quality is invalid" do
        result = mock_task_completion_result(score: 0.90)
        result[:details][:completion_analysis][:output_quality] = "excellent"
        expect(result).not_to be_valid_task_completion_result
      end

      it "provides detailed failure message listing all issues" do
        result = { label: nil, score: nil }
        expect {
          expect(result).to be_valid_task_completion_result
        }.to raise_error(RSpec::Expectations::ExpectationNotMetError, /Missing label.*Missing score.*Missing details/m)
      end
    end
  end

  describe "have_correct_tool_usage" do
    context "when tool usage score meets threshold" do
      it "passes with default threshold (0.85)" do
        result = mock_tool_correctness_result(score: 0.90)
        expect(result).to have_correct_tool_usage
      end

      it "passes with custom threshold" do
        result = mock_tool_correctness_result(score: 0.75)
        expect(result).to have_correct_tool_usage(min_score: 0.70)
      end

      it "passes with score exactly at threshold" do
        result = mock_tool_correctness_result(score: 0.85)
        expect(result).to have_correct_tool_usage(min_score: 0.85)
      end
    end

    context "when tool usage score below threshold" do
      it "fails with default threshold" do
        result = mock_tool_correctness_result(score: 0.60)
        expect(result).not_to have_correct_tool_usage
      end

      it "fails with custom threshold" do
        result = mock_tool_correctness_result(score: 0.70)
        expect(result).not_to have_correct_tool_usage(min_score: 0.75)
      end

      it "provides helpful failure message" do
        result = mock_tool_correctness_result(score: 0.60)
        expect {
          expect(result).to have_correct_tool_usage
        }.to raise_error(RSpec::Expectations::ExpectationNotMetError, /Expected tool correctness score to be at least 85%, but got 60%/)
      end
    end

    context "when result is invalid" do
      it "fails when missing method field" do
        result = mock_tool_correctness_result(score: 0.90)
        result[:details].delete(:method)
        expect(result).not_to have_correct_tool_usage
      end

      it "fails when missing task_context" do
        result = mock_tool_correctness_result(score: 0.90)
        result[:details].delete(:task_context)
        expect(result).not_to have_correct_tool_usage
      end
    end
  end

  describe "use_tools_correctly" do
    context "when tools used appropriately" do
      it "passes when tool_selection_analysis indicates appropriate usage" do
        result = mock_tool_correctness_result(score: 0.90, appropriate_selection: true)
        expect(result).to use_tools_correctly
      end

      it "passes with high score and appropriate selection" do
        result = mock_tool_correctness_result(score: 0.95, appropriate_selection: true)
        expect(result).to use_tools_correctly
      end
    end

    context "when tools used inappropriately" do
      it "fails when tool_selection_analysis indicates inappropriate usage" do
        result = mock_tool_correctness_result(score: 0.60, appropriate_selection: false)
        expect(result).not_to use_tools_correctly
      end

      it "provides helpful failure message with analysis" do
        result = mock_tool_correctness_result(score: 0.60, appropriate_selection: false)
        expect {
          expect(result).to use_tools_correctly
        }.to raise_error(RSpec::Expectations::ExpectationNotMetError, /Expected tools to be used correctly.*some invalid tool selections/)
      end
    end

    context "when result structure is invalid" do
      it "fails when missing tool_selection_analysis" do
        result = mock_tool_correctness_result(score: 0.90)
        result[:details].delete(:tool_selection_analysis)
        expect(result).not_to use_tools_correctly
      end
    end
  end

  describe "select_appropriate_tools" do
    context "when tool selection is appropriate" do
      it "passes when analysis indicates appropriate selection" do
        result = mock_tool_correctness_result(score: 0.90, appropriate_selection: true)
        expect(result).to select_appropriate_tools
      end
    end

    context "when tool selection is inappropriate" do
      it "fails when analysis indicates invalid selection" do
        result = mock_tool_correctness_result(score: 0.60, appropriate_selection: false)
        expect(result).not_to select_appropriate_tools
      end

      it "provides helpful failure message" do
        result = mock_tool_correctness_result(score: 0.60, appropriate_selection: false)
        expect {
          expect(result).to select_appropriate_tools
        }.to raise_error(RSpec::Expectations::ExpectationNotMetError, /Expected appropriate tool selection, but got: some invalid tool selections/)
      end
    end
  end

  describe "have_valid_tool_parameters" do
    context "when tool parameters are valid" do
      it "passes when parameters provided for all tools" do
        result = mock_tool_correctness_result(score: 0.90)
        expect(result).to have_valid_tool_parameters
      end
    end

    context "when tool parameters are invalid" do
      it "fails when parameters missing" do
        result = mock_tool_correctness_result(score: 0.70)
        result[:details][:parameter_correctness_analysis] = "some tools missing parameters"
        expect(result).not_to have_valid_tool_parameters
      end

      it "provides helpful failure message" do
        result = mock_tool_correctness_result(score: 0.70)
        result[:details][:parameter_correctness_analysis] = "some tools missing parameters"
        expect {
          expect(result).to have_valid_tool_parameters
        }.to raise_error(RSpec::Expectations::ExpectationNotMetError, /Expected valid tool parameters, but got: some tools missing parameters/)
      end
    end
  end

  describe "have_minimal_tool_issues" do
    context "when tool issues are minimal" do
      it "passes with no issues (default max: 1)" do
        result = mock_tool_correctness_result(score: 0.95)
        result[:details][:issues_found] = []
        expect(result).to have_minimal_tool_issues
      end

      it "passes with issues within threshold" do
        result = mock_tool_correctness_result(score: 0.85)
        result[:details][:issues_found] = ["minor: could cache results"]
        expect(result).to have_minimal_tool_issues(max_issues: 1)
      end

      it "passes with custom threshold" do
        result = mock_tool_correctness_result(score: 0.80)
        result[:details][:issues_found] = ["issue1", "issue2", "issue3"]
        expect(result).to have_minimal_tool_issues(max_issues: 3)
      end
    end

    context "when tool issues exceed threshold" do
      it "fails when too many issues" do
        result = mock_tool_correctness_result(score: 0.70)
        result[:details][:issues_found] = ["issue1", "issue2"]
        expect(result).not_to have_minimal_tool_issues(max_issues: 1)
      end

      it "provides helpful failure message with issue count" do
        result = mock_tool_correctness_result(score: 0.70)
        result[:details][:issues_found] = ["invalid tool", "missing params"]
        expect {
          expect(result).to have_minimal_tool_issues(max_issues: 1)
        }.to raise_error(RSpec::Expectations::ExpectationNotMetError, /Expected at most 1 tool usage issues, but found 2: invalid tool, missing params/)
      end
    end
  end

  describe "be_valid_tool_correctness_result" do
    context "with valid result structure" do
      it "passes with complete valid result" do
        result = mock_tool_correctness_result(score: 0.90)
        expect(result).to be_valid_tool_correctness_result
      end

      it "passes with all required fields present" do
        result = mock_tool_correctness_result(score: 0.75, appropriate_selection: false)
        expect(result).to be_valid_tool_correctness_result
      end
    end

    context "with invalid result structure" do
      it "fails when missing label" do
        result = mock_tool_correctness_result(score: 0.90)
        result.delete(:label)
        expect(result).not_to be_valid_tool_correctness_result
      end

      it "fails when missing score" do
        result = mock_tool_correctness_result(score: 0.90)
        result.delete(:score)
        expect(result).not_to be_valid_tool_correctness_result
      end

      it "fails when missing details" do
        result = mock_tool_correctness_result(score: 0.90)
        result.delete(:details)
        expect(result).not_to be_valid_tool_correctness_result
      end

      it "fails when method is not llm_judge" do
        result = mock_tool_correctness_result(score: 0.90)
        result[:details][:method] = "heuristic"
        expect(result).not_to be_valid_tool_correctness_result
      end

      it "fails when missing tool_selection_analysis" do
        result = mock_tool_correctness_result(score: 0.90)
        result[:details].delete(:tool_selection_analysis)
        expect(result).not_to be_valid_tool_correctness_result
      end

      it "fails when available_tools_count is not integer" do
        result = mock_tool_correctness_result(score: 0.90)
        result[:details][:available_tools_count] = "5"
        expect(result).not_to be_valid_tool_correctness_result
      end

      it "provides detailed failure message listing all issues" do
        result = { label: nil, score: nil }
        expect {
          expect(result).to be_valid_tool_correctness_result
        }.to raise_error(RSpec::Expectations::ExpectationNotMetError, /Missing label.*Missing score.*Missing details/m)
      end
    end
  end

  describe "have_better_task_completion_than" do
    context "when task completion improved" do
      it "passes when new result has higher score" do
        baseline = mock_task_completion_result(score: 0.70)
        improved = mock_task_completion_result(score: 0.85)
        expect(improved).to have_better_task_completion_than(baseline)
      end

      it "passes with significant improvement" do
        baseline = mock_task_completion_result(score: 0.60)
        improved = mock_task_completion_result(score: 0.95)
        expect(improved).to have_better_task_completion_than(baseline)
      end
    end

    context "when task completion regressed" do
      it "fails when new result has lower score" do
        baseline = mock_task_completion_result(score: 0.85)
        regressed = mock_task_completion_result(score: 0.70)
        expect(regressed).not_to have_better_task_completion_than(baseline)
      end

      it "provides helpful failure message with scores" do
        baseline = mock_task_completion_result(score: 0.85)
        regressed = mock_task_completion_result(score: 0.70)
        expect {
          expect(regressed).to have_better_task_completion_than(baseline)
        }.to raise_error(RSpec::Expectations::ExpectationNotMetError, /Expected task completion to be better than baseline, but got 70% vs 85% \(-15% change\)/)
      end
    end

    context "when task completion unchanged" do
      it "fails when scores are equal" do
        baseline = mock_task_completion_result(score: 0.80)
        unchanged = mock_task_completion_result(score: 0.80)
        expect(unchanged).not_to have_better_task_completion_than(baseline)
      end
    end
  end

  describe "have_better_tool_usage_than" do
    context "when tool usage improved" do
      it "passes when new result has higher score" do
        baseline = mock_tool_correctness_result(score: 0.70)
        improved = mock_tool_correctness_result(score: 0.85)
        expect(improved).to have_better_tool_usage_than(baseline)
      end

      it "passes with significant improvement" do
        baseline = mock_tool_correctness_result(score: 0.60)
        improved = mock_tool_correctness_result(score: 0.95)
        expect(improved).to have_better_tool_usage_than(baseline)
      end
    end

    context "when tool usage regressed" do
      it "fails when new result has lower score" do
        baseline = mock_tool_correctness_result(score: 0.85)
        regressed = mock_tool_correctness_result(score: 0.70)
        expect(regressed).not_to have_better_tool_usage_than(baseline)
      end

      it "provides helpful failure message with scores" do
        baseline = mock_tool_correctness_result(score: 0.85)
        regressed = mock_tool_correctness_result(score: 0.70)
        expect {
          expect(regressed).to have_better_tool_usage_than(baseline)
        }.to raise_error(RSpec::Expectations::ExpectationNotMetError, /Expected tool usage to be better than baseline, but got 70% vs 85% \(-15% change\)/)
      end
    end

    context "when tool usage unchanged" do
      it "fails when scores are equal" do
        baseline = mock_tool_correctness_result(score: 0.80)
        unchanged = mock_tool_correctness_result(score: 0.80)
        expect(unchanged).not_to have_better_tool_usage_than(baseline)
      end
    end
  end
end
