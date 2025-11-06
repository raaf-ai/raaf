# frozen_string_literal: true

RSpec.describe "Regression Matchers" do
  let(:baseline_output) { "Ruby is a dynamic, object-oriented programming language with elegant syntax." }
  let(:improved_output) { "Ruby is a dynamic, object-oriented programming language with elegant syntax and powerful metaprogramming capabilities." }
  let(:regressed_output) { "Python is good." }

  let(:baseline_usage) { { input_tokens: 100, output_tokens: 50 } }
  let(:baseline_latency) { 500 }

  let(:baseline_span) do
    {
      id: "regression_test",
      output: baseline_output,
      metadata: {
        output: baseline_output,
        usage: baseline_usage,
        latency_ms: baseline_latency
      }
    }
  end

  let(:good_result) do
    run = RAAF::Eval::EvaluationRun.new(
      span: baseline_span,
      configurations: { test: {} }
    )
    run.instance_variable_set(:@results, {
      test: {
        success: true,
        output: improved_output,
        usage: { input_tokens: 95, output_tokens: 45 },
        latency_ms: 450
      }
    })
    run.instance_variable_set(:@executed, true)
    RAAF::Eval::EvaluationResult.new(run: run, baseline: baseline_span)
  end

  let(:regressed_result) do
    run = RAAF::Eval::EvaluationRun.new(
      span: baseline_span,
      configurations: { test: {} }
    )
    run.instance_variable_set(:@results, {
      test: {
        success: true,
        output: regressed_output,
        usage: { input_tokens: 150, output_tokens: 80 },
        latency_ms: 700
      }
    })
    run.instance_variable_set(:@executed, true)
    RAAF::Eval::EvaluationResult.new(run: run, baseline: baseline_span)
  end

  describe "not_have_regressions matcher" do
    it "passes when no regressions detected" do
      expect(good_result).to_not have_regressions
    end

    it "fails when quality regresses" do
      expect {
        expect(regressed_result).to_not have_regressions
      }.to raise_error(RSpec::Expectations::ExpectationNotMetError)
    end

    it "provides clear failure message with regression details" do
      begin
        expect(regressed_result).to_not have_regressions
      rescue RSpec::Expectations::ExpectationNotMetError => e
        expect(e.message).to include("regressions")
        expect(e.message).to include("quality")
      end
    end

    it "supports severity filtering" do
      expect(good_result).to_not have_regressions.of_severity(:high)
    end

    context "when negated" do
      it "fails when no regressions present" do
        expect {
          expect(good_result).to have_regressions
        }.to raise_error(RSpec::Expectations::ExpectationNotMetError)
      end

      it "provides clear negated failure message" do
        begin
          expect(good_result).to have_regressions
        rescue RSpec::Expectations::ExpectationNotMetError => e
          expect(e.message).to include("Expected regressions")
          expect(e.message).to include("none were detected")
        end
      end
    end
  end

  describe "perform_better_than matcher" do
    it "passes when performance improves across metrics" do
      expect(good_result).to perform_better_than(:baseline).on_metrics(:quality, :latency, :tokens)
    end

    it "fails when performance regresses" do
      expect {
        expect(regressed_result).to perform_better_than(:baseline)
      }.to raise_error(RSpec::Expectations::ExpectationNotMetError)
    end

    it "provides detailed regression information" do
      begin
        expect(regressed_result).to perform_better_than(:baseline)
      rescue RSpec::Expectations::ExpectationNotMetError => e
        expect(e.message).to include("regressions")
      end
    end

    it "supports metric selection" do
      expect(good_result).to perform_better_than(:baseline).on_metrics(:latency)
    end

    it "detects quality regressions" do
      expect {
        expect(regressed_result).to perform_better_than(:baseline).on_metrics(:quality)
      }.to raise_error(RSpec::Expectations::ExpectationNotMetError)
    end

    it "detects latency regressions" do
      expect {
        expect(regressed_result).to perform_better_than(:baseline).on_metrics(:latency)
      }.to raise_error(RSpec::Expectations::ExpectationNotMetError)
    end

    it "detects token usage regressions" do
      expect {
        expect(regressed_result).to perform_better_than(:baseline).on_metrics(:tokens)
      }.to raise_error(RSpec::Expectations::ExpectationNotMetError)
    end

    context "when negated" do
      it "provides clear negated failure message" do
        begin
          expect(regressed_result).to_not perform_better_than(:baseline)
        rescue RSpec::Expectations::ExpectationNotMetError => e
          expect(e.message).to include("not improve")
        end
      end
    end
  end

  describe "have_acceptable_variance matcher" do
    let(:consistent_results) do
      run = RAAF::Eval::EvaluationRun.new(
        span: baseline_span,
        configurations: { run1: {}, run2: {}, run3: {} }
      )
      run.instance_variable_set(:@results, {
        run1: { success: true, output: "A" * 100, latency_ms: 500 },
        run2: { success: true, output: "B" * 102, latency_ms: 510 },
        run3: { success: true, output: "C" * 98, latency_ms: 495 }
      })
      run.instance_variable_set(:@executed, true)
      RAAF::Eval::EvaluationResult.new(run: run, baseline: baseline_span)
    end

    let(:inconsistent_results) do
      run = RAAF::Eval::EvaluationRun.new(
        span: baseline_span,
        configurations: { run1: {}, run2: {}, run3: {} }
      )
      run.instance_variable_set(:@results, {
        run1: { success: true, output: "A" * 100, latency_ms: 500 },
        run2: { success: true, output: "B" * 200, latency_ms: 1000 },
        run3: { success: true, output: "C" * 50, latency_ms: 300 }
      })
      run.instance_variable_set(:@executed, true)
      RAAF::Eval::EvaluationResult.new(run: run, baseline: baseline_span)
    end

    it "passes when variance is within acceptable range" do
      expect(consistent_results).to have_acceptable_variance.within(2).standard_deviations
    end

    it "fails when variance is too high" do
      expect {
        expect(inconsistent_results).to have_acceptable_variance.within(2).standard_deviations
      }.to raise_error(RSpec::Expectations::ExpectationNotMetError)
    end

    it "provides details about outliers" do
      begin
        expect(inconsistent_results).to have_acceptable_variance.within(2).standard_deviations
      rescue RSpec::Expectations::ExpectationNotMetError => e
        expect(e.message).to include("outlier")
        expect(e.message).to include("standard deviations")
      end
    end

    it "supports custom metric selection" do
      expect(consistent_results).to have_acceptable_variance.for_metric(:output_length)
    end

    it "checks latency variance" do
      expect(consistent_results).to have_acceptable_variance.for_metric(:latency)
    end

    it "checks token variance" do
      token_result = RAAF::Eval::EvaluationRun.new(
        span: baseline_span,
        configurations: { run1: {}, run2: {} }
      )
      token_result.instance_variable_set(:@results, {
        run1: { success: true, output: "A", usage: { input_tokens: 100, output_tokens: 50 } },
        run2: { success: true, output: "B", usage: { input_tokens: 105, output_tokens: 48 } }
      })
      token_result.instance_variable_set(:@executed, true)
      result = RAAF::Eval::EvaluationResult.new(run: token_result, baseline: baseline_span)

      expect(result).to have_acceptable_variance.for_metric(:tokens)
    end

    it "handles edge case with less than 2 samples" do
      single_result = RAAF::Eval::EvaluationRun.new(
        span: baseline_span,
        configurations: { run1: {} }
      )
      single_result.instance_variable_set(:@results, {
        run1: { success: true, output: "A" * 100 }
      })
      single_result.instance_variable_set(:@executed, true)
      result = RAAF::Eval::EvaluationResult.new(run: single_result, baseline: baseline_span)

      expect(result).to have_acceptable_variance
    end

    context "when negated" do
      it "provides clear negated failure message" do
        begin
          expect(consistent_results).to_not have_acceptable_variance
        rescue RSpec::Expectations::ExpectationNotMetError => e
          expect(e.message).to include("exceed")
          expect(e.message).to include("within bounds")
        end
      end
    end
  end

  describe "edge cases" do
    it "handles missing usage data gracefully" do
      result_no_usage = RAAF::Eval::EvaluationRun.new(
        span: baseline_span,
        configurations: { test: {} }
      )
      result_no_usage.instance_variable_set(:@results, {
        test: { success: true, output: improved_output }
      })
      result_no_usage.instance_variable_set(:@executed, true)
      eval_result = RAAF::Eval::EvaluationResult.new(run: result_no_usage, baseline: baseline_span)

      expect(eval_result).to_not have_regressions
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
      eval_result = RAAF::Eval::EvaluationResult.new(run: failed_result, baseline: baseline_span)

      expect(eval_result).to_not have_regressions
    end
  end
end
