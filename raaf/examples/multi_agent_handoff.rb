#!/usr/bin/env ruby
# frozen_string_literal: true

require "raaf"

##
# Multi-Agent Handoff Example
#
# This example demonstrates how to create multiple agents and use
# handoffs to delegate tasks between them.
#

puts "=== Multi-Agent Handoff Example ==="
puts

# Create specialized agents
math_agent = RAAF::Agent.new(
  name: "MathExpert",
  instructions: "You are a mathematics expert. Solve math problems step by step.",
  model: "gpt-4o"
)

weather_agent = RAAF::Agent.new(
  name: "WeatherBot",
  instructions: "You are a weather specialist. Provide weather information.",
  model: "gpt-4o"
)

# Create a coordinator agent that can hand off to specialists
coordinator = RAAF::Agent.new(
  name: "Coordinator",
  instructions: "You are a coordinator. Route questions to appropriate specialists.",
  model: "gpt-4o",
  handoff_agents: [math_agent, weather_agent]
)

puts "Created agents:"
puts "  - #{coordinator.name} (coordinator)"
puts "  - #{math_agent.name} (specialist)"
puts "  - #{weather_agent.name} (specialist)"
puts

# Create runner for the coordinator
runner = RAAF::Runner.new(agent: coordinator)

# Test handoff scenarios
test_scenarios = [
  {
    query: "What's 234 * 567?",
    expected_agent: "MathExpert"
  },
  {
    query: "Will it rain tomorrow in Seattle?",
    expected_agent: "WeatherBot"
  },
  {
    query: "Calculate the square root of 144",
    expected_agent: "MathExpert"
  }
]

test_scenarios.each_with_index do |scenario, index|
  puts "Scenario #{index + 1}: #{scenario[:query]}"
  
  result = runner.run(scenario[:query])
  
  puts "Final Response: #{result.messages.last[:content]}"
  
  # Show which agent handled the request
  if result.final_agent
    puts "Handled by: #{result.final_agent.name}"
  end
  
  puts
end

puts "=== Example Complete ==="