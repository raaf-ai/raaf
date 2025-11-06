#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "raaf/eval/rspec"

# Example: Simple Evaluation Test
#
# This example shows how to write a basic evaluation test that checks
# if an agent maintains quality when changing the temperature parameter.

RSpec.describe "SearchAgent Simple Evaluation", :evaluation do
  # Configure RSpec to include RAAF Eval helpers
  include RAAF::Eval::RSpec

  # Create a baseline span for testing
  let(:baseline_span) do
    {
      id: "span_123",
      agent_name: "SearchAgent",
      output: "Ruby is a dynamic, object-oriented programming language focused on simplicity and productivity.",
      usage: { input_tokens: 50, output_tokens: 20 },
      latency_ms: 250,
      metadata: {
        model: "gpt-4o",
        temperature: 0.7,
        instructions: "Provide concise information about programming languages.",
        messages: [
          { role: "user", content: "Tell me about Ruby programming language" }
        ]
      }
    }
  end

  before do
    # Store the baseline span in the repository
    RAAF::Eval::SpanRepository.store("span_123", baseline_span)
  end

  after do
    # Clean up
    RAAF::Eval::SpanRepository.clear!
  end

  it "maintains quality with higher temperature" do
    # Evaluate the span with modified temperature
    result = evaluate_span("span_123")
      .with_configuration(temperature: 0.9)
      .run

    # Assert quality is maintained
    expect(result).to maintain_quality.within(30).percent

    # Assert token usage is reasonable
    expect(result).to use_tokens.within(20).percent_of(:baseline)
  end

  it "maintains quality with lower temperature" do
    result = evaluate_span("span_123")
      .with_configuration(temperature: 0.3)
      .run

    expect(result).to maintain_quality
    expect(result).to have_similar_output_to(:baseline)
  end
end

# Run the example
if __FILE__ == $PROGRAM_NAME
  require "rspec/autorun"
end
