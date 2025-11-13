# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Eval, ".define" do
  describe "top-level DSL entry point" do
    it "returns an evaluator instance when given a block" do
      evaluator = described_class.define do
        # Empty block is valid
      end

      expect(evaluator).to be_a(RAAF::Eval::DslEngine::Evaluator)
    end

    it "evaluates the block in DSL context" do
      field_selected = false

      evaluator = described_class.define do
        select "output", as: :output
        field_selected = true
      end

      expect(field_selected).to be true
      expect(evaluator).to be_a(RAAF::Eval::DslEngine::Evaluator)
    end

    it "passes configuration from DSL block to evaluator" do
      evaluator = described_class.define do
        select "usage.total_tokens", as: :tokens

        evaluate_field :tokens do
          evaluate_with :token_efficiency, max_increase_pct: 10
        end
      end

      # Evaluator should have the field selection configured
      definition = evaluator.instance_variable_get(:@definition)
      expect(definition).to be_a(Hash)
      expect(definition[:field_selector]).to be_a(RAAF::Eval::DSL::FieldSelector)
    end

    it "raises error when no block given" do
      expect {
        described_class.define
      }.to raise_error(ArgumentError, /no block given/)
    end
  end

  describe "DSL builder pattern" do
    it "collects field selections" do
      evaluator = described_class.define do
        select "output", as: :output
        select "usage.total_tokens", as: :tokens
        select "latency_ms", as: :latency
      end

      definition = evaluator.instance_variable_get(:@definition)
      field_selector = definition[:field_selector]

      expect(field_selector.fields.size).to eq(3)
    end

    it "collects field evaluators" do
      evaluator = described_class.define do
        select "output", as: :output

        evaluate_field :output do
          evaluate_with :semantic_similarity, threshold: 0.85
          evaluate_with :coherence, min_score: 0.8
          combine_with :and
        end
      end

      definition = evaluator.instance_variable_get(:@definition)
      evaluator_definition = definition[:evaluator_definition]

      expect(evaluator_definition.field_evaluator_sets[:output]).to be_a(RAAF::Eval::DSL::FieldEvaluatorSet)
    end

    it "collects progress callbacks" do
      callback_called = false

      evaluator = described_class.define do
        on_progress do |event|
          callback_called = true
        end
      end

      definition = evaluator.instance_variable_get(:@definition)
      callbacks = definition[:progress_callbacks]

      expect(callbacks.size).to eq(1)
      callbacks.first.call({})
      expect(callback_called).to be true
    end

    it "collects history configuration" do
      evaluator = described_class.define do
        history do
          auto_save true
          retention_days 30
          retention_count 100
          tags environment: 'production'
        end
      end

      definition = evaluator.instance_variable_get(:@definition)
      history_config = definition[:history_config]

      expect(history_config[:auto_save]).to be true
      expect(history_config[:retention_days]).to eq(30)
      expect(history_config[:retention_count]).to eq(100)
      expect(history_config[:tags]).to eq(environment: 'production')
    end
  end
end
