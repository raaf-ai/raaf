# frozen_string_literal: true

require "rails_helper"

# Every other screen in the console reads a span's tokens through SpanUsage,
# which knows the other key shapes and the native columns. The replay
# comparison read `llm.usage` and `usage` alone, so a DSL agent span — which
# records its counts elsewhere — showed both token tiles at 0 with a note of
# "was 0".
RSpec.describe RAAF::Rails::Tracing::Replay::ShowComponent, type: :component do
  let(:trace) do
    RAAF::Rails::Tracing::TraceRecord.create!(
      trace_id: "trace_#{SecureRandom.hex(16)}", workflow_name: "Scout",
      status: "completed", started_at: 1.hour.ago
    )
  end

  def span(attributes)
    create_span(
      trace_id: trace.trace_id, name: "Scout", kind: "agent", status: "ok",
      start_time: 10.minutes.ago, end_time: 10.minutes.ago + 1, duration_ms: 1000,
      span_attributes: attributes
    )
  end

  def screen(original, replayed)
    replay = instance_double(RAAF::Rails::Tracing::SpanReplay, replayed_span: replayed)
    described_class.new(replay: replay, original_span: original)
  end

  # The shape a DSL agent writes, which the old reader missed entirely.
  let(:dsl_agent_span) { span("input_tokens" => 1200, "output_tokens" => 340, "agent.model" => "gpt-4o") }

  # The shape the old reader did understand, kept so the change is a widening
  # rather than a swap.
  let(:llm_span) { span("llm" => { "usage" => { "input_tokens" => 90, "output_tokens" => 20 } }) }

  it "reads the tokens a DSL agent span recorded" do
    usage = screen(llm_span, dsl_agent_span).send(:usage, dsl_agent_span)

    expect(usage).to eq(input_tokens: 1200, output_tokens: 340)
  end

  it "still reads the llm.usage shape it always read" do
    usage = screen(llm_span, dsl_agent_span).send(:usage, llm_span)

    expect(usage).to eq(input_tokens: 90, output_tokens: 20)
  end

  describe "the cost tile" do
    # Whether the cheaper model was in fact cheaper is usually why the replay
    # was run, and the comparison reported duration, tokens and model without
    # ever saying so.
    it "reports what the replayed span was billed" do
      tile = screen(llm_span, dsl_agent_span).send(:cost_metric)

      expect(tile[:label]).to eq("Cost")
      expect(tile[:value]).to match(/\A\$\d+\.\d{4}\z/)
    end

    # Cheaper is the good direction, which is the opposite of every other
    # delta on the screen.
    it "reads a cheaper replay as the good direction" do
      expensive = span("input_tokens" => 100_000, "output_tokens" => 50_000, "agent.model" => "gpt-4o")
      cheap = span("input_tokens" => 100, "output_tokens" => 50, "agent.model" => "gpt-4o")

      expect(screen(expensive, cheap).send(:cost_metric)).to include(tone: :success)
      expect(screen(cheap, expensive).send(:cost_metric)).to include(tone: :warning)
    end
  end
end
