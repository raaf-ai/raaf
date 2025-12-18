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
      expect(test_class).to respond_to(:evaluator_name)
    end

    it "includes the Evaluator module for interface compliance" do
      expect(test_class.included_modules).to include(RAAF::Eval::DSL::Evaluator)
    end

    it "provides instance evaluate method" do
      instance = test_class.new
      expect(instance).to respond_to(:evaluate)
    end

    it "initializes evaluator configuration on inclusion" do
      config = test_class.instance_variable_get(:@_evaluator_config)
      expect(config).to include(
        selections: [],
        field_evaluations: {},
        progress_callback: nil
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

    describe ".history (deprecated)" do
      it "raises DeprecatedDSLError when called with options" do
        expect {
          test_class.history baseline: true, last_n: 10
        }.to raise_error(RAAF::Eval::DeprecatedDSLError, /history/)
      end

      it "raises DeprecatedDSLError when called without options" do
        expect {
          test_class.history
        }.to raise_error(RAAF::Eval::DeprecatedDSLError, /history/)
      end

      it "provides migration guidance in the error message" do
        error_message = nil

        begin
          test_class.history auto_save: true
        rescue RAAF::Eval::DeprecatedDSLError => e
          error_message = e.message
        end

        expect(error_message).to include("database-backed policies")
        expect(error_message).to include("EvaluationPolicy")
        expect(error_message).to include("CONTINUOUS_EVAL_MIGRATION")
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

  describe "auto-registration with evaluator_name" do
    let(:registry) { RAAF::Eval::DSL::EvaluatorRegistry.instance }

    # Use unique names for each test to avoid conflicts
    let(:unique_name) { :"test_auto_register_#{SecureRandom.hex(4)}" }

    it "auto-registers when evaluator_name is called with a name" do
      test_class = Class.new do
        include RAAF::Eval::DSL::EvaluatorDefinition
      end
      test_class.evaluator_name(unique_name)

      expect(registry.registered?(unique_name)).to be true
      expect(registry.get(unique_name)).to eq(test_class)
    end

    it "returns the evaluator name when called as getter" do
      test_class = Class.new do
        include RAAF::Eval::DSL::EvaluatorDefinition
      end
      test_class.evaluator_name(unique_name)

      expect(test_class.evaluator_name).to eq(unique_name)
    end

    it "converts string names to symbols" do
      string_name = "string_eval_#{SecureRandom.hex(4)}"
      test_class = Class.new do
        include RAAF::Eval::DSL::EvaluatorDefinition
      end
      test_class.evaluator_name(string_name)

      expect(test_class.evaluator_name).to eq(string_name.to_sym)
      expect(registry.registered?(string_name.to_sym)).to be true
    end

    it "returns nil when evaluator_name not set" do
      test_class = Class.new do
        include RAAF::Eval::DSL::EvaluatorDefinition
      end

      expect(test_class.evaluator_name).to be_nil
    end
  end

  describe "for_agent and agent_name" do
    it "stores the agent name when for_agent is called with a name" do
      test_class = Class.new do
        include RAAF::Eval::DSL::EvaluatorDefinition
        for_agent "Prospect::Scoring"
      end

      expect(test_class.for_agent).to eq("Prospect::Scoring")
    end

    it "returns nil for for_agent when not set" do
      test_class = Class.new do
        include RAAF::Eval::DSL::EvaluatorDefinition
      end

      expect(test_class.for_agent).to be_nil
    end

    it "returns explicit agent name via agent_name method" do
      test_class = Class.new do
        include RAAF::Eval::DSL::EvaluatorDefinition
        for_agent "Custom::Agent"
      end

      expect(test_class.agent_name).to eq("Custom::Agent")
    end

    it "derives agent name from class name when not explicitly set" do
      # Create a class with a proper name in Eval namespace
      stub_const("Eval::Prospect::Scoring", Class.new do
        include RAAF::Eval::DSL::EvaluatorDefinition
      end)

      expect(Eval::Prospect::Scoring.agent_name).to eq("Prospect::Scoring")
    end

    it "returns nil when class is not in Eval namespace and for_agent not set" do
      # Anonymous class has no name
      test_class = Class.new do
        include RAAF::Eval::DSL::EvaluatorDefinition
      end

      expect(test_class.agent_name).to be_nil
    end
  end

  describe "evaluated_fields and field_selections" do
    let(:test_class) do
      Class.new do
        include RAAF::Eval::DSL::EvaluatorDefinition

        select "output", as: :output
        select "usage.total_tokens", as: :tokens
        select "latency", as: :latency

        evaluate_field :output do
          evaluate_with :semantic_similarity
        end

        evaluate_field :tokens do
          evaluate_with :threshold, max: 4000
        end
      end
    end

    it "returns all field names being evaluated via evaluated_fields" do
      expect(test_class.evaluated_fields).to contain_exactly(:output, :tokens)
    end

    it "returns all field selections via field_selections" do
      expect(test_class.field_selections).to contain_exactly(
        { path: "output", as: :output },
        { path: "usage.total_tokens", as: :tokens },
        { path: "latency", as: :latency }
      )
    end

    it "returns empty array when no fields are evaluated" do
      empty_class = Class.new do
        include RAAF::Eval::DSL::EvaluatorDefinition
      end

      expect(empty_class.evaluated_fields).to eq([])
      expect(empty_class.field_selections).to eq([])
    end
  end

  describe "instance evaluate delegation" do
    let(:test_class) do
      Class.new do
        include RAAF::Eval::DSL::EvaluatorDefinition

        select "output", as: :output
        evaluate_field :output do
          evaluate_with :json_validity
        end
      end
    end

    it "delegates instance evaluate to class evaluator" do
      instance = test_class.new
      mock_evaluator = double("evaluator")
      field_context = double("field_context")

      allow(test_class).to receive(:evaluator).and_return(mock_evaluator)
      expect(mock_evaluator).to receive(:evaluate).with(field_context, foo: :bar)

      instance.evaluate(field_context, foo: :bar)
    end

    it "passes options through to the evaluator" do
      instance = test_class.new
      mock_evaluator = double("evaluator")
      field_context = double("field_context")

      allow(test_class).to receive(:evaluator).and_return(mock_evaluator)
      expect(mock_evaluator).to receive(:evaluate).with(field_context, threshold: 0.9, strict: true)

      instance.evaluate(field_context, threshold: 0.9, strict: true)
    end
  end
end
