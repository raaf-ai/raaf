#!/usr/bin/env ruby
# frozen_string_literal: true

# Test script to verify the handoff logging fix

require_relative 'lib/raaf-core'

# Enable debug logging to see the message logging
ENV['RAAF_DEBUG_CATEGORIES'] = 'api,handoff'
ENV['RAAF_LOG_LEVEL'] = 'debug'

puts "=== Testing Handoff Logging Fix ==="
puts "Debug categories: #{ENV['RAAF_DEBUG_CATEGORIES']}"
puts "Log level: #{ENV['RAAF_LOG_LEVEL']}"
puts

# Create agents
search_agent = RAAF::Agent.new(
  name: "SearchAgent",
  instructions: "You are a search agent. When users need help with companies, transfer them to the company discovery agent.",
  model: "gpt-4o"
)

company_agent = RAAF::Agent.new(
  name: "CompanyDiscoveryAgent",
  instructions: "You are a company discovery agent. Help users find information about companies.",
  model: "gpt-4o"
)

# Set up handoff
puts "Setting up handoff: SearchAgent → CompanyDiscoveryAgent"
search_agent.add_handoff(company_agent)
puts "Handoff configured successfully"
puts

# Create runner
runner = RAAF::Runner.new(agent: search_agent)

# Test basic functionality
puts "=== Test 1: Basic Query (should not trigger handoff) ==="
begin
  result = runner.run("Hello, how are you?")
  puts "✅ Test 1 passed - Basic query worked"
  puts "Response: #{result.messages.last[:content]}"
rescue => e
  puts "❌ Test 1 failed: #{e.message}"
  puts "Error class: #{e.class}"
end

puts
puts "=== Test 2: Handoff Query (should trigger handoff) ==="
begin
  result = runner.run("I need help finding information about a company")
  puts "✅ Test 2 passed - Handoff query worked"
  puts "Response: #{result.messages.last[:content]}"
rescue => e
  puts "❌ Test 2 failed: #{e.message}"
  puts "Error class: #{e.class}"
  puts "Stack trace: #{e.backtrace.first(5).join("\n")}"
end

puts
puts "=== Test Complete ==="
puts "If you see debug messages with 🚀 RUNNER: Request tool details above, the fix is working!"