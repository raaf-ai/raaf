# frozen_string_literal: true

require "rails_helper"

# The registry groups in SQL; billing groups in Ruby. If the two disagree about
# a tool's name, a billed tool reports no spend.
RSpec.describe RAAF::Rails::Tracing::ToolSpans, type: :component do
  let(:trace) do
    RAAF::Rails::Tracing::TraceRecord.create!(
      trace_id: "trace_#{SecureRandom.hex(16)}", workflow_name: "Scout",
      status: "completed", started_at: 1.hour.ago
    )
  end

  def span(attributes)
    create_span(trace_id: trace.trace_id, name: "run.workflow.tool.Web.search",
                kind: "tool", status: "ok", start_time: 5.minutes.ago,
                end_time: 5.minutes.ago + 1, duration_ms: 900,
                span_attributes: attributes)
  end

  it "matches SQL-grouped names against Ruby-grouped billing" do
    span("function" => { "name" => "web_search" },
         "input_tokens" => 1000, "output_tokens" => 400, "agent.model" => "gpt-4o")

    relation = RAAF::Rails::Tracing::SpanRecord.includes(:trace)
                                               .where(kind: RAAF::Rails::Tracing::SpanRecord::TOOL_KINDS)
    screen = described_class.new(total_tool_spans: relation, params: {})
    cards = screen.send(:aggregates).map { |name, agg| screen.send(:card_for, name, agg) }

    expect(cards.first[:name]).to eq("web_search")
    expect(cards.first[:spend]).not_to be_nil
  end
end
