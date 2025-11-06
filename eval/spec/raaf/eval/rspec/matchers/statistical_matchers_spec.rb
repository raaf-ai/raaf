# frozen_string_literal: true

RSpec.describe "Statistical Matchers" do
  let(:baseline_output) { "A" * 100 }

  let(:baseline_span) do
    {
      id: "statistical_test",
      output: baseline_output,
      metadata: { output: baseline_output }
    }
  end

  let(:significantly_different_result) do
    run = RAAF::Eval::EvaluationRun.new(
      span: baseline_span,
      configurations: { run1: {}, run2: {}, run3: {}, run4: {}, run5: {} }
    )
    run.instance_variable_set(:@results, {
      run1: { success: true, output: "B" * 150 },
      run2: { success: true, output: "C" * 155 },
      run3: { success: true, output: "D" * 160 },
      run4: { success: true, output: "E" * 145 },
      run5: { success: true, output: "F" * 152 }
    })
    run.instance_variable_set(:@executed, true)
    RAAF::Eval::EvaluationResult.new(run: run, baseline: baseline_span)
  end

  let(:similar_result) do
    run = RAAF::Eval::EvaluationRun.new(
      span: baseline_span,
      configurations: { run1: {}, run2: {}, run3: {} }
    )
    run.instance_variable_set(:@results, {
      run1: { success: true, output: "B" * 102 },
      run2: { success: true, output: "C" * 98 },
      run3: { success: true, output: "D" * 101 }
    })
    run.instance_variable_set(:@executed, true)
    RAAF::Eval::EvaluationResult.new(run: run, baseline: baseline_span)
  end

  describe "be_statistically_significant matcher" do
    it "detects statistically significant differences" do
      # Mock the statistical significance calculation
      allow(RAAF::Eval::Metrics).to receive(:statistical_significance).and_return(
        { p_value: 0.01, is_significant: true }
      )

      expect(significantly_different_result).to be_statistically_significant
    end

    it "fails when difference is not significant" do
      allow(RAAF::Eval::Metrics).to receive(:statistical_significance).and_return(
        { p_value: 0.15, is_significant: false }
      )

      expect {
        expect(similar_result).to be_statistically_significant
      }.to raise_error(RSpec::Expectations::ExpectationNotMetError)
    end

    it "provides clear failure message with p-value" do
      allow(RAAF::Eval::Metrics).to receive(:statistical_significance).and_return(
        { p_value: 0.15, is_significant: false }
      )

      begin
        expect(similar_result).to be_statistically_significant
      rescue RSpec::Expectations::ExpectationNotMetError => e
        expect(e.message).to include("p-value")
        expect(e.message).to include("0.15")
      end
    end

    it "supports custom significance level" do
      allow(RAAF::Eval::Metrics).to receive(:statistical_significance).and_return(
        { p_value: 0.08, is_significant: false }
      )

      expect {
        expect(similar_result).to be_statistically_significant.at_level(0.05)
      }.to raise_error(RSpec::Expectations::ExpectationNotMetError)
    end

    it "handles empty samples" do
      empty_result = RAAF::Eval::EvaluationRun.new(
        span: baseline_span,
        configurations: { run1: {} }
      )
      empty_result.instance_variable_set(:@results, {})
      empty_result.instance_variable_set(:@executed, true)
      result = RAAF::Eval::EvaluationResult.new(run: empty_result, baseline: baseline_span)

      expect(result).to_not be_statistically_significant
    end

    context "when negated" do
      it "provides clear negated failure message" do
        allow(RAAF::Eval::Metrics).to receive(:statistical_significance).and_return(
          { p_value: 0.01, is_significant: true }
        )

        begin
          expect(significantly_different_result).to_not be_statistically_significant
        rescue RSpec::Expectations::ExpectationNotMetError => e
          expect(e.message).to include("no statistical significance")
          expect(e.message).to include("p-value")
        end
      end
    end
  end

  describe "have_effect_size matcher" do
    let(:large_effect_result) do
      run = RAAF::Eval::EvaluationRun.new(
        span: baseline_span,
        configurations: { run1: {}, run2: {}, run3: {} }
      )
      run.instance_variable_set(:@results, {
        run1: { success: true, output: "B" * 200 },
        run2: { success: true, output: "C" * 210 },
        run3: { success: true, output: "D" * 190 }
      })
      run.instance_variable_set(:@executed, true)
      RAAF::Eval::EvaluationResult.new(run: run, baseline: baseline_span)
    end

    let(:small_effect_result) do
      run = RAAF::Eval::EvaluationRun.new(
        span: baseline_span,
        configurations: { run1: {}, run2: {} }
      )
      run.instance_variable_set(:@results, {
        run1: { success: true, output: "B" * 102 },
        run2: { success: true, output: "C" * 98 }
      })
      run.instance_variable_set(:@executed, true)
      RAAF::Eval::EvaluationResult.new(run: run, baseline: baseline_span)
    end

    it "detects large effect sizes" do
      expect(large_effect_result).to have_effect_size.above(0.5)
    end

    it "detects any measurable effect" do
      expect(large_effect_result).to have_effect_size
    end

    it "fails when effect size is too small" do
      expect {
        expect(small_effect_result).to have_effect_size.above(0.8)
      }.to raise_error(RSpec::Expectations::ExpectationNotMetError)
    end

    it "provides clear failure message with effect size value" do
      begin
        expect(small_effect_result).to have_effect_size.above(0.8)
      rescue RSpec::Expectations::ExpectationNotMetError => e
        expect(e.message).to include("effect size")
        expect(e.message).to match(/\d+\.\d+/)
      end
    end

    it "supports 'of' syntax for threshold" do
      expect(large_effect_result).to have_effect_size.of(0.5)
    end

    it "handles empty samples" do
      empty_result = RAAF::Eval::EvaluationRun.new(
        span: baseline_span,
        configurations: { run1: {} }
      )
      empty_result.instance_variable_set(:@results, {})
      empty_result.instance_variable_set(:@executed, true)
      result = RAAF::Eval::EvaluationResult.new(run: empty_result, baseline: baseline_span)

      expect(result).to_not have_effect_size
    end

    context "when negated" do
      it "provides clear negated failure message" do
        begin
          expect(large_effect_result).to_not have_effect_size
        rescue RSpec::Expectations::ExpectationNotMetError => e
          expect(e.message).to include("no effect")
          expect(e.message).to include("small effect")
        end
      end
    end
  end

  describe "have_confidence_interval matcher" do
    let(:narrow_ci_result) do
      run = RAAF::Eval::EvaluationRun.new(
        span: baseline_span,
        configurations: { run1: {}, run2: {}, run3: {}, run4: {}, run5: {} }
      )
      run.instance_variable_set(:@results, {
        run1: { success: true, output: "B" * 100 },
        run2: { success: true, output: "C" * 102 },
        run3: { success: true, output: "D" * 98 },
        run4: { success: true, output: "E" * 101 },
        run5: { success: true, output: "F" * 99 }
      })
      run.instance_variable_set(:@executed, true)
      RAAF::Eval::EvaluationResult.new(run: run, baseline: baseline_span)
    end

    let(:wide_ci_result) do
      run = RAAF::Eval::EvaluationRun.new(
        span: baseline_span,
        configurations: { run1: {}, run2: {}, run3: {} }
      )
      run.instance_variable_set(:@results, {
        run1: { success: true, output: "B" * 50 },
        run2: { success: true, output: "C" * 150 },
        run3: { success: true, output: "D" * 100 }
      })
      run.instance_variable_set(:@executed, true)
      RAAF::Eval::EvaluationResult.new(run: run, baseline: baseline_span)
    end

    it "passes when CI is within specified bounds" do
      expect(narrow_ci_result).to have_confidence_interval.within(90, 110)
    end

    it "fails when CI exceeds bounds" do
      expect {
        expect(wide_ci_result).to have_confidence_interval.within(90, 110)
      }.to raise_error(RSpec::Expectations::ExpectationNotMetError)
    end

    it "provides clear failure message with CI values" do
      begin
        expect(wide_ci_result).to have_confidence_interval.within(90, 110)
      rescue RSpec::Expectations::ExpectationNotMetError => e
        expect(e.message).to include("confidence interval")
        expect(e.message).to include("[")
        expect(e.message).to include("]")
      end
    end

    it "supports custom confidence level" do
      expect(narrow_ci_result).to have_confidence_interval.at_confidence(0.99).within(80, 120)
    end

    it "works without bounds (just calculates CI)" do
      expect(narrow_ci_result).to have_confidence_interval
    end

    it "handles empty samples" do
      empty_result = RAAF::Eval::EvaluationRun.new(
        span: baseline_span,
        configurations: { run1: {} }
      )
      empty_result.instance_variable_set(:@results, {})
      empty_result.instance_variable_set(:@executed, true)
      result = RAAF::Eval::EvaluationResult.new(run: empty_result, baseline: baseline_span)

      expect(result).to_not have_confidence_interval.within(90, 110)
    end

    it "supports 90% confidence level" do
      expect(narrow_ci_result).to have_confidence_interval.at_confidence(0.90)
    end

    it "supports 95% confidence level (default)" do
      expect(narrow_ci_result).to have_confidence_interval.at_confidence(0.95)
    end

    it "supports 99% confidence level" do
      expect(narrow_ci_result).to have_confidence_interval.at_confidence(0.99)
    end

    context "when negated" do
      it "provides clear negated failure message" do
        begin
          expect(narrow_ci_result).to_not have_confidence_interval.within(90, 110)
        rescue RSpec::Expectations::ExpectationNotMetError => e
          expect(e.message).to include("outside range")
          expect(e.message).to include("within bounds")
        end
      end
    end
  end

  describe "edge cases and integration" do
    it "handles failed evaluations gracefully" do
      failed_result = RAAF::Eval::EvaluationRun.new(
        span: baseline_span,
        configurations: { run1: {} }
      )
      failed_result.instance_variable_set(:@results, {
        run1: { success: false, error: "Test error" }
      })
      failed_result.instance_variable_set(:@executed, true)
      result = RAAF::Eval::EvaluationResult.new(run: failed_result, baseline: baseline_span)

      expect(result).to_not have_effect_size
      expect(result).to_not have_confidence_interval.within(90, 110)
    end

    it "handles mixed success/failure results" do
      mixed_result = RAAF::Eval::EvaluationRun.new(
        span: baseline_span,
        configurations: { run1: {}, run2: {}, run3: {} }
      )
      mixed_result.instance_variable_set(:@results, {
        run1: { success: true, output: "B" * 100 },
        run2: { success: false, error: "Error" },
        run3: { success: true, output: "D" * 105 }
      })
      mixed_result.instance_variable_set(:@executed, true)
      result = RAAF::Eval::EvaluationResult.new(run: mixed_result, baseline: baseline_span)

      # Should work with only successful results
      expect(result).to have_confidence_interval
    end
  end
end
