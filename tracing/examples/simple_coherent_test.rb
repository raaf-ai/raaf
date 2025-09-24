#!/usr/bin/env ruby
# frozen_string_literal: true

# Simple test of coherent tracing without complex logging

puts "🚀 Simple RAAF Coherent Tracing Test"

# Create a simple processor that just prints spans
class SimpleTestProcessor
  def on_span_start(span)
    puts "🟢 Span started: #{span.name}"
  end

  def on_span_end(span)
    puts "🔴 Span ended: #{span.name} (#{span.duration}ms) - #{span.status}"
    puts "   Parent: #{span.parent_id || 'ROOT'}"
    puts "   Attributes: #{span.attributes.size} items"
  end

  def force_flush
    # No-op
  end

  def shutdown
    # No-op
  end
end

# Load the tracing system
begin
  require_relative "../lib/raaf/tracing"

  # Add our simple processor
  RAAF::Tracing.add_trace_processor(SimpleTestProcessor.new)

  puts "✅ Tracing system loaded successfully"
rescue => e
  puts "❌ Error loading tracing: #{e.message}"
  exit 1
end

# Define test components
class TestPipeline
  include RAAF::Tracing::Traceable
  trace_as :pipeline

  attr_reader :name

  def initialize(name)
    @name = name
  end

  def execute
    with_tracing(:execute) do
      puts "   🔄 Pipeline #{name} executing"
      "Pipeline completed"
    end
  end

  def collect_span_attributes
    super.merge({
      "pipeline.name" => name,
      "pipeline.type" => "test"
    })
  end
end

class TestAgent
  include RAAF::Tracing::Traceable
  trace_as :agent

  attr_reader :name, :parent_component

  def initialize(name, parent_component: nil)
    @name = name
    @parent_component = parent_component
  end

  def run
    with_tracing(:run) do
      puts "     🤖 Agent #{name} running"
      "Agent completed"
    end
  end

  def collect_span_attributes
    super.merge({
      "agent.name" => name,
      "agent.model" => "test-model"
    })
  end
end

puts "\n📝 Testing Basic Hierarchy..."

begin
  # Create components
  pipeline = TestPipeline.new("TestPipeline")
  agent = TestAgent.new("TestAgent", parent_component: pipeline)

  # Execute workflow
  RAAF::Tracing.trace("Simple Test") do
    pipeline.execute
    agent.run
  end

  puts "\n✅ Basic hierarchy test completed successfully!"

  # Test nested execution
  puts "\n📝 Testing Nested Execution..."

  pipeline.with_tracing(:execute) do
    agent.with_tracing(:run) do
      puts "     🎯 Nested execution completed"
    end
  end

  puts "\n✅ Nested execution test completed successfully!"

rescue => e
  puts "\n❌ Error during test: #{e.message}"
  puts e.backtrace.first(5).join("\n")
end

# Clean up
puts "\n🧹 Cleaning up..."
RAAF::Tracing.force_flush

puts "\n🎉 All tests completed!"