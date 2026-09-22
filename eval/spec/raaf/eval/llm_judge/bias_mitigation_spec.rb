# frozen_string_literal: true

require "spec_helper"
require "raaf/eval/llm_judge"

RSpec.describe RAAF::Eval::LLMJudge::BiasMitigation do
  describe RAAF::Eval::LLMJudge::BiasMitigation::PositionDebiaser do
    let(:judge) { RAAF::Eval::LLMJudge::StatisticalJudge.new(model: "gpt-4o") }
    let(:debiaser) { described_class.new(judge: judge, permutations: 2) }

    # The debiaser asks the same question twice with the outputs swapped, and the
    # judge sees nothing but the prompt. Reading the two outputs back out of it is
    # what lets a stub hold an opinion about the text ("this one is better") or
    # about the position ("whichever came first"), which is the pair of behaviours
    # #compare exists to tell apart. Left to a real model there is no API key, every
    # judgement fails into "did not pass", and both orderings agree by accident.
    def judge_answers(confidence: 0.9, &prefers_first)
      allow(judge).to receive(:evaluate) do |input:, **|
        first, second = input.scan(/## Output [AB]\n(.+?)\n\n/m).flatten

        {
          passed: prefers_first.call(first, second),
          confidence: confidence.respond_to?(:call) ? confidence.call(first) : confidence,
          reasoning: "preferred #{prefers_first.call(first, second) ? first : second}"
        }
      end
    end

    describe "#compare" do
      let(:input) { "Write a greeting" }
      let(:output_a) { "Hello, how are you today?" }
      let(:output_b) { "Hi there!" }
      let(:criteria) { "Which greeting is more friendly and warm?" }

      def compare
        debiaser.compare(input: input, output_a: output_a, output_b: output_b, criteria: criteria)
      end

      it "picks the output the judge preferred in both orderings" do
        judge_answers { |first, _second| first == output_a }

        expect(compare).to include(
          winner: :a,
          consistent: true,
          position_bias_detected: false,
          confidence: 0.9
        )
      end

      it "picks the other output when that is the one preferred" do
        judge_answers { |first, _second| first == output_b }

        expect(compare).to include(winner: :b, consistent: true)
      end

      # A judge that always prefers whatever it read first contradicts itself the
      # moment the order is swapped. That contradiction is the measurement.
      it "detects position bias and calls the result a tie" do
        judge_answers { |_first, _second| true }

        expect(compare).to include(
          winner: :tie,
          consistent: false,
          position_bias_detected: true,
          confidence: 0.45 # halved for the contradiction, capped at 0.5
        )
      end

      # Unless one ordering was much more sure of itself, in which case it wins.
      it "follows the confident ordering when one is far surer than the other" do
        judge_answers(confidence: ->(first) { first == output_a ? 0.95 : 0.5 }) { true }

        expect(compare).to include(winner: :a, consistent: false, position_bias_detected: true)
      end

      it "reports which ordering said what" do
        judge_answers { |first, _second| first == output_a }

        result = compare

        expect(result[:forward_result]).to include(first_label: "A", second_label: "B", prefers_first: true)
        expect(result[:reverse_result]).to include(first_label: "B", second_label: "A", prefers_first: false)
        expect(result[:reasoning]).to start_with("Both orderings agree:")
      end

      it "says so in the reasoning when the orderings disagree" do
        judge_answers { |_first, _second| true }

        expect(compare[:reasoning]).to start_with("Position bias detected.")
      end
    end

    describe "#rank" do
      let(:input) { "Explain Ruby" }
      let(:outputs) { ["Ruby is a language", "Ruby is great!", "Ruby = programming"] }
      let(:criteria) { "Which explanation is clearest?" }

      # A judge with a settled order of preference, so the ranking has a right answer.
      before do
        order = { outputs[2] => 3, outputs[0] => 2, outputs[1] => 1 }
        judge_answers { |first, second| order.fetch(first) > order.fetch(second) }
      end

      it "ranks the outputs by how often each one won" do
        result = debiaser.rank(input: input, outputs: outputs, criteria: criteria)

        expect(result[:ranking]).to eq(
          [
            { index: 2, output: outputs[2], score: 2 },
            { index: 0, output: outputs[0], score: 1 },
            { index: 1, output: outputs[1], score: 0 }
          ]
        )
      end

      it "compares every pair once, in both orderings" do
        result = debiaser.rank(input: input, outputs: outputs, criteria: criteria)

        expect(result[:total_comparisons]).to eq(3) # 3 outputs -> 3 pairs
        expect(result[:comparisons].map { |c| c[:pair] }).to eq([[0, 1], [0, 2], [1, 2]])
        expect(result[:position_bias_count]).to eq(0) # this judge has a real preference
        expect(judge).to have_received(:evaluate).exactly(6).times # each pair, each way
      end

      it "counts the pairs the judge contradicted itself on" do
        judge_answers { |_first, _second| true }

        result = debiaser.rank(input: input, outputs: outputs, criteria: criteria)

        expect(result[:position_bias_count]).to eq(3)
        expect(result[:ranking].map { |r| r[:score] }).to all(eq(1.0)) # every pair a tie
      end
    end
  end

  describe RAAF::Eval::LLMJudge::BiasMitigation::LengthBiasAnalyzer do
    let(:analyzer) { described_class.new }

    describe "#analyze_length_correlation" do
      context "with length-correlated scores (bias present)" do
        let(:evaluations) do
          # Longer outputs get higher scores
          (1..20).map do |i|
            {
              output: "A" * (i * 10),  # Increasing length
              score: 0.4 + (i * 0.03)  # Increasing score
            }
          end
        end

        it "detects length bias" do
          analysis = analyzer.analyze_length_correlation(evaluations)

          expect(analysis[:correlation]).to be > 0.5
          expect(analysis[:bias_detected]).to be true
          expect(analysis[:bias_direction]).to eq(:prefers_longer)
        end

        it "returns correlation strength" do
          analysis = analyzer.analyze_length_correlation(evaluations)

          expect(analysis[:bias_strength]).to be_in(%i[weak moderate strong very_strong])
        end

        it "includes length statistics" do
          analysis = analyzer.analyze_length_correlation(evaluations)

          expect(analysis[:length_stats]).to have_key(:min)
          expect(analysis[:length_stats]).to have_key(:max)
          expect(analysis[:length_stats]).to have_key(:mean)
          expect(analysis[:length_stats]).to have_key(:std)
        end
      end

      context "with no length correlation (no bias)" do
        let(:evaluations) do
          (1..20).map do |_i|
            {
              output: "A" * rand(10..100),  # Random length
              score: rand(0.4..0.9)         # Random score
            }
          end
        end

        it "reports low correlation" do
          analysis = analyzer.analyze_length_correlation(evaluations)

          # With random data, correlation should be low
          expect(analysis[:correlation].abs).to be < 0.7
        end
      end
    end

    describe "#normalize_for_length" do
      let(:biased_evaluations) do
        (1..10).map do |i|
          {
            output: "A" * (i * 20),
            score: 0.5 + (i * 0.04)
          }
        end
      end

      it "returns normalized scores when bias is detected" do
        normalized = analyzer.normalize_for_length(biased_evaluations)

        expect(normalized.size).to eq(10)
        normalized.each do |item|
          expect(item).to have_key(:output)
          expect(item).to have_key(:original_score)
          expect(item).to have_key(:normalized_score)
          expect(item).to have_key(:adjustment)
          expect(item[:normalized_score]).to be_between(0.0, 1.0)
        end
      end

      it "returns original evaluations when no bias" do
        unbiased = [
          { output: "Short", score: 0.8 },
          { output: "Very long response here", score: 0.7 }
        ]

        result = analyzer.normalize_for_length(unbiased)

        # With only 2 samples, no reliable bias detection
        expect(result).to eq(unbiased)
      end
    end
  end

  describe RAAF::Eval::LLMJudge::BiasMitigation::FormatBiasAnalyzer do
    let(:analyzer) { described_class.new }

    describe "#analyze" do
      let(:evaluations) do
        [
          { output: "# Header\n\nText with **bold**", score: 0.9 },
          { output: "- Item 1\n- Item 2", score: 0.85 },
          { output: "```ruby\ncode\n```", score: 0.8 },
          { output: "Plain text response", score: 0.5 },
          { output: "Simple answer", score: 0.55 },
          { output: "## Another\n\n**formatted** `code`", score: 0.88 },
          { output: "No formatting here", score: 0.48 },
          { output: "1. First\n2. Second", score: 0.82 }
        ]
      end

      it "analyzes multiple format features" do
        analysis = analyzer.analyze(evaluations)

        expect(analysis).to have_key(:format_biases)
        expect(analysis[:format_biases]).to have_key(:markdown_headers)
        expect(analysis[:format_biases]).to have_key(:bullet_lists)
        expect(analysis[:format_biases]).to have_key(:code_blocks)
        expect(analysis[:format_biases]).to have_key(:bold_text)
      end

      it "reports correlation for each feature" do
        analysis = analyzer.analyze(evaluations)

        analysis[:format_biases].each_value do |details|
          expect(details).to have_key(:correlation)
          expect(details).to have_key(:bias_detected)
          expect(details).to have_key(:direction)
          expect(details).to have_key(:feature_frequency)
        end
      end

      it "identifies significant biases" do
        analysis = analyzer.analyze(evaluations)

        expect(analysis).to have_key(:significant_biases)
        expect(analysis[:significant_biases]).to be_an(Array)
        expect(analysis).to have_key(:bias_count)
      end
    end
  end

  describe RAAF::Eval::LLMJudge::BiasMitigation::ConsistencyChecker do
    let(:judge) { RAAF::Eval::LLMJudge::StatisticalJudge.new(model: "gpt-4o", temperature: 0.0) }
    let(:checker) { described_class.new(judge: judge, repetitions: 3) }

    # The checker asks the same question repeatedly and reports how far the answers
    # drift. Scripting the answers per call is the only way to have a drift to
    # measure: a real judge here has no API key, fails identically every time, and
    # reads as perfectly consistent.
    def judge_says(*answers)
      replies = answers.map do |(passed, confidence)|
        { passed: passed, confidence: confidence, reasoning: "stubbed" }
      end

      allow(judge).to receive(:evaluate).and_return(*replies)
    end

    describe "#check" do
      let(:criteria) { "Is the answer correct?" }

      def check
        checker.check(input: "What is 2+2?", output: "4", criteria: criteria)
      end

      it "calls the judge once per repetition and keeps every answer" do
        judge_says([true, 0.9], [true, 0.9], [true, 0.9])

        expect(check[:individual_results].size).to eq(3)
        expect(judge).to have_received(:evaluate).exactly(3).times
      end

      it "reports a judge that answers the same way every time as consistent" do
        judge_says([true, 0.9], [true, 0.8], [true, 0.7])

        expect(check).to include(
          consistent: true,
          agreement_rate: 1.0,
          passed_ratio: 1.0,
          mean_confidence: be_within(0.001).of(0.8)
        )
      end

      # Agreeing that the output fails is just as consistent as agreeing it passes.
      it "counts unanimous failure as consistent too" do
        judge_says([false, 0.6], [false, 0.6], [false, 0.6])

        expect(check).to include(consistent: true, passed_ratio: 0.0, agreement_rate: 1.0)
      end

      it "reports a judge that changes its mind as inconsistent" do
        judge_says([true, 0.9], [false, 0.9], [true, 0.9])

        result = check

        expect(result).to include(consistent: false, agreement_rate: be_within(0.001).of(2.0 / 3))
        expect(result[:passed_ratio]).to be_within(0.001).of(2.0 / 3)
      end

      it "measures how much the judge's confidence moved" do
        judge_says([true, 0.5], [true, 0.7], [true, 0.9])

        # Sample variance of 0.5, 0.7, 0.9 is 0.04.
        expect(check[:confidence_variance]).to be_within(0.0001).of(0.04)
      end

      it "reports no variance when the confidence never moved" do
        judge_says([true, 0.8], [true, 0.8], [true, 0.8])

        expect(check[:confidence_variance]).to be_within(1e-12).of(0.0)
      end
    end

    # The regression the checker shipped with: a judge caches its answers by
    # input, so asking it the same question three times used to return one model
    # call and two copies of its answer, and every judge measured as perfectly
    # consistent. This one goes through the real cache rather than stubbing over it.
    context "with a judge that caches, asked through #evaluate" do
      # The judge above caches by default; this group answers a step lower down,
      # at the model call, so the cache decision is the code under test.
      before do
        allow(judge).to receive(:call_judge_model).and_return(
          { passed: true, confidence: 0.9, reasoning: "yes" }.to_json,
          { passed: false, confidence: 0.4, reasoning: "no" }.to_json,
          { passed: true, confidence: 0.8, reasoning: "yes again" }.to_json
        )
      end

      it "asks the model once per repetition and sees the judge change its mind" do
        result = checker.check(input: "What is 2+2?", output: "4", criteria: "Is the answer correct?")

        expect(judge).to have_received(:call_judge_model).exactly(3).times
        expect(result).to include(consistent: false, agreement_rate: be_within(0.001).of(2.0 / 3))
        expect(result[:individual_results].map { |r| r[:passed] }).to eq([true, false, true])
      end
    end

    describe "#check_batch" do
      let(:samples) do
        [
          { input: "Q1", output: "A1" },
          { input: "Q2", output: "A2" },
          { input: "Q3", output: "A3" }
        ]
      end
      let(:criteria) { "Is this correct?" }

      # Nine answers, three per sample: the second sample is the one the judge
      # cannot make its mind up about.
      before do
        judge_says(
          [true, 0.9], [true, 0.9], [true, 0.9],
          [true, 0.9], [false, 0.9], [true, 0.9],
          [false, 0.9], [false, 0.9], [false, 0.9]
        )
      end

      it "reports the share of samples the judge was steady on" do
        result = checker.check_batch(samples, criteria: criteria)

        expect(result[:overall_consistency_rate]).to be_within(0.001).of(2.0 / 3)
        expect(result[:mean_agreement_rate]).to be_within(0.001).of((1.0 + (2.0 / 3) + 1.0) / 3)
      end

      it "names the sample it was not steady on" do
        result = checker.check_batch(samples, criteria: criteria)

        expect(result[:inconsistent_samples].size).to eq(1)
        expect(result[:inconsistent_samples].first).to include(index: 1, sample: samples[1])
        expect(result[:inconsistent_samples].first[:result]).to include(consistent: false)
      end
    end
  end
end
