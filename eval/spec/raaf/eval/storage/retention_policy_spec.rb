# frozen_string_literal: true

require "spec_helper"
require "raaf/eval/storage/retention_policy"
require "raaf/eval/storage/evaluation_run"

RSpec.describe RAAF::Eval::Storage::RetentionPolicy do
  # Clear all runs before each test
  before { RAAF::Eval::Storage::EvaluationRun.destroy_all }
  after { RAAF::Eval::Storage::EvaluationRun.destroy_all }

  describe "#cleanup" do
    context "with no retention policy" do
      it "keeps all runs when both policies are nil" do
        3.times { |i| create_run(age_days: i) }

        policy = described_class.new(nil, nil)
        deleted_count = policy.cleanup

        expect(deleted_count).to eq(0)
        expect(RAAF::Eval::Storage::EvaluationRun.all.size).to eq(3)
      end
    end

    context "with retention_days only" do
      it "keeps runs within retention period" do
        create_run(age_days: 10)  # Within 30 days
        create_run(age_days: 20)  # Within 30 days
        create_run(age_days: 40)  # Outside 30 days - DELETE

        policy = described_class.new(30, nil)
        deleted_count = policy.cleanup

        expect(deleted_count).to eq(1)
        expect(RAAF::Eval::Storage::EvaluationRun.all.size).to eq(2)
      end

      it "keeps all runs when all are within period" do
        3.times { |i| create_run(age_days: 10 + i) }

        policy = described_class.new(30, nil)
        deleted_count = policy.cleanup

        expect(deleted_count).to eq(0)
        expect(RAAF::Eval::Storage::EvaluationRun.all.size).to eq(3)
      end

      it "deletes all runs when all exceed period" do
        3.times { |i| create_run(age_days: 40 + i) }

        policy = described_class.new(30, nil)
        deleted_count = policy.cleanup

        expect(deleted_count).to eq(3)
        expect(RAAF::Eval::Storage::EvaluationRun.all).to be_empty
      end
    end

    context "with retention_count only" do
      it "keeps last N runs" do
        # Create 5 runs, ordered by age (oldest first)
        5.times { |i| create_run(age_days: 10 + i, name: "run_#{i}") }

        policy = described_class.new(nil, 3)
        deleted_count = policy.cleanup

        expect(deleted_count).to eq(2)
        remaining = RAAF::Eval::Storage::EvaluationRun.all
        expect(remaining.size).to eq(3)
        # Verify we kept the 3 most recent (smallest age_days)
        expect(remaining.map(&:evaluator_name).sort).to eq(["run_2", "run_3", "run_4"])
      end

      it "keeps all runs when count exceeds total" do
        3.times { |i| create_run(age_days: i) }

        policy = described_class.new(nil, 10)
        deleted_count = policy.cleanup

        expect(deleted_count).to eq(0)
        expect(RAAF::Eval::Storage::EvaluationRun.all.size).to eq(3)
      end

      it "deletes oldest runs when exceeding count" do
        # Create 10 runs
        10.times { |i| create_run(age_days: i, name: "run_#{i}") }

        policy = described_class.new(nil, 5)
        deleted_count = policy.cleanup

        expect(deleted_count).to eq(5)
        remaining = RAAF::Eval::Storage::EvaluationRun.all
        expect(remaining.size).to eq(5)
      end
    end

    context "with OR logic (both retention_days and retention_count)" do
      it "keeps runs that satisfy EITHER condition" do
        # Scenario: retention_days: 30, retention_count: 3
        # Keep if (within 30 days) OR (within last 3 by insertion order)

        create_run(age_days: 10, name: "recent_1")      # Keep (within days, insertion_order 0)
        create_run(age_days: 15, name: "recent_2")      # Keep (within days, insertion_order 1)
        create_run(age_days: 50, name: "old_deleted")   # DELETE (outside days AND not in last 3, insertion_order 2)
        create_run(age_days: 40, name: "old_kept")      # Keep (outside days BUT in last 3, insertion_order 3)
        create_run(age_days: 20, name: "recent_3")      # Keep (within days AND in last 3, insertion_order 4)
        create_run(age_days: 25, name: "within_days")   # Keep (within days AND in last 3, insertion_order 5)

        policy = described_class.new(30, 3)
        deleted_count = policy.cleanup

        expect(deleted_count).to eq(1)
        remaining = RAAF::Eval::Storage::EvaluationRun.all
        expect(remaining.size).to eq(5)
        expect(remaining.map(&:evaluator_name)).to contain_exactly(
          "recent_1", "recent_2", "old_kept", "recent_3", "within_days"
        )
      end

      it "keeps old run if within retention_count" do
        # Old run (100 days) but within last 2 runs - KEEP by count
        create_run(age_days: 60, name: "older")      # DELETE (outside days AND not in count, insertion_order 0)
        create_run(age_days: 100, name: "very_old")  # Keep (within count, insertion_order 1)
        create_run(age_days: 50, name: "old")        # Keep (within count, insertion_order 2)

        policy = described_class.new(30, 2)
        deleted_count = policy.cleanup

        expect(deleted_count).to eq(1)
        remaining = RAAF::Eval::Storage::EvaluationRun.all
        expect(remaining.size).to eq(2)
        expect(remaining.map(&:evaluator_name)).to contain_exactly("very_old", "old")
      end

      it "keeps recent run even if not in retention_count" do
        # Many old runs (within last N) + 1 recent run outside count - recent KEPT by days
        create_run(age_days: 5, name: "recent")  # Keep (within days, insertion_order 0, NOT in last 5)
        6.times { |i| create_run(age_days: 50 + i, name: "old_#{i}") }  # Last 5 kept by count

        policy = described_class.new(30, 5)
        deleted_count = policy.cleanup

        expect(deleted_count).to eq(1)  # old_0 deleted (outside days AND not in last 5)
        remaining = RAAF::Eval::Storage::EvaluationRun.all
        expect(remaining.size).to eq(6)
        # Should keep the recent run + 5 most recent old runs by insertion order
        expect(remaining.map(&:evaluator_name)).to include("recent")
        expect(remaining.map(&:evaluator_name)).to include("old_1", "old_2", "old_3", "old_4", "old_5")
      end

      it "deletes runs that fail BOTH conditions" do
        # Outside 30 days AND outside last 2 runs by insertion order - DELETE
        create_run(age_days: 40, name: "old_1")         # DELETE (outside days AND not in last 2, insertion_order 0)
        create_run(age_days: 50, name: "old_2")         # DELETE (outside days AND not in last 2, insertion_order 1)
        create_run(age_days: 5, name: "very_recent")    # Keep (within days AND in last 2, insertion_order 2)
        create_run(age_days: 10, name: "recent")        # Keep (within days AND in last 2, insertion_order 3)

        policy = described_class.new(30, 2)
        deleted_count = policy.cleanup

        expect(deleted_count).to eq(2)
        remaining = RAAF::Eval::Storage::EvaluationRun.all
        expect(remaining.size).to eq(2)
        expect(remaining.map(&:evaluator_name)).to contain_exactly("very_recent", "recent")
      end
    end

    context "edge cases" do
      it "handles run exactly at retention_days threshold" do
        create_run(age_days: 30, name: "at_threshold")  # Exactly 30 days

        policy = described_class.new(30, nil)
        deleted_count = policy.cleanup

        # Should keep (>= comparison)
        expect(deleted_count).to eq(0)
        expect(RAAF::Eval::Storage::EvaluationRun.all.size).to eq(1)
      end

      it "handles run exactly at retention_count threshold" do
        3.times { |i| create_run(age_days: i, name: "run_#{i}") }

        policy = described_class.new(nil, 3)
        deleted_count = policy.cleanup

        # All 3 should be kept
        expect(deleted_count).to eq(0)
        expect(RAAF::Eval::Storage::EvaluationRun.all.size).to eq(3)
      end
    end
  end

  # Helper method to create evaluation run with specific age
  def create_run(age_days:, name: "test_run")
    run = RAAF::Eval::Storage::EvaluationRun.create!(
      evaluator_name: name,
      configuration_name: "default",
      span_id: "span_#{rand(1000)}"
    )
    # Manually set created_at to simulate age
    run.created_at = Time.now - (age_days * 24 * 60 * 60)
    run
  end
end
