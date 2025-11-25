# frozen_string_literal: true

RSpec.describe RAAF::Eval::Models::ContinuousEvaluationResult, type: :model do
  describe "validations" do
    it "requires span_id" do
      result = build(:continuous_evaluation_result, span_id: nil)
      expect(result).not_to be_valid
      expect(result.errors[:span_id]).to include("can't be blank")
    end

    it "requires trace_id" do
      result = build(:continuous_evaluation_result, trace_id: nil)
      expect(result).not_to be_valid
      expect(result.errors[:trace_id]).to include("can't be blank")
    end

    it "requires evaluator_name" do
      result = build(:continuous_evaluation_result, evaluator_name: nil)
      expect(result).not_to be_valid
      expect(result.errors[:evaluator_name]).to include("can't be blank")
    end

    it "requires evaluator_type" do
      result = build(:continuous_evaluation_result, evaluator_type: nil)
      expect(result).not_to be_valid
      expect(result.errors[:evaluator_type]).to include("can't be blank")
    end

    it "requires valid evaluator_type" do
      result = build(:continuous_evaluation_result, evaluator_type: "invalid")
      expect(result).not_to be_valid
      expect(result.errors[:evaluator_type]).to be_present
    end

    it "accepts valid evaluator_type values" do
      %w[rule_based statistical llm_judge].each do |type|
        result = build(:continuous_evaluation_result, evaluator_type: type)
        expect(result).to be_valid, "Expected evaluator_type '#{type}' to be valid"
      end
    end

    it "requires agent_name" do
      result = build(:continuous_evaluation_result, agent_name: nil)
      expect(result).not_to be_valid
      expect(result.errors[:agent_name]).to include("can't be blank")
    end

    it "requires status" do
      result = build(:continuous_evaluation_result, status: nil)
      expect(result).not_to be_valid
      expect(result.errors[:status]).to include("can't be blank")
    end

    it "requires valid status" do
      result = build(:continuous_evaluation_result, status: "invalid")
      expect(result).not_to be_valid
      expect(result.errors[:status]).to be_present
    end

    it "accepts valid status values" do
      %w[passed failed warning error].each do |status|
        result = build(:continuous_evaluation_result, status: status)
        expect(result).to be_valid, "Expected status '#{status}' to be valid"
      end
    end

    it "validates score is between 0 and 1" do
      result = build(:continuous_evaluation_result, score: -0.1)
      expect(result).not_to be_valid

      result.score = 1.1
      expect(result).not_to be_valid

      result.score = 0.5
      expect(result).to be_valid
    end

    it "allows nil score" do
      result = build(:continuous_evaluation_result, score: nil)
      expect(result).to be_valid
    end

    it "requires evaluation_type to be automated" do
      result = build(:continuous_evaluation_result, evaluation_type: "manual")
      expect(result).not_to be_valid
    end
  end

  describe "scopes" do
    before do
      create(:continuous_evaluation_result, status: "passed", agent_name: "AgentA")
      create(:continuous_evaluation_result, status: "passed", agent_name: "AgentB")
      create(:continuous_evaluation_result, status: "failed", agent_name: "AgentA")
      create(:continuous_evaluation_result, status: "warning", agent_name: "AgentA")
      create(:continuous_evaluation_result, :error, agent_name: "AgentA")
    end

    it "filters by status" do
      expect(described_class.passed.count).to eq(2)
      expect(described_class.failed.count).to eq(1)
      expect(described_class.warning.count).to eq(1)
      expect(described_class.errored.count).to eq(1)
    end

    it "filters by agent_name" do
      expect(described_class.for_agent("AgentA").count).to eq(4)
      expect(described_class.for_agent("AgentB").count).to eq(1)
    end

    it "filters by evaluator_name" do
      create(:continuous_evaluation_result, evaluator_name: "quality_check")
      expect(described_class.for_evaluator("quality_check").count).to eq(1)
    end

    it "filters by environment" do
      create(:continuous_evaluation_result, environment: "staging")
      expect(described_class.for_environment("staging").count).to eq(1)
      expect(described_class.for_environment("production").count).to eq(5)
    end

    it "filters by date range" do
      create(:continuous_evaluation_result, created_at: 2.days.ago)
      expect(described_class.in_date_range(1.day.ago, Time.current).count).to eq(5)
    end

    it "orders by created_at descending" do
      results = described_class.recent
      expect(results.first.created_at).to be >= results.last.created_at
    end
  end

  describe "#passed?" do
    it "returns true for passed status" do
      result = build(:continuous_evaluation_result, status: "passed")
      expect(result.passed?).to be true
    end

    it "returns false for other statuses" do
      %w[failed warning error].each do |status|
        result = build(:continuous_evaluation_result, status: status)
        expect(result.passed?).to be false
      end
    end
  end

  describe "#failed?" do
    it "returns true for failed status" do
      result = build(:continuous_evaluation_result, status: "failed")
      expect(result.failed?).to be true
    end
  end

  describe "#warning?" do
    it "returns true for warning status" do
      result = build(:continuous_evaluation_result, status: "warning")
      expect(result.warning?).to be true
    end
  end

  describe "#error?" do
    it "returns true for error status" do
      result = build(:continuous_evaluation_result, status: "error")
      expect(result.error?).to be true
    end
  end

  describe "#success?" do
    it "returns true for passed or warning" do
      expect(build(:continuous_evaluation_result, status: "passed").success?).to be true
      expect(build(:continuous_evaluation_result, status: "warning").success?).to be true
    end

    it "returns false for failed or error" do
      expect(build(:continuous_evaluation_result, status: "failed").success?).to be false
      expect(build(:continuous_evaluation_result, status: "error").success?).to be false
    end
  end

  describe "#label" do
    it "returns good for high scores" do
      result = build(:continuous_evaluation_result, score: 0.9)
      expect(result.label).to eq("good")
    end

    it "returns average for medium scores" do
      result = build(:continuous_evaluation_result, score: 0.7)
      expect(result.label).to eq("average")
    end

    it "returns bad for low scores" do
      result = build(:continuous_evaluation_result, score: 0.4)
      expect(result.label).to eq("bad")
    end

    it "returns unknown for nil scores" do
      result = build(:continuous_evaluation_result, score: nil)
      expect(result.label).to eq("unknown")
    end
  end

  describe "#duration" do
    it "returns evaluation_duration_ms in seconds" do
      result = build(:continuous_evaluation_result, evaluation_duration_ms: 1500)
      expect(result.duration).to eq(1.5)
    end

    it "returns nil when evaluation_duration_ms is nil" do
      result = build(:continuous_evaluation_result, evaluation_duration_ms: nil)
      expect(result.duration).to be_nil
    end
  end

  describe "associations" do
    it "belongs to evaluation_policy optionally" do
      result = build(:continuous_evaluation_result, evaluation_policy: nil)
      expect(result).to be_valid
    end

    it "belongs to evaluation_queue_item optionally" do
      result = build(:continuous_evaluation_result, evaluation_queue_item: nil)
      expect(result).to be_valid
    end
  end

  describe ".aggregate_by_status" do
    before do
      create_list(:continuous_evaluation_result, 3, status: "passed")
      create_list(:continuous_evaluation_result, 2, status: "failed")
      create(:continuous_evaluation_result, status: "warning")
    end

    it "returns counts by status" do
      aggregates = described_class.aggregate_by_status
      expect(aggregates["passed"]).to eq(3)
      expect(aggregates["failed"]).to eq(2)
      expect(aggregates["warning"]).to eq(1)
    end
  end

  describe ".pass_rate" do
    before do
      create_list(:continuous_evaluation_result, 7, status: "passed")
      create_list(:continuous_evaluation_result, 2, status: "failed")
      create(:continuous_evaluation_result, status: "warning")
    end

    it "calculates pass rate as percentage" do
      # 7 passed + 1 warning = 8 successful out of 10
      expect(described_class.pass_rate).to be_within(0.01).of(0.8)
    end
  end

  describe ".average_score" do
    before do
      create(:continuous_evaluation_result, score: 0.8)
      create(:continuous_evaluation_result, score: 0.9)
      create(:continuous_evaluation_result, score: 0.7)
    end

    it "calculates average score" do
      expect(described_class.average_score).to be_within(0.01).of(0.8)
    end
  end
end
