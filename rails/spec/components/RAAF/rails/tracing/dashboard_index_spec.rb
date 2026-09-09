# frozen_string_literal: true

require "rails_helper"

# The Overview's job is to say four things the reader cannot get elsewhere on
# the screen. It used to say three: Success rate was Failure rate's
# complement, an agent tile printed its trace count where its model belongs,
# and a panel titled Live never said when anything started.
RSpec.describe RAAF::Rails::Tracing::DashboardIndex, type: :component do
  def overview(total: 100, failed: 4, completed: 90)
    { total_traces: total, failed_traces: failed, completed_traces: completed,
      running_traces: total - failed - completed, total_spans: 400, error_spans: 9,
      avg_trace_duration: 2.5, success_rate: 90.0, error_rate: 2.25 }
  end

  def screen(workflows: [], spend: {}, models: {}, traces: [], stats: overview)
    described_class.new(overview_stats: stats, top_workflows: workflows,
                        recent_traces: traces, workflow_spend: spend,
                        workflow_models: models)
  end

  def workflow(name: "Scout", trace_count: 12, success_rate: 100.0, p95: 1.5)
    { workflow_name: name, trace_count: trace_count, success_rate: success_rate,
      p95_duration: p95, avg_duration: 1.0, error_count: 0 }
  end

  describe "the KPI row" do
    it "carries four figures none of which restates another" do
      labels = screen.send(:kpi_stats).map { |stat| stat[:label] }

      expect(labels).to eq(["Runs", "Failure rate", "Avg duration", "Spend"])
    end

    it "totals what the window's workflows were billed" do
      render_inline screen(spend: { "Scout" => 1.25, "Enrich" => 0.4 })

      expect(page).to have_content("$1.65")
      expect(page).to have_content("2 workflows billed")
    end

    # Nothing billed is not the same as billing zero: printing $0.00 claims a
    # measurement nobody took.
    it "makes no claim where nothing was billed at all" do
      render_inline screen

      expect(page).to have_content("nothing billed · selected range")
      expect(page).to have_no_content("$0.00")
    end
  end

  describe "an agent tile" do
    it "names the model the workflow ran and counts its runs once" do
      tile = screen(workflows: [workflow(trace_count: 3120)],
                    models: { "Scout" => "gpt-4o" }).send(:agent_tiles).first

      expect(tile).to include(model: "gpt-4o", runs: "3,120")
    end

    # The grid drops the slot rather than printing a separator with nothing
    # in front of it.
    it "leaves the model slot empty for a workflow that recorded none" do
      tile = screen(workflows: [workflow]).send(:agent_tiles).first

      expect(tile[:model]).to be_nil
    end
  end

  describe "a live run" do
    it "says when the run started" do
      trace = instance_double(RAAF::Rails::Tracing::TraceRecord,
                              workflow_name: "Scout", trace_id: "trace_1",
                              status: "running", duration_ms: 900,
                              started_at: 3.minutes.ago, spans: [])

      render_inline screen(traces: [trace])

      expect(page).to have_content("3 minutes ago")
    end
  end
end
