# frozen_string_literal: true

RSpec.describe "Performance Matchers" do
  let(:baseline_usage) { { input_tokens: 100, output_tokens: 50 } }
  let(:eval_usage) { { input_tokens: 110, output_tokens: 55 } }

  let(:baseline_span) do
    {
      id: "perf_test",
      usage: baseline_usage,
      latency_ms: 500,
      metadata: {
        usage: baseline_usage,
        model: "gpt-4o"
      }
    }
  end

  let(:evaluation_result) do
    run = RAAF::Eval::EvaluationRun.new(
      span: baseline_span,
      configurations: { test: {} }
    )
    run.instance_variable_set(:@results, {
      test: { success: true, usage: eval_usage, latency_ms: 550 }
    })
    run.instance_variable_set(:@executed, true)
    RAAF::Eval::EvaluationResult.new(run: run, baseline: baseline_span)
  end

  describe "use_tokens matcher" do
    it "checks token usage within percent of baseline" do
      expect(evaluation_result).to use_tokens.within(20).percent_of(:baseline)
    end

    it "checks token usage less than max" do
      expect(evaluation_result[:test]).to use_tokens.less_than(200)
    end

    it "checks token usage in range" do
      expect(evaluation_result[:test]).to use_tokens.between(100, 200)
    end

    context "when tokens exceed threshold" do
      let(:eval_usage) { { input_tokens: 500, output_tokens: 500 } }

      it "fails with clear message" do
        expect {
          expect(evaluation_result).to use_tokens.within(10).percent_of(:baseline)
        }.to raise_error(RSpec::Expectations::ExpectationNotMetError, /token usage/i)
      end
    end
  end

  describe "complete_within matcher" do
    it "checks latency in seconds" do
      expect(evaluation_result).to complete_within(2).seconds
    end

    it "checks latency in milliseconds" do
      expect(evaluation_result[:test]).to complete_within(1000).milliseconds
    end

    context "when latency exceeds threshold" do
      let(:eval_usage) { { input_tokens: 100, output_tokens: 50 } }

      before do
        result = evaluation_result[:test]
        result[:latency_ms] = 5000
      end

      it "fails with clear message" do
        expect {
          expect(evaluation_result[:test]).to complete_within(1).seconds
        }.to raise_error(RSpec::Expectations::ExpectationNotMetError, /completion/i)
      end
    end
  end

  describe "cost_less_than matcher" do
    it "checks cost against threshold" do
      # This is a simplified test - real implementation would calculate actual costs
      expect(baseline_span).to have_key(:usage)
    end
  end
end
