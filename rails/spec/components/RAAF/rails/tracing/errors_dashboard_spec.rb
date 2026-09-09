# frozen_string_literal: true

require "rails_helper"

# The Overview's Failing now panel gives each signature a first-seen, an
# arrival rate and a trend. The dedicated screen you click through to gave
# less than the summary that sent you there.
RSpec.describe RAAF::Rails::Tracing::ErrorsDashboard, type: :component do
  def signature(exception: "Faraday::TimeoutError", message: "execution expired",
                agent: "Scout", count: 40, traces: 12,
                first_seen: 20.minutes.ago, last_seen: Time.current, trend: 12)
    { exception: exception, message: message, agent: agent, kind: "llm",
      count: count, traces: traces, trend: trend,
      first_seen: first_seen, last_seen: last_seen,
      span_id: "span_1", trace_id: "trace_1" }
  end

  def screen(signatures, params = {})
    described_class.new(signatures: signatures, params: params)
  end

  describe "a signature row" do
    it "reports the runs it touched and when it started" do
      render_inline screen([signature])

      expect(page).to have_content("Traces")
      expect(page).to have_content("First seen")
      expect(page).to have_content("12")
    end

    # Forty failures over a week and forty in a minute are the same count and
    # different emergencies.
    it "reports how fast the signature is arriving" do
      row = screen([signature(count: 40, first_seen: 20.minutes.ago, last_seen: Time.current)])

      expect(row.send(:rate_phrase, row.instance_variable_get(:@signatures).first)).to eq("2/min")
    end

    it "says nothing rather than 0/min for a signature arriving slower than that" do
      row = screen([])
      slow = signature(count: 3, first_seen: 5.hours.ago, last_seen: Time.current)

      expect(row.send(:rate_phrase, slow)).to be_nil
    end

    it "makes no rate claim about a signature that fired once" do
      row = screen([])
      once = signature(count: 1, first_seen: 1.minute.ago, last_seen: Time.current)

      expect(row.send(:rate_phrase, once)).to be_nil
    end
  end

  describe "the filter rail" do
    it "offers a chip per failing agent, counted over the whole window" do
      chips = screen([signature(agent: "Scout", count: 40),
                      signature(agent: "Enrich", count: 5)]).send(:agent_chips)

      expect(chips.map { |chip| chip[:label] }).to eq(%w[All Scout Enrich])
      expect(chips.map { |chip| chip[:count] }).to eq([45, 40, 5])
    end

    it "narrows the table to the chip that is active" do
      visible = screen([signature(agent: "Scout"), signature(agent: "Enrich")],
                       { agent: "Scout" }).send(:visible_signatures)

      expect(visible.map { |row| row[:agent] }).to eq(["Scout"])
    end

    it "searches the exception and its message" do
      visible = screen([signature(exception: "Faraday::TimeoutError"),
                        signature(exception: "JSON::ParserError", message: "unexpected token")],
                       { q: "parser" }).send(:visible_signatures)

      expect(visible.map { |row| row[:exception] }).to eq(["JSON::ParserError"])
    end

    # "Nothing failed" over an active filter is a lie about the window.
    it "distinguishes nothing failing from nothing matching" do
      expect(screen([]).send(:empty_state)).to include(title: "Nothing failed")
      expect(screen([], { q: "nope" }).send(:empty_state)).to include(title: "No signature matches")
    end

    it "carries the range forward so filtering does not reset the window" do
      chips = screen([signature(agent: "Scout")], { range: "7d" }).send(:agent_chips)

      expect(chips.last[:href]).to include("range=7d", "agent=Scout")
    end
  end
end
