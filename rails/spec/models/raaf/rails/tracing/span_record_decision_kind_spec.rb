# frozen_string_literal: true

require "rails_helper"

# A decision model call is recorded as its own span kind. Before the kind was
# listed here, a decision span written through this model was rejected as
# invalid, and the Tools screen - where a call an agent makes to something
# outside itself belongs - did not count it.
RSpec.describe RAAF::Rails::Tracing::SpanRecord, "decision spans", type: :model do
  def decision_span(attributes: {})
    described_class.new(name: "run.workflow.decision.~typesafe/jev-latest.decide",
                        kind: "decision",
                        trace_id: "trace_#{SecureRandom.hex(16)}",
                        span_attributes: attributes)
  end

  it "accepts the kind a decision call records" do
    expect(decision_span).to be_valid
  end

  it "counts as a call made to something outside the agent" do
    expect(described_class::TOOL_KINDS).to include("decision")
  end

  it "is not counted as an agent, which is a thing somebody deploys and watches" do
    expect(described_class::AGENT_KINDS).not_to include("decision")
  end

  # The provider reports the exact cost of the call, and no token price table
  # has an entry for a decision model.
  it "is billed by the fee it reports rather than by its tokens" do
    record = decision_span(attributes: { "decision.cost_cents" => "0.0028",
                                         "decision.tokens.input" => "663" })

    expect(RAAF::Tracing::SpanUsage.billing_mode(record)).to eq(:cost)
    expect(RAAF::Tracing::SpanUsage.fee_for_span(record)).to be_within(1e-9).of(0.000_028)
  end

  it "still reports the tokens it recorded, for size rather than for price" do
    record = decision_span(attributes: { "decision.tokens.input" => "663",
                                         "decision.tokens.output" => "93",
                                         "decision.result.model" => "typesafe/jev-1.13-20260917" })

    expect(record.token_usage).to include(input: 663, output: 93, model: "typesafe/jev-1.13-20260917")
  end
end
