# frozen_string_literal: true

require "rails_helper"

# The Result screen asked "whether this verdict is the odd one out" and answered
# it with recent results of the same policy — empty whenever the policy has
# graded one span, and a mix of different questions on different scales whenever
# it is not.
RSpec.describe RAAF::Rails::Continuous::CheckHistory do
  def result_for(span:, field:, score:, evaluator: "timeline_relevance", ago: 1.hour)
    RAAF::Eval::Models::ContinuousEvaluationResult.create!(
      span_id: span, trace_id: "trace_history", evaluation_type: "automated",
      evaluator_name: evaluator, evaluator_type: "rule_based",
      agent_name: "TimelineRelevanceScorer", environment: "test",
      status: "good", score: score, metrics: {}, evaluation_duration_ms: 1,
      created_at: Time.current - ago, metadata: { "field_name" => field }
    )
  end

  let(:subject_result) { result_for(span: "span_a", field: "scored_events", score: 1.0) }

  describe "what counts as comparable" do
    it "takes the same check on other spans" do
      other = result_for(span: "span_b", field: "scored_events", score: 0.9)

      expect(described_class.new(result: subject_result).results).to contain_exactly(other)
    end

    # A relevance verdict beside a latency verdict is two numbers that cannot be
    # the odd one out of each other.
    it "leaves out another field of the same evaluator" do
      result_for(span: "span_b", field: "output", score: 0.2)

      expect(described_class.new(result: subject_result).results).to be_empty
    end

    it "leaves out another evaluator on the same field" do
      result_for(span: "span_b", field: "scored_events", score: 0.2, evaluator: "other_check")

      expect(described_class.new(result: subject_result).results).to be_empty
    end

    # The same span graded twice is the same question asked twice, and the
    # screen lists those separately.
    it "leaves out another grading of the same span" do
      result_for(span: "span_a", field: "scored_events", score: 0.4)

      expect(described_class.new(result: subject_result).results).to be_empty
    end

    it "leaves out results older than the window" do
      result_for(span: "span_b", field: "scored_events", score: 0.4, ago: 60.days)

      expect(described_class.new(result: subject_result).results).to be_empty
    end
  end

  describe "the figures" do
    before do
      result_for(span: "span_b", field: "scored_events", score: 0.4)
      result_for(span: "span_c", field: "scored_events", score: 0.6)
    end

    # This result is one of its own check's answers. Leaving it out would make a
    # run of identical verdicts look like it had variety.
    it "counts this result among the check's scores" do
      expect(described_class.new(result: subject_result).count).to eq(3)
    end

    it "reports the middle score" do
      expect(described_class.new(result: subject_result).median).to eq(0.6)
    end

    it "places this verdict among the rest" do
      expect(described_class.new(result: subject_result).rank).to eq(1.0)
    end
  end

  # The one fact a single result can never carry, and the one most worth
  # knowing: a check returning 1.00 on every span it has graded is not passing,
  # it is not measuring.
  describe "a check that never varies" do
    before do
      result_for(span: "span_b", field: "scored_events", score: 1.0)
      result_for(span: "span_c", field: "scored_events", score: 1.0)
    end

    it "is flat" do
      expect(described_class.new(result: subject_result).flat?).to be(true)
    end

    # Ranking a verdict among identical verdicts says "this one is among its
    # highest" about a number that is also its lowest.
    it "makes no claim about where this one sits" do
      expect(described_class.new(result: subject_result).rank).to be_nil
    end
  end

  describe "too little history to see a pattern" do
    it "does not call a check flat on its first run" do
      expect(described_class.new(result: subject_result).flat?).to be_nil
    end
  end

  # A score of 0.62 is good news after 0.40 and bad news after 0.90. The number
  # on its own cannot say which.
  describe "reading this verdict against what came before" do
    let(:subject_result) do
      result_for(span: "span_a", field: "scored_events", score: 0.62, ago: 1.hour)
    end

    before do
      result_for(span: "span_b", field: "scored_events", score: 0.90, ago: 2.hours)
      result_for(span: "span_c", field: "scored_events", score: 0.40, ago: 3.hours)
    end

    it "names the run before this one" do
      expect(described_class.new(result: subject_result).previous.score.to_f).to eq(0.9)
    end

    it "says how far this one moved from it" do
      expect(described_class.new(result: subject_result).delta_vs_previous)
        .to be_within(0.0001).of(-0.28)
    end

    it "averages the runs that came before" do
      expect(described_class.new(result: subject_result).average).to be_within(0.0001).of(0.65)
    end

    it "says how far this one sits from that average" do
      expect(described_class.new(result: subject_result).delta_vs_average)
        .to be_within(0.0001).of(-0.03)
    end

    it "says how many runs the average is taken over" do
      expect(described_class.new(result: subject_result).earlier_count).to eq(2)
    end

    # An average this verdict is part of moves towards it, so every result
    # would look closer to normal than it is.
    it "leaves this result out of its own average" do
      expect(described_class.new(result: subject_result).average).not_to eq(0.64)
    end

    # A later run is not what came before, however recently it was written.
    it "ignores a run that happened after this one" do
      result_for(span: "span_d", field: "scored_events", score: 0.1, ago: 1.minute)

      expect(described_class.new(result: subject_result).previous.score.to_f).to eq(0.9)
    end

    # The panel does not list a re-grading of this span, and must not measure
    # against one either: the figures and the rows below them would then be
    # drawn from different sets.
    it "leaves a re-grading of this span out of the average" do
      result_for(span: "span_a", field: "scored_events", score: 0.2, ago: 4.hours)

      expect(described_class.new(result: subject_result).earlier_count).to eq(2)
    end

    # Otherwise a span graded four times outvotes three spans graded once.
    it "lets one span speak once, through its latest verdict" do
      result_for(span: "span_b", field: "scored_events", score: 0.10, ago: 4.hours)

      history = described_class.new(result: subject_result)
      expect(history.earlier_count).to eq(2)
      expect(history.average).to be_within(0.0001).of(0.65)
    end
  end

  # The card read "4 scores · median 0.65", a running average over 3 runs and
  # a never-varies verdict, above an empty list — every figure taken from three
  # re-gradings of the one span the listing leaves out.
  describe "a check that has only ever graded this span" do
    before do
      result_for(span: "span_a", field: "scored_events", score: 1.0, ago: 2.hours)
      result_for(span: "span_a", field: "scored_events", score: 1.0, ago: 3.hours)
      result_for(span: "span_a", field: "scored_events", score: 1.0, ago: 4.hours)
    end

    it "has nothing to say about how it usually scores" do
      history = described_class.new(result: subject_result)

      expect(history.count).to eq(1)
      expect(history.any?).to be(false)
      expect(history.average).to be_nil
      expect(history.previous).to be_nil
    end

    # One span answered the same way four times has not shown that the check
    # cannot tell two things apart. It has not been asked two things.
    it "does not call the check flat" do
      expect(described_class.new(result: subject_result).flat?).to be_nil
    end

    # Counted apart from the spans, because it answers a different question:
    # not what the check scores, but whether it answers the same input twice
    # the same way.
    it "counts the runs it has had here" do
      expect(described_class.new(result: subject_result).repeat_count).to eq(4)
    end

    it "says the runs agreed" do
      expect(described_class.new(result: subject_result).repeats_agree?).to be(true)
    end
  end

  describe "a span this check answered differently on a re-run" do
    before { result_for(span: "span_a", field: "scored_events", score: 0.2, ago: 2.hours) }

    it "says so rather than calling the check repeatable" do
      expect(described_class.new(result: subject_result).repeats_agree?).to be(false)
    end
  end

  describe "a check on its first run" do
    it "has one run here and nothing to agree with" do
      history = described_class.new(result: subject_result)

      expect(history.repeat_count).to eq(1)
      expect(history.repeats_agree?).to be_nil
    end
  end

  describe "the first run of a check" do
    it "has nothing before it to compare with" do
      history = described_class.new(result: subject_result)

      expect(history.previous).to be_nil
      expect(history.delta_vs_previous).to be_nil
      expect(history.average).to be_nil
    end
  end

  describe "a result whose field cannot be read" do
    let(:fieldless) do
      RAAF::Eval::Models::ContinuousEvaluationResult.create!(
        span_id: "span_z", trace_id: "trace_history", evaluation_type: "automated",
        evaluator_name: "timeline_relevance", evaluator_type: "rule_based",
        agent_name: "Scorer", environment: "test", status: "good", score: 0.5,
        metrics: {}, evaluation_duration_ms: 1, metadata: {}, details: {}
      )
    end

    it "compares it with nothing rather than with the whole evaluator" do
      result_for(span: "span_b", field: "scored_events", score: 0.9)

      expect(described_class.new(result: fieldless).results).to be_empty
    end
  end
end
