# frozen_string_literal: true

require "rails_helper"

# The screen's own docstring says it answers "which tool is costing us", and
# each card gave calls, an error rate and a p95 — three measures of activity
# and none of money, though tool spans are what the cost rollup bills.
RSpec.describe RAAF::Rails::Tracing::ToolSpans, type: :component do
  let(:trace) do
    RAAF::Rails::Tracing::TraceRecord.create!(
      trace_id: "trace_#{SecureRandom.hex(16)}", workflow_name: "Scout",
      status: "completed", started_at: 1.hour.ago
    )
  end

  def tool_span(name: "web_search", input: nil, output: nil, model: nil, fee_cents: nil)
    attributes = { "function" => { "name" => name } }
    attributes["input_tokens"] = input if input
    attributes["output_tokens"] = output if output
    attributes["agent.model"] = model if model

    create_span(
      trace_id: trace.trace_id,
      name: "tool.#{name}", kind: "tool", status: "ok",
      start_time: 10.minutes.ago, end_time: 10.minutes.ago + 1, duration_ms: 900,
      span_attributes: attributes
    ).tap do |span|
      span.update_columns(call_fee_cents: fee_cents) if fee_cents
    end
  end

  def cards(spans)
    screen = described_class.new(total_tool_spans: spans, params: {})

    screen.send(:aggregates).map { |name, agg| screen.send(:card_for, name, agg) }
  end

  it "bills a tool for the tokens its calls recorded" do
    card = cards([tool_span(input: 1000, output: 400, model: "gpt-4o")]).first

    expect(card[:tokens]).to eq("1.4k")
    expect(card[:spend]).to eq("$0.0065")
  end

  # Two decimals would round a real bill away to nothing: a single tool call
  # is routinely worth a fraction of a cent.
  it "keeps a sub-cent bill readable, and rounds a larger one to cents" do
    small = cards([tool_span(input: 10, output: 5, model: "gpt-4o")]).first
    large = cards([tool_span(input: 4_000_000, output: 1_000_000, model: "gpt-4o")]).first

    expect(small[:spend]).to match(/\A\$0\.\d{4}\z/)
    expect(large[:spend]).to match(/\A\$\d+\.\d{2}\z/)
  end

  # A tool nothing ever billed is not a free tool, it is an unmeasured one.
  it "reports no spend for a tool that was never billed" do
    card = cards([tool_span]).first

    expect(card[:spend]).to be_nil
    expect(card[:tokens]).to be_nil
  end

  it "keeps the activity figures it always had" do
    card = cards([tool_span(input: 10, output: 5, model: "gpt-4o")]).first

    expect(card).to include(calls: "1", error_rate: "0.0%")
  end
end
