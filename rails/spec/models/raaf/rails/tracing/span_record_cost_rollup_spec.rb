# frozen_string_literal: true

require "rails_helper"

RSpec.describe RAAF::Rails::Tracing::SpanRecord, type: :model do
  describe ".cost_rollup" do
    let(:trace) do
      RAAF::Rails::Tracing::TraceRecord.create!(
        trace_id: "trace_#{SecureRandom.hex(16)}",
        workflow_name: "Fleet",
        status: "completed",
        started_at: 2.hours.ago
      )
    end

    # A run of its own, so the preceding window counts a run rather than
    # sharing this window's trace and reporting the same one twice.
    let(:earlier_trace) do
      RAAF::Rails::Tracing::TraceRecord.create!(
        trace_id: "trace_#{SecureRandom.hex(16)}",
        workflow_name: "Fleet",
        status: "completed",
        started_at: 3.hours.ago
      )
    end

    def span(name:, kind: "agent", parent_id: nil, model: nil, input: nil, output: nil,
             started_at: 10.minutes.ago, trace_id: nil, attributes: {})
      usage = {}
      usage["agent.model"] = model if model
      usage["input_tokens"] = input if input
      usage["output_tokens"] = output if output
      usage.merge!(attributes.transform_keys(&:to_s))

      create_span(
        trace_id: trace_id || trace.trace_id,
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

    it "totals the tokens the window recorded" do
      span(name: "Scout", model: "gpt-4o", input: 1000, output: 400)
      span(name: "Enricher", model: "gpt-4o-mini", input: 600, output: 200)

      rollup = described_class.cost_rollup(timeframe: window)

      expect(rollup).to include(input_tokens: 1600, output_tokens: 600, total_tokens: 2200)
    end

    # An agent span and its LLM children routinely carry the same counts.
    it "does not count an LLM child whose parent already recorded the usage" do
      agent = span(name: "Scout", model: "gpt-4o", input: 1000, output: 400)
      span(name: "gpt-4o", kind: "llm", parent_id: agent.span_id,
           model: "gpt-4o", input: 1000, output: 400)

      expect(described_class.cost_rollup(timeframe: window)[:total_tokens]).to eq(1400)
    end

    it "counts the LLM children of an agent span that recorded nothing itself" do
      agent = span(name: "Scout")
      span(name: "gpt-4o", kind: "llm", parent_id: agent.span_id,
           model: "gpt-4o", input: 1000, output: 400)

      expect(described_class.cost_rollup(timeframe: window)[:total_tokens]).to eq(1400)
    end

    # The whole point of billing both screens from one rule.
    it "totals to what the Agents screen bills for the same window" do
      agent = span(name: "Scout", model: "gpt-4o", input: 1000, output: 400)
      span(name: "gpt-4o", kind: "llm", parent_id: agent.span_id,
           model: "gpt-4o", input: 1000, output: 400)
      other = span(name: "Enricher")
      span(name: "gpt-4o-mini", kind: "llm", parent_id: other.span_id,
           model: "gpt-4o-mini", input: 600, output: 200)

      rollup = described_class.cost_rollup(timeframe: window)
      agents = described_class.agent_rollup(timeframe: window)

      expect(rollup[:total_cost]).to be_within(1e-6).of(agents.sum { |row| row[:spend] })
      expect(rollup[:total_tokens]).to eq(agents.sum { |row| row[:tokens] })
    end

    it "counts one run per trace that cost something" do
      other = RAAF::Rails::Tracing::TraceRecord.create!(
        trace_id: "trace_#{SecureRandom.hex(16)}", workflow_name: "Fleet",
        status: "completed", started_at: 2.hours.ago
      )
      span(name: "Scout", model: "gpt-4o", input: 100, output: 100)
      span(name: "Scout", model: "gpt-4o", input: 100, output: 100)
      span(name: "Scout", model: "gpt-4o", input: 100, output: 100, trace_id: other.trace_id)

      expect(described_class.cost_rollup(timeframe: window)[:runs]).to eq(2)
    end

    describe "the model breakdown" do
      it "groups spend and tokens by model, dearest first" do
        span(name: "Scout", model: "gpt-4o", input: 100_000, output: 100_000)
        span(name: "Enricher", model: "gpt-4o-mini", input: 1000, output: 1000)

        rows = described_class.cost_rollup(timeframe: window)[:by_model]

        expect(rows.map { |row| row[:name] }).to eq(%w[gpt-4o gpt-4o-mini])
        expect(rows.first[:tokens]).to eq(200_000)
      end

      it "leaves out the spans that never named a model" do
        span(name: "Scout", input: 100, output: 100)

        expect(described_class.cost_rollup(timeframe: window)[:by_model]).to eq([])
      end

      it "keeps only as many rows as asked for" do
        %w[a b c].each_with_index do |model, index|
          span(name: "Scout", model: model, input: (index + 1) * 1000, output: 100)
        end

        expect(described_class.cost_rollup(timeframe: window, top: 2)[:by_model].size).to eq(2)
      end
    end

    describe "the agent breakdown" do
      it "reuses the Agents rollup, ordered by spend" do
        span(name: "Cheap", model: "gpt-4o-mini", input: 1000, output: 1000)
        span(name: "Dear", model: "gpt-4o", input: 100_000, output: 100_000)

        rows = described_class.cost_rollup(timeframe: window)[:by_agent]

        expect(rows.map { |row| row[:name] }).to eq(%w[Dear Cheap])
      end

      it "leaves out an agent that cost nothing and used nothing" do
        span(name: "Free")
        span(name: "Dear", model: "gpt-4o", input: 1000, output: 1000)

        expect(described_class.cost_rollup(timeframe: window)[:by_agent].map { |row| row[:name] })
          .to eq(["Dear"])
      end
    end

    # A search provider charges per query and reports no tokens. Priced off a
    # token count it billed as free, so this screen presented a total with an
    # entire class of spend missing from it.
    describe "spend charged per call rather than per token" do
      def search(parent_id: nil, cents: 0.5, provider: "scraping_bee", **rest)
        span(name: "Ai::SearchProviders::ScrapingBee", kind: "component", parent_id: parent_id,
             attributes: { "component.type" => "search", "provider" => provider,
                           "cost_cents" => cents },
             **rest)
      end

      it "adds a search fee to the window's total" do
        search
        search(cents: 1)

        expect(described_class.cost_rollup(timeframe: window)[:total_cost])
          .to be_within(1e-9).of(0.015)
      end

      it "counts a trace whose only spend was search" do
        search

        expect(described_class.cost_rollup(timeframe: window)[:runs]).to eq(1)
      end

      # The de-duplication exists because an agent copies its LLM children's
      # token counts onto itself. Nothing copies a fee, so dropping it for
      # having an agent parent would delete the charge outright.
      it "keeps a search fee whose parent is an agent" do
        agent = span(name: "Scout", model: "gpt-4o", input: 1000, output: 400)
        search(parent_id: agent.span_id)

        rollup = described_class.cost_rollup(timeframe: window)

        expect(rollup[:total_cost]).to be > agent.reload.cost_usd
      end

      it "still totals to what the Agents screen bills" do
        agent = span(name: "Scout", model: "gpt-4o", input: 1000, output: 400)
        search(parent_id: agent.span_id)

        rollup = described_class.cost_rollup(timeframe: window)
        agents = described_class.agent_rollup(timeframe: window)

        expect(rollup[:total_cost]).to be_within(1e-6).of(agents.sum { |row| row[:spend] })
      end

      # A per-call span has no model to group by, and a row named nothing is
      # dropped from the breakdown — so the fee would vanish from the panel
      # while still counting toward the total above it.
      it "files the fee under the provider that charged it" do
        search

        rows = described_class.cost_rollup(timeframe: window)[:by_model]

        expect(rows.map { |row| row[:name] }).to eq(["scraping_bee"])
        expect(rows.first[:cost]).to be_within(1e-9).of(0.005)
      end

      it "contributes no tokens" do
        search

        expect(described_class.cost_rollup(timeframe: window)[:total_tokens]).to eq(0)
      end
    end

    # A job brackets a run rather than buying anything. Its children each
    # report their own spend, so billing the job as well counts it twice.
    it "charges nothing for a job span, even carrying its children's counts" do
      span(name: "ServiceExecutionJob", kind: "job", model: "gpt-4o", input: 1000, output: 400)

      expect(described_class.cost_rollup(timeframe: window))
        .to include(total_cost: 0.0, total_tokens: 0, runs: 0, by_model: [])
    end

    it "counts only the spans inside the window" do
      span(name: "Scout", model: "gpt-4o", input: 1000, output: 1000, started_at: 3.days.ago)

      expect(described_class.cost_rollup(timeframe: window)).to include(total_tokens: 0, runs: 0)
    end

    it "is all zeroes when nothing ran" do
      rollup = described_class.cost_rollup(timeframe: window)

      expect(rollup).to include(total_cost: 0.0, total_tokens: 0, runs: 0,
                                by_model: [], by_agent: [])
    end

    # What the KPI deltas are measured against.
    describe "the preceding window" do
      it "totals the same length of time immediately before the window" do
        span(name: "Scout", model: "gpt-4o", input: 1000, output: 400,
             started_at: 90.minutes.ago, trace_id: earlier_trace.trace_id)

        preceding = described_class.cost_rollup(timeframe: window)[:preceding]

        expect(preceding[:runs]).to eq(1)
        expect(preceding[:total_cost]).to be > 0
      end

      it "leaves out what the window itself billed" do
        span(name: "Scout", model: "gpt-4o", input: 1000, output: 400)

        rollup = described_class.cost_rollup(timeframe: window)

        expect(rollup[:total_cost]).to be > 0
        expect(rollup[:preceding]).to be_nil
      end

      it "reaches back no further than one window" do
        span(name: "Scout", model: "gpt-4o", input: 1000, output: 400,
             started_at: 5.hours.ago, trace_id: earlier_trace.trace_id)

        expect(described_class.cost_rollup(timeframe: window)[:preceding]).to be_nil
      end

      # A first window of traffic is not "up 100%": there is nothing to
      # compare it with, and the screen says so by showing no delta at all.
      it "is nil when the preceding window billed nothing" do
        expect(described_class.cost_rollup(timeframe: window)[:preceding]).to be_nil
      end

      it "is nil without a window to precede" do
        span(name: "Scout", model: "gpt-4o", input: 1000, output: 400)

        expect(described_class.cost_rollup[:preceding]).to be_nil
      end
    end
  end
end
