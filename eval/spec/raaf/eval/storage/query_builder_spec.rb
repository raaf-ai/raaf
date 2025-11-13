# frozen_string_literal: true

require "spec_helper"
require "raaf/eval/storage/query_builder"
require "raaf/eval/storage/evaluation_run"

RSpec.describe RAAF::Eval::Storage::QueryBuilder do
  # Clear all runs before each test
  before { RAAF::Eval::Storage::EvaluationRun.destroy_all }
  after { RAAF::Eval::Storage::EvaluationRun.destroy_all }

  describe "#execute" do
    before do
      # Create test data
      RAAF::Eval::Storage::EvaluationRun.create!(
        evaluator_name: "quality_check",
        configuration_name: "baseline",
        span_id: "span_1",
        tags: { environment: "production", version: "1.0.0" },
        created_at: Time.now - (5 * 24 * 60 * 60) # 5 days ago
      )

      RAAF::Eval::Storage::EvaluationRun.create!(
        evaluator_name: "quality_check",
        configuration_name: "experiment",
        span_id: "span_2",
        tags: { environment: "staging", version: "1.0.0" },
        created_at: Time.now - (3 * 24 * 60 * 60) # 3 days ago
      )

      RAAF::Eval::Storage::EvaluationRun.create!(
        evaluator_name: "performance_test",
        configuration_name: "baseline",
        span_id: "span_3",
        tags: { environment: "production", version: "2.0.0" },
        created_at: Time.now - (1 * 24 * 60 * 60) # 1 day ago
      )

      RAAF::Eval::Storage::EvaluationRun.create!(
        evaluator_name: "performance_test",
        configuration_name: "experiment",
        span_id: "span_4",
        tags: { environment: "staging", version: "2.0.0" },
        created_at: Time.now - (10 * 24 * 60 * 60) # 10 days ago
      )
    end

    context "filter by evaluator_name" do
      it "returns runs matching evaluator name" do
        builder = described_class.new(evaluator_name: "quality_check")
        results = builder.execute

        expect(results.size).to eq(2)
        expect(results.map(&:evaluator_name).uniq).to eq(["quality_check"])
      end

      it "returns empty array when no matches" do
        builder = described_class.new(evaluator_name: "nonexistent")
        results = builder.execute

        expect(results).to be_empty
      end
    end

    context "filter by configuration_name" do
      it "returns runs matching configuration name" do
        builder = described_class.new(configuration_name: "baseline")
        results = builder.execute

        expect(results.size).to eq(2)
        expect(results.map(&:configuration_name).uniq).to eq(["baseline"])
      end

      it "handles symbol configuration names" do
        builder = described_class.new(configuration_name: :baseline)
        results = builder.execute

        expect(results.size).to eq(2)
      end
    end

    context "filter by date range" do
      it "filters by start_date only" do
        start_date = Time.now - (4 * 24 * 60 * 60) # 4 days ago
        builder = described_class.new(start_date: start_date)
        results = builder.execute

        expect(results.size).to eq(2) # Excludes 5-day-old and 10-day-old (only 3-day and 1-day match)
        expect(results.none? { |r| r.created_at < start_date }).to be true
      end

      it "filters by end_date only" do
        end_date = Time.now - (2 * 24 * 60 * 60) # 2 days ago
        builder = described_class.new(end_date: end_date)
        results = builder.execute

        expect(results.size).to eq(3) # Excludes 1-day-old
        expect(results.none? { |r| r.created_at > end_date }).to be true
      end

      it "filters by both start_date and end_date" do
        start_date = Time.now - (6 * 24 * 60 * 60)
        end_date = Time.now - (2 * 24 * 60 * 60)
        builder = described_class.new(start_date: start_date, end_date: end_date)
        results = builder.execute

        expect(results.size).to eq(2) # 5-day and 3-day old
        expect(results.all? { |r| r.created_at.between?(start_date, end_date) }).to be true
      end
    end

    context "filter by tags" do
      it "filters by single tag" do
        builder = described_class.new(tags: { environment: "production" })
        results = builder.execute

        expect(results.size).to eq(2)
        expect(results.all? { |r| r.tags[:environment] == "production" }).to be true
      end

      it "filters by multiple tags (AND logic)" do
        builder = described_class.new(tags: { environment: "production", version: "1.0.0" })
        results = builder.execute

        expect(results.size).to eq(1)
        expect(results.first.evaluator_name).to eq("quality_check")
        expect(results.first.configuration_name).to eq("baseline")
      end

      it "handles string and symbol tag keys" do
        # Query with string key
        builder1 = described_class.new(tags: { "environment" => "production" })
        results1 = builder1.execute

        # Query with symbol key
        builder2 = described_class.new(tags: { environment: "production" })
        results2 = builder2.execute

        expect(results1.size).to eq(results2.size)
      end

      it "returns empty array when no tags match" do
        builder = described_class.new(tags: { environment: "development" })
        results = builder.execute

        expect(results).to be_empty
      end
    end

    context "combined filters" do
      it "combines evaluator_name and configuration_name" do
        builder = described_class.new(
          evaluator_name: "quality_check",
          configuration_name: "baseline"
        )
        results = builder.execute

        expect(results.size).to eq(1)
        expect(results.first.evaluator_name).to eq("quality_check")
        expect(results.first.configuration_name).to eq("baseline")
      end

      it "combines evaluator_name and tags" do
        builder = described_class.new(
          evaluator_name: "performance_test",
          tags: { environment: "staging" }
        )
        results = builder.execute

        expect(results.size).to eq(1)
        expect(results.first.configuration_name).to eq("experiment")
      end

      it "combines all filter types" do
        start_date = Time.now - (6 * 24 * 60 * 60)
        end_date = Time.now - (2 * 24 * 60 * 60)

        builder = described_class.new(
          evaluator_name: "quality_check",
          configuration_name: "baseline",
          start_date: start_date,
          end_date: end_date,
          tags: { environment: "production" }
        )
        results = builder.execute

        expect(results.size).to eq(1)
        expect(results.first.span_id).to eq("span_1")
      end

      it "returns empty when combined filters have no matches" do
        builder = described_class.new(
          evaluator_name: "quality_check",
          tags: { environment: "production", version: "2.0.0" } # No quality_check with 2.0.0
        )
        results = builder.execute

        expect(results).to be_empty
      end
    end

    context "result ordering" do
      it "returns results sorted by created_at descending" do
        builder = described_class.new(evaluator_name: "quality_check")
        results = builder.execute

        expect(results.size).to eq(2)
        expect(results.first.created_at).to be > results.last.created_at
        expect(results.first.span_id).to eq("span_2") # 3 days ago
        expect(results.last.span_id).to eq("span_1")  # 5 days ago
      end

      it "maintains sort order with all results" do
        builder = described_class.new({}) # No filters
        results = builder.execute

        expect(results.size).to eq(4)
        # Verify descending order
        results.each_cons(2) do |current, next_run|
          expect(current.created_at).to be >= next_run.created_at
        end
      end
    end

    context "edge cases" do
      it "handles empty filter hash" do
        builder = described_class.new({})
        results = builder.execute

        expect(results.size).to eq(4) # All runs
      end

      it "handles nil tags when filtering" do
        # Create run with nil tags
        RAAF::Eval::Storage::EvaluationRun.create!(
          evaluator_name: "no_tags",
          configuration_name: "default",
          span_id: "span_5",
          tags: nil
        )

        builder = described_class.new(tags: { environment: "production" })
        results = builder.execute

        # Should not crash, just filter out nil tags
        expect(results.size).to eq(2)
        expect(results.none? { |r| r.evaluator_name == "no_tags" }).to be true
      end

      it "handles missing tag fields gracefully" do
        builder = described_class.new(tags: { nonexistent_field: "value" })
        results = builder.execute

        expect(results).to be_empty
      end
    end
  end
end
