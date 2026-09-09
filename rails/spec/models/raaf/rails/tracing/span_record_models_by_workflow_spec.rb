# frozen_string_literal: true

require "rails_helper"

# The Overview's agent tiles name the model each workflow ran. The tile used
# to print the trace count into that slot, so it read "3120 traces · 3,120
# runs" and never named a model at all.
RSpec.describe RAAF::Rails::Tracing::SpanRecord, type: :model do
  describe ".models_by_workflow" do
    def trace(workflow_name)
      RAAF::Rails::Tracing::TraceRecord.create!(
        trace_id: "trace_#{SecureRandom.hex(16)}",
        workflow_name: workflow_name,
        status: "completed",
        started_at: 2.hours.ago
      )
    end

    def span(trace_id:, model: nil, input: 1000, output: 400, started_at: 10.minutes.ago)
      attributes = {}
      attributes["agent.model"] = model if model
      attributes["input_tokens"] = input if input
      attributes["output_tokens"] = output if output

      create_span(
        trace_id: trace_id,
        name: "Scout",
        kind: "agent",
        status: "ok",
        start_time: started_at,
        end_time: started_at + 1,
        duration_ms: 1000,
        span_attributes: attributes
      )
    end

    def window
      1.hour.ago..Time.current
    end

    it "names the model each workflow ran" do
      scout = trace("Scout")
      enrich = trace("Enrich")
      span(trace_id: scout.trace_id, model: "gpt-4o")
      span(trace_id: enrich.trace_id, model: "claude-3-5-sonnet")

      expect(described_class.models_by_workflow(timeframe: window))
        .to eq("Scout" => "gpt-4o", "Enrich" => "claude-3-5-sonnet")
    end

    # A tile has room for one model. The one a workflow ran most is a better
    # answer than "and two others".
    it "names the model a workflow ran most where it ran more than one" do
      scout = trace("Scout")
      2.times { span(trace_id: scout.trace_id, model: "gpt-4o") }
      span(trace_id: scout.trace_id, model: "gpt-4o-mini")

      expect(described_class.models_by_workflow(timeframe: window)).to eq("Scout" => "gpt-4o")
    end

    # Absent rather than nil-valued: the tile prints its run count alone
    # rather than a slot reading "—".
    it "leaves out a workflow that recorded no model" do
      span(trace_id: trace("Scout").trace_id, model: nil)

      expect(described_class.models_by_workflow(timeframe: window)).to eq({})
    end

    it "reads only the window it was given" do
      scout = trace("Scout")
      span(trace_id: scout.trace_id, model: "gpt-4o", started_at: 5.hours.ago)

      expect(described_class.models_by_workflow(timeframe: window)).to eq({})
    end
  end
end
