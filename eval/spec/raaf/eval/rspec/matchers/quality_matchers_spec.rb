# frozen_string_literal: true

RSpec.describe "Quality Matchers" do
  let(:baseline_output) { "Ruby is a dynamic, object-oriented programming language." }
  let(:similar_output) { "Ruby is a dynamic and object-oriented programming language." }
  let(:different_output) { "Python is a high-level programming language." }

  let(:baseline_span) do
    {
      id: "quality_test",
      output: baseline_output,
      metadata: { output: baseline_output }
    }
  end

  let(:evaluation_result) do
    run = RAAF::Eval::EvaluationRun.new(
      span: baseline_span,
      configurations: { test: {} }
    )
    run.instance_variable_set(:@results, {
      test: { success: true, output: similar_output }
    })
    run.instance_variable_set(:@executed, true)
    RAAF::Eval::EvaluationResult.new(run: run, baseline: baseline_span)
  end

  describe "maintain_quality matcher" do
    it "passes when quality is maintained" do
      expect(evaluation_result).to maintain_quality
    end

    it "supports threshold customization" do
      expect(evaluation_result).to maintain_quality.within(30).percent
    end

    context "with failing quality" do
      let(:similar_output) { different_output }

      it "fails when quality drops" do
        expect {
          expect(evaluation_result).to maintain_quality
        }.to raise_error(RSpec::Expectations::ExpectationNotMetError)
      end

      it "provides clear failure message" do
        begin
          expect(evaluation_result).to maintain_quality
        rescue RSpec::Expectations::ExpectationNotMetError => e
          expect(e.message).to include("quality")
        end
      end
    end
  end

  describe "have_similar_output_to matcher" do
    it "compares against baseline" do
      expect(evaluation_result).to have_similar_output_to(:baseline).within(20).percent
    end

    it "compares against string" do
      expect(evaluation_result[:test]).to have_similar_output_to(baseline_output).within(20).percent
    end
  end

  describe "have_coherent_output matcher" do
    it "checks output coherence" do
      expect(evaluation_result).to have_coherent_output
    end

    it "supports custom threshold" do
      expect(evaluation_result).to have_coherent_output.with_threshold(0.5)
    end
  end

  describe "not_hallucinate matcher" do
    it "detects absence of hallucinations" do
      expect(evaluation_result).to_not not_hallucinate
    end
  end
end
