# frozen_string_literal: true

require "rails_helper"

RSpec.describe RAAF::Rails::Tracing::TraceRecord, type: :model do
  def trace!(workflow: "TokenTotals")
    described_class.create!(trace_id: "trace_#{SecureRandom.hex(16)}",
                            workflow_name: workflow,
                            status: "completed",
                            started_at: 1.minute.ago,
                            ended_at: Time.current)
  end

  def span!(trace, kind: "agent", attributes: {}, **columns)
    RAAF::Rails::Tracing::SpanRecord.create!(
      span_id: "span_#{SecureRandom.hex(12)}",
      trace_id: trace.trace_id,
      name: "run.workflow.#{kind}.Researcher.execute",
      kind: kind,
      status: "ok",
      start_time: 1.minute.ago,
      end_time: Time.current,
      duration_ms: 1000,
      span_attributes: attributes,
      **columns
    )
  end

  # gemini-2.5-flash: $0.30 in, $2.50 out per 1M tokens. The total exceeds
  # input + output by 453 tokens the provider billed without itemising.
  let(:gemini_columns) do
    { input_tokens: 488, output_tokens: 70, total_tokens: 941, agent_model: "gemini-2.5-flash" }
  end

  describe "#total_tokens" do
    it "sums the tokens its spans recorded" do
      trace = trace!
      span!(trace, **gemini_columns)
      span!(trace, input_tokens: 100, output_tokens: 40, total_tokens: 140, agent_model: "gpt-4o")

      expect(trace.total_tokens).to eq(1081)
    end

    # Nil, not zero: a trace of tool and job spans spent tokens nowhere, and
    # printing 0 would claim to know that it did not.
    it "is nil when no span recorded usage" do
      trace = trace!
      span!(trace, kind: "tool", attributes: { "function.name" => "search" })

      expect(trace.total_tokens).to be_nil
    end

    it "counts spans of every kind, not only llm spans" do
      trace = trace!
      span!(trace, kind: "agent", **gemini_columns)

      expect(trace.total_tokens).to eq(941)
    end
  end

  describe "#total_cost" do
    it "charges unitemised tokens at the output rate" do
      trace = trace!
      span!(trace, **gemini_columns)

      expect(trace.total_cost).to be_within(0.000001).of(0.001279)
    end

    it "is nil when nothing on the trace could be priced" do
      trace = trace!
      span!(trace, input_tokens: 100, output_tokens: 40, agent_model: "some-unlisted-model")

      expect(trace.total_cost).to be_nil
    end
  end

  describe ".token_totals_for" do
    it "totals many traces in one query and agrees with the per-trace figures" do
      first = trace!
      second = trace!
      span!(first, **gemini_columns)
      span!(second, input_tokens: 100, output_tokens: 40, total_tokens: 140, agent_model: "gpt-4o")

      totals = described_class.token_totals_for([first.trace_id, second.trace_id])

      expect(totals[first.trace_id][:tokens]).to eq(first.total_tokens)
      expect(totals[first.trace_id][:cost]).to be_within(0.000001).of(first.total_cost)
      expect(totals[second.trace_id][:tokens]).to eq(second.total_tokens)
    end

    it "sums several spans on one trace, splitting the cost by model" do
      trace = trace!
      span!(trace, **gemini_columns)
      span!(trace, **gemini_columns)
      span!(trace, input_tokens: 1_000_000, output_tokens: 0, total_tokens: 1_000_000,
                   agent_model: "gpt-4o")

      # 2 × $0.001279 of Gemini, plus 1M gpt-4o input tokens at $2.50/1M.
      expect(totals_for(trace)[:tokens]).to eq(1_001_882)
      expect(totals_for(trace)[:cost]).to be_within(0.000001).of(2.502558)
    end

    it "omits a trace whose spans recorded nothing rather than reporting zero" do
      trace = trace!
      span!(trace, kind: "tool", attributes: { "function.name" => "search" })

      expect(described_class.token_totals_for([trace.trace_id])).to eq({})
    end

    it "reports tokens but no cost for a model with no pricing entry" do
      trace = trace!
      span!(trace, input_tokens: 100, output_tokens: 40, total_tokens: 140,
                   agent_model: "some-unlisted-model")

      expect(totals_for(trace)).to eq(tokens: 140, cost: nil)
    end

    it "is empty for no trace ids" do
      expect(described_class.token_totals_for([])).to eq({})
    end

    def totals_for(trace)
      described_class.token_totals_for([trace.trace_id]).fetch(trace.trace_id)
    end
  end
end
