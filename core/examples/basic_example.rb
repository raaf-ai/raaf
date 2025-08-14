#!/usr/bin/env ruby
# frozen_string_literal: true

##
# Simple Basic Example - Core RAAF Functionality
#
# This example demonstrates the most basic RAAF functionality without
# handoffs, tools, or complex features. It verifies that the core
# agent-runner architecture works correctly.
#
# @author RAAF Team
# @since 0.1.0
# @example Run this example
#   OPENAI_API_KEY=your-key ruby examples/basic_example.rb

require "bundler/setup"
require "raaf-core"

puts "=== RAAF Core Basic Example ==="
puts "🤖 Testing basic agent-runner functionality"

##
# Create a simple agent without any tools or handoffs
# This demonstrates the minimum configuration needed for RAAF
simple_agent = RAAF::Agent.new(
  name: "BasicAssistant",
  instructions: "You are a helpful assistant. Answer questions directly and completely.",
  model: "gpt-4o-mini"  # Cost-effective model for basic examples
)

# Create a runner (automatically uses ResponsesProvider with built-in retry)
runner = RAAF::Runner.new(agent: simple_agent)

puts "\n🔄 Running basic conversation..."

begin
  # Test basic agent functionality
  result = runner.run("Hello, how are you?")

  # Display results with proper formatting
  puts "\n✅ Conversation successful!"
  puts "   Agent: #{result.last_agent.name}"
  puts "   Response: #{result.messages.last[:content][0..100]}..."
  puts "   Message count: #{result.messages.length}"

  puts "\n🎉 Basic RAAF functionality verified!"

rescue RAAF::Error => e
  puts "\n❌ RAAF Error: #{e.message}"
  puts "   Make sure OPENAI_API_KEY is set in your environment."
  puts "   Example: OPENAI_API_KEY=your-key ruby #{__FILE__}"
rescue StandardError => e
  puts "\n❌ Unexpected error: #{e.message}"
  puts "   Please check your configuration and try again."
end
