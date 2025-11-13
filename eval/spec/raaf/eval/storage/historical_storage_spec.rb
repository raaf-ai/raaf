# frozen_string_literal: true

require "spec_helper"
require "raaf/eval/storage/historical_storage"
require "raaf/eval/storage/evaluation_run"

RSpec.describe RAAF::Eval::Storage::HistoricalStorage do
  # Clear all runs before each test
  before { RAAF::Eval::Storage::EvaluationRun.destroy_all }
  after { RAAF::Eval::Storage::EvaluationRun.destroy_all }

  describe ".save" do
    it "saves evaluation result with all metadata" do
      result = double(
        "EvaluationResult",
        to_h: { field_results: {}, passed: true },
        field_results: { output: { passed: true, score: 0.95 } },
        passed?: true,
        aggregate_score: 0.95
      )

      run = described_class.save(
        evaluator_name: "my_evaluator",
        configuration_name: :baseline,
        span_id: "span_123",
        result: result,
        tags: { environment: "test", version: "1.0.0" },
        duration_ms: 1234.56
      )

      expect(run).to be_a(RAAF::Eval::Storage::EvaluationRun)
      expect(run.evaluator_name).to eq("my_evaluator")
      expect(run.configuration_name).to eq("baseline")
      expect(run.span_id).to eq("span_123")
      expect(run.tags).to eq({ environment: "test", version: "1.0.0" })
      expect(run.overall_passed).to be true
      expect(run.aggregate_score).to eq(0.95)
      expect(run.duration_ms).to eq(1234.56)
    end

    it "converts symbol configuration names to strings" do
      result = double(
        "EvaluationResult",
        to_h: {},
        field_results: {},
        passed?: true,
        aggregate_score: 0.9
      )

      run = described_class.save(
        evaluator_name: "test",
        configuration_name: :low_temp,
        span_id: "span_1",
        result: result
      )

      expect(run.configuration_name).to eq("low_temp")
    end

    it "handles empty tags" do
      result = double(
        "EvaluationResult",
        to_h: {},
        field_results: {},
        passed?: true,
        aggregate_score: 0.9
      )

      run = described_class.save(
        evaluator_name: "test",
        configuration_name: "default",
        span_id: "span_1",
        result: result,
        tags: {}
      )

      expect(run.tags).to eq({})
    end

    it "defaults duration_ms to 0" do
      result = double(
        "EvaluationResult",
        to_h: {},
        field_results: {},
        passed?: true,
        aggregate_score: 0.9
      )

      run = described_class.save(
        evaluator_name: "test",
        configuration_name: "default",
        span_id: "span_1",
        result: result
      )

      expect(run.duration_ms).to eq(0)
    end
  end

  describe ".query" do
    before do
      # Create test runs
      result = double(
        "EvaluationResult",
        to_h: {},
        field_results: {},
        passed?: true,
        aggregate_score: 0.9
      )

      described_class.save(
        evaluator_name: "quality_check",
        configuration_name: :baseline,
        span_id: "span_1",
        result: result,
        tags: { environment: "production" }
      )

      described_class.save(
        evaluator_name: "quality_check",
        configuration_name: :experiment,
        span_id: "span_2",
        result: result,
        tags: { environment: "staging" }
      )

      described_class.save(
        evaluator_name: "performance_test",
        configuration_name: :baseline,
        span_id: "span_3",
        result: result,
        tags: { environment: "production" }
      )
    end

    it "queries by evaluator_name" do
      results = described_class.query(evaluator_name: "quality_check")

      expect(results.size).to eq(2)
      expect(results.map(&:evaluator_name).uniq).to eq(["quality_check"])
    end

    it "queries by configuration_name" do
      results = described_class.query(configuration_name: :baseline)

      expect(results.size).to eq(2)
      expect(results.map(&:configuration_name).uniq).to eq(["baseline"])
    end

    it "queries by tags" do
      results = described_class.query(tags: { environment: "production" })

      expect(results.size).to eq(2)
      expect(results.all? { |r| r.tags[:environment] == "production" }).to be true
    end

    it "queries with combined filters" do
      results = described_class.query(
        evaluator_name: "quality_check",
        configuration_name: :baseline,
        tags: { environment: "production" }
      )

      expect(results.size).to eq(1)
      expect(results.first.span_id).to eq("span_1")
    end

    it "queries with date range" do
      start_date = Time.now - (1 * 24 * 60 * 60)
      end_date = Time.now + (1 * 24 * 60 * 60)

      results = described_class.query(start_date: start_date, end_date: end_date)

      expect(results.size).to eq(3) # All recent runs
    end

    it "returns empty array when no matches" do
      results = described_class.query(evaluator_name: "nonexistent")

      expect(results).to be_empty
    end
  end

  describe ".latest" do
    before do
      result = double(
        "EvaluationResult",
        to_h: {},
        field_results: {},
        passed?: true,
        aggregate_score: 0.9
      )

      5.times do |i|
        described_class.save(
          evaluator_name: "test_#{i}",
          configuration_name: "default",
          span_id: "span_#{i}",
          result: result
        )
        sleep 0.001 # Ensure different timestamps
      end
    end

    it "returns N most recent runs" do
      results = described_class.latest(limit: 3)

      expect(results.size).to eq(3)
      # Verify descending order
      expect(results.first.evaluator_name).to eq("test_4")
      expect(results.last.evaluator_name).to eq("test_2")
    end

    it "returns all runs when limit exceeds count" do
      results = described_class.latest(limit: 10)

      expect(results.size).to eq(5)
    end

    it "defaults to 10 runs" do
      15.times do |i|
        result = double(
          "EvaluationResult",
          to_h: {},
          field_results: {},
          passed?: true,
          aggregate_score: 0.9
        )

        described_class.save(
          evaluator_name: "extra_#{i}",
          configuration_name: "default",
          span_id: "span_extra_#{i}",
          result: result
        )
      end

      results = described_class.latest

      expect(results.size).to eq(10)
    end
  end

  describe ".cleanup_retention" do
    it "delegates to RetentionPolicy with retention parameters" do
      policy = double("RetentionPolicy", cleanup: 5)
      allow(RAAF::Eval::Storage::RetentionPolicy).to receive(:new).and_return(policy)

      deleted_count = described_class.cleanup_retention(retention_days: 30, retention_count: 100)

      expect(RAAF::Eval::Storage::RetentionPolicy).to have_received(:new).with(30, 100)
      expect(deleted_count).to eq(5)
    end

    it "handles nil retention parameters" do
      policy = double("RetentionPolicy", cleanup: 0)
      allow(RAAF::Eval::Storage::RetentionPolicy).to receive(:new).and_return(policy)

      deleted_count = described_class.cleanup_retention(retention_days: nil, retention_count: nil)

      expect(RAAF::Eval::Storage::RetentionPolicy).to have_received(:new).with(nil, nil)
      expect(deleted_count).to eq(0)
    end
  end

  describe ".delete" do
    it "deletes specific run by ID" do
      result = double(
        "EvaluationResult",
        to_h: {},
        field_results: {},
        passed?: true,
        aggregate_score: 0.9
      )

      run = described_class.save(
        evaluator_name: "test",
        configuration_name: "default",
        span_id: "span_1",
        result: result
      )

      described_class.delete(run.id)

      expect(RAAF::Eval::Storage::EvaluationRun.find(run.id)).to be_nil
    end
  end

  describe ".clear_all" do
    it "removes all evaluation runs" do
      result = double(
        "EvaluationResult",
        to_h: {},
        field_results: {},
        passed?: true,
        aggregate_score: 0.9
      )

      3.times do |i|
        described_class.save(
          evaluator_name: "test_#{i}",
          configuration_name: "default",
          span_id: "span_#{i}",
          result: result
        )
      end

      described_class.clear_all

      expect(RAAF::Eval::Storage::EvaluationRun.all).to be_empty
    end
  end
end
