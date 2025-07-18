#!/usr/bin/env ruby
# frozen_string_literal: true

require "raaf"

##
# Agent with Tools Example
#
# This example demonstrates how to create an agent with custom tools
# and use them in conversations.
#

puts "=== Agent with Tools Example ==="
puts

# Define custom tools
def get_weather(location)
  # In a real application, this would call a weather API
  "The weather in #{location} is sunny and 72°F with light winds."
end

def calculate_tip(bill_amount, tip_percentage = 15)
  tip = (bill_amount * tip_percentage / 100.0).round(2)
  total = bill_amount + tip
  "For a bill of $#{bill_amount} with #{tip_percentage}% tip: Tip = $#{tip}, Total = $#{total}"
end

def search_web(query)
  # Mock web search - in real app would use actual search API
  "Search results for '#{query}': Found 3 relevant articles about #{query}."
end

# Create agent with tools
agent = RAAF::Agent.new(
  name: "UtilityBot",
  instructions: "You are a helpful utility assistant. Use the available tools to help users.",
  model: "gpt-4o",
  tools: [
    method(:get_weather),
    method(:calculate_tip),
    method(:search_web)
  ]
)

puts "Created agent: #{agent.name}"
puts "Available tools: #{agent.tools.map(&:name).join(', ')}"
puts

# Create runner
runner = RAAF::Runner.new(agent: agent)

# Test different tool usage
test_queries = [
  "What's the weather like in Tokyo?",
  "Help me calculate a 20% tip for a $45 dinner bill",
  "Search for information about Ruby programming best practices"
]

test_queries.each_with_index do |query, index|
  puts "Query #{index + 1}: #{query}"
  result = runner.run(query)
  puts "Response: #{result.messages.last[:content]}"
  puts
end

puts "=== Example Complete ==="