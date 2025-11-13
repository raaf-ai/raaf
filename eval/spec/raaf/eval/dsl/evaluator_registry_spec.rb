# frozen_string_literal: true

require "spec_helper"
require "raaf/eval/dsl/evaluator_registry"
require "raaf/eval/dsl/evaluator"

RSpec.describe RAAF::Eval::DSL::EvaluatorRegistry do
  # Reset registry between tests
  before do
    described_class.instance.instance_variable_set(:@evaluators, {})
  end

  describe ".instance" do
    it "returns a singleton instance" do
      instance1 = described_class.instance
      instance2 = described_class.instance
      expect(instance1).to be(instance2)
    end
  end

  describe "#register" do
    let(:test_evaluator) do
      Class.new do
        include RAAF::Eval::DSL::Evaluator
        evaluator_name :test_evaluator

        def evaluate(field_context, **options)
          { passed: true, message: "Test passed" }
        end
      end
    end

    it "registers an evaluator by name" do
      registry = described_class.instance
      registry.register(:test_evaluator, test_evaluator)
      
      expect(registry.get(:test_evaluator)).to eq(test_evaluator)
    end

    it "accepts string names and converts to symbols" do
      registry = described_class.instance
      registry.register("test_evaluator", test_evaluator)
      
      expect(registry.get(:test_evaluator)).to eq(test_evaluator)
      expect(registry.get("test_evaluator")).to eq(test_evaluator)
    end

    it "raises error for duplicate registration" do
      registry = described_class.instance
      registry.register(:test_evaluator, test_evaluator)
      
      expect {
        registry.register(:test_evaluator, test_evaluator)
      }.to raise_error(RAAF::Eval::DSL::EvaluatorRegistry::DuplicateEvaluatorError, 
                       /Evaluator 'test_evaluator' is already registered/)
    end

    it "validates that evaluator includes Evaluator module" do
      invalid_evaluator = Class.new
      registry = described_class.instance
      
      expect {
        registry.register(:invalid, invalid_evaluator)
      }.to raise_error(RAAF::Eval::DSL::EvaluatorRegistry::InvalidEvaluatorError,
                       /must include RAAF::Eval::DSL::Evaluator/)
    end

    it "validates that evaluator_name matches registration name" do
      mismatched_evaluator = Class.new do
        include RAAF::Eval::DSL::Evaluator
        evaluator_name :wrong_name

        def evaluate(field_context, **options)
          { passed: true, message: "Test" }
        end
      end

      registry = described_class.instance
      
      expect {
        registry.register(:test_evaluator, mismatched_evaluator)
      }.to raise_error(RAAF::Eval::DSL::EvaluatorRegistry::InvalidEvaluatorError,
                       /evaluator_name must match registration name/)
    end

    it "is thread-safe during registration" do
      registry = described_class.instance
      threads = []
      
      10.times do |i|
        threads << Thread.new do
          evaluator = Class.new do
            include RAAF::Eval::DSL::Evaluator
            define_singleton_method(:evaluator_name) { :"test_evaluator_#{i}" }

            def evaluate(field_context, **options)
              { passed: true, message: "Test" }
            end
          end
          
          evaluator.extend(RAAF::Eval::DSL::Evaluator::ClassMethods)
          evaluator.evaluator_name(:"test_evaluator_#{i}")
          
          registry.register(:"test_evaluator_#{i}", evaluator)
        end
      end
      
      threads.each(&:join)
      
      expect(registry.all_names.size).to eq(10)
    end
  end

  describe "#get" do
    let(:test_evaluator) do
      Class.new do
        include RAAF::Eval::DSL::Evaluator
        evaluator_name :test_evaluator

        def evaluate(field_context, **options)
          { passed: true, message: "Test passed" }
        end
      end
    end

    before do
      described_class.instance.register(:test_evaluator, test_evaluator)
    end

    it "retrieves a registered evaluator by symbol name" do
      evaluator = described_class.instance.get(:test_evaluator)
      expect(evaluator).to eq(test_evaluator)
    end

    it "retrieves a registered evaluator by string name" do
      evaluator = described_class.instance.get("test_evaluator")
      expect(evaluator).to eq(test_evaluator)
    end

    it "raises error for unregistered evaluator" do
      expect {
        described_class.instance.get(:nonexistent)
      }.to raise_error(RAAF::Eval::DSL::EvaluatorRegistry::UnregisteredEvaluatorError,
                       /Evaluator 'nonexistent' not found/)
    end

    it "provides suggestions for similar evaluator names" do
      described_class.instance.register(:semantic_similarity, test_evaluator)
      
      expect {
        described_class.instance.get(:semantic_similary) # typo
      }.to raise_error(RAAF::Eval::DSL::EvaluatorRegistry::UnregisteredEvaluatorError,
                       /Did you mean: semantic_similarity/)
    end
  end

  describe "#registered?" do
    let(:test_evaluator) do
      Class.new do
        include RAAF::Eval::DSL::Evaluator
        evaluator_name :test_evaluator

        def evaluate(field_context, **options)
          { passed: true, message: "Test passed" }
        end
      end
    end

    it "returns true for registered evaluators" do
      described_class.instance.register(:test_evaluator, test_evaluator)
      expect(described_class.instance.registered?(:test_evaluator)).to be true
    end

    it "returns false for unregistered evaluators" do
      expect(described_class.instance.registered?(:nonexistent)).to be false
    end

    it "accepts both symbol and string names" do
      described_class.instance.register(:test_evaluator, test_evaluator)
      expect(described_class.instance.registered?("test_evaluator")).to be true
    end
  end

  describe "#all_names" do
    let(:evaluator1) do
      Class.new do
        include RAAF::Eval::DSL::Evaluator
        evaluator_name :evaluator1

        def evaluate(field_context, **options)
          { passed: true, message: "Test" }
        end
      end
    end

    let(:evaluator2) do
      Class.new do
        include RAAF::Eval::DSL::Evaluator
        evaluator_name :evaluator2

        def evaluate(field_context, **options)
          { passed: true, message: "Test" }
        end
      end
    end

    it "returns all registered evaluator names" do
      registry = described_class.instance
      registry.register(:evaluator1, evaluator1)
      registry.register(:evaluator2, evaluator2)
      
      names = registry.all_names
      expect(names).to contain_exactly(:evaluator1, :evaluator2)
    end

    it "returns empty array when no evaluators registered" do
      expect(described_class.instance.all_names).to eq([])
    end
  end

  describe "#auto_register_built_ins" do
    it "registers all built-in evaluators" do
      registry = described_class.instance
      registry.auto_register_built_ins
      
      # Should have 22 built-in evaluators
      expect(registry.all_names.size).to eq(22)
      
      # Verify some key evaluators are registered
      expect(registry.registered?(:semantic_similarity)).to be true
      expect(registry.registered?(:token_efficiency)).to be true
      expect(registry.registered?(:no_regression)).to be true
    end

    it "is idempotent (can be called multiple times)" do
      registry = described_class.instance
      registry.auto_register_built_ins
      count1 = registry.all_names.size
      
      registry.auto_register_built_ins
      count2 = registry.all_names.size
      
      expect(count1).to eq(count2)
    end
  end
end
