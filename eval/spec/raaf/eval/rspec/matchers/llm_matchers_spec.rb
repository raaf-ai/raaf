# frozen_string_literal: true

RSpec.describe "LLM Matchers" do
  let(:helpful_output) { "Ruby is a programming language designed with developer happiness in mind. It has elegant syntax that is easy to read and write." }
  let(:technical_output) { "Ruby uses dynamic typing and automatic memory management. The MRI implementation uses a global interpreter lock (GIL)." }
  let(:unhelpful_output) { "Stuff about programming." }

  let(:baseline_span) do
    {
      id: "llm_test",
      output: helpful_output,
      metadata: { output: helpful_output }
    }
  end

  let(:helpful_result) do
    run = RAAF::Eval::EvaluationRun.new(
      span: baseline_span,
      configurations: { test: {} }
    )
    run.instance_variable_set(:@results, {
      test: { success: true, output: helpful_output }
    })
    run.instance_variable_set(:@executed, true)
    RAAF::Eval::EvaluationResult.new(run: run, baseline: baseline_span)
  end

  let(:technical_result) do
    run = RAAF::Eval::EvaluationRun.new(
      span: baseline_span,
      configurations: { test: {} }
    )
    run.instance_variable_set(:@results, {
      test: { success: true, output: technical_output }
    })
    run.instance_variable_set(:@executed, true)
    RAAF::Eval::EvaluationResult.new(run: run, baseline: baseline_span)
  end

  let(:unhelpful_result) do
    run = RAAF::Eval::EvaluationRun.new(
      span: baseline_span,
      configurations: { test: {} }
    )
    run.instance_variable_set(:@results, {
      test: { success: true, output: unhelpful_output }
    })
    run.instance_variable_set(:@executed, true)
    RAAF::Eval::EvaluationResult.new(run: run, baseline: baseline_span)
  end

  describe "satisfy_llm_check matcher" do
    before do
      # Mock LLMJudge to avoid actual API calls
      allow(RAAF::Eval::RSpec::LLMJudge).to receive(:new).and_return(mock_judge)
    end

    let(:mock_judge) do
      instance_double(
        RAAF::Eval::RSpec::LLMJudge,
        check: { label: "good", confidence: 0.9, reasoning: "Output is informative and well-structured" }
      )
    end

    it "uses LLM judge for custom checks" do
      expect(mock_judge).to receive(:check).with(helpful_output, "is informative and well-written")
      expect(helpful_result).to satisfy_llm_check("is informative and well-written")
    end

    it "returns label 'good' when judge approves" do
      expect(helpful_result).to satisfy_llm_check("explains the topic clearly")
    end

    it "returns label 'bad' when judge disapproves" do
      allow(mock_judge).to receive(:check).and_return(
        { label: "bad", confidence: 0.8, reasoning: "Output lacks detail" }
      )

      expect {
        expect(unhelpful_result).to satisfy_llm_check("is comprehensive")
      }.to raise_error(RSpec::Expectations::ExpectationNotMetError)
    end

    it "provides clear failure message with judge reasoning" do
      allow(mock_judge).to receive(:check).and_return(
        { label: "bad", confidence: 0.8, reasoning: "Output lacks detail" }
      )

      begin
        expect(unhelpful_result).to satisfy_llm_check("is comprehensive")
      rescue RSpec::Expectations::ExpectationNotMetError => e
        expect(e.message).to include("satisfy")
        expect(e.message).to include("lacks detail")
        expect(e.message).to include("confidence")
      end
    end

    it "supports custom judge model" do
      expect(helpful_result).to satisfy_llm_check("is helpful").using_model("gpt-4")
    end

    it "supports custom confidence threshold" do
      allow(mock_judge).to receive(:check).and_return(
        { label: "good", confidence: 0.6, reasoning: "Somewhat helpful" }
      )

      expect {
        expect(helpful_result).to satisfy_llm_check("is helpful").with_confidence(0.8)
      }.to raise_error(RSpec::Expectations::ExpectationNotMetError)
    end

    it "respects confidence threshold" do
      allow(mock_judge).to receive(:check).and_return(
        { label: "good", confidence: 0.6, reasoning: "Somewhat helpful" }
      )

      # Should pass with lower threshold
      expect(helpful_result).to satisfy_llm_check("is helpful").with_confidence(0.5)
    end

    context "when negated" do
      it "provides clear negated failure message" do
        begin
          expect(helpful_result).to_not satisfy_llm_check("is helpful")
        rescue RSpec::Expectations::ExpectationNotMetError => e
          expect(e.message).to include("not satisfy")
          expect(e.message).to include("it did")
        end
      end
    end
  end

  describe "satisfy_llm_criteria matcher" do
    before do
      allow(RAAF::Eval::RSpec::LLMJudge).to receive(:new).and_return(mock_judge)
    end

    let(:mock_judge) do
      instance_double(
        RAAF::Eval::RSpec::LLMJudge,
        check_criteria: { label: "good",
          criteria: [
            { name: "clarity", label: "good", reasoning: "Clear and concise" },
            { name: "accuracy", label: "good", reasoning: "Technically accurate" },
            { name: "completeness", label: "good", reasoning: "Covers key points" }
          ]
        }
      )
    end

    it "checks multiple criteria" do
      criteria = ["is clear", "is accurate", "is complete"]
      expect(helpful_result).to satisfy_llm_criteria(criteria)
    end

    it "supports hash-based criteria with names" do
      criteria = {
        clarity: "Output is easy to understand",
        accuracy: "Information is factually correct",
        completeness: "All important aspects are covered"
      }

      expect(helpful_result).to satisfy_llm_criteria(criteria)
    end

    it "supports weighted criteria" do
      criteria = {
        clarity: { description: "Easy to understand", weight: 2.0 },
        accuracy: { description: "Factually correct", weight: 1.5 },
        completeness: { description: "Comprehensive", weight: 1.0 }
      }

      expect(helpful_result).to satisfy_llm_criteria(criteria)
    end

    it "returns label 'bad' when any criterion fails" do
      allow(mock_judge).to receive(:check_criteria).and_return(
        { label: "bad",
          criteria: [
            { name: "clarity", label: "good", reasoning: "Clear" },
            { name: "accuracy", label: "bad", reasoning: "Contains errors" },
            { name: "completeness", label: "good", reasoning: "Complete" }
          ]
        }
      )

      expect {
        expect(unhelpful_result).to satisfy_llm_criteria(["is clear", "is accurate", "is complete"])
      }.to raise_error(RSpec::Expectations::ExpectationNotMetError)
    end

    it "provides clear failure message listing failed criteria" do
      allow(mock_judge).to receive(:check_criteria).and_return(
        { label: "bad",
          criteria: [
            { name: "clarity", label: "good", reasoning: "Clear" },
            { name: "accuracy", label: "bad", reasoning: "Contains errors" },
            { name: "completeness", label: "bad", reasoning: "Incomplete" }
          ]
        }
      )

      begin
        expect(unhelpful_result).to satisfy_llm_criteria(["is clear", "is accurate", "is complete"])
      rescue RSpec::Expectations::ExpectationNotMetError => e
        expect(e.message).to include("2 failed")
        expect(e.message).to include("accuracy")
        expect(e.message).to include("completeness")
        expect(e.message).to include("Contains errors")
        expect(e.message).to include("Incomplete")
      end
    end

    it "supports custom judge model" do
      criteria = ["is clear", "is helpful"]
      expect(helpful_result).to satisfy_llm_criteria(criteria).using_model("gpt-4")
    end

    context "when negated" do
      it "provides clear negated failure message" do
        begin
          expect(helpful_result).to_not satisfy_llm_criteria(["is clear"])
        rescue RSpec::Expectations::ExpectationNotMetError => e
          expect(e.message).to include("fail criteria")
          expect(e.message).to include("all passed")
        end
      end
    end
  end

  describe "be_judged_as matcher" do
    before do
      allow(RAAF::Eval::RSpec::LLMJudge).to receive(:new).and_return(mock_judge)
    end

    let(:mock_judge) do
      instance_double(
        RAAF::Eval::RSpec::LLMJudge,
        judge_single: { label: "good", reasoning: "Output meets description" },
        judge: { label: "good", reasoning: "First output is better" }
      )
    end

    it "makes flexible quality judgments" do
      expect(helpful_result).to be_judged_as("helpful and informative")
    end

    it "supports comparison to baseline" do
      expect(technical_result).to be_judged_as("more technical").than(:baseline)
    end

    it "supports comparison to specific output" do
      expect(technical_result).to be_judged_as("more technical").than(helpful_output)
    end

    it "supports comparison to another result" do
      expect(technical_result).to be_judged_as("more technical").than(:test)
    end

    it "returns label 'bad' when judgment doesn't match" do
      allow(mock_judge).to receive(:judge_single).and_return(
        { label: "bad", reasoning: "Output doesn't match description" }
      )

      expect {
        expect(unhelpful_result).to be_judged_as("comprehensive and detailed")
      }.to raise_error(RSpec::Expectations::ExpectationNotMetError)
    end

    it "provides clear failure message with reasoning" do
      allow(mock_judge).to receive(:judge_single).and_return(
        { label: "bad", reasoning: "Too brief and lacks examples" }
      )

      begin
        expect(unhelpful_result).to be_judged_as("comprehensive")
      rescue RSpec::Expectations::ExpectationNotMetError => e
        expect(e.message).to include("judged as 'comprehensive'")
        expect(e.message).to include("Too brief and lacks examples")
      end
    end

    it "supports custom judge model" do
      expect(helpful_result).to be_judged_as("helpful").using_model("gpt-4")
    end

    it "builds appropriate comparison prompts" do
      # Test that prompts are constructed correctly
      expect(mock_judge).to receive(:judge).with(
        technical_output,
        helpful_output,
        anything
      )

      expect(technical_result).to be_judged_as("more technical").than(:baseline)
    end

    context "when negated" do
      it "provides clear negated failure message" do
        begin
          expect(helpful_result).to_not be_judged_as("helpful")
        rescue RSpec::Expectations::ExpectationNotMetError => e
          expect(e.message).to include("not be judged as")
          expect(e.message).to include("it was")
        end
      end
    end
  end

  describe "edge cases and integration" do
    before do
      allow(RAAF::Eval::RSpec::LLMJudge).to receive(:new).and_return(mock_judge)
    end

    let(:mock_judge) do
      instance_double(
        RAAF::Eval::RSpec::LLMJudge,
        check: { label: "good", confidence: 0.9, reasoning: "Good" },
        check_criteria: { label: "good", criteria: [] },
        judge_single: { label: "good", reasoning: "Good" }
      )
    end

    it "handles empty output" do
      empty_result = RAAF::Eval::EvaluationRun.new(
        span: baseline_span,
        configurations: { test: {} }
      )
      empty_result.instance_variable_set(:@results, {
        test: { success: true, output: "" }
      })
      empty_result.instance_variable_set(:@executed, true)
      result = RAAF::Eval::EvaluationResult.new(run: empty_result, baseline: baseline_span)

      expect(result).to satisfy_llm_check("is empty")
    end

    it "handles failed evaluations" do
      failed_result = RAAF::Eval::EvaluationRun.new(
        span: baseline_span,
        configurations: { test: {} }
      )
      failed_result.instance_variable_set(:@results, {
        test: { success: false, error: "Test error" }
      })
      failed_result.instance_variable_set(:@executed, true)
      result = RAAF::Eval::EvaluationResult.new(run: failed_result, baseline: baseline_span)

      # Should handle gracefully with empty output
      expect(result).to satisfy_llm_check("has no content")
    end

    it "can combine LLM matchers with other matchers" do
      expect(helpful_result).to satisfy_llm_check("is helpful").and have_length.greater_than(10)
    end
  end
end
