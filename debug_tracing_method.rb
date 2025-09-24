#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'tracing/lib/raaf-tracing'

puts "🔍 Testing tracing method discovery..."

# Create a simple test class
class TestAgent
  include RAAF::Tracing::Traceable
  trace_as :agent

  def initialize(name: "TestAgent")
    @name = name
  end

  attr_reader :name
end

# Test the agent
agent = TestAgent.new(name: "MarketAnalysis")

puts "🔍 Agent created: #{agent.class.name}"
puts "🔍 Agent name: #{agent.name}"
puts "🔍 Agent methods: #{agent.class.instance_methods(false).grep(/tracing/)}"

# Check where tracing comes from
puts "🔍 Agent ancestors: #{agent.class.ancestors.first(10).map(&:name)}"

# Try to find with_tracing method
if agent.respond_to?(:with_tracing)
  puts "🔍 Agent HAS with_tracing method"
  puts "🔍 Method defined in: #{agent.method(:with_tracing).source_location}"
else
  puts "🔍 Agent does NOT have with_tracing method"
end

# Test the method call
puts "🔍 Testing with_tracing call..."
begin
  agent.with_tracing(:execute, agent_name: "MarketAnalysis") do
    puts "🔍 Inside with_tracing block"
    "test result"
  end
  puts "🔍 with_tracing completed successfully"
rescue => e
  puts "❌ with_tracing failed: #{e.message}"
  puts "❌ Error class: #{e.class}"
  puts "❌ Backtrace: #{e.backtrace.first(3).join(', ')}"
end

puts "Done testing"