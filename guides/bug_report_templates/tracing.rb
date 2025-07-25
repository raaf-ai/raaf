# frozen_string_literal: true

require "bundler/inline"

gemfile(true) do
  source "https://rubygems.org"

  gem "raaf"
  gem "rspec"
  # If you want to test against edge RAAF replace the raaf line with this:
  # gem "raaf", github: "enterprisemodules/raaf", branch: "main"
end

require "raaf"
require "rspec/autorun"

RSpec.describe "RAAF Tracing Bug Report" do
  it "creates span tracer successfully" do
    tracer = RAAF::Tracing::SpanTracer.new
    
    expect(tracer).to be_a(RAAF::Tracing::SpanTracer)
  end

  it "configures console processor" do
    processor = RAAF::Tracing::ConsoleProcessor.new(
      log_level: :debug,
      include_payloads: true
    )
    
    tracer = RAAF::Tracing::SpanTracer.new
    tracer.add_processor(processor)
    
    expect(processor).to be_a(RAAF::Tracing::ConsoleProcessor)
  end

  it "configures OpenAI processor" do
    processor = RAAF::Tracing::OpenAIProcessor.new(
      api_key: "test-key",
      project_id: "test-project"
    )
    
    tracer = RAAF::Tracing::SpanTracer.new  
    tracer.add_processor(processor)
    
    expect(processor).to be_a(RAAF::Tracing::OpenAIProcessor)
  end

  it "integrates tracing with agent runner" do
    tracer = RAAF::Tracing::SpanTracer.new
    tracer.add_processor(RAAF::Tracing::ConsoleProcessor.new)
    
    agent = RAAF::Agent.new(
      name: "TracedAgent",
      instructions: "You are being traced",
      model: "gpt-4o-mini"
    )
    
    runner = RAAF::Runner.new(
      agent: agent,
      tracer: tracer
    )
    
    # Test that tracer is properly attached
    expect(tracer).to be_a(RAAF::Tracing::SpanTracer)
    expect(runner).to be_a(RAAF::Runner)
  end

  it "tracks costs accurately" do
    cost_tracker = RAAF::Tracing::CostTracker.new(
      pricing: {
        'gpt-4o' => { input: 5.00, output: 15.00 },
        'gpt-4o-mini' => { input: 0.15, output: 0.60 }
      }
    )
    
    # Test cost calculation
    cost = cost_tracker.calculate_cost(
      model: 'gpt-4o-mini',
      input_tokens: 100,
      output_tokens: 50
    )
    
    expected_cost = (100 * 0.15 / 1_000_000) + (50 * 0.60 / 1_000_000)
    expect(cost).to be_within(0.0001).of(expected_cost)
  end

  it "analyzes traces and provides insights" do
    analyzer = RAAF::Tracing::TraceAnalyzer.new
    
    # Mock trace data for testing
    traces = [
      {
        span_id: "span_1",
        duration_ms: 1500,
        model: "gpt-4o-mini",
        input_tokens: 100,
        output_tokens: 50,
        cost: 0.045
      }
    ]
    
    insights = analyzer.analyze_traces(traces)
    
    expect(insights).to be_a(Hash)
    expect(insights).to have_key(:total_cost)
    expect(insights).to have_key(:average_duration)
  end

  # Add your specific test case here that demonstrates the bug
  it "reproduces your specific tracing bug case" do
    # Replace this with your specific test case that demonstrates the tracing bug
    expect(true).to be true # Replace this with your actual test case
  end
end