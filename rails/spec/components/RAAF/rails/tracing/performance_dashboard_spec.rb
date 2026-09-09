# frozen_string_literal: true

require "rails_helper"

# The controller asks about a fixed list of four span kinds, so a kind nothing
# ran comes back as a row of zeroes. The screen used to report that list as a
# measurement.
RSpec.describe RAAF::Rails::Tracing::PerformanceDashboard, type: :component do
  def kind(total: 10, avg: 200.0, p95: 400.0, median: 150.0)
    { total_spans: total, avg_duration_ms: avg, p95_duration_ms: p95, median_duration_ms: median }
  end

  def screen(by_kind)
    described_class.new(performance_by_kind: by_kind)
  end

  describe "the Kinds tile" do
    it "counts the kinds that recorded a span" do
      screen = screen("agent" => kind, "llm" => kind, "tool" => kind(total: 0, p95: 0.0),
                      "handoff" => kind(total: 0, p95: 0.0))

      expect(screen.send(:observed_by_kind).keys).to eq(%w[agent llm])
    end

    it "reads zero rather than four on a window with no spans in it" do
      screen = screen("agent" => kind(total: 0), "llm" => kind(total: 0))

      expect(screen.send(:observed_by_kind)).to be_empty
    end
  end

  describe "By kind" do
    # A bar at 0ms for a kind nothing ran is a row the reader has to discount
    # before reading the rows that mean something.
    it "lists only the kinds with spans behind them" do
      render_inline screen("agent" => kind, "handoff" => kind(total: 0, p95: 0.0))

      expect(page).to have_content("agent")
      expect(page).to have_no_content("handoff")
    end
  end

  describe "Worst p95" do
    it "tones by the figure rather than red on every window" do
      expect(screen("llm" => kind(p95: 40.0)).send(:worst_p95_tone)).to eq(:success)
      expect(screen("llm" => kind(p95: 5_000.0)).send(:worst_p95_tone)).to eq(:warning)
      expect(screen("llm" => kind(p95: 30_000.0)).send(:worst_p95_tone)).to eq(:danger)
    end

    # An empty window has no slowest kind, so it makes no claim about one.
    it "does not report a window with nothing in it as slow" do
      expect(screen("llm" => kind(total: 0, p95: 0.0)).send(:worst_p95_tone)).to eq(:success)
    end
  end
end
