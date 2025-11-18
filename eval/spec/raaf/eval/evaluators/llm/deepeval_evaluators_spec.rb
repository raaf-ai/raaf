# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../../lib/raaf/eval/evaluators/llm/base_evaluator"
require_relative "../../../../../lib/raaf/eval/evaluators/llm/hallucination"
require_relative "../../../../../lib/raaf/eval/evaluators/llm/answer_relevancy"
require_relative "../../../../../lib/raaf/eval/evaluators/llm/faithfulness"
require_relative "../../../../../lib/raaf/eval/evaluators/llm/bias"
require_relative "../../../../../lib/raaf/eval/evaluators/llm/toxicity"

RSpec.describe "DeepEval-Inspired LLM Evaluators" do
  let(:output_result) do
    {
      output: "Paris is the capital of France. The Eiffel Tower is a famous landmark in Paris."
    }
  end
  let(:field_context) { RAAF::Eval::DSL::FieldContext.new(:output, output_result) }

  describe RAAF::Eval::Evaluators::LLM::BaseEvaluator do
    # Test threshold resolution and validation through a concrete implementation
    let(:test_evaluator_class) do
      Class.new(described_class).tap do |klass|
        klass.const_set(:DEFAULT_GOOD_THRESHOLD, 0.80)
        klass.const_set(:DEFAULT_AVERAGE_THRESHOLD, 0.60)

        # Define class name method for anonymous class
        klass.define_singleton_method(:name) { "TestEvaluator" }

        klass.define_method(:evaluate) do |field_context, **options|
          good_threshold, average_threshold = resolve_thresholds(options)
          score = 0.75 # Mock score
          label = calculate_label(score,
                                 good_threshold: good_threshold,
                                 average_threshold: average_threshold)

          build_result(score, label, good_threshold, average_threshold,
            evaluated_field: field_context.field_name,
            method: "test"
          )
        end
      end
    end

    context "threshold resolution" do
      it "uses class defaults when no overrides provided" do
        evaluator = test_evaluator_class.new
        result = evaluator.evaluate(field_context)

        expect(result[:details][:thresholds][:good]).to eq(0.80)
        expect(result[:details][:thresholds][:average]).to eq(0.60)
      end

      it "uses instance defaults when provided at initialization" do
        evaluator = test_evaluator_class.new(good_threshold: 0.90, average_threshold: 0.70)
        result = evaluator.evaluate(field_context)

        expect(result[:details][:thresholds][:good]).to eq(0.90)
        expect(result[:details][:thresholds][:average]).to eq(0.70)
      end

      it "uses call-time overrides with highest priority" do
        evaluator = test_evaluator_class.new(good_threshold: 0.90, average_threshold: 0.70)
        result = evaluator.evaluate(field_context, good_threshold: 0.95, average_threshold: 0.85)

        expect(result[:details][:thresholds][:good]).to eq(0.95)
        expect(result[:details][:thresholds][:average]).to eq(0.85)
      end

      it "supports partial call-time override (good only)" do
        evaluator = test_evaluator_class.new(good_threshold: 0.90, average_threshold: 0.70)
        result = evaluator.evaluate(field_context, good_threshold: 0.95)

        expect(result[:details][:thresholds][:good]).to eq(0.95)
        expect(result[:details][:thresholds][:average]).to eq(0.70)
      end

      it "supports partial call-time override (average only)" do
        evaluator = test_evaluator_class.new(good_threshold: 0.90, average_threshold: 0.70)
        result = evaluator.evaluate(field_context, average_threshold: 0.65)

        expect(result[:details][:thresholds][:good]).to eq(0.90)
        expect(result[:details][:thresholds][:average]).to eq(0.65)
      end
    end

    context "threshold validation" do
      it "raises error when good_threshold <= average_threshold" do
        expect {
          test_evaluator_class.new(good_threshold: 0.70, average_threshold: 0.90)
        }.to raise_error(ArgumentError, /good_threshold .* must be > average_threshold/)
      end

      it "raises error when good_threshold equals average_threshold" do
        expect {
          test_evaluator_class.new(good_threshold: 0.80, average_threshold: 0.80)
        }.to raise_error(ArgumentError, /good_threshold .* must be > average_threshold/)
      end

      it "raises error when good_threshold > 1.0" do
        expect {
          test_evaluator_class.new(good_threshold: 1.5, average_threshold: 0.70)
        }.to raise_error(ArgumentError, /Thresholds must be between 0.0 and 1.0/)
      end

      it "raises error when average_threshold < 0.0" do
        expect {
          test_evaluator_class.new(good_threshold: 0.90, average_threshold: -0.1)
        }.to raise_error(ArgumentError, /Thresholds must be between 0.0 and 1.0/)
      end

      it "accepts valid threshold boundaries (0.0 and 1.0)" do
        expect {
          test_evaluator_class.new(good_threshold: 1.0, average_threshold: 0.0)
        }.not_to raise_error
      end
    end

    context "label calculation" do
      let(:evaluator) { test_evaluator_class.new(good_threshold: 0.80, average_threshold: 0.60) }

      it "returns 'good' when score >= good_threshold" do
        score_evaluator = Class.new(described_class).tap do |klass|
          klass.const_set(:DEFAULT_GOOD_THRESHOLD, 0.80)
          klass.const_set(:DEFAULT_AVERAGE_THRESHOLD, 0.60)

          # Define class name method for anonymous class
          klass.define_singleton_method(:name) { "GoodScoreEvaluator" }

          klass.define_method(:evaluate) do |field_context, **options|
            good_threshold, average_threshold = resolve_thresholds(options)
            score = 0.85
            label = calculate_label(score,
                                   good_threshold: good_threshold,
                                   average_threshold: average_threshold)
            build_result(score, label, good_threshold, average_threshold, evaluated_field: field_context.field_name)
          end
        end

        result = score_evaluator.new.evaluate(field_context)
        expect(result[:label]).to eq("good")
      end

      it "returns 'average' when score between thresholds" do
        score_evaluator = Class.new(described_class).tap do |klass|
          klass.const_set(:DEFAULT_GOOD_THRESHOLD, 0.80)
          klass.const_set(:DEFAULT_AVERAGE_THRESHOLD, 0.60)

          # Define class name method for anonymous class
          klass.define_singleton_method(:name) { "AverageScoreEvaluator" }

          klass.define_method(:evaluate) do |field_context, **options|
            good_threshold, average_threshold = resolve_thresholds(options)
            score = 0.70
            label = calculate_label(score,
                                   good_threshold: good_threshold,
                                   average_threshold: average_threshold)
            build_result(score, label, good_threshold, average_threshold, evaluated_field: field_context.field_name)
          end
        end

        result = score_evaluator.new.evaluate(field_context)
        expect(result[:label]).to eq("average")
      end

      it "returns 'bad' when score < average_threshold" do
        score_evaluator = Class.new(described_class).tap do |klass|
          klass.const_set(:DEFAULT_GOOD_THRESHOLD, 0.80)
          klass.const_set(:DEFAULT_AVERAGE_THRESHOLD, 0.60)

          # Define class name method for anonymous class
          klass.define_singleton_method(:name) { "BadScoreEvaluator" }

          klass.define_method(:evaluate) do |field_context, **options|
            good_threshold, average_threshold = resolve_thresholds(options)
            score = 0.50
            label = calculate_label(score,
                                   good_threshold: good_threshold,
                                   average_threshold: average_threshold)
            build_result(score, label, good_threshold, average_threshold, evaluated_field: field_context.field_name)
          end
        end

        result = score_evaluator.new.evaluate(field_context)
        expect(result[:label]).to eq("bad")
      end
    end

    context "result structure" do
      let(:evaluator) { test_evaluator_class.new }

      it "returns standardized result hash with required keys" do
        result = evaluator.evaluate(field_context)

        expect(result).to have_key(:label)
        expect(result).to have_key(:score)
        expect(result).to have_key(:message)
        expect(result).to have_key(:details)
      end

      it "includes threshold metadata in details" do
        result = evaluator.evaluate(field_context)

        expect(result[:details][:thresholds]).to include(:good, :average, :used)
      end

      it "includes evaluated field name in details" do
        result = evaluator.evaluate(field_context)

        expect(result[:details][:evaluated_field]).to eq("output")
      end
    end
  end

  describe RAAF::Eval::Evaluators::LLM::Hallucination do
    let(:evaluator) { described_class.new }
    let(:context_data) { "France is a country in Western Europe. Paris is its capital city and home to the Eiffel Tower." }

    context "with factual content" do
      it "returns 'good' label for factual content" do
        eval_result = evaluator.evaluate(field_context, context: context_data)

        expect(eval_result[:label]).to eq("good")
        expect(eval_result[:score]).to be >= described_class::DEFAULT_GOOD_THRESHOLD
      end

      it "uses default thresholds when not specified" do
        eval_result = evaluator.evaluate(field_context, context: context_data)

        expect(eval_result[:details][:thresholds][:good]).to eq(0.90)
        expect(eval_result[:details][:thresholds][:average]).to eq(0.70)
      end
    end

    context "with hallucinated content" do
      let(:hallucinated_output) do
        { output: "Paris is the capital of France with a population of 50 million people. It has 20 major airports." }
      end
      let(:hallucinated_context) { "France is a country in Western Europe. Paris is its capital city." }
      let(:hallucinated_field_context) { RAAF::Eval::DSL::FieldContext.new(:output, hallucinated_output) }

      it "returns lower score for hallucinated content" do
        eval_result = evaluator.evaluate(hallucinated_field_context, context: hallucinated_context)

        # Mock implementation penalizes extra content not in context
        expect(eval_result[:score]).to be < described_class::DEFAULT_GOOD_THRESHOLD
      end
    end

    context "without context" do
      it "raises error when context is missing" do
        expect {
          evaluator.evaluate(field_context)
        }.to raise_error(NoMethodError, /undefined method/)
      end
    end

    context "with custom thresholds" do
      it "uses instance thresholds" do
        strict_evaluator = described_class.new(good_threshold: 0.98, average_threshold: 0.90)
        eval_result = strict_evaluator.evaluate(field_context, context: context_data)

        expect(eval_result[:details][:thresholds][:good]).to eq(0.98)
        expect(eval_result[:details][:thresholds][:average]).to eq(0.90)
      end

      it "uses call-time threshold overrides" do
        eval_result = evaluator.evaluate(field_context,
          context: context_data,
          good_threshold: 0.95,
          average_threshold: 0.85
        )

        expect(eval_result[:details][:thresholds][:good]).to eq(0.95)
        expect(eval_result[:details][:thresholds][:average]).to eq(0.85)
      end
    end

    context "result structure" do
      it "includes method metadata" do
        eval_result = evaluator.evaluate(field_context, context: context_data)

        expect(eval_result[:details][:method]).to eq("llm_judge")
      end

      it "includes hallucination percentage" do
        eval_result = evaluator.evaluate(field_context, context: context_data)

        expect(eval_result[:details][:factual_accuracy_percentage]).to be_a(Integer)
        expect(eval_result[:details][:factual_accuracy_percentage]).to be_between(0, 100)
      end
    end
  end

  describe RAAF::Eval::Evaluators::LLM::AnswerRelevancy do
    let(:evaluator) { described_class.new }
    let(:query_data) { "What is the capital of France?" }

    context "with relevant answer" do
      it "returns 'good' label for relevant answer" do
        relevant_output = { output: "The capital of France is Paris." }
        relevant_field_context = RAAF::Eval::DSL::FieldContext.new(:output, relevant_output)

        eval_result = evaluator.evaluate(relevant_field_context, query: query_data)

        expect(eval_result[:label]).to eq("good")
        expect(eval_result[:score]).to be >= described_class::DEFAULT_GOOD_THRESHOLD
      end

      it "uses default thresholds" do
        eval_result = evaluator.evaluate(field_context, query: query_data)

        expect(eval_result[:details][:thresholds][:good]).to eq(0.80)
        expect(eval_result[:details][:thresholds][:average]).to eq(0.60)
      end
    end

    context "with irrelevant answer" do
      let(:irrelevant_output) { { output: "I like pizza and ice cream." } }
      let(:irrelevant_field_context) { RAAF::Eval::DSL::FieldContext.new(:output, irrelevant_output) }

      it "returns lower score for irrelevant answer" do
        eval_result = evaluator.evaluate(irrelevant_field_context, query: query_data)

        expect(eval_result[:score]).to be < described_class::DEFAULT_AVERAGE_THRESHOLD
        expect(eval_result[:label]).to eq("bad")
      end
    end

    context "with partially relevant answer" do
      let(:partial_output) { { output: "France is a beautiful country in Europe. The capital is Paris." } }
      let(:partial_field_context) { RAAF::Eval::DSL::FieldContext.new(:output, partial_output) }

      it "returns average score for partially relevant answer" do
        eval_result = evaluator.evaluate(partial_field_context, query: query_data)

        expect(eval_result[:score]).to be_between(
          described_class::DEFAULT_AVERAGE_THRESHOLD,
          described_class::DEFAULT_GOOD_THRESHOLD
        ).exclusive
      end
    end

    context "without query" do
      it "raises error when query is missing" do
        expect {
          evaluator.evaluate(field_context)
        }.to raise_error(NoMethodError, /undefined method/)
      end
    end

    context "with custom thresholds" do
      it "applies strict thresholds" do
        strict_evaluator = described_class.new(good_threshold: 0.90, average_threshold: 0.75)
        eval_result = strict_evaluator.evaluate(field_context, query: query_data)

        expect(eval_result[:details][:thresholds][:good]).to eq(0.90)
        expect(eval_result[:details][:thresholds][:average]).to eq(0.75)
      end
    end

    context "result structure" do
      it "includes relevancy percentage" do
        eval_result = evaluator.evaluate(field_context, query: query_data)

        expect(eval_result[:details][:relevancy_percentage]).to be_a(Integer)
        expect(eval_result[:details][:relevancy_percentage]).to be_between(0, 100)
      end

      it "includes query in details" do
        eval_result = evaluator.evaluate(field_context, query: query_data)

        expect(eval_result[:details][:query]).to eq(query_data)
      end
    end
  end

  describe RAAF::Eval::Evaluators::LLM::Faithfulness do
    let(:evaluator) { described_class.new }

    context "with faithful answer" do
      let(:faithful_output) do
        { output: "Paris is the capital of France and it is located in Western Europe" }
      end
      let(:retrieval_context_data) do
        "Documentation France is a country in Western Europe Paris is the capital city of France"
      end
      let(:faithful_field_context) { RAAF::Eval::DSL::FieldContext.new(:output, faithful_output) }

      it "returns 'good' label for faithful answer" do
        eval_result = evaluator.evaluate(faithful_field_context, retrieval_context: retrieval_context_data)

        expect(eval_result[:label]).to eq("good")
        expect(eval_result[:score]).to be >= described_class::DEFAULT_GOOD_THRESHOLD
      end

      it "uses default thresholds" do
        eval_result = evaluator.evaluate(faithful_field_context, retrieval_context: retrieval_context_data)

        expect(eval_result[:details][:thresholds][:good]).to eq(0.90)
        expect(eval_result[:details][:thresholds][:average]).to eq(0.75)
      end
    end

    context "with unfaithful answer" do
      let(:unfaithful_output) do
        { output: "Paris has a population of 50 million and is the largest city in Europe." }
      end
      let(:unfaithful_retrieval_context) do
        "France documentation: Paris is the capital of France."
      end
      let(:unfaithful_field_context) { RAAF::Eval::DSL::FieldContext.new(:output, unfaithful_output) }

      it "returns lower score for unfaithful content" do
        eval_result = evaluator.evaluate(unfaithful_field_context, retrieval_context: unfaithful_retrieval_context)

        # Mock implementation checks word overlap
        expect(eval_result[:score]).to be < described_class::DEFAULT_GOOD_THRESHOLD
      end
    end

    context "with array retrieval context" do
      let(:array_output) do
        { output: "Paris is the capital of France and home to the Eiffel Tower." }
      end
      let(:array_retrieval_context) do
        [
          "Document 1: Paris is the capital of France.",
          "Document 2: The Eiffel Tower is located in Paris."
        ]
      end
      let(:array_field_context) { RAAF::Eval::DSL::FieldContext.new(:output, array_output) }

      it "handles array of context documents" do
        eval_result = evaluator.evaluate(array_field_context, retrieval_context: array_retrieval_context)

        expect(eval_result[:label]).to satisfy { |label| ["good", "average", "bad"].include?(label) }
        expect(eval_result[:score]).to be_between(0.0, 1.0)
      end

      it "includes context chunk count" do
        eval_result = evaluator.evaluate(array_field_context, retrieval_context: array_retrieval_context)

        expect(eval_result[:details][:context_chunks]).to eq(2)
      end
    end

    context "without retrieval context" do
      let(:no_context_output) { { output: "Paris is the capital." } }
      let(:no_context_field_context) { RAAF::Eval::DSL::FieldContext.new(:output, no_context_output) }

      it "raises error when retrieval_context is missing" do
        expect {
          evaluator.evaluate(no_context_field_context)
        }.to raise_error(NoMethodError, /undefined method/)
      end
    end

    context "result structure" do
      let(:structure_output) do
        { output: "Paris is the capital of France." }
      end
      let(:structure_retrieval_context) do
        "Documentation: France is a country. Paris is its capital."
      end
      let(:structure_field_context) { RAAF::Eval::DSL::FieldContext.new(:output, structure_output) }

      it "includes faithfulness percentage" do
        eval_result = evaluator.evaluate(structure_field_context, retrieval_context: structure_retrieval_context)

        expect(eval_result[:details][:faithfulness_percentage]).to be_a(Integer)
        expect(eval_result[:details][:faithfulness_percentage]).to be_between(0, 100)
      end

      it "includes method as llm_judge_rag" do
        eval_result = evaluator.evaluate(structure_field_context, retrieval_context: structure_retrieval_context)

        expect(eval_result[:details][:method]).to eq("llm_judge_rag")
      end
    end
  end

  describe RAAF::Eval::Evaluators::LLM::Bias do
    let(:evaluator) { described_class.new }

    context "with unbiased content" do
      let(:result) do
        {
          output: "The candidate has strong technical skills and relevant experience for the position."
        }
      end

      it "returns 'good' label for unbiased content" do
        result = evaluator.evaluate(field_context)

        expect(result[:label]).to eq("good")
        expect(result[:score]).to be >= described_class::DEFAULT_GOOD_THRESHOLD
      end

      it "uses default thresholds" do
        result = evaluator.evaluate(field_context)

        expect(result[:details][:thresholds][:good]).to eq(0.90)
        expect(result[:details][:thresholds][:average]).to eq(0.70)
      end
    end

    context "with biased content" do
      let(:biased_output) do
        {
          output: "All engineers are always the same. Every developer never listens. Typical behavior from that group."
        }
      end
      let(:biased_field_context) { RAAF::Eval::DSL::FieldContext.new(:output, biased_output) }

      it "detects bias through heuristics" do
        result = evaluator.evaluate(biased_field_context)

        # Mock implementation checks for bias indicators (all, always, never, every)
        expect(result[:score]).to be < described_class::DEFAULT_GOOD_THRESHOLD
      end

      it "includes detected biases in details" do
        result = evaluator.evaluate(biased_field_context)

        expect(result[:details][:detected_biases]).to be_an(Array)
      end
    end

    context "with specific bias types" do
      let(:result) do
        {
          output: "The candidate has excellent qualifications."
        }
      end

      it "checks only specified bias types" do
        result = evaluator.evaluate(field_context, bias_types: [:gender, :racial])

        expect(result[:details][:bias_types_checked]).to eq([:gender, :racial])
      end

      it "checks all bias types by default" do
        result = evaluator.evaluate(field_context)

        expect(result[:details][:bias_types_checked]).to eq(described_class::BIAS_TYPES)
      end
    end

    context "with invalid bias types" do
      let(:result) { { output: "Some content" } }

      it "raises error for invalid bias types" do
        expect {
          evaluator.evaluate(field_context, bias_types: [:invalid_type])
        }.to raise_error(ArgumentError, /Invalid bias types/)
      end
    end

    context "supported bias types" do
      it "supports all documented bias types" do
        expected_types = %i[
          gender racial political age religious
          socioeconomic disability sexual_orientation
        ]

        expect(described_class::BIAS_TYPES).to match_array(expected_types)
      end
    end

    context "result structure" do
      let(:result) { { output: "The candidate is well-qualified." } }

      it "includes unbiased percentage" do
        result = evaluator.evaluate(field_context)

        expect(result[:details][:unbiased_percentage]).to be_a(Integer)
        expect(result[:details][:unbiased_percentage]).to be_between(0, 100)
      end

      it "includes evaluation note" do
        result = evaluator.evaluate(field_context)

        expect(result[:details][:evaluation_note]).to be_a(String)
        expect(result[:details][:evaluation_note]).not_to be_empty
      end
    end
  end

  describe RAAF::Eval::Evaluators::LLM::Toxicity do
    let(:evaluator) { described_class.new }

    context "with safe content" do
      let(:result) do
        {
          output: "Thank you for your question. I'd be happy to help you with that."
        }
      end

      it "returns 'good' label for safe content" do
        result = evaluator.evaluate(field_context)

        expect(result[:label]).to eq("good")
        expect(result[:score]).to be >= described_class::DEFAULT_GOOD_THRESHOLD
      end

      it "uses strict default thresholds for safety" do
        result = evaluator.evaluate(field_context)

        expect(result[:details][:thresholds][:good]).to eq(0.95)
        expect(result[:details][:thresholds][:average]).to eq(0.80)
      end
    end

    context "with potentially toxic content" do
      let(:toxic_output) do
        {
          output: "I hate this. Attack them immediately. Kill the process."
        }
      end
      let(:toxic_field_context) { RAAF::Eval::DSL::FieldContext.new(:output, toxic_output) }

      it "detects toxic indicators" do
        result = evaluator.evaluate(toxic_field_context)

        # Mock implementation checks for toxic words
        expect(result[:score]).to be < described_class::DEFAULT_GOOD_THRESHOLD
      end

      it "includes detected toxic issues" do
        result = evaluator.evaluate(toxic_field_context)

        expect(result[:details][:toxic_issues_detected]).to be_an(Array)
      end
    end

    context "with specific toxicity categories" do
      let(:result) do
        {
          output: "Please be respectful in your communications."
        }
      end

      it "checks only specified categories" do
        result = evaluator.evaluate(field_context, categories: [:hate_speech, :harassment])

        expect(result[:details][:categories_checked]).to eq([:hate_speech, :harassment])
      end

      it "checks all categories by default" do
        result = evaluator.evaluate(field_context)

        expect(result[:details][:categories_checked]).to eq(described_class::TOXICITY_CATEGORIES)
      end
    end

    context "with invalid categories" do
      let(:result) { { output: "Some content" } }

      it "raises error for invalid categories" do
        expect {
          evaluator.evaluate(field_context, categories: [:invalid_category])
        }.to raise_error(ArgumentError, /Invalid toxicity categories/)
      end
    end

    context "supported toxicity categories" do
      it "supports all documented categories" do
        expected_categories = %i[
          profanity hate_speech harassment violence sexual
          threatening identity_attack insult severe_toxicity
        ]

        expect(described_class::TOXICITY_CATEGORIES).to match_array(expected_categories)
      end
    end

    context "result structure" do
      let(:result) { { output: "This is a helpful and respectful response." } }

      it "includes safety percentage" do
        result = evaluator.evaluate(field_context)

        expect(result[:details][:safety_percentage]).to be_a(Integer)
        expect(result[:details][:safety_percentage]).to be_between(0, 100)
      end

      it "includes evaluation note" do
        result = evaluator.evaluate(field_context)

        expect(result[:details][:evaluation_note]).to be_a(String)
        expect(result[:details][:evaluation_note]).not_to be_empty
      end

      it "uses llm_judge method" do
        result = evaluator.evaluate(field_context)

        expect(result[:details][:method]).to eq("llm_judge")
      end
    end

    context "with zero-tolerance thresholds" do
      let(:result) { { output: "Professional and appropriate content." } }

      it "supports very strict thresholds" do
        strict_evaluator = described_class.new(good_threshold: 0.98, average_threshold: 0.95)
        result = strict_evaluator.evaluate(field_context)

        expect(result[:details][:thresholds][:good]).to eq(0.98)
        expect(result[:details][:thresholds][:average]).to eq(0.95)
      end
    end
  end
end
