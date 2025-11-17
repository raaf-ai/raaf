# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Evaluator Definition DSL Integration" do
  describe "end-to-end evaluation" do
    let(:evaluator_class) do
      Class.new do
        include RAAF::Eval::DSL::EvaluatorDefinition

        select "output", as: :output
        evaluate_field :output do
          evaluate_with :semantic_similarity, threshold: 0.85
        end
      end
    end

    it "builds a functional evaluator from DSL configuration" do
      evaluator = evaluator_class.evaluator

      expect(evaluator).to be_a(RAAF::Eval::DslEngine::Evaluator)
      expect(evaluator).to respond_to(:evaluate)
    end

    it "evaluator is properly cached" do
      eval1 = evaluator_class.evaluator
      eval2 = evaluator_class.evaluator

      expect(eval1.object_id).to eq(eval2.object_id)
    end
  end

  describe "complex evaluator definition" do
    let(:complex_evaluator) do
      Class.new do
        include RAAF::Eval::DSL::EvaluatorDefinition

        select "usage.total_tokens", as: :tokens
        select "usage.prompt_tokens", as: :prompt_tokens
        select "output", as: :output

        evaluate_field :tokens do
          evaluate_with :token_efficiency, max_increase_pct: 15
        end

        evaluate_field :output do
          evaluate_with :semantic_similarity, threshold: 0.85
          evaluate_with :no_regression
          combine_with :and
        end

        on_progress do |event|
          # Progress callback
        end

        history auto_save: true, retention_count: 10, retention_days: 30
      end
    end

    it "handles complex configurations correctly" do
      evaluator = complex_evaluator.evaluator

      expect(evaluator).to be_a(RAAF::Eval::DslEngine::Evaluator)

      # Verify configuration was applied
      config = complex_evaluator.instance_variable_get(:@_evaluator_config)
      expect(config[:selections].count).to eq(3)
      expect(config[:field_evaluations].keys).to contain_exactly(:tokens, :output)
      expect(config[:progress_callback]).not_to be_nil
      expect(config[:history_options]).to include(auto_save: true, retention_count: 10, retention_days: 30)
    end
  end

  describe "module pattern comparison" do
    context "before pattern (simulated)" do
      let(:old_pattern_class) do
        Class.new do
          class << self
            def evaluator
              @evaluator ||= RAAF::Eval.define do
                select "output", as: :output
                evaluate_field :output do
                  evaluate_with :semantic_similarity
                end
              end
            end

            def reset_evaluator!
              @evaluator = nil
            end
          end
        end
      end

      it "works with old singleton pattern" do
        evaluator = old_pattern_class.evaluator
        expect(evaluator).to be_a(RAAF::Eval::DslEngine::Evaluator)
      end
    end

    context "new pattern" do
      let(:new_pattern_class) do
        Class.new do
          include RAAF::Eval::DSL::EvaluatorDefinition

          select "output", as: :output
          evaluate_field :output do
            evaluate_with :semantic_similarity
          end
        end
      end

      it "works with new module pattern" do
        evaluator = new_pattern_class.evaluator
        expect(evaluator).to be_a(RAAF::Eval::DslEngine::Evaluator)
      end

      it "provides same API as old pattern" do
        expect(new_pattern_class).to respond_to(:evaluator)
        expect(new_pattern_class).to respond_to(:reset_evaluator!)

        evaluator = new_pattern_class.evaluator
        expect(evaluator).to be_a(RAAF::Eval::DslEngine::Evaluator)

        new_pattern_class.reset_evaluator!
        evaluator2 = new_pattern_class.evaluator
        expect(evaluator2.object_id).not_to eq(evaluator.object_id)
      end
    end
  end
end
