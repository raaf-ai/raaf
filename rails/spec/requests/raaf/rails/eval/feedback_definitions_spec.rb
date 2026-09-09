# frozen_string_literal: true

require "rails_helper"

# FeedbackScoreDefinition is a real model with a full CRUD controller. The
# Feedback screen's "Score definitions" card derived its rows from the scores
# instead, under a comment saying the schema had no definition table.
RSpec.describe RAAF::Rails::Eval::FeedbackScoresController, type: :request do
  def definition(name:, score_type: "numerical", min: 1.0, max: 5.0, categories: nil)
    RAAF::Eval::Models::FeedbackScoreDefinition.create!(
      name: name, score_type: score_type, min_value: min, max_value: max,
      categories: categories
    )
  end

  def score(name:, value: 3.0)
    RAAF::Eval::Models::FeedbackScore.create!(
      name: name, source: "ui", span_id: "span_#{SecureRandom.hex(12)}", value: value
    )
  end

  def definitions
    controller = described_class.new
    controller.send(:score_definitions)
  end

  # Invisible before this: a definition with no scores contributed no rows to
  # a grouping taken over the scores.
  it "lists a definition that has never been scored against" do
    definition(name: "relevance")

    row = definitions.find { |one| one[:name] == "relevance" }

    expect(row).to include(count: 0, declared: true)
  end

  # It showed as 2–4 until something extreme was recorded.
  it "reports the range the definition declares, not the one its scores cover" do
    definition(name: "relevance", min: 1.0, max: 5.0)
    score(name: "relevance", value: 2.0)
    score(name: "relevance", value: 4.0)

    row = definitions.find { |one| one[:name] == "relevance" }

    expect(row[:range]).to eq("1.00 – 5.00")
    expect(row[:count]).to eq(2)
  end

  it "counts a categorical definition's declared categories" do
    definition(name: "quality", score_type: "categorical", min: nil, max: nil,
               categories: %w[excellent good poor])

    row = definitions.find { |one| one[:name] == "quality" }

    expect(row).to include(type: "categorical", range: "3 cats")
  end

  # Dropping these would hide real data behind a missing record, so they stay
  # and say what they are.
  it "keeps a name that was scored under no definition, and marks it" do
    score(name: "ad_hoc", value: 0.7)

    row = definitions.find { |one| one[:name] == "ad_hoc" }

    expect(row).to include(declared: false, count: 1)
  end

  describe "the retired statistics screen" do
    it "answers JSON and no longer renders a page" do
      get statistics_eval_feedback_scores_path

      expect(response.media_type).to eq("application/json")
      expect(response.parsed_body.keys).to include("statistics", "distribution")
    end
  end
end
