# frozen_string_literal: true

require "rails_helper"

RSpec.describe RAAF::Rails::Tracing::SpanRecord, type: :model do
  describe ".spend_by_workflow" do
    def trace(workflow_name)
      RAAF::Rails::Tracing::TraceRecord.create!(
        trace_id: "trace_#{SecureRandom.hex(16)}",
        workflow_name: workflow_name,
        status: "completed",
        started_at: 2.hours.ago
      )
    end

    def span(trace_id:, name: "Scout", kind: "agent", parent_id: nil, model: nil,
             input: nil, output: nil, started_at: 10.minutes.ago)
      usage = {}
      usage["agent.model"] = model if model
      usage["input_tokens"] = input if input
      usage["output_tokens"] = output if output

      create_span(
        trace_id: trace_id,
        parent_id: parent_id,
        name: name,
        kind: kind,
        status: "ok",
        start_time: started_at,
        end_time: started_at + 1,
        duration_ms: 1000,
        span_attributes: usage
      )
    end

    def window
      1.hour.ago..Time.current
    end

    it "bills each workflow for the spans its traces recorded" do
      scout = trace("Scout")
      enrich = trace("Enrich")
      span(trace_id: scout.trace_id, model: "gpt-4o", input: 1000, output: 400)
      span(trace_id: enrich.trace_id, model: "gpt-4o", input: 500, output: 200)

      spend = described_class.spend_by_workflow(timeframe: window)

      expect(spend.keys).to match_array(%w[Scout Enrich])
      expect(spend["Scout"]).to be > spend["Enrich"]
    end

    it "sums the runs of one workflow into a single figure" do
      scout = trace("Scout")
      other = trace("Scout")
      span(trace_id: scout.trace_id, model: "gpt-4o", input: 1000, output: 400)
      span(trace_id: other.trace_id, model: "gpt-4o", input: 1000, output: 400)

      spend = described_class.spend_by_workflow(timeframe: window)

      expect(spend.size).to eq(1)
      expect(spend["Scout"]).to be_positive
    end

    # The same rule cost_rollup applies: an agent span and its LLM children
    # routinely carry the same counts, and billing both doubles the run.
    it "does not bill an LLM child whose parent already recorded the usage" do
      scout = trace("Scout")
      agent = span(trace_id: scout.trace_id, model: "gpt-4o", input: 1000, output: 400)
      span(trace_id: scout.trace_id, name: "gpt-4o", kind: "llm", parent_id: agent.span_id,
           model: "gpt-4o", input: 1000, output: 400)

      expect(described_class.spend_by_workflow(timeframe: window)["Scout"])
        .to eq(described_class.cost_rollup(timeframe: window)[:total_cost])
    end

    # Absent rather than zero: a workflow that never called a model has no
    # spend to report, which the tile says with an em dash instead of $0.00.
    it "omits a workflow whose spans recorded no usage" do
      job = trace("JobProgressionCleanupJob")
      span(trace_id: job.trace_id, name: "perform", kind: "job")

      expect(described_class.spend_by_workflow(timeframe: window)).not_to have_key("JobProgressionCleanupJob")
    end

    it "ignores spans outside the window" do
      scout = trace("Scout")
      span(trace_id: scout.trace_id, model: "gpt-4o", input: 1000, output: 400,
           started_at: 3.hours.ago)

      expect(described_class.spend_by_workflow(timeframe: window)).to be_empty
    end
  end
end
