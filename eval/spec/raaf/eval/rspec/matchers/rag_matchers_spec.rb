# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../../lib/raaf/eval/rspec/matchers/rag_matchers"

RSpec.describe "RAG Matchers" do
  include RAAF::Eval::RSpec::Matchers::RAGMatchers
  # Helper to create mock evaluation results
  def mock_relevancy_result(score:, query: "What is AI?")
    {
      label: score >= 0.75 ? "good" : (score >= 0.50 ? "average" : "bad"),
      score: score,
      message: "Contextual relevancy: #{(score * 100).round}%",
      details: {
        evaluated_field: :context,
        method: "contextual_relevancy",
        query: query,
        context_preview: "AI is artificial intelligence...",
        context_length: 150,
        relevancy_reasoning: "The context is highly relevant to the query."
      }
    }
  end

  def mock_precision_result(score:, relevant_count:, irrelevant_count:, query: "What is ML?")
    total = relevant_count + irrelevant_count
    {
      label: score >= 0.75 ? "good" : (score >= 0.50 ? "average" : "bad"),
      score: score,
      message: "Contextual precision: #{(score * 100).round}%",
      details: {
        evaluated_field: :context,
        method: "contextual_precision",
        query: query,
        document_count: total,
        relevant_count: relevant_count,
        irrelevant_count: irrelevant_count,
        document_relevance: Array.new(total) { |i|
          { index: i, relevant: i < relevant_count }
        },
        precision_reasoning: "Precision analysis complete."
      }
    }
  end

  def mock_recall_result(score:, retrieved_relevant:, missed_relevant:, query: "What is DL?")
    {
      label: score >= 0.75 ? "good" : (score >= 0.50 ? "average" : "bad"),
      score: score,
      message: "Contextual recall: #{(score * 100).round}%",
      details: {
        evaluated_field: :context,
        method: "contextual_recall",
        query: query,
        retrieved_count: retrieved_relevant + 2,  # Add some irrelevant
        available_count: retrieved_relevant + missed_relevant + 3,  # Add some irrelevant
        relevant_count: retrieved_relevant + missed_relevant,
        retrieved_relevant_count: retrieved_relevant,
        missed_relevant_count: missed_relevant,
        document_analysis: [],
        recall_reasoning: "Recall analysis complete."
      }
    }
  end

  describe "have_high_contextual_relevancy" do
    it "passes when score meets default threshold (0.75)" do
      result = mock_relevancy_result(score: 0.80)
      expect(result).to have_high_contextual_relevancy
    end

    it "passes when score meets custom threshold" do
      result = mock_relevancy_result(score: 0.70)
      expect(result).to have_high_contextual_relevancy(min_score: 0.65)
    end

    it "fails when score is below default threshold" do
      result = mock_relevancy_result(score: 0.60)
      expect(result).not_to have_high_contextual_relevancy
    end

    it "fails when score is below custom threshold" do
      result = mock_relevancy_result(score: 0.70)
      expect(result).not_to have_high_contextual_relevancy(min_score: 0.80)
    end

    it "fails when method is not contextual_relevancy" do
      result = mock_precision_result(score: 0.90, relevant_count: 9, irrelevant_count: 1)
      expect(result).not_to have_high_contextual_relevancy
    end

    it "provides helpful failure message" do
      result = mock_relevancy_result(score: 0.60)
      expect {
        expect(result).to have_high_contextual_relevancy
      }.to raise_error(RSpec::Expectations::ExpectationNotMetError, /Expected contextual relevancy score to be at least 75%, but got 60%/)
    end
  end

  describe "have_high_precision" do
    it "passes when score meets default threshold (0.75)" do
      result = mock_precision_result(score: 0.80, relevant_count: 8, irrelevant_count: 2)
      expect(result).to have_high_precision
    end

    it "passes when score meets custom threshold" do
      result = mock_precision_result(score: 0.70, relevant_count: 7, irrelevant_count: 3)
      expect(result).to have_high_precision(min_score: 0.65)
    end

    it "fails when score is below default threshold" do
      result = mock_precision_result(score: 0.60, relevant_count: 6, irrelevant_count: 4)
      expect(result).not_to have_high_precision
    end

    it "fails when method is not contextual_precision" do
      result = mock_relevancy_result(score: 0.90)
      expect(result).not_to have_high_precision
    end

    it "provides helpful failure message" do
      result = mock_precision_result(score: 0.60, relevant_count: 6, irrelevant_count: 4)
      expect {
        expect(result).to have_high_precision
      }.to raise_error(RSpec::Expectations::ExpectationNotMetError, /Expected contextual precision score to be at least 75%, but got 60%/)
    end
  end

  describe "have_high_recall" do
    it "passes when score meets default threshold (0.75)" do
      result = mock_recall_result(score: 0.80, retrieved_relevant: 8, missed_relevant: 2)
      expect(result).to have_high_recall
    end

    it "passes when score meets custom threshold" do
      result = mock_recall_result(score: 0.70, retrieved_relevant: 7, missed_relevant: 3)
      expect(result).to have_high_recall(min_score: 0.65)
    end

    it "fails when score is below default threshold" do
      result = mock_recall_result(score: 0.60, retrieved_relevant: 6, missed_relevant: 4)
      expect(result).not_to have_high_recall
    end

    it "fails when method is not contextual_recall" do
      result = mock_precision_result(score: 0.90, relevant_count: 9, irrelevant_count: 1)
      expect(result).not_to have_high_recall
    end

    it "provides helpful failure message" do
      result = mock_recall_result(score: 0.60, retrieved_relevant: 6, missed_relevant: 4)
      expect {
        expect(result).to have_high_recall
      }.to raise_error(RSpec::Expectations::ExpectationNotMetError, /Expected contextual recall score to be at least 75%, but got 60%/)
    end
  end

  describe "have_minimal_irrelevant_documents" do
    it "passes when irrelevant count is within default limit (2)" do
      result = mock_precision_result(score: 0.90, relevant_count: 9, irrelevant_count: 1)
      expect(result).to have_minimal_irrelevant_documents
    end

    it "passes when irrelevant count is exactly at limit" do
      result = mock_precision_result(score: 0.80, relevant_count: 8, irrelevant_count: 2)
      expect(result).to have_minimal_irrelevant_documents
    end

    it "passes when irrelevant count is within custom limit" do
      result = mock_precision_result(score: 0.70, relevant_count: 7, irrelevant_count: 3)
      expect(result).to have_minimal_irrelevant_documents(max_count: 5)
    end

    it "fails when irrelevant count exceeds default limit" do
      result = mock_precision_result(score: 0.70, relevant_count: 7, irrelevant_count: 3)
      expect(result).not_to have_minimal_irrelevant_documents
    end

    it "fails when irrelevant count exceeds custom limit" do
      result = mock_precision_result(score: 0.80, relevant_count: 8, irrelevant_count: 2)
      expect(result).not_to have_minimal_irrelevant_documents(max_count: 1)
    end

    it "fails when method is not contextual_precision" do
      result = mock_recall_result(score: 0.90, retrieved_relevant: 9, missed_relevant: 1)
      expect(result).not_to have_minimal_irrelevant_documents
    end

    it "provides helpful failure message" do
      result = mock_precision_result(score: 0.70, relevant_count: 7, irrelevant_count: 3)
      expect {
        expect(result).to have_minimal_irrelevant_documents
      }.to raise_error(RSpec::Expectations::ExpectationNotMetError, /Expected at most 2 irrelevant documents, but got 3/)
    end
  end

  describe "have_minimal_missed_documents" do
    it "passes when missed count is within default limit (1)" do
      result = mock_recall_result(score: 0.90, retrieved_relevant: 9, missed_relevant: 1)
      expect(result).to have_minimal_missed_documents
    end

    it "passes when missed count is exactly at limit" do
      result = mock_recall_result(score: 0.90, retrieved_relevant: 9, missed_relevant: 1)
      expect(result).to have_minimal_missed_documents
    end

    it "passes when missed count is within custom limit" do
      result = mock_recall_result(score: 0.70, retrieved_relevant: 7, missed_relevant: 3)
      expect(result).to have_minimal_missed_documents(max_count: 5)
    end

    it "fails when missed count exceeds default limit" do
      result = mock_recall_result(score: 0.80, retrieved_relevant: 8, missed_relevant: 2)
      expect(result).not_to have_minimal_missed_documents
    end

    it "fails when missed count exceeds custom limit" do
      result = mock_recall_result(score: 0.90, retrieved_relevant: 9, missed_relevant: 1)
      expect(result).not_to have_minimal_missed_documents(max_count: 0)
    end

    it "fails when method is not contextual_recall" do
      result = mock_precision_result(score: 0.90, relevant_count: 9, irrelevant_count: 1)
      expect(result).not_to have_minimal_missed_documents
    end

    it "provides helpful failure message" do
      result = mock_recall_result(score: 0.80, retrieved_relevant: 8, missed_relevant: 2)
      expect {
        expect(result).to have_minimal_missed_documents
      }.to raise_error(RSpec::Expectations::ExpectationNotMetError, /Expected at most 1 missed relevant documents, but got 2/)
    end
  end

  describe "be_valid_rag_result" do
    context "with contextual_relevancy result" do
      it "passes for valid result structure" do
        result = mock_relevancy_result(score: 0.80)
        expect(result).to be_valid_rag_result
      end

      it "fails when missing label" do
        result = mock_relevancy_result(score: 0.80)
        result.delete(:label)
        expect(result).not_to be_valid_rag_result
      end

      it "fails when missing required detail fields" do
        result = mock_relevancy_result(score: 0.80)
        result[:details].delete(:context_preview)
        expect(result).not_to be_valid_rag_result
      end
    end

    context "with contextual_precision result" do
      it "passes for valid result structure" do
        result = mock_precision_result(score: 0.80, relevant_count: 8, irrelevant_count: 2)
        expect(result).to be_valid_rag_result
      end

      it "fails when missing document_relevance array" do
        result = mock_precision_result(score: 0.80, relevant_count: 8, irrelevant_count: 2)
        result[:details].delete(:document_relevance)
        expect(result).not_to be_valid_rag_result
      end

      it "fails when document counts are not integers" do
        result = mock_precision_result(score: 0.80, relevant_count: 8, irrelevant_count: 2)
        result[:details][:document_count] = "10"
        expect(result).not_to be_valid_rag_result
      end
    end

    context "with contextual_recall result" do
      it "passes for valid result structure" do
        result = mock_recall_result(score: 0.80, retrieved_relevant: 8, missed_relevant: 2)
        expect(result).to be_valid_rag_result
      end

      it "fails when missing document_analysis array" do
        result = mock_recall_result(score: 0.80, retrieved_relevant: 8, missed_relevant: 2)
        result[:details].delete(:document_analysis)
        expect(result).not_to be_valid_rag_result
      end

      it "fails when counts are not integers" do
        result = mock_recall_result(score: 0.80, retrieved_relevant: 8, missed_relevant: 2)
        result[:details][:retrieved_count] = "10"
        expect(result).not_to be_valid_rag_result
      end
    end

    it "fails for invalid method type" do
      result = mock_relevancy_result(score: 0.80)
      result[:details][:method] = "invalid_method"
      expect(result).not_to be_valid_rag_result
    end

    it "provides detailed failure message listing all issues" do
      result = {
        label: nil,
        score: 0.80,
        message: "test",
        details: {
          method: "contextual_relevancy"
        }
      }

      expect {
        expect(result).to be_valid_rag_result
      }.to raise_error(RSpec::Expectations::ExpectationNotMetError, /Missing label.*Missing or invalid query/m)
    end
  end

  describe "have_high_f1_score" do
    it "passes when F1 score meets default threshold (0.75)" do
      precision_result = mock_precision_result(score: 0.80, relevant_count: 8, irrelevant_count: 2)
      recall_result = mock_recall_result(score: 0.80, retrieved_relevant: 8, missed_relevant: 2)

      expect([precision_result, recall_result]).to have_high_f1_score
    end

    it "passes when F1 score meets custom threshold" do
      precision_result = mock_precision_result(score: 0.70, relevant_count: 7, irrelevant_count: 3)
      recall_result = mock_recall_result(score: 0.70, retrieved_relevant: 7, missed_relevant: 3)

      expect([precision_result, recall_result]).to have_high_f1_score(min_f1: 0.65)
    end

    it "fails when F1 score is below threshold" do
      precision_result = mock_precision_result(score: 0.60, relevant_count: 6, irrelevant_count: 4)
      recall_result = mock_recall_result(score: 0.60, retrieved_relevant: 6, missed_relevant: 4)

      expect([precision_result, recall_result]).not_to have_high_f1_score
    end

    it "handles imbalanced precision and recall" do
      precision_result = mock_precision_result(score: 0.90, relevant_count: 9, irrelevant_count: 1)
      recall_result = mock_recall_result(score: 0.50, retrieved_relevant: 5, missed_relevant: 5)

      # F1 = 2 * (0.90 * 0.50) / (0.90 + 0.50) = 2 * 0.45 / 1.40 ≈ 0.643
      expect([precision_result, recall_result]).not_to have_high_f1_score
    end

    it "fails when precision result is invalid" do
      precision_result = mock_relevancy_result(score: 0.90)
      recall_result = mock_recall_result(score: 0.80, retrieved_relevant: 8, missed_relevant: 2)

      expect([precision_result, recall_result]).not_to have_high_f1_score
    end

    it "fails when recall result is invalid" do
      precision_result = mock_precision_result(score: 0.80, relevant_count: 8, irrelevant_count: 2)
      recall_result = mock_relevancy_result(score: 0.90)

      expect([precision_result, recall_result]).not_to have_high_f1_score
    end

    it "provides helpful failure message with F1 calculation" do
      precision_result = mock_precision_result(score: 0.60, relevant_count: 6, irrelevant_count: 4)
      recall_result = mock_recall_result(score: 0.60, retrieved_relevant: 6, missed_relevant: 4)

      expect {
        expect([precision_result, recall_result]).to have_high_f1_score
      }.to raise_error(RSpec::Expectations::ExpectationNotMetError, /Expected F1 score to be at least 75%, but got 60% \(precision: 60%, recall: 60%\)/)
    end
  end

  describe "meet_all_rag_thresholds" do
    it "passes when all metrics meet default thresholds" do
      results = {
        relevancy: mock_relevancy_result(score: 0.80),
        precision: mock_precision_result(score: 0.80, relevant_count: 8, irrelevant_count: 2),
        recall: mock_recall_result(score: 0.80, retrieved_relevant: 8, missed_relevant: 2)
      }

      expect(results).to meet_all_rag_thresholds
    end

    it "passes when all metrics meet custom thresholds" do
      results = {
        relevancy: mock_relevancy_result(score: 0.70),
        precision: mock_precision_result(score: 0.70, relevant_count: 7, irrelevant_count: 3),
        recall: mock_recall_result(score: 0.70, retrieved_relevant: 7, missed_relevant: 3)
      }

      expect(results).to meet_all_rag_thresholds(relevancy: 0.65, precision: 0.65, recall: 0.65)
    end

    it "fails when relevancy is below threshold" do
      results = {
        relevancy: mock_relevancy_result(score: 0.60),
        precision: mock_precision_result(score: 0.80, relevant_count: 8, irrelevant_count: 2),
        recall: mock_recall_result(score: 0.80, retrieved_relevant: 8, missed_relevant: 2)
      }

      expect(results).not_to meet_all_rag_thresholds
    end

    it "fails when precision is below threshold" do
      results = {
        relevancy: mock_relevancy_result(score: 0.80),
        precision: mock_precision_result(score: 0.60, relevant_count: 6, irrelevant_count: 4),
        recall: mock_recall_result(score: 0.80, retrieved_relevant: 8, missed_relevant: 2)
      }

      expect(results).not_to meet_all_rag_thresholds
    end

    it "fails when recall is below threshold" do
      results = {
        relevancy: mock_relevancy_result(score: 0.80),
        precision: mock_precision_result(score: 0.80, relevant_count: 8, irrelevant_count: 2),
        recall: mock_recall_result(score: 0.60, retrieved_relevant: 6, missed_relevant: 4)
      }

      expect(results).not_to meet_all_rag_thresholds
    end

    it "works with string keys" do
      results = {
        "relevancy" => mock_relevancy_result(score: 0.80),
        "precision" => mock_precision_result(score: 0.80, relevant_count: 8, irrelevant_count: 2),
        "recall" => mock_recall_result(score: 0.80, retrieved_relevant: 8, missed_relevant: 2)
      }

      expect(results).to meet_all_rag_thresholds
    end

    it "provides helpful failure message listing all failed checks" do
      results = {
        relevancy: mock_relevancy_result(score: 0.60),
        precision: mock_precision_result(score: 0.65, relevant_count: 6, irrelevant_count: 4),
        recall: mock_recall_result(score: 0.70, retrieved_relevant: 7, missed_relevant: 3)
      }

      expect {
        expect(results).to meet_all_rag_thresholds
      }.to raise_error(RSpec::Expectations::ExpectationNotMetError, /Relevancy: 60% < 75%.*Precision: 65% < 75%/m)
    end

    it "handles missing metrics gracefully" do
      results = {
        precision: mock_precision_result(score: 0.80, relevant_count: 8, irrelevant_count: 2),
        recall: mock_recall_result(score: 0.80, retrieved_relevant: 8, missed_relevant: 2)
      }

      # Should pass even with missing relevancy
      expect(results).to meet_all_rag_thresholds
    end
  end

  describe "have_balanced_retrieval" do
    it "passes when precision and recall are balanced within default tolerance (0.15)" do
      precision_result = mock_precision_result(score: 0.80, relevant_count: 8, irrelevant_count: 2)
      recall_result = mock_recall_result(score: 0.75, retrieved_relevant: 7, missed_relevant: 3)

      expect([precision_result, recall_result]).to have_balanced_retrieval
    end

    it "passes when precision and recall are exactly equal" do
      precision_result = mock_precision_result(score: 0.80, relevant_count: 8, irrelevant_count: 2)
      recall_result = mock_recall_result(score: 0.80, retrieved_relevant: 8, missed_relevant: 2)

      expect([precision_result, recall_result]).to have_balanced_retrieval
    end

    it "passes when difference is within custom tolerance" do
      precision_result = mock_precision_result(score: 0.90, relevant_count: 9, irrelevant_count: 1)
      recall_result = mock_recall_result(score: 0.70, retrieved_relevant: 7, missed_relevant: 3)

      expect([precision_result, recall_result]).to have_balanced_retrieval(tolerance: 0.25)
    end

    it "fails when precision and recall differ by more than default tolerance" do
      precision_result = mock_precision_result(score: 0.90, relevant_count: 9, irrelevant_count: 1)
      recall_result = mock_recall_result(score: 0.60, retrieved_relevant: 6, missed_relevant: 4)

      expect([precision_result, recall_result]).not_to have_balanced_retrieval
    end

    it "fails when difference exceeds custom tolerance" do
      precision_result = mock_precision_result(score: 0.80, relevant_count: 8, irrelevant_count: 2)
      recall_result = mock_recall_result(score: 0.75, retrieved_relevant: 7, missed_relevant: 3)

      expect([precision_result, recall_result]).not_to have_balanced_retrieval(tolerance: 0.03)
    end

    it "fails when precision result is invalid" do
      precision_result = mock_relevancy_result(score: 0.90)
      recall_result = mock_recall_result(score: 0.80, retrieved_relevant: 8, missed_relevant: 2)

      expect([precision_result, recall_result]).not_to have_balanced_retrieval
    end

    it "fails when recall result is invalid" do
      precision_result = mock_precision_result(score: 0.80, relevant_count: 8, irrelevant_count: 2)
      recall_result = mock_relevancy_result(score: 0.90)

      expect([precision_result, recall_result]).not_to have_balanced_retrieval
    end

    it "provides helpful failure message with actual difference" do
      precision_result = mock_precision_result(score: 0.90, relevant_count: 9, irrelevant_count: 1)
      recall_result = mock_recall_result(score: 0.60, retrieved_relevant: 6, missed_relevant: 4)

      expect {
        expect([precision_result, recall_result]).to have_balanced_retrieval
      }.to raise_error(RSpec::Expectations::ExpectationNotMetError, /Expected precision and recall to be balanced \(within 15%\), but difference was 30% \(precision: 90%, recall: 60%\)/)
    end
  end
end
