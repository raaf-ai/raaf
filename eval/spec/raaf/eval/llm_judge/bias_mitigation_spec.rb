# frozen_string_literal: true

require "spec_helper"
require "raaf/eval/llm_judge"

RSpec.describe RAAF::Eval::LLMJudge::BiasMitigation do
  describe RAAF::Eval::LLMJudge::BiasMitigation::PositionDebiaser do
    let(:judge) { RAAF::Eval::LLMJudge::StatisticalJudge.new(model: "gpt-4o") }
    let(:debiaser) { described_class.new(judge: judge, permutations: 2) }

    describe "#compare", :vcr do
      let(:input) { "Write a greeting" }
      let(:output_a) { "Hello, how are you today?" }
      let(:output_b) { "Hi there!" }
      let(:criteria) { "Which greeting is more friendly and warm?" }

      it "returns comparison result with debiasing" do
        result = debiaser.compare(
          input: input,
          output_a: output_a,
          output_b: output_b,
          criteria: criteria
        )

        expect(result).to have_key(:winner)
        expect(result[:winner]).to be_in([:a, :b, :tie])
        expect(result).to have_key(:confidence)
        expect(result).to have_key(:consistent)
        expect(result).to have_key(:position_bias_detected)
        expect(result).to have_key(:forward_result)
        expect(result).to have_key(:reverse_result)
      end

      it "includes reasoning" do
        result = debiaser.compare(
          input: input,
          output_a: output_a,
          output_b: output_b,
          criteria: criteria
        )

        expect(result).to have_key(:reasoning)
        expect(result[:reasoning]).to be_a(String)
      end
    end

    describe "#rank", :vcr do
      let(:input) { "Explain Ruby" }
      let(:outputs) { ["Ruby is a language", "Ruby is great!", "Ruby = programming"] }
      let(:criteria) { "Which explanation is clearest?" }

      it "returns ranking with position bias analysis" do
        result = debiaser.rank(
          input: input,
          outputs: outputs,
          criteria: criteria
        )

        expect(result).to have_key(:ranking)
        expect(result[:ranking].size).to eq(3)
        expect(result).to have_key(:comparisons)
        expect(result).to have_key(:position_bias_count)
        expect(result).to have_key(:total_comparisons)
      end

      it "assigns scores to each output" do
        result = debiaser.rank(
          input: input,
          outputs: outputs,
          criteria: criteria
        )

        result[:ranking].each do |item|
          expect(item).to have_key(:index)
          expect(item).to have_key(:output)
          expect(item).to have_key(:score)
        end
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

          expect(analysis[:bias_strength]).to be_in([:weak, :moderate, :strong, :very_strong])
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
          (1..20).map do |i|
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

    describe "#check", :vcr do
      let(:sample) { { input: "What is 2+2?", output: "4" } }
      let(:criteria) { "Is the answer correct?" }

      it "returns consistency analysis" do
        result = checker.check(
          input: sample[:input],
          output: sample[:output],
          criteria: criteria
        )

        expect(result).to have_key(:consistent)
        expect(result).to have_key(:agreement_rate)
        expect(result).to have_key(:passed_ratio)
        expect(result).to have_key(:confidence_variance)
        expect(result).to have_key(:mean_confidence)
        expect(result).to have_key(:individual_results)
      end

      it "returns valid agreement rate" do
        result = checker.check(
          input: sample[:input],
          output: sample[:output],
          criteria: criteria
        )

        expect(result[:agreement_rate]).to be_between(0.0, 1.0)
      end

      it "includes individual results" do
        result = checker.check(
          input: sample[:input],
          output: sample[:output],
          criteria: criteria
        )

        expect(result[:individual_results].size).to eq(3)
      end
    end

    describe "#check_batch", :vcr do
      let(:samples) do
        [
          { input: "Q1", output: "A1" },
          { input: "Q2", output: "A2" },
          { input: "Q3", output: "A3" }
        ]
      end
      let(:criteria) { "Is this correct?" }

      it "returns aggregate consistency statistics" do
        result = checker.check_batch(samples, criteria: criteria)

        expect(result).to have_key(:overall_consistency_rate)
        expect(result).to have_key(:mean_agreement_rate)
        expect(result).to have_key(:mean_confidence_variance)
        expect(result).to have_key(:inconsistent_samples)
      end

      it "identifies inconsistent samples" do
        result = checker.check_batch(samples, criteria: criteria)

        expect(result[:inconsistent_samples]).to be_an(Array)
        result[:inconsistent_samples].each do |item|
          expect(item).to have_key(:index)
          expect(item).to have_key(:sample)
          expect(item).to have_key(:result)
        end
      end
    end
  end
end
