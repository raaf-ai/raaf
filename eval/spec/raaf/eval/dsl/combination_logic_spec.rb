# frozen_string_literal: true

RSpec.describe RAAF::Eval::DSL::CombinationLogic do
  describe ".combine_and" do
    context "when all evaluators pass" do
      let(:evaluator_results) do
        [
          { label: "good", score: 0.9, details: { check1: "pass" }, message: "Check 1 passed" },
          { label: "good", score: 0.8, details: { check2: "pass" }, message: "Check 2 passed" },
          { label: "good", score: 0.85, details: { check3: "pass" }, message: "Check 3 passed" }
        ]
      end

      it "returns passed result" do
        result = described_class.combine_and(evaluator_results)
        expect(result[:label]).to eq("good")
      end

      it "uses minimum score" do
        result = described_class.combine_and(evaluator_results)
        expect(result[:score]).to eq(0.8)
      end

      it "merges details from all evaluators" do
        result = described_class.combine_and(evaluator_results)
        expect(result[:details]).to include(:check1, :check2, :check3)
      end

      it "combines messages with AND prefix" do
        result = described_class.combine_and(evaluator_results)
        expect(result[:message]).to include("AND:")
        expect(result[:message]).to include("Check 1 passed")
        expect(result[:message]).to include("Check 2 passed")
        expect(result[:message]).to include("Check 3 passed")
      end
    end

    context "when one evaluator fails" do
      let(:evaluator_results) do
        [
          { label: "good", score: 0.9, details: { check1: "pass" }, message: "Check 1 passed" },
          { label: "bad", score: 0.5, details: { check2: "fail" }, message: "Check 2 failed" },
          { label: "good", score: 0.85, details: { check3: "pass" }, message: "Check 3 passed" }
        ]
      end

      it "returns failed result" do
        result = described_class.combine_and(evaluator_results)
        expect(result[:label]).to eq("bad")
      end

      it "uses minimum score" do
        result = described_class.combine_and(evaluator_results)
        expect(result[:score]).to eq(0.5)
      end
    end

    context "when all evaluators fail" do
      let(:evaluator_results) do
        [
          { label: "bad", score: 0.4, details: {}, message: "Check 1 failed" },
          { label: "bad", score: 0.3, details: {}, message: "Check 2 failed" }
        ]
      end

      it "returns failed result" do
        result = described_class.combine_and(evaluator_results)
        expect(result[:label]).to eq("bad")
      end

      it "uses minimum score" do
        result = described_class.combine_and(evaluator_results)
        expect(result[:score]).to eq(0.3)
      end
    end
  end

  describe ".combine_or" do
    context "when all evaluators pass" do
      let(:evaluator_results) do
        [
          { label: "good", score: 0.9, details: { check1: "pass" }, message: "Check 1 passed" },
          { label: "good", score: 0.8, details: { check2: "pass" }, message: "Check 2 passed" }
        ]
      end

      it "returns passed result" do
        result = described_class.combine_or(evaluator_results)
        expect(result[:label]).to eq("good")
      end

      it "uses maximum score" do
        result = described_class.combine_or(evaluator_results)
        expect(result[:score]).to eq(0.9)
      end

      it "includes only passing messages" do
        result = described_class.combine_or(evaluator_results)
        expect(result[:message]).to include("OR:")
        expect(result[:message]).to include("Check 1 passed")
        expect(result[:message]).to include("Check 2 passed")
      end
    end

    context "when one evaluator passes" do
      let(:evaluator_results) do
        [
          { label: "bad", score: 0.4, details: { check1: "fail" }, message: "Check 1 failed" },
          { label: "good", score: 0.85, details: { check2: "pass" }, message: "Check 2 passed" },
          { label: "bad", score: 0.3, details: { check3: "fail" }, message: "Check 3 failed" }
        ]
      end

      it "returns passed result" do
        result = described_class.combine_or(evaluator_results)
        expect(result[:label]).to eq("good")
      end

      it "uses maximum score" do
        result = described_class.combine_or(evaluator_results)
        expect(result[:score]).to eq(0.85)
      end

      it "includes only passing messages" do
        result = described_class.combine_or(evaluator_results)
        expect(result[:message]).to include("Check 2 passed")
        expect(result[:message]).not_to include("Check 1 failed")
        expect(result[:message]).not_to include("Check 3 failed")
      end
    end

    context "when all evaluators fail" do
      let(:evaluator_results) do
        [
          { label: "bad", score: 0.4, details: {}, message: "Check 1 failed" },
          { label: "bad", score: 0.3, details: {}, message: "Check 2 failed" }
        ]
      end

      it "returns failed result" do
        result = described_class.combine_or(evaluator_results)
        expect(result[:label]).to eq("bad")
      end

      it "uses maximum score of failed evaluators" do
        result = described_class.combine_or(evaluator_results)
        expect(result[:score]).to eq(0.4)
      end

      it "includes all messages when all failed" do
        result = described_class.combine_or(evaluator_results)
        expect(result[:message]).to include("Check 1 failed")
        expect(result[:message]).to include("Check 2 failed")
      end
    end
  end

  describe ".combine_lambda" do
    context "with weighted average calculation" do
      let(:evaluator_results) do
        {
          similarity: { label: "good", score: 0.9, details: {}, message: "High similarity" },
          coherence: { label: "good", score: 0.7, details: {}, message: "Good coherence" }
        }
      end

      let(:lambda_proc) do
        lambda { |results|
          similarity_weight = 0.7
          coherence_weight = 0.3

          combined_score = (results[:similarity][:score] * similarity_weight) +
                           (results[:coherence][:score] * coherence_weight)

          {
            label: combined_score >= 0.8 ? "good" : (combined_score >= 0.6 ? "average" : "bad"),
            score: combined_score,
            details: {
              similarity: results[:similarity],
              coherence: results[:coherence],
              weights: { similarity: similarity_weight, coherence: coherence_weight }
            },
            message: "Weighted quality score: #{(combined_score * 100).round(2)}%"
          }
        }
      end

      it "calculates weighted average correctly" do
        result = described_class.combine_lambda(evaluator_results, lambda_proc)
        expected_score = (0.9 * 0.7) + (0.7 * 0.3)
        expect(result[:score]).to eq(expected_score)
      end

      it "returns passed when threshold met" do
        result = described_class.combine_lambda(evaluator_results, lambda_proc)
        expect(result[:label]).to eq("good")
      end

      it "includes detailed breakdown" do
        result = described_class.combine_lambda(evaluator_results, lambda_proc)
        expect(result[:details][:weights]).to eq({ similarity: 0.7, coherence: 0.3 })
      end
    end

    context "with conditional requirements logic" do
      let(:evaluator_results) do
        {
          primary: { label: "good", score: 0.9, details: {}, message: "Primary check passed" },
          secondary: { label: "bad", score: 0.5, details: {}, message: "Secondary check failed" }
        }
      end

      let(:lambda_proc) do
        lambda { |results|
          # Primary must pass, secondary is optional bonus
          base_pass = results[:primary][:label] != "bad"
          bonus = results[:secondary][:label] != "bad" ? 0.1 : 0
          final_score = results[:primary][:score] + bonus

          {
            label: base_pass ? "good" : "bad",
            score: final_score,
            details: { primary: results[:primary], secondary: results[:secondary] },
            message: "Primary: #{base_pass}, Secondary bonus: #{bonus}"
          }
        }
      end

      it "returns label 'good' when primary passes even if secondary fails" do
        result = described_class.combine_lambda(evaluator_results, lambda_proc)
        expect(result[:label]).to eq("good")
      end

      it "calculates score with conditional bonus" do
        result = described_class.combine_lambda(evaluator_results, lambda_proc)
        expect(result[:score]).to eq(0.9) # No bonus since secondary failed
      end
    end

    context "with bonus scoring logic" do
      let(:evaluator_results) do
        {
          baseline: { label: "good", score: 0.7, details: {}, message: "Baseline met" },
          excellence: { label: "good", score: 0.95, details: {}, message: "Excellence achieved" }
        }
      end

      let(:lambda_proc) do
        lambda { |results|
          base_score = results[:baseline][:score]
          excellence_score = results[:excellence][:score]

          # Award bonus if excellence threshold met
          bonus = excellence_score >= 0.9 ? 0.2 : 0
          final_score = [base_score + bonus, 1.0].min

          {
            label: results[:baseline][:label],
            score: final_score,
            details: { bonus_awarded: bonus > 0 },
            message: "Score: #{final_score} (bonus: #{bonus})"
          }
        }
      end

      it "awards bonus for excellence" do
        result = described_class.combine_lambda(evaluator_results, lambda_proc)
        expect(result[:score]).to be_within(0.001).of(0.9) # 0.7 + 0.2 bonus
        expect(result[:details][:bonus_awarded]).to be true
      end
    end

    context "with invalid lambda result" do
      let(:evaluator_results) do
        { test: { label: "good", score: 0.9, details: {}, message: "Test" } }
      end

      let(:invalid_lambda) do
        lambda { |_results| { label: "good" } } # Missing required fields
      end

      it "raises error for missing required fields" do
        expect {
          described_class.combine_lambda(evaluator_results, invalid_lambda)
        }.to raise_error(RAAF::Eval::DSL::InvalidLambdaResultError)
      end
    end
  end
end
