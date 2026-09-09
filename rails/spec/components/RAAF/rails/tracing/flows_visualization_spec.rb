# frozen_string_literal: true

require "rails_helper"

# Two claims the Flows screen could not back: a share of wall clock it did not
# compute, and a tab whose picker had been removed. It computes the first one
# now, over the union of each node's intervals rather than the sum of them.
RSpec.describe RAAF::Rails::Tracing::FlowsVisualization, type: :component do
  def screen(params: {}, traces: [], nodes: [], busy: nil)
    stats = busy ? { busy_duration: busy } : {}
    described_class.new(flow_data: { nodes: nodes, edges: [], stats: stats }, agents: [],
                        traces: traces, path_spans: [], range: "24h", params: params)
  end

  def node(name, total:, busy:)
    { id: "agent_#{name}", name: name, type: "agent", count: 1, error_count: 0,
      total_duration: total, busy_duration: busy }
  end

  describe "pipeline heat" do
    # The bars are a share of elapsed time, which is the union of each node's
    # intervals over the union of everything's -- not the sum of the spans'
    # durations, which counts a parallel span in full and a nested one twice.
    it "names the measure it reports" do
      render_inline screen(params: { tab: "pipeline" })

      expect(page).to have_content("share of elapsed time")
      expect(page).to have_no_content("share of total span time")
    end

    # A step that fanned out over ten workers accounts for a lot of summed
    # duration and not much of the clock. Ranking by the sum while reporting
    # the union would leave the order and the numbers disagreeing.
    it "ranks the steps by the figure they report" do
      steps = screen(params: { tab: "pipeline" }, busy: 10_000,
                     nodes: [node("Scout", total: 40_000, busy: 4000),
                             node("Enrich", total: 9000, busy: 9000)]).send(:pipeline_steps)

      expect(steps.map { |step| step[:name] }).to eq(%w[Enrich Scout])
      expect(steps.map { |step| step[:pct] }).to eq([90.0, 40.0])
    end

    # Two steps that ran at once are each responsible for the same seconds.
    it "gives a step that ran throughout the whole of the elapsed time" do
      steps = screen(params: { tab: "pipeline" }, busy: 10_000,
                     nodes: [node("Scout", total: 10_000, busy: 10_000),
                             node("Enrich", total: 10_000, busy: 10_000)]).send(:pipeline_steps)

      expect(steps.map { |step| step[:pct] }).to eq([100.0, 100.0])
    end

    it "draws no bars for a window in which nothing ran" do
      steps = screen(params: { tab: "pipeline" }, busy: 0,
                     nodes: [node("Scout", total: 10_000, busy: 0)]).send(:pipeline_steps)

      expect(steps).to be_empty
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
