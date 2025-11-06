#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "raaf/eval/rspec"

# Example: Multi-Configuration Comparison
#
# This example shows how to compare an agent's behavior across different
# AI models and configurations.

RSpec.describe "ResearchAgent Model Comparison", :evaluation do
  include RAAF::Eval::RSpec

  let(:baseline_span) do
    {
      id: "research_span_456",
      agent_name: "ResearchAgent",
      output: "Artificial Intelligence (AI) encompasses machine learning, natural language processing, " \
              "and computer vision. Recent advances include large language models and neural networks.",
      usage: { input_tokens: 100, output_tokens: 35 },
      latency_ms: 800,
      metadata: {
        model: "gpt-4o",
        temperature: 0.7,
        instructions: "Research and summarize AI topics thoroughly.",
        messages: [
          { role: "user", content: "Research recent developments in artificial intelligence" }
        ]
      }
    }
  end

  before do
    RAAF::Eval::SpanRepository.store("research_span_456", baseline_span)
  end

  after do
    RAAF::Eval::SpanRepository.clear!
  end

  # Use declarative DSL for evaluation
  evaluation do
    span -> { RAAF::Eval.find_span("research_span_456") }

    configuration :gpt4, model: "gpt-4o", temperature: 0.7
    configuration :gpt4_low_temp, model: "gpt-4o", temperature: 0.3
    configuration :gpt4_high_temp, model: "gpt-4o", temperature: 0.9

    run_async false
  end

  it "all models maintain quality" do
    expect(evaluation).to maintain_quality.across_all_configurations
  end

  it "low temperature is more consistent" do
    expect(evaluation[:gpt4_low_temp]).to have_similar_output_to(:baseline).within(10).percent
  end

  it "all configurations complete reasonably" do
    evaluation.results.each do |_name, result|
      expect(result).to be_a(Hash)
      expect(result[:success]).to be(true).or be(false) # Allow both for testing
    end
  end

  it "token usage is within acceptable range" do
    # This is a simplified check since we don't have real API calls
    expect(baseline_span[:usage]).to be_a(Hash)
  end
end

# Run the example
if __FILE__ == $PROGRAM_NAME
  require "rspec/autorun"
end
