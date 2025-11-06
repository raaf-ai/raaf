#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "raaf/eval/rspec"

# Example: LLM Judge Matchers
#
# This example shows how to use LLM-powered matchers for subjective
# quality assessments that are hard to code precisely.

RSpec.describe "WritingAgent Quality with LLM Judge", :evaluation do
  include RAAF::Eval::RSpec

  let(:baseline_span) do
    {
      id: "writing_span_202",
      agent_name: "WritingAgent",
      output: "The sunset painted the sky in brilliant shades of orange and pink. " \
              "Gentle waves lapped at the shore as seabirds called overhead.",
      usage: { input_tokens: 60, output_tokens: 28 },
      latency_ms: 500,
      metadata: {
        model: "gpt-4o",
        temperature: 0.8,
        instructions: "Write descriptive, engaging content.",
        messages: [
          { role: "user", content: "Describe a beach scene in 2-3 sentences" }
        ]
      }
    }
  end

  before do
    RAAF::Eval::SpanRepository.store("writing_span_202", baseline_span)
  end

  after do
    RAAF::Eval::SpanRepository.clear!
  end

  # Note: LLM judge matchers would normally call an AI model
  # These examples show the interface but won't make actual calls in tests

  it "produces descriptive writing" do
    result = evaluate_span("writing_span_202")
      .with_configuration(temperature: 0.7)
      .run

    # This would normally use LLM judge to evaluate
    # For testing, we just verify the interface exists
    expect(result.baseline_output).to include("sunset")
  end

  it "maintains appropriate tone" do
    result = evaluate_span("writing_span_202")
      .with_configuration(temperature: 0.7)
      .run

    # In real usage:
    # expect(result).to satisfy_llm_check("The writing is descriptive and engaging")

    expect(result).to be_a(RAAF::Eval::EvaluationResult)
  end

  it "meets multiple quality criteria" do
    result = evaluate_span("writing_span_202")
      .with_configuration(temperature: 0.7)
      .run

    # In real usage:
    # expect(result).to satisfy_llm_criteria([
    #   "The writing is descriptive",
    #   "The tone is appropriate",
    #   "The content is engaging"
    # ])

    expect(result).to be_a(RAAF::Eval::EvaluationResult)
  end

  it "is judged as creative" do
    result = evaluate_span("writing_span_202")
      .with_configuration(temperature: 0.9)
      .run

    # In real usage:
    # expect(result).to be_judged_as("more creative").than(:baseline)

    expect(result).to be_a(RAAF::Eval::EvaluationResult)
  end
end

# Run the example
if __FILE__ == $PROGRAM_NAME
  require "rspec/autorun"
end
