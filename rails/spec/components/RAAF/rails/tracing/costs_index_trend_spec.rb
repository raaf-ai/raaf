# frozen_string_literal: true

require "rails_helper"

# $2.57 says nothing on its own. The design puts a comparison on the two
# figures that have one — spend and cost per run — against the window
# immediately before this one.
RSpec.describe RAAF::Rails::Tracing::CostsIndex, type: :component do
  def kpis(preceding:, total_cost: 2.57, runs: 39, window_hours: 168)
    described_class.new(cost_data: {
                          total_cost: total_cost, total_tokens: 1_400_000, input_tokens: 779_800,
                          output_tokens: 607_200, runs: runs, window_hours: window_hours,
                          preceding: preceding, breakdowns: []
                        }).send(:kpi_stats).index_by { |stat| stat[:label] }
  end

  describe "spend" do
    it "reports how far it moved against the window before it" do
      spend = kpis(preceding: { total_cost: 2.68, runs: 40 })["Spend"]

      expect(spend[:delta]).to eq("-4.1%")
      expect(spend[:note]).to eq("vs $2.68 in the preceding 7d")
    end

    # Inverted against every other KPI on the console: a bill going up is the
    # one worth looking at.
    it "reads a rising bill as the direction worth noticing" do
      expect(kpis(preceding: { total_cost: 2.00, runs: 40 })["Spend"]).to include(tone: :warning)
      expect(kpis(preceding: { total_cost: 3.00, runs: 40 })["Spend"]).to include(tone: :success)
    end

    it "says flat rather than +0.0% for a window that did not move" do
      expect(kpis(preceding: { total_cost: 2.57, runs: 39 })["Spend"])
        .to include(delta: "flat", tone: :accent)
    end

    # Nothing to compare against is not the same as no change, so the card
    # makes no claim at all.
    it "makes no comparison without a preceding window" do
      spend = kpis(preceding: nil)["Spend"]

      expect(spend[:delta]).to be_nil
      expect(spend).to include(note: "in the selected range", tone: :accent)
    end
  end

  describe "cost per run" do
    # In dollars, because a percentage of $0.065 is not a number anybody can
    # act on without converting it back.
    it "reports the change in money rather than in percent" do
      card = kpis(preceding: { total_cost: 2.68, runs: 42 })["Cost / run"]

      expect(card[:delta]).to eq("+$0.002")
      expect(card[:note]).to eq("39 runs billed · $0.064 before")
    end

    it "keeps its run count and claims nothing without a preceding window" do
      card = kpis(preceding: nil)["Cost / run"]

      expect(card[:delta]).to be_nil
      expect(card[:note]).to eq("39 runs billed")
    end

    it "does not divide by a preceding window that billed no runs" do
      card = kpis(preceding: { total_cost: 0.0, runs: 0 })["Cost / run"]

      expect(card[:delta]).to eq("+$0.066")
      expect(card[:tone]).to eq(:warning)
    end
  end

  it "names the preceding window by this window's length, not by the range chip" do
    spend = kpis(preceding: { total_cost: 2.68, runs: 40 }, window_hours: 6)["Spend"]

    expect(spend[:note]).to end_with("in the preceding 6h")
  end

  # The design compares it against a budget, and this route has no budget to
  # compare it with; a percentage here would only repeat Spend's.
  it "leaves projected month without a delta" do
    card = kpis(preceding: { total_cost: 2.68, runs: 40 })["Projected month"]

    expect(card[:delta]).to be_nil
    expect(card[:note]).to eq("at the pace of the selected range")
  end
end
