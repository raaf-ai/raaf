# frozen_string_literal: true

RSpec.describe RAAF::Eval::Models::EvaluationMetric, type: :model do
  describe "validations" do
    it "requires agent_name" do
      metric = build(:evaluation_metric, agent_name: nil)
      expect(metric).not_to be_valid
      expect(metric.errors[:agent_name]).to include("can't be blank")
    end

    it "requires period_type" do
      metric = build(:evaluation_metric, period_type: nil)
      expect(metric).not_to be_valid
      expect(metric.errors[:period_type]).to include("can't be blank")
    end

    it "requires valid period_type" do
      metric = build(:evaluation_metric, period_type: "invalid")
      expect(metric).not_to be_valid
      expect(metric.errors[:period_type]).to be_present
    end

    it "accepts valid period_type values" do
      %w[hourly daily weekly].each do |type|
        metric = build(:evaluation_metric, period_type: type)
        expect(metric).to be_valid, "Expected period_type '#{type}' to be valid"
      end
    end

    it "requires period_start" do
      metric = build(:evaluation_metric, period_start: nil)
      expect(metric).not_to be_valid
      expect(metric.errors[:period_start]).to include("can't be blank")
    end

    it "enforces unique constraint on dimension columns" do
      create(:evaluation_metric,
             agent_name: "TestAgent",
             environment: "production",
             model: "gpt-4o",
             evaluator_name: "token_limit",
             period_type: "daily",
             period_start: Date.current.beginning_of_day)

      duplicate = build(:evaluation_metric,
                        agent_name: "TestAgent",
                        environment: "production",
                        model: "gpt-4o",
                        evaluator_name: "token_limit",
                        period_type: "daily",
                        period_start: Date.current.beginning_of_day)
      expect(duplicate).not_to be_valid
    end

    it "allows same dimensions with different period_start" do
      create(:evaluation_metric, period_start: Date.yesterday.beginning_of_day)
      metric = build(:evaluation_metric, period_start: Date.current.beginning_of_day)
      expect(metric).to be_valid
    end

    it "allows same dimensions with different period_type" do
      create(:evaluation_metric, period_type: "daily")
      metric = build(:evaluation_metric, period_type: "hourly", period_start: Time.current.beginning_of_hour)
      expect(metric).to be_valid
    end
  end

  describe "scopes" do
    before do
      create(:evaluation_metric, agent_name: "AgentA", period_type: "daily")
      create(:evaluation_metric, agent_name: "AgentA", period_type: "hourly", :hourly)
      create(:evaluation_metric, agent_name: "AgentB", period_type: "daily")
      create(:evaluation_metric, agent_name: "AgentA", period_type: "weekly", :weekly)
    end

    it "filters by agent_name" do
      expect(described_class.for_agent("AgentA").count).to eq(3)
      expect(described_class.for_agent("AgentB").count).to eq(1)
    end

    it "filters by period_type" do
      expect(described_class.hourly.count).to eq(1)
      expect(described_class.daily.count).to eq(2)
      expect(described_class.weekly.count).to eq(1)
    end

    it "filters by environment" do
      create(:evaluation_metric, environment: "staging")
      expect(described_class.for_environment("production").count).to eq(4)
      expect(described_class.for_environment("staging").count).to eq(1)
    end

    it "filters by model" do
      create(:evaluation_metric, model: "claude-3")
      expect(described_class.for_model("gpt-4o").count).to eq(4)
      expect(described_class.for_model("claude-3").count).to eq(1)
    end

    it "filters by evaluator" do
      create(:evaluation_metric, evaluator_name: "quality_check")
      expect(described_class.for_evaluator("token_limit").count).to eq(4)
      expect(described_class.for_evaluator("quality_check").count).to eq(1)
    end

    it "filters by date range" do
      create(:evaluation_metric, period_start: 10.days.ago)
      expect(described_class.in_period_range(7.days.ago, Time.current).count).to eq(4)
    end

    it "orders by period_start descending" do
      metrics = described_class.recent
      expect(metrics.first.period_start).to be >= metrics.last.period_start
    end
  end

  describe "#pass_rate" do
    it "calculates pass rate as percentage" do
      metric = build(:evaluation_metric,
                     total_evaluations: 100,
                     passed_count: 70,
                     warning_count: 10)
      expect(metric.pass_rate).to be_within(0.01).of(0.8) # (70 + 10) / 100
    end

    it "returns 0 when no evaluations" do
      metric = build(:evaluation_metric, total_evaluations: 0)
      expect(metric.pass_rate).to eq(0)
    end
  end

  describe "#fail_rate" do
    it "calculates fail rate as percentage" do
      metric = build(:evaluation_metric,
                     total_evaluations: 100,
                     failed_count: 15,
                     error_count: 5)
      expect(metric.fail_rate).to be_within(0.01).of(0.2) # (15 + 5) / 100
    end
  end

  describe "#success_count" do
    it "sums passed and warning counts" do
      metric = build(:evaluation_metric, passed_count: 70, warning_count: 10)
      expect(metric.success_count).to eq(80)
    end
  end

  describe "#failure_count" do
    it "sums failed and error counts" do
      metric = build(:evaluation_metric, failed_count: 15, error_count: 5)
      expect(metric.failure_count).to eq(20)
    end
  end

  describe ".upsert_for_period" do
    let(:dimensions) do
      {
        agent_name: "TestAgent",
        environment: "production",
        model: "gpt-4o",
        evaluator_name: "token_limit",
        period_type: "daily",
        period_start: Date.current.beginning_of_day
      }
    end

    it "creates a new metric when none exists" do
      expect do
        described_class.upsert_for_period(dimensions, total_evaluations: 10, passed_count: 8)
      end.to change(described_class, :count).by(1)
    end

    it "updates existing metric" do
      metric = create(:evaluation_metric, **dimensions, total_evaluations: 5, passed_count: 4)

      described_class.upsert_for_period(dimensions, total_evaluations: 10, passed_count: 8)

      metric.reload
      expect(metric.total_evaluations).to eq(10)
      expect(metric.passed_count).to eq(8)
    end

    it "increments counts when specified" do
      metric = create(:evaluation_metric, **dimensions, total_evaluations: 5, passed_count: 4)

      described_class.increment_for_period(dimensions, total_evaluations: 1, passed_count: 1)

      metric.reload
      expect(metric.total_evaluations).to eq(6)
      expect(metric.passed_count).to eq(5)
    end
  end

  describe ".aggregate_from_results" do
    let!(:results) do
      [
        create(:continuous_evaluation_result, agent_name: "TestAgent", status: "passed", score: 0.9),
        create(:continuous_evaluation_result, agent_name: "TestAgent", status: "passed", score: 0.8),
        create(:continuous_evaluation_result, agent_name: "TestAgent", status: "failed", score: 0.3),
        create(:continuous_evaluation_result, agent_name: "TestAgent", status: "warning", score: 0.7)
      ]
    end

    it "calculates aggregate metrics from results" do
      metrics = described_class.aggregate_from_results(
        RAAF::Eval::Models::ContinuousEvaluationResult.where(agent_name: "TestAgent"),
        agent_name: "TestAgent",
        period_type: "daily",
        period_start: Date.current.beginning_of_day
      )

      expect(metrics.total_evaluations).to eq(4)
      expect(metrics.passed_count).to eq(2)
      expect(metrics.failed_count).to eq(1)
      expect(metrics.warning_count).to eq(1)
      expect(metrics.avg_score).to be_within(0.01).of(0.675)
    end

    it "calculates score statistics" do
      metrics = described_class.aggregate_from_results(
        RAAF::Eval::Models::ContinuousEvaluationResult.where(agent_name: "TestAgent"),
        agent_name: "TestAgent",
        period_type: "daily",
        period_start: Date.current.beginning_of_day
      )

      expect(metrics.min_score).to be_within(0.01).of(0.3)
      expect(metrics.max_score).to be_within(0.01).of(0.9)
    end
  end

  describe ".score_percentiles" do
    before do
      # Create 100 results with varied scores
      (1..100).each do |i|
        create(:continuous_evaluation_result, agent_name: "TestAgent", score: i / 100.0)
      end
    end

    it "calculates percentiles correctly" do
      percentiles = described_class.calculate_percentiles(
        RAAF::Eval::Models::ContinuousEvaluationResult.where(agent_name: "TestAgent")
      )

      expect(percentiles[:p50]).to be_within(0.05).of(0.5)
      expect(percentiles[:p90]).to be_within(0.05).of(0.9)
      expect(percentiles[:p95]).to be_within(0.05).of(0.95)
    end
  end

  describe ".build_score_distribution" do
    before do
      create(:continuous_evaluation_result, score: 0.15)
      create(:continuous_evaluation_result, score: 0.25)
      create(:continuous_evaluation_result, score: 0.85)
      create(:continuous_evaluation_result, score: 0.95)
    end

    it "builds histogram buckets" do
      distribution = described_class.build_score_distribution(
        RAAF::Eval::Models::ContinuousEvaluationResult.all
      )

      expect(distribution["0.1-0.2"]).to eq(1)
      expect(distribution["0.2-0.3"]).to eq(1)
      expect(distribution["0.8-0.9"]).to eq(1)
      expect(distribution["0.9-1.0"]).to eq(1)
    end
  end
end
