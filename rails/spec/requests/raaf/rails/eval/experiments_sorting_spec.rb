# frozen_string_literal: true

require "rails_helper"

# Spend is the figure that decides between two runs whose scores are level, and
# it was the one column on the screen you could not order by, because it was
# priced as each row was drawn rather than recorded.
RSpec.describe "ordering experiments by what they cost", type: :request do
  let(:dataset) { RAAF::Eval::Models::Dataset.create!(name: "Briefings #{SecureRandom.hex(3)}") }

  def experiment(name, cost:, created_at: Time.current)
    RAAF::Eval::Models::Experiment.create!(name: name, dataset: dataset, model: "gpt-4o",
                                          cost: cost, created_at: created_at)
  end

  before do
    experiment("Cheap and new", cost: 0.01, created_at: 1.minute.ago)
    experiment("Dear and old", cost: 5.00, created_at: 2.days.ago)
    experiment("Never priced", cost: nil, created_at: 1.hour.ago)
  end

  def names_in_order
    body = response.body
    %w[Cheap\ and\ new Dear\ and\ old Never\ priced].sort_by { |name| body.index(name) || Float::INFINITY }
  end

  it "lists the newest first by default" do
    get eval_experiments_path

    expect(names_in_order).to eq(["Cheap and new", "Never priced", "Dear and old"])
  end

  it "lists the dearest first when asked" do
    get eval_experiments_path(sort: "spend")

    expect(names_in_order.first).to eq("Dear and old")
  end

  # A run nobody priced has no figure to rank. Sorting it to the top would bury
  # the expensive runs under the ones with no answer.
  it "sorts a run with no recorded cost last" do
    get eval_experiments_path(sort: "spend")

    expect(names_in_order.last).to eq("Never priced")
  end

  it "offers the ordering from the list itself" do
    get eval_experiments_path

    expect(response.body).to include("show dearest first")
  end

  it "keeps the filter when the ordering changes" do
    get eval_experiments_path(sort: "spend", status: "pending")

    expect(response.body).to include("sort=spend")
  end
end
