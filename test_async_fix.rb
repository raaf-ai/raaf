#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require_relative 'core/lib/raaf-core'
require_relative 'tracing/lib/raaf-tracing'

# Enable debug logging
ENV['RAAF_DEBUG_CATEGORIES'] = 'tracing'
ENV['RAAF_LOG_LEVEL'] = 'debug'

# Test tools for parallel execution
def get_weather(location)
  puts "🌤️  Getting weather for #{location}"
  "Weather in #{location}: sunny, 72°F"
end

def get_time(timezone = 'UTC')
  puts "🕰️  Getting time for #{timezone}"
  "Current time in #{timezone}: 10:30 AM"
end

def get_news(topic)
  puts "📰 Getting news about #{topic}"
  "Latest #{topic} news: Everything is awesome!"
end

puts "🧪 Testing Async/Thread.current fix for tool execution..."
puts "=" * 60

begin
  # Create agent with multiple tools
  agent = RAAF::Agent.new(
    name: "TestAgent",
    instructions: "You are a helpful assistant. Use the available tools to help the user.",
    model: "gpt-4o"
  )

  agent.add_tool(method(:get_weather))
  agent.add_tool(method(:get_time))
  agent.add_tool(method(:get_news))

  # Set up tracing with console output
  tracer = RAAF::Tracing::SpanTracer.new
  tracer.add_processor(RAAF::Tracing::ConsoleProcessor.new)

  runner = RAAF::Runner.new(agent: agent, tracer: tracer)

  puts "\n🚀 Running agent with multiple tools (should execute in parallel)..."
  result = runner.run("Get the weather in Tokyo, the time in JST, and news about Ruby programming")

  puts "\n✅ Agent execution completed!"
  puts "Final output: #{result.final_output}"

rescue StandardError => e
  puts "\n❌ Error occurred: #{e.message}"
  puts "Backtrace:"
  puts e.backtrace.first(10).join("\n")
end

puts "\n" + "=" * 60
puts "🔍 Expected trace hierarchy:"
puts "  1. Agent span (root, parent: nil)"
puts "  2. Tool spans should be SIBLINGS under agent span, not nested"
puts "  3. LLM spans should have kind: :llm, not :agent"
puts "=" * 60