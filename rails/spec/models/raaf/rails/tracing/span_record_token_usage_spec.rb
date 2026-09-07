# frozen_string_literal: true

require "rails_helper"

RSpec.describe RAAF::Rails::Tracing::SpanRecord, type: :model do
  def span(kind: "agent", attributes: {}, **columns)
    described_class.new(name: "run.workflow.agent.Researcher.execute",
                        kind: kind,
                        span_attributes: attributes,
                        **columns)
  end

  describe "#token_usage" do
    # The tokens are on the agent span, under top-level keys. Readers that
    # went looking for a nested "usage" hash found nothing and reported an
    # empty token column over spans that had all recorded their usage.
    it "reads the top-level keys an agent span records" do
      record = span(attributes: { "agent.model" => "gemini-2.5-flash",
                                  "input_tokens" => 488,
                                  "output_tokens" => 70,
                                  "total_tokens" => 941 })

      expect(record.token_usage)
        .to eq(input: 488, output: 70, total: 941, model: "gemini-2.5-flash")
    end

    it "prefers the native columns when they have been filled" do
      record = span(input_tokens: 10, output_tokens: 5, total_tokens: 15, agent_model: "gpt-4o",
                    attributes: { "input_tokens" => 999 })

      expect(record.token_usage)
        .to eq(input: 10, output: 5, total: 15, model: "gpt-4o")
    end
  end

  describe "#total_token_count" do
    it "counts the reported total, not input plus output" do
      record = span(attributes: { "agent.model" => "gemini-2.5-flash",
                                  "input_tokens" => 488,
                                  "output_tokens" => 70,
                                  "total_tokens" => 941 })

      expect(record.total_token_count).to eq(941)
    end

    # An em dash, not a zero: nothing was recorded, so nothing is known.
    it "is nil for a span that recorded no usage" do
      expect(span(kind: "tool", attributes: { "function.name" => "search" }).total_token_count)
        .to be_nil
    end

    it "is nil for a span carrying only a configured token ceiling" do
      expect(span(attributes: { "agent.max_tokens" => "N/A" }).total_token_count).to be_nil
    end
  end

  describe "#cost_usd" do
    it "charges for tokens the provider billed but did not itemise" do
      record = span(attributes: { "agent.model" => "gemini-2.5-flash",
                                  "input_tokens" => 488,
                                  "output_tokens" => 70,
                                  "total_tokens" => 941 })

      # 488 input at $0.30/1M, and 941 - 488 = 453 billable output at $2.50/1M —
      # 453, not the 70 the provider itemised.
      expect(record.cost_usd).to be_within(0.000001).of(0.001279)
    end

    it "is nil when the model has no pricing entry" do
      record = span(attributes: { "agent.model" => "some-unlisted-model",
                                  "input_tokens" => 100,
                                  "output_tokens" => 40 })

      expect(record.cost_usd).to be_nil
    end
  end

  describe "#operation_details" do
    it "reports tokens for an agent span, which is where they are recorded" do
      record = span(attributes: { "agent.model" => "gpt-4o",
                                  "input_tokens" => 100,
                                  "output_tokens" => 40,
                                  "total_tokens" => 140 })

      expect(record.operation_details)
        .to include(model: "gpt-4o", input_tokens: 100, output_tokens: 40, total_tokens: 140)
    end
  end
end
