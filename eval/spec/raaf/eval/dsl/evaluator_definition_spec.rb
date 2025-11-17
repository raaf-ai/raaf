# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Eval::DSL::EvaluatorDefinition do
  describe "module inclusion" do
    let(:test_class) do
      Class.new do
        include RAAF::Eval::DSL::EvaluatorDefinition
      end
    end

    it "extends class with ClassMethods when included" do
      expect(test_class).to respond_to(:select)
      expect(test_class).to respond_to(:evaluate_field)
      expect(test_class).to respond_to(:on_progress)
      expect(test_class).to respond_to(:history)
      expect(test_class).to respond_to(:evaluator)
      expect(test_class).to respond_to(:reset_evaluator!)
    end

    it "initializes evaluator configuration on inclusion" do
      config = test_class.instance_variable_get(:@_evaluator_config)
      expect(config).to include(
        selections: [],
        field_evaluations: {},
        progress_callback: nil,
        history_options: {}
      )
    end

    it "allows multiple classes to include the module independently" do
      class1 = Class.new { include RAAF::Eval::DSL::EvaluatorDefinition }
      class2 = Class.new { include RAAF::Eval::DSL::EvaluatorDefinition }

      class1.select "field1", as: :f1
      class2.select "field2", as: :f2

      config1 = class1.instance_variable_get(:@_evaluator_config)
      config2 = class2.instance_variable_get(:@_evaluator_config)

      expect(config1[:selections]).to eq([{ path: "field1", as: :f1 }])
      expect(config2[:selections]).to eq([{ path: "field2", as: :f2 }])
    end
  end

  describe "DSL methods" do
    let(:test_class) do
      Class.new do
        include RAAF::Eval::DSL::EvaluatorDefinition
      end
    end

    describe ".select" do
      it "stores field selections" do
        test_class.select "usage.total_tokens", as: :tokens
        test_class.select "messages.*.content", as: :messages

        config = test_class.instance_variable_get(:@_evaluator_config)
        expect(config[:selections]).to contain_exactly(
          { path: "usage.total_tokens", as: :tokens },
          { path: "messages.*.content", as: :messages }
        )
      end

      it "accumulates multiple selections" do
        test_class.select "field1", as: :f1
        test_class.select "field2", as: :f2

        config = test_class.instance_variable_get(:@_evaluator_config)
        expect(config[:selections].count).to eq(2)
      end

      it "preserves order of selections" do
        test_class.select "field1", as: :f1
        test_class.select "field2", as: :f2
        test_class.select "field3", as: :f3

        config = test_class.instance_variable_get(:@_evaluator_config)
        expect(config[:selections].map { |s| s[:as] }).to eq([:f1, :f2, :f3])
      end
    end

    describe ".evaluate_field" do
      it "stores field evaluation blocks" do
        block = -> { evaluate_with :similarity }
        test_class.evaluate_field :output, &block

        config = test_class.instance_variable_get(:@_evaluator_config)
        expect(config[:field_evaluations][:output]).to eq(block)
      end

      it "replaces previous block for same field" do
        test_class.evaluate_field(:output) { evaluate_with :similarity }
        second_block = -> { evaluate_with :regression }
        test_class.evaluate_field(:output, &second_block)

        config = test_class.instance_variable_get(:@_evaluator_config)
        expect(config[:field_evaluations][:output]).to eq(second_block)
        expect(config[:field_evaluations].keys).to eq([:output])
      end
    end

    describe ".on_progress" do
      it "stores progress callback" do
        callback = ->(event) { puts event.progress }
        test_class.on_progress(&callback)

        config = test_class.instance_variable_get(:@_evaluator_config)
        expect(config[:progress_callback]).to eq(callback)
      end

      it "replaces previous callback" do
        test_class.on_progress { |e| puts "first" }
        second_callback = ->(e) { puts "second" }
        test_class.on_progress(&second_callback)

        config = test_class.instance_variable_get(:@_evaluator_config)
        expect(config[:progress_callback]).to eq(second_callback)
      end
    end

    describe ".history" do
      it "stores history configuration options" do
        test_class.history baseline: true, last_n: 10

        config = test_class.instance_variable_get(:@_evaluator_config)
        expect(config[:history_options]).to eq(
          baseline: true,
          last_n: 10
        )
      end

      it "merges multiple history calls" do
        test_class.history baseline: true
        test_class.history last_n: 10, auto_save: true

        config = test_class.instance_variable_get(:@_evaluator_config)
        expect(config[:history_options]).to eq(
          baseline: true,
          last_n: 10,
          auto_save: true
        )
      end
    end
  end

  describe "evaluator caching" do
    let(:test_class) do
      Class.new do
        include RAAF::Eval::DSL::EvaluatorDefinition

        select "output", as: :output
        evaluate_field :output do
          evaluate_with :semantic_similarity
        end
      end
    end

    before do
      # Reset evaluator between tests
      test_class.reset_evaluator! if test_class.instance_variable_defined?(:@evaluator)
    end

    it "caches evaluator on first call" do
      eval1 = test_class.evaluator
      eval2 = test_class.evaluator

      expect(eval1).to be_a(RAAF::Eval::DslEngine::Evaluator)
      expect(eval1.object_id).to eq(eval2.object_id)
    end

    it "rebuilds evaluator after reset" do
      eval1 = test_class.evaluator
      test_class.reset_evaluator!
      eval2 = test_class.evaluator

      expect(eval1.object_id).not_to eq(eval2.object_id)
    end

    it "reset_evaluator! returns nil" do
      test_class.evaluator
      result = test_class.reset_evaluator!

      expect(result).to be_nil
    end
  end
end
