# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../../lib/raaf/eval/evaluators/llm/base_evaluator"
require_relative "../../../../../lib/raaf/eval/evaluators/llm/contextual_relevancy"

RSpec.describe RAAF::Eval::Evaluators::LLM::ContextualRelevancy do
  # Test data with high relevancy (good keyword overlap)
  let(:relevant_data) do
    {
      query: "What is machine learning?",
      context: "Machine learning is a subset of artificial intelligence that enables computers to learn from data without being explicitly programmed. It involves algorithms that improve automatically through experience."
    }
  end

  # Test data with moderate relevancy (some keyword overlap)
  let(:moderate_data) do
    {
      query: "How does photosynthesis work in plants?",
      context: "Photosynthesis is a process where plants use sunlight and chlorophyll. This biological mechanism allows plants to convert carbon dioxide and water into glucose. The process is essential for plant growth and oxygen production."
    }
  end

  # Test data with low relevancy (minimal keyword overlap)
  let(:irrelevant_data) do
    {
      query: "What is quantum computing?",
      context: "The history of classical music spans several centuries. Composers like Bach and Mozart revolutionized musical composition. Symphony orchestras perform these timeless works."
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

  describe "evaluate with relevant context" do
    let(:evaluator) { described_class.new }
    let(:field_context) do
      RAAF::Eval::DSL::FieldContext.new(:rag_data, { rag_data: relevant_data })
    end

    it "returns structured result with high score" do
      result = evaluator.evaluate(field_context)

      expect(result).to include(:label, :score, :message, :details)
      expect(result[:score]).to be_a(Float)
      expect(result[:score]).to be >= 0.75 # High relevancy threshold
    end

    it "includes relevancy details" do
      result = evaluator.evaluate(field_context)

      expect(result[:details]).to include(
        :evaluated_field,
        :method,
        :query,
        :context_preview,
        :relevancy_reasoning
      )
      expect(result[:details][:method]).to eq("contextual_relevancy")
    end

    it "includes query and context preview" do
      result = evaluator.evaluate(field_context)

      expect(result[:details][:query]).to eq("What is machine learning?")
      expect(result[:details][:context_preview]).to be_a(String)
      expect(result[:details][:context_preview]).not_to be_empty
    end

    it "includes relevancy reasoning" do
      result = evaluator.evaluate(field_context)

      reasoning = result[:details][:relevancy_reasoning]
      expect(reasoning).to be_a(String)
      expect(reasoning).to include("Contextual Relevancy Analysis")
      expect(reasoning).to include("Keyword Coverage")
    end

    it "labels as 'good' for highly relevant context" do
      result = evaluator.evaluate(field_context)

      expect(result[:label]).to eq("good")
    end
  end

  describe "evaluate with moderately relevant context" do
    let(:evaluator) { described_class.new }
    let(:field_context) do
      RAAF::Eval::DSL::FieldContext.new(:rag_data, { rag_data: moderate_data })
    end

    it "returns moderate relevancy score" do
      result = evaluator.evaluate(field_context)

      # Should score between average and good thresholds
      expect(result[:score]).to be_between(0.50, 0.75)
    end

    it "labels as 'average' for moderately relevant context" do
      result = evaluator.evaluate(field_context)

      expect(result[:label]).to eq("average")
    end
  end

  describe "evaluate with irrelevant context" do
    let(:evaluator) { described_class.new }
    let(:field_context) do
      RAAF::Eval::DSL::FieldContext.new(:rag_data, { rag_data: irrelevant_data })
    end

    it "returns low relevancy score" do
      result = evaluator.evaluate(field_context)

      # Should score below average threshold
      expect(result[:score]).to be < 0.50
    end

    it "labels as 'bad' for irrelevant context" do
      result = evaluator.evaluate(field_context)

      expect(result[:label]).to eq("bad")
    end

    it "includes recommendation to improve retrieval" do
      result = evaluator.evaluate(field_context)

      expect(result[:details][:evaluation_note]).to include("improving retrieval")
    end
  end

  describe "evaluate with array of documents" do
    let(:evaluator) { described_class.new }
    let(:docs_data) do
      {
        query: "What is Ruby?",
        context: [
          { content: "Ruby is a dynamic programming language." },
          { content: "Ruby was created by Yukihiro Matsumoto in the 1990s." },
          { content: "Ruby emphasizes simplicity and productivity." }
        ]
      }
    end
    let(:field_context) do
      RAAF::Eval::DSL::FieldContext.new(:rag_data, { rag_data: docs_data })
    end

    it "handles array of documents" do
      result = evaluator.evaluate(field_context)

      expect(result[:score]).to be_a(Float)
      expect(result[:score]).to be >= 0.75 # High relevancy due to keyword overlap
    end

    it "includes combined context preview" do
      result = evaluator.evaluate(field_context)

      preview = result[:details][:context_preview]
      expect(preview).to include("Ruby")
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
      RAAF::Eval::DSL::FieldContext.new(:rag_data, { rag_data: relevant_data })
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
      RAAF::Eval::DSL::FieldContext.new(:rag_data, { rag_data: relevant_data })
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

    it "includes contextual relevancy specific details" do
      result = evaluator.evaluate(field_context)

      expect(result[:details]).to include(
        evaluated_field: :rag_data,
        method: "contextual_relevancy",
        query: be_a(String),
        context_preview: be_a(String),
        context_length: be_a(Integer),
        relevancy_reasoning: be_a(String)
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
