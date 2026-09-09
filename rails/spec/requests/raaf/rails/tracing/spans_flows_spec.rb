# frozen_string_literal: true

require "rails_helper"

# Pipeline heat used to rank nodes by the sum of their spans' durations and
# call the result a share. The sum overstates a run that fans out -- parallel
# spans each contribute in full -- and double counts a nested span, once on
# itself and again inside its parent.
RSpec.describe "flow data measures elapsed time", type: :request do
  let(:trace) do
    RAAF::Rails::Tracing::TraceRecord.create!(
      trace_id: "trace_#{SecureRandom.hex(16)}",
      workflow_name: "FlowsSpec",
      status: "completed",
      started_at: 1.hour.ago
    )
  end

  let(:origin) { 30.minutes.ago.change(usec: 0) }

  def span(kind:, name:, from:, to:, attributes: {}, parent: nil)
    RAAF::Rails::Tracing::SpanRecord.create!(
      span_id: "span_#{SecureRandom.hex(12)}",
      trace_id: trace.trace_id,
      parent_id: parent,
      name: name,
      kind: kind,
      status: "ok",
      start_time: origin + from,
      end_time: origin + to,
      duration_ms: (to - from) * 1000,
      span_attributes: attributes
    )
  end

  def node_named(name)
    get flows_tracing_spans_path(format: :json)
    response.parsed_body["nodes"].find { |node| node["name"] == name }
  end

  # Four seconds of work over two workers, both between second 0 and second 3.
  it "counts a stretch two parallel spans share once" do
    2.times do |index|
      span(kind: "agent", name: "agent.Scout", from: index, to: index + 2,
           attributes: { "agent" => { "name" => "Scout" } })
    end

    scout = node_named("Scout")

    expect(scout["total_duration"].to_f).to eq(4000.0)
    expect(scout["busy_duration"]).to eq(3000.0)
  end

  # The agent ran for ten seconds and called one tool inside them. Elapsed time
  # is ten seconds, which the summed fourteen is not.
  it "counts a nested span inside its parent only once toward the window" do
    parent = span(kind: "agent", name: "agent.Scout", from: 0, to: 10,
                  attributes: { "agent" => { "name" => "Scout" } })
    span(kind: "tool", name: "search", from: 2, to: 6, parent: parent.span_id,
         attributes: { "function" => { "name" => "search" } })

    get flows_tracing_spans_path(format: :json)
    stats = response.parsed_body["stats"]

    expect(response.parsed_body["nodes"].sum { |node| node["total_duration"].to_f }).to eq(14_000.0)
    expect(stats["busy_duration"]).to eq(10_000.0)
  end

  # Each node's own busy time still stands on its own: the tool was running for
  # four of the ten seconds, whoever else was running at the time.
  it "reports each node's own running time" do
    parent = span(kind: "agent", name: "agent.Scout", from: 0, to: 10,
                  attributes: { "agent" => { "name" => "Scout" } })
    span(kind: "tool", name: "search", from: 2, to: 6, parent: parent.span_id,
         attributes: { "function" => { "name" => "search" } })

    expect(node_named("search")["busy_duration"]).to eq(4000.0)
    expect(node_named("Scout")["busy_duration"]).to eq(10_000.0)
  end

  it "measures nothing over a window that holds no spans" do
    get flows_tracing_spans_path(format: :json)

    expect(response.parsed_body["stats"]["busy_duration"]).to eq(0.0)
  end
end
