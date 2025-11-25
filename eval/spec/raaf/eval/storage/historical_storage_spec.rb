# frozen_string_literal: true

require "spec_helper"
require "raaf/eval/storage/historical_storage"
require "raaf/eval/storage/evaluation_run"

RSpec.describe RAAF::Eval::Storage::HistoricalStorage do
  # Clear all runs before each test
  before do
    RAAF::Eval::Storage::EvaluationRun.destroy_all
    # Reset deprecation warnings so they can be tested fresh
    described_class.reset_deprecation_warnings!
  end

  after { RAAF::Eval::Storage::EvaluationRun.destroy_all }

  describe "deprecation warnings" do
    it "emits deprecation warning for save method" do
      result = double(
        "EvaluationResult",
        to_h: {},
        field_results: {},
        passed?: true,
        aggregate_score: 0.9
      )

      expect {
        described_class.save(
          evaluator_name: "test",
          configuration_name: "default",
          span_id: "span_1",
          result: result
        )
      }.to output(/DEPRECATION WARNING/).to_stderr
    end

    it "emits deprecation warning only once per method" do
      result = double(
        "EvaluationResult",
        to_h: {},
        field_results: {},
        passed?: true,
        aggregate_score: 0.9
      )

      # First call should emit warning
      expect {
        described_class.save(
          evaluator_name: "test1",
          configuration_name: "default",
          span_id: "span_1",
          result: result
        )
      }.to output(/DEPRECATION WARNING/).to_stderr

      # Second call should not emit warning
      expect {
        described_class.save(
          evaluator_name: "test2",
          configuration_name: "default",
          span_id: "span_2",
          result: result
        )
      }.not_to output.to_stderr
    end

    it "includes migration guidance in deprecation message" do
      result = double(
        "EvaluationResult",
        to_h: {},
        field_results: {},
        passed?: true,
        aggregate_score: 0.9
      )

      expect {
        described_class.save(
          evaluator_name: "test",
          configuration_name: "default",
          span_id: "span_1",
          result: result
        )
      }.to output(/CONTINUOUS_EVAL_MIGRATION/).to_stderr
    end

    it "emits deprecation warning for query method" do
      expect {
        described_class.query(evaluator_name: "test")
      }.to output(/DEPRECATION WARNING/).to_stderr
    end

    it "emits deprecation warning for latest method" do
      expect {
        described_class.latest(limit: 5)
      }.to output(/DEPRECATION WARNING/).to_stderr
    end

    it "emits deprecation warning for cleanup_retention method" do
      policy = double("RetentionPolicy", cleanup: 0)
      allow(RAAF::Eval::Storage::RetentionPolicy).to receive(:new).and_return(policy)

      expect {
        described_class.cleanup_retention(retention_days: 30)
      }.to output(/DEPRECATION WARNING/).to_stderr
    end
  end

  describe ".save" do
    it "saves evaluation result with all metadata despite deprecation" do
      result = double(
        "EvaluationResult",
        to_h: { field_results: {}, label: "good" },
        field_results: { output: { label: "good", score: 0.95 } },
        passed?: true,
        aggregate_score: 0.95
      )

      run = nil
      expect {
        run = described_class.save(
          evaluator_name: "my_evaluator",
          configuration_name: :baseline,
          span_id: "span_123",
          result: result,
          tags: { environment: "test", version: "1.0.0" },
          duration_ms: 1234.56
        )
      }.to output(/DEPRECATION WARNING/).to_stderr

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

      run = nil
      expect {
        run = described_class.save(
          evaluator_name: "test",
          configuration_name: :low_temp,
          span_id: "span_1",
          result: result
        )
      }.to output.to_stderr

      expect(run.configuration_name).to eq("low_temp")
    end
  end

  describe ".query" do
    before do
      # Create test runs (suppress deprecation warnings for setup)
      described_class.reset_deprecation_warnings!

      result = double(
        "EvaluationResult",
        to_h: {},
        field_results: {},
        passed?: true,
        aggregate_score: 0.9
      )

      # Suppress warnings during setup
      allow(described_class).to receive(:emit_deprecation_warning)

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

      # Reset so we can test deprecation warnings again
      described_class.reset_deprecation_warnings!
      allow(described_class).to receive(:emit_deprecation_warning).and_call_original
    end

    it "queries by evaluator_name despite deprecation" do
      results = nil
      expect {
        results = described_class.query(evaluator_name: "quality_check")
      }.to output(/DEPRECATION WARNING/).to_stderr

      expect(results.size).to eq(2)
      expect(results.map(&:evaluator_name).uniq).to eq(["quality_check"])
    end

    it "queries by configuration_name" do
      # Reset warnings again since previous test triggered it
      described_class.reset_deprecation_warnings!

      results = nil
      expect {
        results = described_class.query(configuration_name: :baseline)
      }.to output(/DEPRECATION WARNING/).to_stderr

      expect(results.size).to eq(2)
      expect(results.map(&:configuration_name).uniq).to eq(["baseline"])
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

      # Suppress warnings during setup
      allow(described_class).to receive(:emit_deprecation_warning)

      5.times do |i|
        described_class.save(
          evaluator_name: "test_#{i}",
          configuration_name: "default",
          span_id: "span_#{i}",
          result: result
        )
        sleep 0.001 # Ensure different timestamps
      end

      # Reset so we can test deprecation warnings again
      described_class.reset_deprecation_warnings!
      allow(described_class).to receive(:emit_deprecation_warning).and_call_original
    end

    it "returns N most recent runs despite deprecation" do
      results = nil
      expect {
        results = described_class.latest(limit: 3)
      }.to output(/DEPRECATION WARNING/).to_stderr

      expect(results.size).to eq(3)
      # Verify descending order
      expect(results.first.evaluator_name).to eq("test_4")
      expect(results.last.evaluator_name).to eq("test_2")
    end
  end

  describe ".cleanup_retention" do
    it "delegates to RetentionPolicy with retention parameters" do
      policy = double("RetentionPolicy", cleanup: 5)
      allow(RAAF::Eval::Storage::RetentionPolicy).to receive(:new).and_return(policy)

      deleted_count = nil
      expect {
        deleted_count = described_class.cleanup_retention(retention_days: 30, retention_count: 100)
      }.to output(/DEPRECATION WARNING/).to_stderr

      expect(RAAF::Eval::Storage::RetentionPolicy).to have_received(:new).with(30, 100)
      expect(deleted_count).to eq(5)
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

      # Suppress warnings during setup
      allow(described_class).to receive(:emit_deprecation_warning)

      run = described_class.save(
        evaluator_name: "test",
        configuration_name: "default",
        span_id: "span_1",
        result: result
      )

      # Reset so we can test deprecation warnings again
      described_class.reset_deprecation_warnings!
      allow(described_class).to receive(:emit_deprecation_warning).and_call_original

      expect {
        described_class.delete(run.id)
      }.to output(/DEPRECATION WARNING/).to_stderr

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

      # Suppress warnings during setup
      allow(described_class).to receive(:emit_deprecation_warning)

      3.times do |i|
        described_class.save(
          evaluator_name: "test_#{i}",
          configuration_name: "default",
          span_id: "span_#{i}",
          result: result
        )
      end

      # Reset so we can test deprecation warnings again
      described_class.reset_deprecation_warnings!
      allow(described_class).to receive(:emit_deprecation_warning).and_call_original

      expect {
        described_class.clear_all
      }.to output(/DEPRECATION WARNING/).to_stderr

      expect(RAAF::Eval::Storage::EvaluationRun.all).to be_empty
    end
  end
end
