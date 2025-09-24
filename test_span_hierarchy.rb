#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require_relative 'tracing/lib/raaf/tracing'
require_relative 'dsl/lib/raaf-dsl'

# Set environment variables for debug
ENV['RAAF_DEBUG_CATEGORIES'] = 'tracing'
ENV['RAAF_LOG_LEVEL'] = 'debug'

# Create a simple test pipeline
class TestPipeline < RAAF::Pipeline
  # Simple flow with one agent
  flow TestAgent

  context do
    default :test_data, "test"
  end
end

# Create a test agent that uses tools
class TestAgent < RAAF::DSL::Agent
  agent_name "TestAgent"
  model "gpt-4o"
  instructions "You are a test agent"
  max_turns 1

  uses_tool :tavily_search

  context do
    required :test_data
  end
end

# Set up tracing
tracer = RAAF::Tracing::SpanTracer.new
tracer.add_processor(RAAF::Tracing::ConsoleProcessor.new)

# Create and run pipeline
puts "\n🧪 Testing span hierarchy with fixed implementation..."
puts "=" * 60

begin
  pipeline = TestPipeline.new(test_data: "Ruby programming")

  # Add tracer to pipeline
  pipeline.instance_variable_set(:@tracer, tracer)

  puts "\n🚀 Running pipeline..."
  result = pipeline.run

  puts "\n✅ Pipeline completed successfully!"
  puts "Result keys: #{result.keys.inspect}"

rescue StandardError => e
  puts "\n❌ Error occurred: #{e.message}"
  puts "Backtrace:"
  puts e.backtrace.first(10).join("\n")
end

puts "\n" + "=" * 60
puts "🔍 Check the spans above - they should show:"
puts "  1. Pipeline span (kind: :pipeline, parent: nil)"
puts "  2. Agent span (kind: :agent, parent: pipeline)"
puts "  3. Tool spans (kind: :agent with execute_tool method, parent: agent)"
puts "=" * 60