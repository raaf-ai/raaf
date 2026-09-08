# frozen_string_literal: true

require "rails_helper"

RSpec.describe RAAF::Rails::Continuous::ScorerHealth, type: :model do
  # Fixed, so "two days ago" means the same thing every run and the window
  # boundaries the states turn on are not a function of the clock.
  let(:now) { Time.utc(2026, 9, 7, 12, 0, 0) }
  let(:health) { described_class.new(window: 7.days, now: now) }

  def result(name:, at:, type: "llm_judge", status: "good", score: 0.8, span: nil,
             agent: "ProbeAgent", duration: 1000, models: nil, cost: nil)
    metrics = {}
    metrics["evaluation_models"] = models if models
    metrics["evaluation_cost"] = cost if cost

    RAAF::Eval::Models::ContinuousEvaluationResult.create!(
      span_id: span || "span_#{SecureRandom.hex(8)}", trace_id: "trace_probe",
      evaluation_type: "automated", evaluator_name: name, evaluator_type: type,
      agent_name: agent, environment: "test", status: status, score: score,
      metrics: metrics, evaluation_duration_ms: duration, created_at: at
    )
  end

  describe "the headline figures" do
    before do
      3.times { result(name: "judge", at: now - 2.days, cost: 0.01) }
      result(name: "flaky", at: now - 1.hour, type: "rule_based", status: "error",
             score: nil, duration: 10, cost: 0.0)
    end

    it "counts every evaluation in the window" do
      expect(health.evaluations).to eq(4)
    end

    it "reports the share that could not be produced at all" do
      expect(health.error_rate).to be_within(0.001).of(0.25)
      expect(health.error_count).to eq(1)
    end

    # An error is the evaluator breaking. A bad verdict is the evaluator
    # working, and must not be counted as a failure of the scorer.
    it "does not count a bad verdict as an error" do
      result(name: "judge", at: now - 1.day, status: "bad", score: 0.1)

      expect(health.error_count).to eq(1)
    end

    it "prices a thousand evaluations from the judge tokens each one recorded" do
      expect(health.cost_per_1k).to be_within(0.01).of(7.5)
    end

    it "takes p95 over the recorded durations" do
      expect(health.latency_p95_ms).to eq(1000.0)
    end

    # The cards and the bars under them are two views of one query, so the
    # series has to total what the cards report.
    it "buckets the same rows the cards total" do
      expect(health.series[:evaluations].size).to eq(described_class::BUCKETS)
      expect(health.series[:evaluations].sum).to eq(health.evaluations)
      expect(health.series[:errors].sum).to eq(health.error_count)
    end
  end

  describe "scorer rows" do
    before do
      4.times { result(name: "judge", at: now - 2.days, score: 0.80, models: ["gpt-4o-2024-11"]) }
      4.times { result(name: "judge", at: now - 9.days, score: 1.00, models: ["gpt-4o-2024-08"]) }
    end

    def row(name) = health.scorers.find { |scorer| scorer[:name] == name }

    it "compares the window's mean with the window before it" do
      expect(row("judge")[:mean]).to be_within(0.001).of(0.80)
      expect(row("judge")[:baseline]).to be_within(0.001).of(1.00)
      expect(row("judge")[:drift]).to be_within(0.001).of(-0.20)
    end

    # The table is read by somebody looking for a check, and the recorded name
    # is the symbol a policy is written in rather than what the check is
    # called. A scorer whose class is gone keeps its symbol, which is still
    # what ran.
    it "carries the title each scorer's class declares for itself" do
      allow_any_instance_of(RAAF::Rails::Continuous::EvaluatorTitles)
        .to receive(:[]).with("judge").and_return("The Judge")

      expect(row("judge")[:title]).to eq("The Judge")
    end

    it "leaves the title empty for a scorer nothing is registered under" do
      expect(row("judge")[:title]).to be_nil
    end

    it "names the judge models the window's evaluations called" do
      expect(row("judge")[:models]).to eq(["gpt-4o-2024-11"])
    end

    it "calls a scorer that moved drifting" do
      expect(row("judge")[:state]).to eq("drifting")
    end

    # A scorer that moved and then went quiet is both things, and the drift is
    # the one somebody has to answer.
    it "reports drift rather than silence when a scorer is both" do
      # Inside the window, but past the point where silence alone would make it
      # stale -- the judge rows above are two days old and still current.
      4.times { result(name: "quiet", at: now - 5.days, score: 0.80) }
      4.times { result(name: "quiet", at: now - 9.days, score: 1.00) }

      expect(row("quiet")[:last_at]).to be < now - (7.days * described_class::STALE_FRACTION)
      expect(row("quiet")[:state]).to eq("drifting")
    end

    it "lists a scorer that ran only in the baseline, as stale" do
      result(name: "retired", at: now - 9.days, type: "rule_based", score: 0.5)

      expect(row("retired")).to include(state: "stale", count: 0, mean: nil)
    end

    it "leaves a steady scorer alone" do
      result(name: "steady", at: now - 1.hour, type: "rule_based", score: 0.9)
      result(name: "steady", at: now - 8.days, type: "rule_based", score: 0.9)

      expect(row("steady")[:state]).to eq("healthy")
    end

    it "counts a scorer's errors beside it" do
      result(name: "judge", at: now - 1.day, status: "error", score: nil)

      expect(row("judge")[:errors]).to eq(1)
    end
  end

  describe "#judge_changes" do
    it "reports a judge model that was swapped underneath a scorer" do
      result(name: "judge", at: now - 2.days, models: ["gpt-4o-2024-11"])
      result(name: "judge", at: now - 9.days, models: ["gpt-4o-2024-08"])

      expect(health.judge_changes)
        .to eq([{ scorer: "judge", was: ["gpt-4o-2024-08"], now: ["gpt-4o-2024-11"] }])
    end

    it "says nothing when the same model scored both windows" do
      result(name: "judge", at: now - 2.days, models: ["gpt-4o-2024-11"])
      result(name: "judge", at: now - 9.days, models: ["gpt-4o-2024-11"])

      expect(health.judge_changes).to be_empty
    end

    it "ignores a scorer that calls no model at all" do
      result(name: "regex", at: now - 2.days, type: "rule_based")
      result(name: "regex", at: now - 9.days, type: "rule_based")

      expect(health.judge_changes).to be_empty
    end
  end

  describe "#agreement" do
    before { result(name: "judge", at: now - 2.days, span: "span_probe", score: 0.80) }

    it "is absent when no span carries a human score" do
      expect(health.agreement).to eq({ value: nil, spans: 0 })
    end

    # A 4 on a 1–5 scale is 0.75, not 4.0. Comparing the raw value would read
    # as a rout rather than as agreement.
    it "normalises a human score through its definition's range" do
      RAAF::Eval::Models::FeedbackScoreDefinition.create!(
        name: "relevance", score_type: "numerical", min_value: 1.0, max_value: 5.0
      )
      RAAF::Eval::Models::FeedbackScore.create!(
        name: "relevance", span_id: "span_probe", value: 4.0, source: "ui",
        scored_by: "reviewer", created_at: now - 2.days
      )

      expect(health.agreement[:spans]).to eq(1)
      expect(health.agreement[:value]).to be_within(0.0001).of(0.95)
    end

    it "drops a value that falls outside the range it claims" do
      RAAF::Eval::Models::FeedbackScoreDefinition.create!(
        name: "relevance", score_type: "numerical", min_value: 0.0, max_value: 1.0
      )
      RAAF::Eval::Models::FeedbackScore.create!(
        name: "relevance", span_id: "span_probe", value: 4.0, source: "ui",
        scored_by: "reviewer", created_at: now - 2.days
      )

      expect(health.agreement).to eq({ value: nil, spans: 0 })
    end
  end

  describe "#coverage" do
    it "counts a span graded four times as one span covered" do
      3.times { |i| result(name: "check_#{i}", at: now - 1.day, span: "span_one") }
      result(name: "check_9", at: now - 1.day, span: "span_two")

      row = health.coverage.find { |entry| entry[:agent].casecmp("ProbeAgent").zero? }

      expect(row[:scored]).to eq(2)
    end
  end

  describe "when the continuous tables are missing" do
    before do
      allow(RAAF::Eval::Models::ContinuousEvaluationResult)
        .to receive(:table_exists?).and_return(false)
    end

    # A host that mounted the dashboard without running the engine's migrations
    # should get an empty screen that says so, not a 500.
    it "reports itself unavailable and answers everything empty" do
      expect(health).not_to be_available
      expect(health.evaluations).to eq(0)
      expect(health.scorers).to be_empty
      expect(health.error_rate).to be_nil
    end
  end
end
