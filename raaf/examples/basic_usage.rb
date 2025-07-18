#!/usr/bin/env ruby
# frozen_string_literal: true

require "raaf"

##
# Basic RAAF Usage Example
#
# This example demonstrates the most basic usage of the Ruby AI Agents Factory
# framework. It shows how to create an agent and run a simple conversation.
#

puts "=== Basic RAAF Usage Example ==="
puts

# Create a simple agent
agent = RAAF::Agent.new(
  name: "Assistant",
  instructions: "You are a helpful assistant. Be concise and friendly.",
  model: "gpt-4o"
)

puts "Created agent: #{agent.name}"
puts "Model: #{agent.model}"
puts

# Create a runner
runner = RAAF::Runner.new(agent: agent)

# Run a simple conversation
puts "Running conversation..."
result = runner.run("Hello! Can you tell me a fun fact about Ruby programming?")

puts "Response:"
puts result.messages.last[:content]
puts

# Show usage information
if result.usage
  puts "Usage:"
  puts "  Input tokens: #{result.usage[:input_tokens]}"
  puts "  Output tokens: #{result.usage[:output_tokens]}"
  puts "  Total tokens: #{result.usage[:total_tokens]}"
end

puts
puts "=== Example Complete ==="