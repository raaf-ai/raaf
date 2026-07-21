# frozen_string_literal: true

require "spec_helper"
require_relative "../../lib/raaf/active_record_processor"

# Pure-logic tests for token/model column extraction. No database or Rails
# runtime required — exercises the stateless class method directly.
RSpec.describe RAAF::Tracing::ActiveRecordProcessor, ".token_columns_from" do
  subject(:cols) { described_class.token_columns_from(attributes) }

  context "with a production agent span payload (top-level token keys)" do
    let(:attributes) do
      {
        "agent.model" => "gemini-2.5-flash",
        "agent.max_tokens" => "N/A",
        "input_tokens" => 2832,
        "output_tokens" => 1569,
        "total_tokens" => 5747
      }
    end

    it "maps tokens and model into native columns" do
      expect(cols).to eq(
        input_tokens: 2832,
        output_tokens: 1569,
        agent_model: "gemini-2.5-flash"
      )
    end
  end

  context "with an llm span payload (llm.usage.* keys)" do
    let(:attributes) do
      {
        "llm.request.model" => "gpt-4o",
        "llm.usage.prompt_tokens" => 10,
        "llm.usage.completion_tokens" => 20
      }
    end

    it "maps prompt/completion tokens and request model" do
      expect(cols).to eq(input_tokens: 10, output_tokens: 20, agent_model: "gpt-4o")
    end
  end

  context "with token usage nested under a usage hash" do
    let(:attributes) do
      { "model" => "claude-sonnet-5", "usage" => { "input_tokens" => 5, "output_tokens" => 7 } }
    end

    it "digs into the usage hash" do
      expect(cols).to eq(input_tokens: 5, output_tokens: 7, agent_model: "claude-sonnet-5")
    end
  end

  context "with symbol keys" do
    let(:attributes) { { input_tokens: 3, output_tokens: 4, "agent.model": "gemini-2.5-flash" } }

    it "tolerates symbol keys" do
      expect(cols).to eq(input_tokens: 3, output_tokens: 4, agent_model: "gemini-2.5-flash")
    end
  end

  context "when token/model data is absent" do
    let(:attributes) { { "component.type" => "job", "job.class" => "MonitoringCheckJob" } }

    it "returns an empty hash so nothing is clobbered on merge" do
      expect(cols).to eq({})
    end
  end

  context "with placeholder and non-numeric values" do
    let(:attributes) do
      { "agent.model" => "N/A", "input_tokens" => "N/A", "output_tokens" => "" }
    end

    it "rejects placeholders instead of writing junk" do
      expect(cols).to eq({})
    end
  end

  context "when attributes is nil" do
    let(:attributes) { nil }

    it "returns an empty hash" do
      expect(cols).to eq({})
    end
  end
end
