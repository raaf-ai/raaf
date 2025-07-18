#!/usr/bin/env ruby
# frozen_string_literal: true

# Simple working example without handoffs to verify basic functionality

require "bundler/setup"
require_relative "../lib/raaf-core"

puts "=== Simple Working Example ==="

# Create a simple agent without any handoffs
simple_agent = RAAF::Agent.new(
  name: "Assistant",
  instructions: "You are a helpful assistant. Answer questions directly and completely.",
  model: "gpt-4o-mini"
)

runner = RAAF::Runner.new(agent: simple_agent)

# Test basic functionality
puts "Testing basic agent..."
result = runner.run("Hello, how are you?")
puts "Response: #{result.messages.last[:content]}"
puts "Agent: #{result.last_agent.name}"

puts "\nBasic functionality works!"