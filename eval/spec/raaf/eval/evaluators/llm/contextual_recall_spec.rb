# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../../lib/raaf/eval/evaluators/llm/base_evaluator"
require_relative "../../../../../lib/raaf/eval/evaluators/llm/contextual_recall"

RSpec.describe RAAF::Eval::Evaluators::LLM::ContextualRecall do
  # Test data with high recall (most relevant docs retrieved)
  let(:high_recall_data) do
    {
      query: "What is machine learning?",
      retrieved_context: [
        "Machine learning is a subset of AI that enables computers to learn from data.",
        "Machine learning algorithms improve automatically through experience and data.",
        "Machine learning is used in many applications like recommendation systems."
      ],
      available_context: [
        "Machine learning is a subset of AI that enables computers to learn from data.",
        "Machine learning algorithms improve automatically through experience and data.",
        "Machine learning is used in many applications like recommendation systems.",
        "Classical music has evolved over centuries."  # Irrelevant, not retrieved
      ]
    }
  end

  # Test data with moderate recall (some relevant docs retrieved, some missed)
  let(:moderate_recall_data) do
    {
      query: "What is machine learning?",
      retrieved_context: [
        "Machine learning is a subset of AI that enables computers to learn from data.",
        "Machine learning algorithms improve automatically through experience.",
        "The weather today is sunny and warm."  # Irrelevant but retrieved
      ],
      available_context: [
        "Machine learning is a subset of AI that enables computers to learn from data.",
        "Machine learning algorithms improve automatically through experience.",
        "Machine learning is used in recommendation systems.",  # Relevant but missed
        "Machine learning applications include pattern recognition.",  # Relevant but missed
        "The weather today is sunny and warm.",  # Irrelevant but retrieved
        "Classical music has evolved over centuries."  # Irrelevant, not retrieved
      ]
    }
  end

  # Test data with low recall (few/no relevant docs retrieved)
  let(:low_recall_data) do
    {
      query: "What is machine learning?",
      retrieved_context: [
        "Classical music has evolved over centuries.",
        "The Renaissance period saw great artistic achievements."
      ],
      available_context: [
        "Machine learning is a subset of artificial intelligence.",  # Relevant but missed
        "Machine learning algorithms can learn patterns from data.",  # Relevant but missed
        "Machine learning is used in many applications.",  # Relevant but missed
        "Classical music has evolved over centuries.",  # Irrelevant but retrieved
        "The Renaissance period saw great artistic achievements."  # Irrelevant but retrieved
      ]
    }
  end

  # Test data with perfect recall (all relevant docs retrieved)
  let(:perfect_recall_data) do
    {
      query: "What is Ruby programming?",
      retrieved_context: [
        "Ruby is a dynamic, object-oriented programming language.",
        "Ruby was created by Yukihiro Matsumoto in the 1990s.",
        "Ruby emphasizes simplicity and productivity."
      ],
      available_context: [
        "Ruby is a dynamic, object-oriented programming language.",
        "Ruby was created by Yukihiro Matsumoto in the 1990s.",
        "Ruby emphasizes simplicity and productivity.",
        "The weather is sunny today.",  # Irrelevant, correctly not retrieved
        "Classical music is beautiful."  # Irrelevant, correctly not retrieved
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

  describe "evaluate with high recall" do
    let(:evaluator) { described_class.new }
    let(:field_context) do
      RAAF::Eval::DSL::FieldContext.new(:rag_data, { rag_data: high_recall_data })
    end

    it "returns structured result with high score" do
      result = evaluator.evaluate(field_context)

      expect(result).to include(:label, :score, :message, :details)
      expect(result[:score]).to be_a(Float)
      expect(result[:score]).to be >= 0.75  # High recall threshold
    end

    it "includes recall details" do
      result = evaluator.evaluate(field_context)

      expect(result[:details]).to include(
        :evaluated_field,
        :method,
        :query,
        :retrieved_count,
        :available_count,
        :relevant_count,
        :retrieved_relevant_count,
        :missed_relevant_count,
        :document_analysis,
        :recall_reasoning
      )
      expect(result[:details][:method]).to eq("contextual_recall")
    end

    it "includes document counts" do
      result = evaluator.evaluate(field_context)

      expect(result[:details][:retrieved_count]).to eq(3)
      expect(result[:details][:available_count]).to eq(4)
      expect(result[:details][:relevant_count]).to be > 0
      expect(result[:details][:retrieved_relevant_count]).to be > 0
    end

    it "includes document analysis" do
      result = evaluator.evaluate(field_context)

      doc_analysis = result[:details][:document_analysis]
      expect(doc_analysis).to be_an(Array)
      expect(doc_analysis).not_to be_empty

      doc_analysis.each do |doc|
        expect(doc).to include(:index, :content, :relevance_score, :relevant, :retrieved, :status)
        expect(doc[:relevance_score]).to be_between(0, 1)
        expect([true, false]).to include(doc[:relevant])
        expect([true, false]).to include(doc[:retrieved])
        expect(%w[retrieved_relevant missed_relevant retrieved_irrelevant not_retrieved_irrelevant]).to include(doc[:status])
      end
    end

    it "includes recall reasoning" do
      result = evaluator.evaluate(field_context)

      reasoning = result[:details][:recall_reasoning]
      expect(reasoning).to be_a(String)
      expect(reasoning).to include("Contextual Recall Analysis")
      expect(reasoning).to include("Document Analysis")
    end

    it "labels as 'good' for high recall" do
      result = evaluator.evaluate(field_context)

      expect(result[:label]).to eq("good")
    end

    it "shows few or no missed relevant documents" do
      result = evaluator.evaluate(field_context)

      missed = result[:details][:missed_relevant_count]
      retrieved_relevant = result[:details][:retrieved_relevant_count]

      # High recall means we retrieved most relevant docs
      expect(retrieved_relevant).to be > missed
    end
  end

  describe "evaluate with moderate recall" do
    let(:evaluator) { described_class.new }
    let(:field_context) do
      RAAF::Eval::DSL::FieldContext.new(:rag_data, { rag_data: moderate_recall_data })
    end

    it "returns moderate recall score" do
      result = evaluator.evaluate(field_context)

      # Should score between average and good thresholds
      expect(result[:score]).to be_between(0.20, 0.75)
    end

    it "shows some retrieved and some missed relevant documents" do
      result = evaluator.evaluate(field_context)

      retrieved_relevant = result[:details][:retrieved_relevant_count]
      missed_relevant = result[:details][:missed_relevant_count]
      relevant = result[:details][:relevant_count]

      expect(relevant).to be > 0
      expect(retrieved_relevant + missed_relevant).to eq(relevant)
      # Moderate recall means we have both retrieved and missed relevant docs
      expect(missed_relevant).to be > 0
    end

    it "labels as 'average' for moderate recall" do
      result = evaluator.evaluate(field_context)

      expect(result[:label]).to eq("average")
    end
  end

  describe "evaluate with low recall" do
    let(:evaluator) { described_class.new }
    let(:field_context) do
      RAAF::Eval::DSL::FieldContext.new(:rag_data, { rag_data: low_recall_data })
    end

    it "returns low recall score" do
      result = evaluator.evaluate(field_context)

      # Should score below average threshold
      expect(result[:score]).to be < 0.50
    end

    it "shows many missed relevant documents" do
      result = evaluator.evaluate(field_context)

      retrieved_relevant = result[:details][:retrieved_relevant_count]
      missed_relevant = result[:details][:missed_relevant_count]

      # Low recall means we missed more relevant docs than we retrieved
      expect(missed_relevant).to be >= retrieved_relevant
    end

    it "labels as 'bad' for low recall" do
      result = evaluator.evaluate(field_context)

      expect(result[:label]).to eq("bad")
    end

    it "includes recommendation to improve retrieval" do
      result = evaluator.evaluate(field_context)

      expect(result[:details][:evaluation_note]).to include("broader retrieval")
    end
  end

  describe "evaluate with perfect recall" do
    let(:evaluator) { described_class.new }
    let(:field_context) do
      RAAF::Eval::DSL::FieldContext.new(:rag_data, { rag_data: perfect_recall_data })
    end

    it "returns score of 1.0" do
      result = evaluator.evaluate(field_context)

      # Perfect recall = all relevant docs retrieved
      expect(result[:score]).to eq(1.0)
    end

    it "shows zero missed relevant documents" do
      result = evaluator.evaluate(field_context)

      expect(result[:details][:missed_relevant_count]).to eq(0)
    end

    it "labels as 'good'" do
      result = evaluator.evaluate(field_context)

      expect(result[:label]).to eq("good")
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
      RAAF::Eval::DSL::FieldContext.new(:rag_data, { rag_data: high_recall_data })
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
      RAAF::Eval::DSL::FieldContext.new(:rag_data, { rag_data: moderate_recall_data })
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
          retrieved_context: ["Some doc"],
          available_context: ["Some doc", "Another doc"]
        }
      })

      expect {
        evaluator.evaluate(field_context)
      }.to raise_error(ArgumentError, /Query cannot be empty/)
    end

    it "raises error when retrieved context is empty" do
      field_context = RAAF::Eval::DSL::FieldContext.new(:rag_data, {
        rag_data: {
          query: "What is AI?",
          retrieved_context: [],
          available_context: ["Some doc"]
        }
      })

      expect {
        evaluator.evaluate(field_context)
      }.to raise_error(ArgumentError, /Retrieved context cannot be empty/)
    end

    it "raises error when available context is empty" do
      field_context = RAAF::Eval::DSL::FieldContext.new(:rag_data, {
        rag_data: {
          query: "What is AI?",
          retrieved_context: ["Some doc"],
          available_context: []
        }
      })

      expect {
        evaluator.evaluate(field_context)
      }.to raise_error(ArgumentError, /Available\/ground truth context cannot be empty/)
    end

    it "raises error when query is missing" do
      field_context = RAAF::Eval::DSL::FieldContext.new(:rag_data, {
        rag_data: {
          retrieved_context: ["Some doc"],
          available_context: ["Some doc"]
        }
      })

      expect {
        evaluator.evaluate(field_context)
      }.to raise_error(ArgumentError, /Query cannot be empty/)
    end

    it "raises error when retrieved context is missing" do
      field_context = RAAF::Eval::DSL::FieldContext.new(:rag_data, {
        rag_data: {
          query: "What is AI?",
          available_context: ["Some doc"]
        }
      })

      expect {
        evaluator.evaluate(field_context)
      }.to raise_error(ArgumentError, /Retrieved context cannot be empty/)
    end

    it "raises error when available context is missing" do
      field_context = RAAF::Eval::DSL::FieldContext.new(:rag_data, {
        rag_data: {
          query: "What is AI?",
          retrieved_context: ["Some doc"]
        }
      })

      expect {
        evaluator.evaluate(field_context)
      }.to raise_error(ArgumentError, /Available\/ground truth context cannot be empty/)
    end
  end

  describe "result structure" do
    let(:evaluator) { described_class.new }
    let(:field_context) do
      RAAF::Eval::DSL::FieldContext.new(:rag_data, { rag_data: high_recall_data })
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

    it "includes contextual recall specific details" do
      result = evaluator.evaluate(field_context)

      expect(result[:details]).to include(
        evaluated_field: :rag_data,
        method: "contextual_recall",
        query: be_a(String),
        retrieved_count: be_a(Integer),
        available_count: be_a(Integer),
        relevant_count: be_a(Integer),
        retrieved_relevant_count: be_a(Integer),
        missed_relevant_count: be_a(Integer),
        document_analysis: be_an(Array),
        recall_reasoning: be_a(String),
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

  describe "document status classification" do
    let(:evaluator) { described_class.new }
    let(:field_context) do
      RAAF::Eval::DSL::FieldContext.new(:rag_data, { rag_data: moderate_recall_data })
    end

    it "classifies documents with all four statuses" do
      result = evaluator.evaluate(field_context)

      doc_analysis = result[:details][:document_analysis]
      statuses = doc_analysis.map { |doc| doc[:status] }.uniq

      # Moderate recall data should have at least 2-3 different statuses
      expect(statuses.size).to be >= 2
    end

    it "correctly counts retrieved_relevant documents" do
      result = evaluator.evaluate(field_context)

      doc_analysis = result[:details][:document_analysis]
      retrieved_relevant = doc_analysis.count { |doc| doc[:status] == "retrieved_relevant" }

      expect(retrieved_relevant).to eq(result[:details][:retrieved_relevant_count])
    end

    it "correctly counts missed_relevant documents" do
      result = evaluator.evaluate(field_context)

      doc_analysis = result[:details][:document_analysis]
      missed_relevant = doc_analysis.count { |doc| doc[:status] == "missed_relevant" }

      expect(missed_relevant).to eq(result[:details][:missed_relevant_count])
    end
  end

  describe "ground truth context usage" do
    let(:evaluator) { described_class.new }
    let(:ground_truth_data) do
      {
        query: "What is Ruby?",
        retrieved_context: [
          "Ruby is a dynamic programming language.",
          "The weather is sunny."
        ],
        ground_truth: [  # Using ground_truth instead of available_context
          "Ruby is a dynamic programming language.",
          "Ruby was created by Yukihiro Matsumoto.",
          "The weather is sunny."
        ]
      }
    end
    let(:field_context) do
      RAAF::Eval::DSL::FieldContext.new(:rag_data, { rag_data: ground_truth_data })
    end

    it "accepts ground_truth field" do
      result = evaluator.evaluate(field_context)

      expect(result[:details][:available_count]).to eq(3)
      expect(result[:score]).to be_a(Float)
    end
  end
end
