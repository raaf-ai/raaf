# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../../lib/raaf/eval/evaluators/llm/base_evaluator"
require_relative "../../../../../lib/raaf/eval/evaluators/llm/contextual_precision"

RSpec.describe RAAF::Eval::Evaluators::LLM::ContextualPrecision do
  # Test data with high precision (all docs relevant)
  let(:high_precision_data) do
    {
      query: "What is machine learning?",
      context: "Machine learning is a subset of AI that enables computers to learn from data.\n\nMachine learning algorithms improve automatically through experience and data.\n\nMachine learning is used in many applications like recommendation systems and image recognition."
    }
  end

  # Test data with moderate precision (some docs relevant, some not)
  let(:moderate_precision_data) do
    {
      query: "What is machine learning?",
      context: "Machine learning is a subset of artificial intelligence.\n\nThe history of computers dates back to the 19th century.\n\nMachine learning algorithms can learn patterns from data automatically."
    }
  end

  # Test data with low precision (most docs irrelevant)
  let(:low_precision_data) do
    {
      query: "What is machine learning?",
      context: "Classical music has evolved over centuries.\n\nThe Renaissance period saw great artistic achievements.\n\nMozart and Beethoven were famous composers."
    }
  end

  # Test data with array of documents (mixed relevance)
  let(:array_docs_data) do
    {
      query: "What is Ruby programming?",
      context: [
        { content: "Ruby is a dynamic, object-oriented programming language." },
        { content: "The weather today is sunny and warm." },
        { content: "Ruby was created by Yukihiro Matsumoto in the 1990s." },
        { content: "Many people enjoy outdoor activities in summer." },
        { content: "Ruby emphasizes simplicity and productivity with elegant syntax." }
      ]
    }
  end

  describe "initialization" do
    it "initializes with default thresholds" do
      evaluator = described_class.new
      expect(evaluator).to be_a(described_class)
    end

    it "accepts custom thresholds" do
      evaluator = described_class.new(
        good_threshold: 0.85,
        average_threshold: 0.60
      )
      expect(evaluator).to be_a(described_class)
    end
  end

  describe "evaluate with high precision context" do
    let(:evaluator) { described_class.new }
    let(:field_context) do
      RAAF::Eval::DSL::FieldContext.new(:rag_data, { rag_data: high_precision_data })
    end

    it "returns structured result with high score" do
      result = evaluator.evaluate(field_context)

      expect(result).to include(:label, :score, :message, :details)
      expect(result[:score]).to be_a(Float)
      expect(result[:score]).to be >= 0.75  # High precision threshold
    end

    it "includes precision details" do
      result = evaluator.evaluate(field_context)

      expect(result[:details]).to include(
        :evaluated_field,
        :method,
        :query,
        :document_count,
        :relevant_count,
        :irrelevant_count,
        :document_relevance,
        :precision_reasoning
      )
      expect(result[:details][:method]).to eq("contextual_precision")
    end

    it "includes document counts" do
      result = evaluator.evaluate(field_context)

      expect(result[:details][:document_count]).to be > 0
      expect(result[:details][:relevant_count]).to be > 0
      expect(result[:details][:relevant_count]).to be <= result[:details][:document_count]
    end

    it "includes document relevance breakdown" do
      result = evaluator.evaluate(field_context)

      doc_relevance = result[:details][:document_relevance]
      expect(doc_relevance).to be_an(Array)
      expect(doc_relevance).not_to be_empty

      doc_relevance.each do |dr|
        expect(dr).to include(:index, :content, :relevance_score, :relevant)
        expect(dr[:relevance_score]).to be_between(0, 1)
        expect([true, false]).to include(dr[:relevant])
      end
    end

    it "includes precision reasoning" do
      result = evaluator.evaluate(field_context)

      reasoning = result[:details][:precision_reasoning]
      expect(reasoning).to be_a(String)
      expect(reasoning).to include("Contextual Precision Analysis")
      expect(reasoning).to include("Document Relevance Breakdown")
    end

    it "labels as 'good' for high precision" do
      result = evaluator.evaluate(field_context)

      expect(result[:label]).to eq("good")
    end
  end

  describe "evaluate with moderate precision context" do
    let(:evaluator) { described_class.new }
    let(:field_context) do
      RAAF::Eval::DSL::FieldContext.new(:rag_data, { rag_data: moderate_precision_data })
    end

    it "returns moderate precision score" do
      result = evaluator.evaluate(field_context)

      # Should score between average and good thresholds
      expect(result[:score]).to be_between(0.30, 0.75)
    end

    it "includes mixed relevant and irrelevant counts" do
      result = evaluator.evaluate(field_context)

      relevant = result[:details][:relevant_count]
      irrelevant = result[:details][:irrelevant_count]
      total = result[:details][:document_count]

      expect(relevant).to be > 0
      expect(irrelevant).to be > 0
      expect(relevant + irrelevant).to eq(total)
    end

    it "labels as 'average' for moderate precision" do
      result = evaluator.evaluate(field_context)

      expect(result[:label]).to eq("average")
    end
  end

  describe "evaluate with low precision context" do
    let(:evaluator) { described_class.new }
    let(:field_context) do
      RAAF::Eval::DSL::FieldContext.new(:rag_data, { rag_data: low_precision_data })
    end

    it "returns low precision score" do
      result = evaluator.evaluate(field_context)

      # Should score below average threshold
      expect(result[:score]).to be < 0.50
    end

    it "shows mostly irrelevant documents" do
      result = evaluator.evaluate(field_context)

      relevant = result[:details][:relevant_count]
      irrelevant = result[:details][:irrelevant_count]

      expect(irrelevant).to be >= relevant
    end

    it "labels as 'bad' for low precision" do
      result = evaluator.evaluate(field_context)

      expect(result[:label]).to eq("bad")
    end

    it "includes recommendation to improve filtering" do
      result = evaluator.evaluate(field_context)

      expect(result[:details][:evaluation_note]).to include("better filtering")
    end
  end

  describe "evaluate with array of documents" do
    let(:evaluator) { described_class.new }
    let(:field_context) do
      RAAF::Eval::DSL::FieldContext.new(:rag_data, { rag_data: array_docs_data })
    end

    it "handles array of documents" do
      result = evaluator.evaluate(field_context)

      expect(result[:score]).to be_a(Float)
      expect(result[:details][:document_count]).to eq(5)
    end

    it "identifies relevant and irrelevant documents" do
      result = evaluator.evaluate(field_context)

      relevant = result[:details][:relevant_count]
      irrelevant = result[:details][:irrelevant_count]
      total = result[:details][:document_count]

      expect(relevant + irrelevant).to eq(total)
      # Should identify Ruby-related docs as relevant, others as irrelevant
      # Mock scoring has randomness, so we expect 1-3 relevant docs (3 Ruby docs total)
      expect(relevant).to be_between(1, 3)
      expect(relevant).to be > 0  # At least some Ruby docs should be relevant
    end

    it "includes relevance breakdown for each document" do
      result = evaluator.evaluate(field_context)

      doc_relevance = result[:details][:document_relevance]
      expect(doc_relevance.length).to eq(5)

      doc_relevance.each_with_index do |dr, idx|
        expect(dr[:index]).to eq(idx)
      end
    end
  end

  describe "custom thresholds" do
    let(:evaluator) do
      described_class.new(
        good_threshold: 0.90,
        average_threshold: 0.70
      )
    end
    let(:field_context) do
      RAAF::Eval::DSL::FieldContext.new(:rag_data, { rag_data: high_precision_data })
    end

    it "applies custom thresholds" do
      result = evaluator.evaluate(field_context)

      # With stricter thresholds, might not be labeled 'good'
      expect([:good, :average]).to include(result[:label].to_sym)
    end

    it "includes threshold metadata" do
      result = evaluator.evaluate(field_context)

      expect(result[:details][:thresholds]).to include(
        good: 0.90,
        average: 0.70
      )
    end
  end

  describe "custom relevance threshold" do
    let(:evaluator) { described_class.new }
    let(:field_context) do
      RAAF::Eval::DSL::FieldContext.new(:rag_data, { rag_data: moderate_precision_data })
    end

    it "accepts custom relevance threshold" do
      result = evaluator.evaluate(field_context, relevance_threshold: 0.80)

      expect(result[:details][:relevance_threshold]).to eq(0.80)
    end

    it "uses custom relevance threshold for document classification" do
      # Lower threshold should classify more docs as relevant
      result_low = evaluator.evaluate(field_context, relevance_threshold: 0.40)
      # Higher threshold should classify fewer docs as relevant
      result_high = evaluator.evaluate(field_context, relevance_threshold: 0.80)

      expect(result_low[:details][:relevant_count]).to be >= result_high[:details][:relevant_count]
    end
  end

  describe "error handling" do
    let(:evaluator) { described_class.new }

    it "raises error when query is empty" do
      field_context = RAAF::Eval::DSL::FieldContext.new(:rag_data, {
        rag_data: {
          query: "",
          context: "Some context"
        }
      })

      expect {
        evaluator.evaluate(field_context)
      }.to raise_error(ArgumentError, /Query cannot be empty/)
    end

    it "raises error when context is empty" do
      field_context = RAAF::Eval::DSL::FieldContext.new(:rag_data, {
        rag_data: {
          query: "What is AI?",
          context: ""
        }
      })

      expect {
        evaluator.evaluate(field_context)
      }.to raise_error(ArgumentError, /Context cannot be empty/)
    end

    it "raises error when query is missing" do
      field_context = RAAF::Eval::DSL::FieldContext.new(:rag_data, {
        rag_data: {
          context: "Some context"
        }
      })

      expect {
        evaluator.evaluate(field_context)
      }.to raise_error(ArgumentError, /Query cannot be empty/)
    end

    it "raises error when context is missing" do
      field_context = RAAF::Eval::DSL::FieldContext.new(:rag_data, {
        rag_data: {
          query: "What is AI?"
        }
      })

      expect {
        evaluator.evaluate(field_context)
      }.to raise_error(ArgumentError, /Context cannot be empty/)
    end
  end

  describe "result structure" do
    let(:evaluator) { described_class.new }
    let(:field_context) do
      RAAF::Eval::DSL::FieldContext.new(:rag_data, { rag_data: high_precision_data })
    end

    it "includes all required result fields" do
      result = evaluator.evaluate(field_context)

      expect(result).to include(
        label: be_a(String),
        score: be_a(Float),
        message: be_a(String),
        details: be_a(Hash)
      )
    end

    it "includes contextual precision specific details" do
      result = evaluator.evaluate(field_context)

      expect(result[:details]).to include(
        evaluated_field: :rag_data,
        method: "contextual_precision",
        query: be_a(String),
        document_count: be_a(Integer),
        relevant_count: be_a(Integer),
        irrelevant_count: be_a(Integer),
        document_relevance: be_an(Array),
        precision_reasoning: be_a(String),
        relevance_threshold: be_a(Float)
      )
    end

    it "includes threshold metadata" do
      result = evaluator.evaluate(field_context)

      expect(result[:details][:thresholds]).to include(
        :good,
        :average,
        :used
      )
    end
  end

  describe "single document handling" do
    let(:evaluator) { described_class.new }
    let(:single_doc_data) do
      {
        query: "What is Ruby?",
        context: "Ruby is a dynamic, object-oriented programming language created by Yukihiro Matsumoto."
      }
    end
    let(:field_context) do
      RAAF::Eval::DSL::FieldContext.new(:rag_data, { rag_data: single_doc_data })
    end

    it "handles single document" do
      result = evaluator.evaluate(field_context)

      expect(result[:details][:document_count]).to eq(1)
      expect(result[:details][:document_relevance].length).to eq(1)
    end

    it "returns precision of 1.0 or 0.0 for single document" do
      result = evaluator.evaluate(field_context)

      # Single document: precision is either 1.0 (relevant) or 0.0 (irrelevant)
      expect([0.0, 1.0]).to include(result[:score])
    end
  end

  describe "direct field access" do
    let(:evaluator) { described_class.new }

    it "handles query as direct field" do
      field_context = RAAF::Eval::DSL::FieldContext.new(:query, { query: "What is AI?" })

      # This should fail because context is missing
      expect {
        evaluator.evaluate(field_context)
      }.to raise_error(ArgumentError, /Context cannot be empty/)
    end

    it "handles context as direct field" do
      field_context = RAAF::Eval::DSL::FieldContext.new(:context, { context: "AI is artificial intelligence" })

      # This should fail because query is missing
      expect {
        evaluator.evaluate(field_context)
      }.to raise_error(ArgumentError, /Query cannot be empty/)
    end
  end
end
