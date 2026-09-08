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
      %w[good average bad error].each do |status|
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

    it "accepts a hand-run sweep as manual" do
      result = build(:continuous_evaluation_result, evaluation_type: "manual")
      expect(result).to be_valid
    end

    it "rejects an evaluation_type it has no meaning for" do
      result = build(:continuous_evaluation_result, evaluation_type: "scheduled")
      expect(result).not_to be_valid
    end
  end

  describe "scopes" do
    before do
      create(:continuous_evaluation_result, status: "good", agent_name: "AgentA")
      create(:continuous_evaluation_result, status: "good", agent_name: "AgentB")
      create(:continuous_evaluation_result, status: "bad", agent_name: "AgentA")
      create(:continuous_evaluation_result, status: "average", agent_name: "AgentA")
      create(:continuous_evaluation_result, :error, agent_name: "AgentA")
    end

    it "filters by status" do
      expect(described_class.good_quality.count).to eq(2)
      expect(described_class.bad_quality.count).to eq(1)
      expect(described_class.average_quality.count).to eq(1)
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

  describe "#good?" do
    it "returns true for good status" do
      result = build(:continuous_evaluation_result, status: "good")
      expect(result.good?).to be true
    end

    it "returns false for other statuses" do
      %w[average bad error].each do |status|
        result = build(:continuous_evaluation_result, status: status)
        expect(result.good?).to be false
      end
    end
  end

  describe "#bad?" do
    it "returns true for bad status" do
      result = build(:continuous_evaluation_result, status: "bad")
      expect(result.bad?).to be true
    end
  end

  describe "#average?" do
    it "returns true for average status" do
      result = build(:continuous_evaluation_result, status: "average")
      expect(result.average?).to be true
    end
  end

  describe "#error?" do
    it "returns true for error status" do
      result = build(:continuous_evaluation_result, status: "error")
      expect(result.error?).to be true
    end
  end

  describe "#success?" do
    it "returns true for good or average" do
      expect(build(:continuous_evaluation_result, status: "good").success?).to be true
      expect(build(:continuous_evaluation_result, status: "average").success?).to be true
    end

    it "returns false for bad or error" do
      expect(build(:continuous_evaluation_result, status: "bad").success?).to be false
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
      create_list(:continuous_evaluation_result, 3, status: "good")
      create_list(:continuous_evaluation_result, 2, status: "bad")
      create(:continuous_evaluation_result, status: "average")
    end

    it "returns counts by status" do
      aggregates = described_class.aggregate_by_status
      expect(aggregates["good"]).to eq(3)
      expect(aggregates["bad"]).to eq(2)
      expect(aggregates["average"]).to eq(1)
    end
  end

  describe ".pass_rate" do
    before do
      create_list(:continuous_evaluation_result, 7, status: "good")
      create_list(:continuous_evaluation_result, 2, status: "bad")
      create(:continuous_evaluation_result, status: "average")
    end

    it "calculates pass rate as percentage" do
      # 7 good + 1 average = 8 acceptable out of 10
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
