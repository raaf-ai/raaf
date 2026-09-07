# frozen_string_literal: true

require "rails_helper"

RSpec.describe RAAF::Rails::Tracing::SpanRecord, type: :model do
  describe ".agent_rollup" do
    let(:trace) do
      RAAF::Rails::Tracing::TraceRecord.create!(
        trace_id: "trace_#{SecureRandom.hex(16)}",
        workflow_name: "Fleet",
        status: "completed",
        started_at: 2.hours.ago
      )
    end

    # Usage goes in the attributes payload rather than the native columns, so
    # the rollup is exercised on the shape a database without the token
    # backfill actually holds.
    def span(name:, kind: "agent", status: "ok", duration_ms: 1000, parent_id: nil,
             model: nil, input: nil, output: nil, started_at: 1.hour.ago)
      usage = {}
      usage["agent.model"] = model if model
      usage["input_tokens"] = input if input
      usage["output_tokens"] = output if output

      described_class.create!(
        span_id: "span_#{SecureRandom.hex(12)}",
        trace_id: trace.trace_id,
        parent_id: parent_id,
        name: name,
        kind: kind,
        status: status,
        start_time: started_at,
        end_time: started_at + (duration_ms / 1000.0),
        duration_ms: duration_ms,
        span_attributes: usage
      )
    end

    it "returns one row per name and kind, busiest first" do
      2.times { span(name: "Scout") }
      3.times { span(name: "Enricher") }

      rows = described_class.agent_rollup

      expect(rows.map { |row| row.values_at(:name, :runs) })
        .to eq([["Enricher", 3], ["Scout", 2]])
    end

    it "keeps a pipeline apart from an agent of the same name" do
      span(name: "Scout", kind: "agent")
      span(name: "Scout", kind: "pipeline")

      expect(described_class.agent_rollup.map { |row| row[:kind] })
        .to contain_exactly("agent", "pipeline")
    end

    it "leaves out the spans that are not a unit of work somebody deploys" do
      span(name: "Scout", kind: "agent")
      span(name: "gpt-4o", kind: "llm")
      span(name: "web_search", kind: "tool")

      expect(described_class.agent_rollup.map { |row| row[:name] }).to eq(["Scout"])
    end

    it "reports the error rate over the agent's own runs" do
      3.times { span(name: "Scout") }
      span(name: "Scout", status: "error")

      row = described_class.agent_rollup.first

      expect(row).to include(errors: 1, runs: 4, error_rate: 25.0)
    end

    it "interpolates p95 across the run durations" do
      [100, 200, 300, 400, 500].each { |ms| span(name: "Scout", duration_ms: ms) }

      expect(described_class.agent_rollup.first[:p95_ms]).to eq(480.0)
    end

    it "reports the model most of the runs recorded" do
      2.times { span(name: "Scout", model: "gpt-4o", input: 10, output: 10) }
      span(name: "Scout", model: "gpt-4o-mini", input: 10, output: 10)
      span(name: "Scout")

      expect(described_class.agent_rollup.first[:model]).to eq("gpt-4o")
    end

    it "leaves the model unset when no run recorded one" do
      span(name: "Scout")

      expect(described_class.agent_rollup.first[:model]).to be_nil
    end

    context "with spend" do
      it "counts the agent span's own usage where it recorded any" do
        agent = span(name: "Scout", model: "gpt-4o", input: 1000, output: 1000)

        expect(described_class.agent_rollup.first[:spend])
          .to be_within(1e-9).of(agent.cost_usd.to_f)
      end

      # A DSL agent writes the same counts on the agent span that its llm
      # children carry, so the two must never be added together.
      it "does not add an LLM child's cost to a parent that recorded the same usage" do
        agent = span(name: "Scout", model: "gpt-4o", input: 1000, output: 1000)
        span(name: "gpt-4o", kind: "llm", parent_id: agent.span_id,
             model: "gpt-4o", input: 1000, output: 1000)

        expect(described_class.agent_rollup.first[:spend])
          .to be_within(1e-9).of(agent.cost_usd.to_f)
      end

      it "falls back to the LLM children of an agent span that recorded no usage" do
        agent = span(name: "Scout")
        child = span(name: "gpt-4o", kind: "llm", parent_id: agent.span_id,
                     model: "gpt-4o", input: 1000, output: 1000)

        expect(described_class.agent_rollup.first[:spend])
          .to be_within(1e-9).of(child.cost_usd.to_f)
      end

      it "reports zero rather than nil when nothing recorded a priced model" do
        span(name: "Scout")

        expect(described_class.agent_rollup.first[:spend]).to eq(0.0)
      end

      # Tokens follow the same one-or-the-other rule, so the Cost & usage
      # breakdown can be built straight off these rows.
      it "reports the tokens behind the spend" do
        agent = span(name: "Scout", model: "gpt-4o", input: 1000, output: 400)
        span(name: "gpt-4o", kind: "llm", parent_id: agent.span_id,
             model: "gpt-4o", input: 1000, output: 400)

        expect(described_class.agent_rollup.first[:tokens]).to eq(1400)
      end
    end

    it "counts only the runs inside the given window" do
      span(name: "Scout", started_at: 20.minutes.ago)
      span(name: "Scout", started_at: 3.days.ago)

      rows = described_class.agent_rollup(timeframe: 1.hour.ago..Time.current)

      expect(rows.first[:runs]).to eq(1)
    end

    it "is empty when nothing ran" do
      expect(described_class.agent_rollup).to eq([])
    end
  end
end
