# frozen_string_literal: true

RSpec.describe RAAF::Eval::Models::FeedbackScore, type: :model do
  describe "validations" do
    it "requires name" do
      score = build(:feedback_score, name: nil)
      expect(score).not_to be_valid
    end

    it "requires valid source" do
      score = build(:feedback_score, source: "invalid")
      expect(score).not_to be_valid
    end

    it "accepts valid source values" do
      %w[ui sdk api automated].each do |source|
        score = build(:feedback_score, source: source)
        expect(score).to be_valid
      end
    end

    it "requires either span_id or trace_id" do
      score = build(:feedback_score, span_id: nil, trace_id: nil)
      expect(score).not_to be_valid
      expect(score.errors[:base]).to include("must have either span_id or trace_id")
    end

    it "requires either value or category_value" do
      score = build(:feedback_score, value: nil, category_value: nil)
      expect(score).not_to be_valid
      expect(score.errors[:base]).to include("must have either a numerical value or category_value")
    end

    it "accepts a trace-level score" do
      score = build(:feedback_score, span_id: nil, trace_id: "trace_123")
      expect(score).to be_valid
    end

    it "accepts a categorical score" do
      score = build(:feedback_score, value: nil, category_value: "good")
      expect(score).to be_valid
    end
  end

  describe "type checks" do
    it "identifies numerical scores" do
      score = build(:feedback_score, value: 0.9, category_value: nil)
      expect(score).to be_numerical
      expect(score).not_to be_categorical
    end

    it "identifies categorical scores" do
      score = build(:feedback_score, value: nil, category_value: "excellent")
      expect(score).to be_categorical
      expect(score).not_to be_numerical
    end

    it "identifies span-level scores" do
      score = build(:feedback_score, span_id: "span_123", trace_id: nil)
      expect(score).to be_span_level
    end

    it "identifies trace-level scores" do
      score = build(:feedback_score, span_id: nil, trace_id: "trace_456")
      expect(score).to be_trace_level
    end
  end

  describe ".score_span" do
    it "creates multiple scores for a span" do
      scores = described_class.score_span(
        span_id: "span_test_123",
        scores: { relevance: 0.9, accuracy: 0.85 },
        scored_by: "tester"
      )

      expect(scores.length).to eq(2)
      expect(scores.all?(&:persisted?)).to be true
      expect(scores.map(&:name)).to contain_exactly("relevance", "accuracy")
    end

    it "handles categorical values" do
      scores = described_class.score_span(
        span_id: "span_test_456",
        scores: { quality: "good" },
        scored_by: "tester"
      )

      expect(scores.first.category_value).to eq("good")
      expect(scores.first.value).to be_nil
    end
  end

  describe ".score_trace" do
    it "creates scores for a trace" do
      scores = described_class.score_trace(
        trace_id: "trace_test_789",
        scores: { overall: 0.75 },
        scored_by: "reviewer"
      )

      expect(scores.first.trace_id).to eq("trace_test_789")
      expect(scores.first.span_id).to be_nil
    end
  end

  describe ".average_value" do
    before do
      create(:feedback_score, name: "relevance", value: 0.8)
      create(:feedback_score, name: "relevance", value: 0.6)
    end

    it "calculates average of numerical scores" do
      avg = described_class.average_value
      expect(avg).to be_within(0.01).of(0.7)
    end
  end

  describe ".category_distribution" do
    before do
      create(:feedback_score, name: "quality", value: nil, category_value: "good")
      create(:feedback_score, name: "quality", value: nil, category_value: "good")
      create(:feedback_score, name: "quality", value: nil, category_value: "bad")
    end

    it "counts categories" do
      dist = described_class.category_distribution
      expect(dist["good"]).to eq(2)
      expect(dist["bad"]).to eq(1)
    end
  end

  describe ".score_statistics" do
    before do
      [0.6, 0.7, 0.8, 0.9, 1.0].each do |v|
        create(:feedback_score, value: v)
      end
    end

    it "calculates statistics" do
      stats = described_class.score_statistics
      expect(stats[:count]).to eq(5)
      expect(stats[:avg]).to be_within(0.01).of(0.8)
      expect(stats[:min]).to eq(0.6)
      expect(stats[:max]).to eq(1.0)
      expect(stats[:median]).to eq(0.8)
    end
  end

  describe "scopes" do
    it "filters by span" do
      s1 = create(:feedback_score, span_id: "span_a")
      create(:feedback_score, span_id: "span_b")

      expect(described_class.for_span("span_a")).to eq([s1])
    end

    it "filters by name" do
      create(:feedback_score, name: "relevance")
      create(:feedback_score, name: "accuracy")

      expect(described_class.for_name("relevance").count).to eq(1)
    end

    it "filters human vs automated" do
      create(:feedback_score, source: "ui")
      create(:feedback_score, source: "automated")

      expect(described_class.from_humans.count).to eq(1)
      expect(described_class.from_automated.count).to eq(1)
    end
  end
end
