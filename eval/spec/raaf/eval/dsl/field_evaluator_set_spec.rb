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
        expect do
          field_set.add_evaluator(:coherence, {}, evaluator_alias: :check1)
        end.to raise_error(RAAF::Eval::DSL::DuplicateAliasError)
      end
    end

    context "with multiple evaluators" do
      it "maintains definition order" do
        field_set.add_evaluator(:first, {})
        field_set.add_evaluator(:second, {})
        field_set.add_evaluator(:third, {})

        names = field_set.evaluators.map { |e| e[:name] }
        expect(names).to eq(%i[first second third])
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
      lambda_proc = ->(results) { results }
      field_set.set_combination(lambda_proc)
      expect(field_set.combination_strategy).to eq(lambda_proc)
    end

    it "raises error for invalid strategy" do
      expect do
        field_set.set_combination(:invalid)
      end.to raise_error(RAAF::Eval::DSL::InvalidCombinationStrategyError)
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
              { label: "good",
                score: 0.9,
                details: { similarity_score: 0.9 },
                message: "Similarity: 0.9 (threshold: #{threshold})" }
            end
          end
        when :coherence
          Class.new do
            def evaluate(_context, **options)
              min_score = options[:min_score] || 0.7
              { label: "good",
                score: 0.85,
                details: { coherence_score: 0.85 },
                message: "Coherence: 0.85 (min: #{min_score})" }
            end
          end
        when :failing_evaluator
          Class.new do
            def evaluate(_context, **_options)
              { label: "bad",
                score: 0.5,
                details: {},
                message: "Failed check" }
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
        combined = field_set.evaluate(field_context)[:combined]

        expect(combined[:score]).to eq(0.85) # minimum
        expect(combined[:message]).to start_with("AND:")
      end
    end

    context "with OR combination" do
      before do
        field_set.add_evaluator(:semantic_similarity, { threshold: 0.85 })
        field_set.add_evaluator(:failing_evaluator, {})
        field_set.set_combination(:or)
      end

      it "takes the best score when at least one evaluator scores well" do
        combined = field_set.evaluate(field_context)[:combined]

        expect(combined[:score]).to eq(0.9) # maximum
        expect(combined[:message]).to start_with("OR:")
      end
    end

    context "with lambda combination" do
      before do
        field_set.add_evaluator(:semantic_similarity, { threshold: 0.85 }, evaluator_alias: :sim)
        field_set.add_evaluator(:coherence, { min_score: 0.8 }, evaluator_alias: :coh)

        field_set.set_combination(lambda { |results|
          avg_score = (results[:sim][:score] + results[:coh][:score]) / 2.0
          {
            label: if avg_score >= 0.8
                     "good"
                   else
                     (avg_score >= 0.6 ? "average" : "bad")
                   end,
            passed: avg_score >= 0.6,
            score: avg_score,
            details: { average: avg_score },
            message: "Average: #{avg_score}"
          }
        })
      end

      it "applies custom lambda logic" do
        combined = field_set.evaluate(field_context)[:combined]

        expected_avg = (0.9 + 0.85) / 2.0
        expect(combined[:score]).to eq(expected_avg)
        expect(combined[:label]).to eq("good")
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
        combined = field_set.evaluate(field_context)[:combined]

        # The crash scores zero, and AND takes the minimum
        expect(combined[:passed]).to be false
        expect(combined[:score]).to eq(0.0)
      end

      it "includes error details" do
        combined = field_set.evaluate(field_context)[:combined]

        # Error details should be captured
        expect(combined[:message]).to include("Evaluator crashed")
      end

      it "flags the combined result as errored and names the evaluator" do
        combined = field_set.evaluate(field_context)[:combined]

        expect(combined[:error]).to be true
        expect(combined[:errored_evaluators]).to eq([:error_evaluator])
      end

      it "flags only the evaluator that raised" do
        individual = field_set.evaluate(field_context)[:individual]

        expect(individual[:error_evaluator][:error]).to be true
        expect(individual[:error_evaluator][:details][:error_class]).to eq("StandardError")
        expect(individual[:semantic_similarity][:error]).to be_nil
      end
    end

    context "with multiple evaluators and partial failure" do
      before do
        field_set.add_evaluator(:semantic_similarity, { threshold: 0.85 })
        field_set.add_evaluator(:failing_evaluator, {})
        field_set.add_evaluator(:coherence, { min_score: 0.8 })
      end

      it "takes the worst score with AND" do
        field_set.set_combination(:and)
        combined = field_set.evaluate(field_context)[:combined]

        expect(combined[:score]).to eq(0.5)
      end

      it "takes the best score with OR" do
        field_set.set_combination(:or)
        combined = field_set.evaluate(field_context)[:combined]

        expect(combined[:score]).to eq(0.9)
      end

      it "does not flag an error when every evaluator returned a verdict" do
        field_set.set_combination(:and)
        combined = field_set.evaluate(field_context)[:combined]

        expect(combined[:error]).to be_nil
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
              { label: "good", score: 0.8, details: {}, message: "Executed #{@name}" }
            end
          end
        end

        field_set.add_evaluator(:first, {})
        field_set.add_evaluator(:second, {})
        field_set.add_evaluator(:third, {})
      end

      it "executes evaluators in definition order" do
        field_set.evaluate(field_context)

        expect(execution_order).to eq(%i[first second third])
      end
    end
  end
end
