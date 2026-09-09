# frozen_string_literal: true

require "rails_helper"

# Two claims the Flows screen could not back: a share of wall clock it did not
# compute, and a tab whose picker had been removed.
RSpec.describe RAAF::Rails::Tracing::FlowsVisualization, type: :component do
  def screen(params: {}, traces: [], nodes: [])
    described_class.new(flow_data: { nodes: nodes, edges: [] }, agents: [],
                        traces: traces, path_spans: [], range: "24h", params: params)
  end

  describe "pipeline heat" do
    # The summed durations exceed the elapsed time: parallel spans each
    # contribute in full, and a nested span is counted inside its parent as
    # well as on its own.
    it "labels the share for the total it is actually taken over" do
      render_inline screen(params: { tab: "pipeline" })

      expect(page).to have_content("share of total span time")
      expect(page).to have_no_content("wall clock, slowest first")
    end
  end

  describe "the Single trace path tab" do
    let(:traces) { [%w[trace_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa Scout], %w[trace_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb Enrich]] }

    # Its picker had been removed, so the tab read params[:trace_id] and was
    # reachable only by editing the query string.
    it "offers the window's traces to pick from" do
      options = screen(params: { tab: "trace" }, traces: traces).send(:trace_options)

      expect(options.map(&:last)).to eq(traces.map(&:first))
      expect(options.first.first).to start_with("Scout · ")
    end

    it "renders the picker on the tab" do
      render_inline screen(params: { tab: "trace" }, traces: traces)

      expect(page).to have_css("select[name='trace_id']")
      expect(page).to have_content("Show path")
    end

    it "keeps the window and the agent filter when a trace is chosen" do
      carried = screen(params: { tab: "trace", range: "7d", agent_name: "Scout" },
                       traces: traces).send(:carried_path_params)

      expect(carried).to eq(agent_name: "Scout", range: "7d")
    end

    # Nothing to pick from is not a broken picker, it is an empty window.
    it "draws no picker for a window holding no traces" do
      render_inline screen(params: { tab: "trace" })

      expect(page).to have_no_css("select[name='trace_id']")
    end
  end
end
