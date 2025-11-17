# frozen_string_literal: true

require "spec_helper"
require "raaf/eval"
require "raaf/eval/dsl/evaluator"
require "raaf/eval/dsl/evaluator_registry"

RSpec.describe "Custom Evaluator Integration" do
  # Custom evaluator example from spec
  let(:citation_grounding_evaluator) do
    Class.new do
      include RAAF::Eval::DSL::Evaluator

      evaluator_name :citation_grounding

      def evaluate(field_context, **options)
        text = field_context.value
        knowledge_base = options[:knowledge_base] || []

        citations = extract_citations(text)
        grounded = verify_citations(citations, knowledge_base)

        {
          label: grounded[:unverified].empty? ? "good" : "bad",
          score: grounded[:verified_ratio],
          details: {
            field_evaluated: field_context.field_name,
            total_citations: citations.count,
            verified: grounded[:verified].count,
            unverified: grounded[:unverified],
            ratio: grounded[:verified_ratio]
          },
          message: "#{grounded[:verified].count}/#{citations.count} citations grounded in #{field_context.field_name}"
        }
      end

      private

      def extract_citations(text)
        return [] unless text.is_a?(String)
        text.scan(/\[(\d+)\]/).flatten.map(&:to_i)
      end

      def verify_citations(citations, kb)
        verified = citations.select { |c| kb.include?(c.to_s) }
        {
          verified: verified,
          unverified: citations - verified,
          verified_ratio: citations.empty? ? 1.0 : verified.count.to_f / citations.count
        }
      end
    end
  end

  # Smart quality evaluator with cross-field context
  let(:smart_quality_evaluator) do
    Class.new do
      include RAAF::Eval::DSL::Evaluator

      evaluator_name :smart_quality

      def evaluate(field_context, **options)
        output = field_context.value
        tokens = field_context[:usage][:total_tokens] rescue 0
        model = field_context[:configuration][:model] rescue "unknown"

        base_score = calculate_quality(output)

        # Adjust based on model
        adjusted_score = case model
        when "gpt-4o"
          base_score * 1.0
        when "gpt-3.5-turbo"
          base_score * 1.1
        else
          base_score
        end

        # Penalize inefficiency
        efficiency_penalty = if tokens > 1000 && output.to_s.length < 200
          0.1
        else
          0.0
        end

        final_score = [adjusted_score - efficiency_penalty, 0].max

        {
          label: final_score >= 0.7 ? "good" : (final_score >= 0.5 ? "average" : "bad"),
          score: final_score,
          details: {
            evaluated_field: field_context.field_name,
            base_quality: base_score,
            efficiency_penalty: efficiency_penalty,
            context: {
              model: model,
              tokens: tokens
            }
          },
          message: "Quality: #{(final_score * 100).round}% (model: #{model}, tokens: #{tokens})"
        }
      end

      private

      def calculate_quality(text)
        # Simplified quality calculation
        return 0.0 if text.to_s.empty?
        return 0.5 if text.to_s.length < 10
        0.85
      end
    end
  end

  before do
    # Reset registry
    RAAF::Eval::DSL::EvaluatorRegistry.instance.instance_variable_set(:@evaluators, {})
  end

  describe "global registration" do
    it "registers custom evaluator globally via RAAF::Eval.register_evaluator" do
      RAAF::Eval.register_evaluator(:citation_grounding, citation_grounding_evaluator)
      
      registry = RAAF::Eval::DSL::EvaluatorRegistry.instance
      expect(registry.registered?(:citation_grounding)).to be true
      expect(registry.get(:citation_grounding)).to eq(citation_grounding_evaluator)
    end

    it "can use globally registered evaluator in DSL" do
      RAAF::Eval.register_evaluator(:citation_grounding, citation_grounding_evaluator)
      
      # Should not raise error
      expect {
        RAAF::Eval::DSL::EvaluatorRegistry.instance.get(:citation_grounding)
      }.not_to raise_error
    end
  end

  describe "parameter passing" do
    before do
      RAAF::Eval.register_evaluator(:citation_grounding, citation_grounding_evaluator)
    end

    it "passes parameters to custom evaluator via keyword arguments" do
      result_hash = {
        output: "The capital of France is Paris [1]. The Eiffel Tower [2] is a famous landmark.",
        baseline_output: "France is known for Paris [1]."
      }

      field_context = RAAF::Eval::DSL::FieldContext.new(:output, result_hash)
      knowledge_base = ["1", "2"]

      evaluator_instance = citation_grounding_evaluator.new
      result = evaluator_instance.evaluate(field_context, knowledge_base: knowledge_base)

      expect(result[:label]).to eq("good")
      expect(result[:details][:verified]).to eq([1, 2])
      expect(result[:details][:unverified]).to be_empty
    end

    it "handles missing optional parameters gracefully" do
      result_hash = {
        output: "Text without citations",
        baseline_output: "Baseline"
      }

      field_context = RAAF::Eval::DSL::FieldContext.new(:output, result_hash)
      evaluator_instance = citation_grounding_evaluator.new
      result = evaluator_instance.evaluate(field_context)

      expect(result[:label]).to eq("good") # No citations means all are verified
      expect(result[:details][:total_citations]).to eq(0)
    end
  end

  describe "FieldContext access" do
    before do
      RAAF::Eval.register_evaluator(:smart_quality, smart_quality_evaluator)
    end

    it "provides access to primary field value" do
      result_hash = {
        output: "This is a quality output with sufficient length.",
        usage: { total_tokens: 500 },
        configuration: { model: "gpt-4o" }
      }

      field_context = RAAF::Eval::DSL::FieldContext.new(:output, result_hash)
      evaluator_instance = smart_quality_evaluator.new
      result = evaluator_instance.evaluate(field_context)

      expect(result[:label]).to eq("good")
      expect(result[:details][:evaluated_field]).to eq(:output)
    end

    it "provides cross-field context access via field_context[]" do
      result_hash = {
        output: "Short",
        usage: { total_tokens: 1500 },
        configuration: { model: "gpt-4o" }
      }

      field_context = RAAF::Eval::DSL::FieldContext.new(:output, result_hash)
      evaluator_instance = smart_quality_evaluator.new
      result = evaluator_instance.evaluate(field_context)

      # Should apply efficiency penalty
      expect(result[:details][:efficiency_penalty]).to be > 0
      expect(result[:details][:context][:tokens]).to eq(1500)
      expect(result[:details][:context][:model]).to eq("gpt-4o")
    end

    it "handles missing cross-field data gracefully" do
      result_hash = {
        output: "Quality output"
      }

      field_context = RAAF::Eval::DSL::FieldContext.new(:output, result_hash)
      evaluator_instance = smart_quality_evaluator.new
      
      # Should not raise error despite missing usage and configuration
      expect {
        evaluator_instance.evaluate(field_context)
      }.not_to raise_error
    end
  end

  describe "result structure validation" do
    let(:invalid_evaluator) do
      Class.new do
        include RAAF::Eval::DSL::Evaluator

        evaluator_name :invalid_result

        def evaluate(field_context, **options)
          # Missing required :label field
          { score: 0.5, message: "Invalid" }
        end
      end
    end

    before do
      RAAF::Eval.register_evaluator(:invalid_result, invalid_evaluator)
    end

    it "validates result structure has required fields" do
      result_hash = { output: "Test" }
      field_context = RAAF::Eval::DSL::FieldContext.new(:output, result_hash)
      evaluator_instance = invalid_evaluator.new
      
      result = evaluator_instance.evaluate(field_context)
      
      expect {
        evaluator_instance.validate_result!(result)
      }.to raise_error(RAAF::Eval::DSL::InvalidEvaluatorResultError,
                       /must include :label/)
    end
  end

  describe "example custom evaluators" do
    describe "CitationGroundingEvaluator" do
      before do
        RAAF::Eval.register_evaluator(:citation_grounding, citation_grounding_evaluator)
      end

      it "verifies citations against knowledge base" do
        result_hash = {
          output: "Paris [1] is the capital. The Eiffel Tower [2] is famous. Big Ben [3] is in London.",
          baseline_output: "France has Paris [1]."
        }

        field_context = RAAF::Eval::DSL::FieldContext.new(:output, result_hash)
        knowledge_base = ["1", "2"] # Only 1 and 2 are in knowledge base

        evaluator_instance = citation_grounding_evaluator.new
        result = evaluator_instance.evaluate(field_context, knowledge_base: knowledge_base)

        expect(result[:label]).to eq("bad")
        expect(result[:details][:verified]).to eq([1, 2])
        expect(result[:details][:unverified]).to eq([3])
        expect(result[:score]).to be_within(0.01).of(0.67) # 2/3 verified
      end

      it "returns label 'good' when all citations are grounded" do
        result_hash = {
          output: "Paris [1] is the capital. The Eiffel Tower [2] is famous."
        }

        field_context = RAAF::Eval::DSL::FieldContext.new(:output, result_hash)
        knowledge_base = ["1", "2"]

        evaluator_instance = citation_grounding_evaluator.new
        result = evaluator_instance.evaluate(field_context, knowledge_base: knowledge_base)

        expect(result[:label]).to eq("good")
        expect(result[:score]).to eq(1.0)
      end
    end

    describe "SmartQualityEvaluator" do
      before do
        RAAF::Eval.register_evaluator(:smart_quality, smart_quality_evaluator)
      end

      it "adjusts quality expectations based on model" do
        result_hash = {
          output: "This is a quality output with sufficient length.",
          usage: { total_tokens: 500 },
          configuration: { model: "gpt-3.5-turbo" }
        }

        field_context = RAAF::Eval::DSL::FieldContext.new(:output, result_hash)
        evaluator_instance = smart_quality_evaluator.new
        result = evaluator_instance.evaluate(field_context)

        # Should be more lenient for gpt-3.5-turbo (1.1x multiplier)
        expect(result[:details][:base_quality]).to be < result[:score] + result[:details][:efficiency_penalty]
      end

      it "penalizes inefficient token usage" do
        result_hash = {
          output: "Short",
          usage: { total_tokens: 1500 },
          configuration: { model: "gpt-4o" }
        }

        field_context = RAAF::Eval::DSL::FieldContext.new(:output, result_hash)
        evaluator_instance = smart_quality_evaluator.new
        result = evaluator_instance.evaluate(field_context)

        # Should have efficiency penalty
        expect(result[:details][:efficiency_penalty]).to eq(0.1)
        expect(result[:label]).to eq("bad") # Score drops below 0.7
      end
    end
  end

  describe "seamless integration with built-in evaluators" do
    before do
      # Auto-register built-ins
      RAAF::Eval::DSL::EvaluatorRegistry.instance.auto_register_built_ins
      
      # Register custom evaluator
      RAAF::Eval.register_evaluator(:citation_grounding, citation_grounding_evaluator)
    end

    it "can retrieve both built-in and custom evaluators" do
      registry = RAAF::Eval::DSL::EvaluatorRegistry.instance
      
      # Built-in evaluators
      expect(registry.registered?(:semantic_similarity)).to be true
      expect(registry.registered?(:token_efficiency)).to be true
      
      # Custom evaluator
      expect(registry.registered?(:citation_grounding)).to be true
    end

    it "lists all registered evaluators (built-in + custom)" do
      registry = RAAF::Eval::DSL::EvaluatorRegistry.instance
      names = registry.all_names
      
      # Should have 22 built-ins + 1 custom
      expect(names.size).to eq(23)
      expect(names).to include(:semantic_similarity, :citation_grounding)
    end
  end
end
