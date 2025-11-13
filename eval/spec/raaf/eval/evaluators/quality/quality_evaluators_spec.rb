# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Quality Evaluators" do
  let(:output_result) {
    {
      output: "The capital of France is Paris. It is known for the Eiffel Tower.",
      baseline_output: "Paris is the capital of France. The Eiffel Tower is its famous landmark."
    }
  }
  let(:field_context) { RAAF::Eval::DSL::FieldContext.new(:output, output_result) }

  describe RAAF::Eval::Evaluators::Quality::SemanticSimilarity do
    let(:evaluator) { described_class.new }

    it "has correct evaluator name" do
      expect(described_class.evaluator_name).to eq(:semantic_similarity)
    end

    it "passes when semantic similarity is above threshold" do
      result = evaluator.evaluate(field_context, threshold: 0.7)

      expect(result[:passed]).to be true
      expect(result[:score]).to be >= 0.7
      expect(result[:message]).to include("semantic similarity")
    end

    it "fails when texts are semantically different" do
      different_context = RAAF::Eval::DSL::FieldContext.new(
        :output,
        { output: "Quantum physics studies subatomic particles",
          baseline_output: "Paris is the capital of France" }
      )

      result = evaluator.evaluate(different_context, threshold: 0.8)

      expect(result[:passed]).to be false
      expect(result[:score]).to be < 0.8
    end

    it "uses default threshold when not specified" do
      result = evaluator.evaluate(field_context)
      expect(result[:details][:threshold]).to eq(0.8)
    end
  end

  describe RAAF::Eval::Evaluators::Quality::Coherence do
    let(:evaluator) { described_class.new }

    it "has correct evaluator name" do
      expect(described_class.evaluator_name).to eq(:coherence)
    end

    it "passes for coherent text" do
      coherent_context = RAAF::Eval::DSL::FieldContext.new(
        :output,
        { output: "First, we prepare the ingredients. Next, we mix them together. Finally, we bake the cake." }
      )

      result = evaluator.evaluate(coherent_context, min_score: 0.7)

      expect(result[:passed]).to be true
      expect(result[:score]).to be >= 0.7
      expect(result[:message]).to include("coherence")
    end

    it "fails for incoherent text" do
      incoherent_context = RAAF::Eval::DSL::FieldContext.new(
        :output,
        { output: "Purple. Yesterday walking. Therefore banana computer! Sky runs quickly?" }
      )

      result = evaluator.evaluate(incoherent_context, min_score: 0.8)

      expect(result[:passed]).to be false
      expect(result[:score]).to be < 0.8
    end

    it "includes coherence analysis in details" do
      result = evaluator.evaluate(field_context)

      expect(result[:details]).to include(:coherence_score, :analysis)
      expect(result[:details][:analysis]).to be_a(Hash)
    end
  end

  describe RAAF::Eval::Evaluators::Quality::HallucinationDetection do
    let(:evaluator) { described_class.new }

    it "has correct evaluator name" do
      expect(described_class.evaluator_name).to eq(:hallucination_detection)
    end

    it "passes when no hallucinations detected" do
      factual_context = RAAF::Eval::DSL::FieldContext.new(
        :output,
        { output: "Paris is the capital of France.",
          baseline_output: "The capital of France is Paris." }
      )

      result = evaluator.evaluate(factual_context)

      expect(result[:passed]).to be true
      expect(result[:message]).to include("No hallucinations detected")
    end

    it "fails when hallucinations are detected" do
      hallucinated_context = RAAF::Eval::DSL::FieldContext.new(
        :output,
        { output: "Paris is the capital of France with a population of 50 million.",
          baseline_output: "Paris is the capital of France." }
      )

      result = evaluator.evaluate(hallucinated_context, strict: true)

      expect(result[:passed]).to be false
      expect(result[:details][:hallucinations]).to be_an(Array)
      expect(result[:details][:hallucinations]).not_to be_empty
    end
  end

  describe RAAF::Eval::Evaluators::Quality::Relevance do
    let(:evaluator) { described_class.new }

    it "has correct evaluator name" do
      expect(described_class.evaluator_name).to eq(:relevance)
    end

    it "passes when response is relevant" do
      relevant_context = RAAF::Eval::DSL::FieldContext.new(
        :output,
        { output: "The capital of France is Paris.",
          prompt: "What is the capital of France?" }
      )

      result = evaluator.evaluate(relevant_context, threshold: 0.7)

      expect(result[:passed]).to be true
      expect(result[:score]).to be >= 0.7
      expect(result[:message]).to include("relevant")
    end

    it "fails when response is irrelevant" do
      irrelevant_context = RAAF::Eval::DSL::FieldContext.new(
        :output,
        { output: "I like pizza.",
          prompt: "What is the capital of France?" }
      )

      result = evaluator.evaluate(irrelevant_context, threshold: 0.7)

      expect(result[:passed]).to be false
      expect(result[:score]).to be < 0.7
    end

    it "uses baseline prompt when available" do
      context_with_baseline = RAAF::Eval::DSL::FieldContext.new(
        :output,
        { output: "Paris",
          baseline_prompt: "Capital of France?",
          prompt: "What city?" }
      )

      result = evaluator.evaluate(context_with_baseline)

      expect(result[:details][:prompt_used]).to eq("Capital of France?")
    end
  end
end