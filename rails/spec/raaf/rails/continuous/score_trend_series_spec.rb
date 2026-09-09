# frozen_string_literal: true

require "rails_helper"

# The engine's autoload paths are not reachable from the specs — every
# `spec/components` file dies on `uninitialized constant RAAF::Rails::Tracing`
# before it runs an example. This class has no such dependency, so it is loaded
# by path and tested for real rather than joining that pile.
require_relative "../../../../app/controllers/RAAF/rails/time_range"
require_relative "../../../../app/models/RAAF/rails/continuous/score_trend_series"

# Stands in for the database the series groups its rows in, playing both the
# model that builds the statement and the connection that runs it. The SQL text
# is not interpreted; what it does instead is the grouping the statement asks
# for, so an example can still be written in timestamps and scores while the
# series receives what a GROUP BY would hand it.
#
# What that leaves untested is the bucketing itself, which is now
# `width_bucket` and needs a Postgres to run. The bucket starts it is given are
# the series' own, so the boundaries either side of a cell are still the real
# ones; it is only the arithmetic between them that has moved out of reach.
#
# Declared at the top level rather than inside the example group: a class
# defined in a block leaks into the global namespace anyway, and this way it
# says so.
class FakeEvaluationTable
  def initialize(starts:, rows: [], debuts: {})
    @starts = starts
    @rows = rows
    @debuts = debuts
  end

  def table_exists? = true
  def table_name = "fake_evaluations"
  def check_key_stored? = true

  # The series builds its statement through the model and runs it on the
  # connection. Here both of those are this object.
  def sanitize_sql_array(statement) = statement.first
  def connection = self

  # The two statements the series issues, told apart by the one column only the
  # release query names.
  def select_rows(sql)
    sql.include?("agent_version") ? debut_rows : score_rows
  end

  private

  # `[keys..., bucket, sum, count]`, the shape the GROUP BY returns. A row is
  # written `[*keys, at, score]`, so the keys are whatever precedes the last
  # two — three columns for an evaluator, one for a feedback score.
  def score_rows
    totals = Hash.new { |hash, key| hash[key] = [0.0, 0] }

    @rows.each do |row|
      *keys, at, score = row
      index = bucket_of(at)
      next unless index

      sum, count = totals[[*keys, index]]
      totals[[*keys, index]] = [sum + score, count + 1]
    end

    totals.map { |key, (sum, count)| [*key, sum, count] }
  end

  # A version whose first result predates the window is excluded by the
  # statement's own `NOT EXISTS`; here it simply falls outside every bucket.
  def debut_rows
    @debuts.filter_map do |version, at|
      index = bucket_of(at)
      index && [version, index]
    end
  end

  def bucket_of(at) = @starts.rindex { |start| start <= at }
end

RSpec.describe RAAF::Rails::Continuous::ScoreTrendSeries do
  # Every bucket is counted back from "now", so the clock is held still.
  let(:noon) { Time.new(2026, 9, 7, 12, 0, 0) }

  before { allow(Time).to receive(:current).and_return(noon) }

  def series(rows: [], feedback: [], debuts: {}, range: "30d")
    instance = described_class.new(range: range)
    starts = instance.send(:starts)

    results = FakeEvaluationTable.new(starts: starts, rows: rows, debuts: debuts)
    scores = FakeEvaluationTable.new(starts: starts, rows: feedback)

    allow(instance).to receive_messages(result_model: results, feedback_model: scores)
    instance.call
  end

  # One evaluation row, as the grouping sees it before it is grouped. A row
  # carries the check it is about; one recorded before checks were kept apart
  # carries nil, and the series then has nothing to name the line after but
  # the evaluator.
  def result(name, agent, type, at, score, check: nil)
    [name, agent, type, check, at, score]
  end

  describe "the grid" do
    it "draws one bucket per day over a month, oldest first" do
      trends = series

      expect(trends[:buckets].size).to eq(30)
      expect(trends[:buckets].first[:at]).to be < trends[:buckets].last[:at]
      expect(trends[:window]).to eq("30 days")
      expect(trends[:unit]).to eq("day")
    end

    it "sizes the bucket to the window it is answering" do
      expect(series(range: "1h")[:buckets].size).to eq(60)
      expect(series(range: "24h")[:buckets].size).to eq(24)
      expect(series(range: "7d")[:buckets].size).to eq(7)
    end

    it "falls back rather than raising on a range nobody offers" do
      expect(series(range: "nonsense")[:window]).to eq("30 days")
    end
  end

  describe "a row" do
    let(:rows) do
      (0..29).map do |day|
        at = noon.beginning_of_day - ((29 - day) * 1.day) + 6.hours
        result("faithfulness", "Company::EnrichAgent", "llm_judge", at,
               day < 23 ? 0.95 : 0.80)
      end
    end

    it "says what kind of evaluator it is in the console's words" do
      expect(series(rows: rows)[:rows].first[:kind]).to eq("LLM judge")
    end

    it "carries a score per bucket, the newest last" do
      row = series(rows: rows)[:rows].first

      expect(row[:series].size).to eq(30)
      expect(row[:current]).to be_within(0.001).of(0.80)
      expect(row[:median]).to be_within(0.001).of(0.95)
    end

    it "measures the drop against the week before it" do
      expect(series(rows: rows)[:rows].first[:delta]).to be_within(0.001).of(-0.15)
    end

    it "leaves a bucket nothing ran in scoreless rather than zero" do
      quiet = rows.reject.with_index { |_, index| index == 24 }
      drawn = series(rows: quiet)[:rows].first[:series]

      expect(drawn[24]).to be_nil
      expect(drawn[23]).not_to be_nil
      expect(drawn[25]).not_to be_nil
    end

    it "keeps the same check against two agents apart" do
      other = result("faithfulness", "Outreach::DraftAgent", "llm_judge", noon, 0.6)

      expect(series(rows: rows + [other])[:rows].map { |row| row[:agent] })
        .to contain_exactly("Company::EnrichAgent", "Outreach::DraftAgent")
    end

    # A rule and a judge on one field used to share a score, plotted once
    # under the evaluator's name, so neither could be watched drifting.
    it "plots each of an evaluator's checks against its own field" do
      judged = result("quality", "Company::EnrichAgent", "llm_judge", noon, 0.9,
                      check: "confidence:llm_judge")
      ruled = result("quality", "Company::EnrichAgent", "rule_based", noon, 0.4,
                     check: "confidence:value_range")

      rows = series(rows: [judged, ruled])[:rows]

      expect(rows.map { |row| row[:name] })
        .to contain_exactly("quality · confidence:llm_judge", "quality · confidence:value_range")
      expect(rows.map { |row| row[:current] }).to contain_exactly(0.9, 0.4)
    end

    # There is nothing to name it after: the parts were never written down.
    it "names a line recorded before checks were kept apart after its evaluator" do
      combined = result("quality", "Company::EnrichAgent", "llm_judge", noon, 0.7)

      expect(series(rows: [combined])[:rows].first[:name]).to eq("quality")
    end
  end

  describe "the headline row" do
    it "means the evaluators rather than the results, so a chatty rule cannot drown a judge" do
      at = noon
      rows = ([result("rule", "A", "rule_based", at, 1.0)] * 50) +
             [result("judge", "A", "llm_judge", at, 0.5)]

      expect(series(rows: rows)[:overall][:series].last).to be_within(0.001).of(0.75)
    end
  end

  describe "the movement window" do
    it "is a quarter of the window either side, said in that window's own unit" do
      expect(series(range: "30d")[:delta_window]).to eq("7d")
      expect(series(range: "24h")[:delta_window]).to eq("6h")
      expect(series(range: "7d")[:delta_window]).to eq("1d")
      expect(series(range: "1h")[:delta_window]).to eq("15m")
    end

    it "reports no movement at all when one side of the comparison is empty" do
      only_today = [result("faithfulness", "A", "rule_based", noon, 0.9)]

      expect(series(rows: only_today)[:rows].first[:delta]).to be_nil
    end
  end

  describe "releases" do
    it "marks the bucket a version first appeared in" do
      shipped = noon.beginning_of_day - 3.days + 1.hour
      trends = series(debuts: { "v12" => shipped })

      expect(trends[:buckets][26][:release]).to eq("v12")
      expect(trends[:buckets].count { |bucket| bucket[:release] }).to eq(1)
    end

    it "ignores a version that was already running when the window opened" do
      trends = series(debuts: { "v11" => noon - 90.days })

      expect(trends[:buckets].count { |bucket| bucket[:release] }).to eq(0)
    end
  end

  describe "feedback scores" do
    it "become a human row with no agent to name" do
      trends = series(feedback: [["thumbs", noon, 0.9]])
      human = trends[:rows].find { |row| row[:kind] == "human" }

      expect(human[:name]).to eq("thumbs")
      expect(human[:agent]).to eq("all agents")
    end
  end

  describe "the row cap" do
    it "keeps the busiest evaluators and counts the rest rather than dropping them quietly" do
      rows = (0..29).flat_map do |index|
        Array.new(index + 1) { result("check_#{index}", "A", "rule_based", noon, 0.9) }
      end
      trends = series(rows: rows)

      expect(trends[:rows].size).to eq(described_class::MAX_ROWS)
      expect(trends[:total_rows]).to eq(30)
      expect(trends[:hidden_rows]).to eq(30 - described_class::MAX_ROWS)
    end
  end
end
