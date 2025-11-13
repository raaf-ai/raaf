# frozen_string_literal: true

RSpec.describe RAAF::Eval::DSL::FieldEvaluatorSet do
  let(:field_set) { described_class.new(:output) }

  describe "#initialize" do
    it "sets field name" do
      expect(field_set.field_name).to eq(:output)
    end

    it "starts with empty evaluators" do
      expect(field_set.evaluators).to be_empty
    end

    it "defaults to AND combination" do
      expect(field_set.combination_strategy).to eq(:and)
    end
  end

  describe "#add_evaluator" do
    context "with basic evaluator" do
      it "adds evaluator with name and options" do
        field_set.add_evaluator(:semantic_similarity, { threshold: 0.85 })

        expect(field_set.evaluators.size).to eq(1)
        expect(field_set.evaluators.first[:name]).to eq(:semantic_similarity)
        expect(field_set.evaluators.first[:options]).to eq({ threshold: 0.85 })
      end

      it "uses evaluator name as alias by default" do
        field_set.add_evaluator(:semantic_similarity, { threshold: 0.85 })

        expect(field_set.evaluators.first[:alias]).to eq(:semantic_similarity)
      end
    end

    context "with custom alias" do
      it "stores custom alias" do
        field_set.add_evaluator(:semantic_similarity, { threshold: 0.85 }, evaluator_alias: :similarity_check)
        
        expect(field_set.evaluators.first[:alias]).to eq(:similarity_check)
      end
    end

    context "with duplicate alias" do
      before do
        field_set.add_evaluator(:semantic_similarity, {}, evaluator_alias: :check1)
      end

      it "raises error when alias duplicated" do
        expect {
          field_set.add_evaluator(:coherence, {}, evaluator_alias: :check1)
        }.to raise_error(RAAF::Eval::DSL::DuplicateAliasError)
      end
    end

    context "with multiple evaluators" do
      it "maintains definition order" do
        field_set.add_evaluator(:first, {})
        field_set.add_evaluator(:second, {})
        field_set.add_evaluator(:third, {})
        
        names = field_set.evaluators.map { |e| e[:name] }
        expect(names).to eq([:first, :second, :third])
      end
    end
  end

  describe "#set_combination" do
    it "sets AND strategy" do
      field_set.set_combination(:and)
      expect(field_set.combination_strategy).to eq(:and)
    end

    it "sets OR strategy" do
      field_set.set_combination(:or)
      expect(field_set.combination_strategy).to eq(:or)
    end

    it "sets lambda strategy" do
      lambda_proc = lambda { |results| results }
      field_set.set_combination(lambda_proc)
      expect(field_set.combination_strategy).to eq(lambda_proc)
    end

    it "raises error for invalid strategy" do
      expect {
        field_set.set_combination(:invalid)
      }.to raise_error(RAAF::Eval::DSL::InvalidCombinationStrategyError)
    end
  end

  describe "#evaluate" do
    let(:field_context) do
      double(:field_context,
             baseline_value: "original output",
             result_value: "new output",
             field_name: :output)
    end

    before do
      # Mock evaluator registry
      allow(RAAF::Eval).to receive(:get_evaluator) do |name|
        case name
        when :semantic_similarity
          Class.new do
            def evaluate(_context, **options)
              threshold = options[:threshold] || 0.8
              {
                passed: true,
                score: 0.9,
                details: { similarity_score: 0.9 },
                message: "Similarity: 0.9 (threshold: #{threshold})"
              }
            end
          end
        when :coherence
          Class.new do
            def evaluate(_context, **options)
              min_score = options[:min_score] || 0.7
              {
                passed: true,
                score: 0.85,
                details: { coherence_score: 0.85 },
                message: "Coherence: 0.85 (min: #{min_score})"
              }
            end
          end
        when :failing_evaluator
          Class.new do
            def evaluate(_context, **_options)
              {
                passed: false,
                score: 0.5,
                details: {},
                message: "Failed check"
              }
            end
          end
        end
      end
    end

    context "with AND combination" do
      before do
        field_set.add_evaluator(:semantic_similarity, { threshold: 0.85 })
        field_set.add_evaluator(:coherence, { min_score: 0.8 })
        field_set.set_combination(:and)
      end

      it "combines results with AND logic" do
        result = field_set.evaluate(field_context)
        
        expect(result[:passed]).to be true
        expect(result[:score]).to eq(0.85) # minimum
      end
    end

    context "with OR combination" do
      before do
        field_set.add_evaluator(:semantic_similarity, { threshold: 0.85 })
        field_set.add_evaluator(:failing_evaluator, {})
        field_set.set_combination(:or)
      end

      it "passes when at least one evaluator passes" do
        result = field_set.evaluate(field_context)
        
        expect(result[:passed]).to be true
        expect(result[:score]).to eq(0.9) # maximum
      end
    end

    context "with lambda combination" do
      before do
        field_set.add_evaluator(:semantic_similarity, { threshold: 0.85 }, evaluator_alias: :sim)
        field_set.add_evaluator(:coherence, { min_score: 0.8 }, evaluator_alias: :coh)
        
        field_set.set_combination(lambda { |results|
          avg_score = (results[:sim][:score] + results[:coh][:score]) / 2.0
          {
            passed: avg_score >= 0.8,
            score: avg_score,
            details: { average: avg_score },
            message: "Average: #{avg_score}"
          }
        })
      end

      it "applies custom lambda logic" do
        result = field_set.evaluate(field_context)
        
        expected_avg = (0.9 + 0.85) / 2.0
        expect(result[:score]).to eq(expected_avg)
        expect(result[:passed]).to be true
      end
    end

    context "with evaluator exception" do
      before do
        allow(RAAF::Eval).to receive(:get_evaluator).with(:error_evaluator).and_return(
          Class.new do
            def evaluate(_context, **_options)
              raise StandardError, "Evaluator crashed"
            end
          end
        )

        field_set.add_evaluator(:semantic_similarity, { threshold: 0.85 })
        field_set.add_evaluator(:error_evaluator, {})
        field_set.set_combination(:and)
      end

      it "marks failed evaluator but continues" do
        result = field_set.evaluate(field_context)
        
        # Should fail because one evaluator failed (AND logic)
        expect(result[:passed]).to be false
      end

      it "includes error details" do
        result = field_set.evaluate(field_context)
        
        # Error details should be captured
        expect(result[:message]).to include("Evaluator crashed")
      end
    end

    context "with multiple evaluators and partial failure" do
      before do
        field_set.add_evaluator(:semantic_similarity, { threshold: 0.85 })
        field_set.add_evaluator(:failing_evaluator, {})
        field_set.add_evaluator(:coherence, { min_score: 0.8 })
      end

      it "fails with AND when one fails" do
        field_set.set_combination(:and)
        result = field_set.evaluate(field_context)
        
        expect(result[:passed]).to be false
      end

      it "passes with OR when one passes" do
        field_set.set_combination(:or)
        result = field_set.evaluate(field_context)
        
        expect(result[:passed]).to be true
      end
    end

    context "sequential execution verification" do
      let(:execution_order) { [] }

      before do
        allow(RAAF::Eval).to receive(:get_evaluator) do |name|
          order_tracker = execution_order
          Class.new do
            define_method(:initialize) do
              @name = name
              @execution_order = order_tracker
            end

            define_method(:evaluate) do |_context, **_options|
              @execution_order << @name
              { passed: true, score: 0.8, details: {}, message: "Executed #{@name}" }
            end
          end
        end

        field_set.add_evaluator(:first, {})
        field_set.add_evaluator(:second, {})
        field_set.add_evaluator(:third, {})
      end

      it "executes evaluators in definition order" do
        field_set.evaluate(field_context)

        expect(execution_order).to eq([:first, :second, :third])
      end
    end
  end
end
