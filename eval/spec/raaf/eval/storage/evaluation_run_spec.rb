# frozen_string_literal: true

require "spec_helper"
require "raaf/eval/storage/evaluation_run"

RSpec.describe RAAF::Eval::Storage::EvaluationRun do
  # Clear all runs before each test to ensure clean state
  before { described_class.destroy_all }
  after { described_class.destroy_all }

  describe ".create!" do
    it "creates a new evaluation run with all attributes" do
      run = described_class.create!(
        evaluator_name: "test_evaluator",
        configuration_name: "baseline",
        span_id: "span_123",
        tags: { environment: "test", version: "1.0.0" },
        result_data: { field_results: {}, passed: true },
        field_results: { output: { passed: true, score: 0.95 } },
        overall_passed: true,
        aggregate_score: 0.95,
        duration_ms: 1234.56
      )

      expect(run.id).not_to be_nil
      expect(run.evaluator_name).to eq("test_evaluator")
      expect(run.configuration_name).to eq("baseline")
      expect(run.span_id).to eq("span_123")
      expect(run.tags).to eq({ environment: "test", version: "1.0.0" })
      expect(run.result_data).to eq({ field_results: {}, passed: true })
      expect(run.field_results).to eq({ output: { passed: true, score: 0.95 } })
      expect(run.overall_passed).to be true
      expect(run.aggregate_score).to eq(0.95)
      expect(run.duration_ms).to eq(1234.56)
      expect(run.created_at).to be_a(Time)
    end

    it "auto-assigns sequential IDs" do
      run1 = described_class.create!(evaluator_name: "test1", configuration_name: "default", span_id: "s1")
      run2 = described_class.create!(evaluator_name: "test2", configuration_name: "default", span_id: "s2")

      expect(run2.id).to eq(run1.id + 1)
    end

    it "sets created_at automatically" do
      before_create = Time.now
      run = described_class.create!(evaluator_name: "test", configuration_name: "default", span_id: "s1")
      after_create = Time.now

      expect(run.created_at).to be_between(before_create, after_create)
    end
  end

  describe ".all" do
    it "returns all evaluation runs" do
      described_class.create!(evaluator_name: "test1", configuration_name: "default", span_id: "s1")
      described_class.create!(evaluator_name: "test2", configuration_name: "default", span_id: "s2")

      expect(described_class.all.size).to eq(2)
    end

    it "returns empty array when no runs exist" do
      expect(described_class.all).to be_empty
    end
  end

  describe ".find" do
    it "finds run by ID" do
      run = described_class.create!(evaluator_name: "test", configuration_name: "default", span_id: "s1")

      found = described_class.find(run.id)
      expect(found).to eq(run)
      expect(found.evaluator_name).to eq("test")
    end

    it "returns nil when run not found" do
      expect(described_class.find(999)).to be_nil
    end
  end

  describe ".where" do
    before do
      described_class.create!(evaluator_name: "test1", configuration_name: "baseline", span_id: "s1")
      described_class.create!(evaluator_name: "test2", configuration_name: "baseline", span_id: "s2")
      described_class.create!(evaluator_name: "test1", configuration_name: "experiment", span_id: "s3")
    end

    it "filters by evaluator_name" do
      results = described_class.where(evaluator_name: "test1")
      expect(results.size).to eq(2)
      expect(results.map(&:evaluator_name).uniq).to eq(["test1"])
    end

    it "filters by configuration_name" do
      results = described_class.where(configuration_name: "baseline")
      expect(results.size).to eq(2)
      expect(results.map(&:configuration_name).uniq).to eq(["baseline"])
    end

    it "filters by multiple conditions" do
      results = described_class.where(evaluator_name: "test1", configuration_name: "baseline")
      expect(results.size).to eq(1)
      expect(results.first.evaluator_name).to eq("test1")
      expect(results.first.configuration_name).to eq("baseline")
    end

    it "returns empty array when no matches" do
      results = described_class.where(evaluator_name: "nonexistent")
      expect(results).to be_empty
    end
  end

  describe ".order" do
    it "orders by created_at ascending" do
      run1 = described_class.create!(evaluator_name: "test1", configuration_name: "default", span_id: "s1")
      sleep 0.001 # Ensure different timestamps
      run2 = described_class.create!(evaluator_name: "test2", configuration_name: "default", span_id: "s2")

      results = described_class.order(created_at: :asc)
      expect(results.map(&:id)).to eq([run1.id, run2.id])
    end

    it "orders by created_at descending" do
      run1 = described_class.create!(evaluator_name: "test1", configuration_name: "default", span_id: "s1")
      sleep 0.001 # Ensure different timestamps
      run2 = described_class.create!(evaluator_name: "test2", configuration_name: "default", span_id: "s2")

      results = described_class.order(created_at: :desc)
      expect(results.map(&:id)).to eq([run2.id, run1.id])
    end
  end

  describe ".limit" do
    before do
      3.times { |i| described_class.create!(evaluator_name: "test#{i}", configuration_name: "default", span_id: "s#{i}") }
    end

    it "limits number of results" do
      results = described_class.limit(2)
      expect(results.size).to eq(2)
    end

    it "returns all results when limit exceeds count" do
      results = described_class.limit(10)
      expect(results.size).to eq(3)
    end
  end

  describe ".destroy_all" do
    it "removes all evaluation runs" do
      3.times { |i| described_class.create!(evaluator_name: "test#{i}", configuration_name: "default", span_id: "s#{i}") }

      described_class.destroy_all
      expect(described_class.all).to be_empty
    end

    it "resets ID sequence" do
      described_class.create!(evaluator_name: "test1", configuration_name: "default", span_id: "s1")
      described_class.destroy_all

      run = described_class.create!(evaluator_name: "test2", configuration_name: "default", span_id: "s2")
      expect(run.id).to eq(1) # ID resets to 1
    end
  end

  describe "#destroy" do
    it "removes the evaluation run" do
      run = described_class.create!(evaluator_name: "test", configuration_name: "default", span_id: "s1")
      initial_count = described_class.all.size

      run.destroy
      expect(described_class.all.size).to eq(initial_count - 1)
      expect(described_class.find(run.id)).to be_nil
    end
  end

  describe "#to_h" do
    it "converts run to hash with all fields" do
      run = described_class.create!(
        evaluator_name: "test_evaluator",
        configuration_name: "baseline",
        span_id: "span_123",
        tags: { env: "prod" },
        result_data: { passed: true },
        field_results: { output: { score: 0.9 } },
        overall_passed: true,
        aggregate_score: 0.9,
        duration_ms: 100.5
      )

      hash = run.to_h
      expect(hash).to include(
        id: run.id,
        evaluator_name: "test_evaluator",
        configuration_name: "baseline",
        span_id: "span_123",
        tags: { env: "prod" },
        result_data: { passed: true },
        field_results: { output: { score: 0.9 } },
        overall_passed: true,
        aggregate_score: 0.9,
        duration_ms: 100.5,
        created_at: run.created_at
      )
    end
  end
end
