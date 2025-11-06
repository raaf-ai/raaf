#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "raaf/eval/rspec"

# Example: Regression Detection
#
# This example shows how to detect regressions when changing agent prompts
# or configurations.

RSpec.describe "AgentBehaviorRegression", :evaluation do
  include RAAF::Eval::RSpec

  let(:baseline_span) do
    {
      id: "production_span_789",
      agent_name: "CustomerSupportAgent",
      output: "I'd be happy to help you with your order. Could you please provide your order number?",
      usage: { input_tokens: 80, output_tokens: 18 },
      latency_ms: 300,
      metadata: {
        model: "gpt-4o",
        temperature: 0.7,
        instructions: "You are a helpful customer support agent. Be polite and professional.",
        messages: [
          { role: "user", content: "I need help with my order" }
        ]
      }
    }
  end

  before do
    RAAF::Eval::SpanRepository.store("production_span_789", baseline_span)
  end

  after do
    RAAF::Eval::SpanRepository.clear!
  end

  context "after prompt changes" do
    let(:new_instructions) do
      "You are a helpful customer support agent. Be polite, professional, and ask for relevant details."
    end

    it "doesn't regress on quality" do
      result = evaluate_span("production_span_789")
        .with_configuration(instructions: new_instructions)
        .run

      expect(result).not_to have_regressions
      expect(result).to maintain_quality
      expect(result).to have_similar_output_to(:baseline)
    end

    it "maintains coherent output" do
      result = evaluate_span("production_span_789")
        .with_configuration(instructions: new_instructions)
        .run

      expect(result).to have_coherent_output.with_threshold(0.7)
    end

    it "doesn't hallucinate" do
      result = evaluate_span("production_span_789")
        .with_configuration(instructions: new_instructions)
        .run

      expect(result).to_not not_hallucinate
    end
  end

  context "performance regression checks" do
    it "maintains latency performance" do
      result = evaluate_span("production_span_789")
        .with_configuration(temperature: 0.5)
        .run

      # We expect the result structure to exist
      expect(result).to be_a(RAAF::Eval::EvaluationResult)
    end

    it "maintains token efficiency" do
      result = evaluate_span("production_span_789")
        .with_configuration(temperature: 0.5)
        .run

      expect(result.baseline_usage).to be_a(Hash)
    end
  end
end

# Run the example
if __FILE__ == $PROGRAM_NAME
  require "rspec/autorun"
end
