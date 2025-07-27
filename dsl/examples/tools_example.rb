#!/usr/bin/env ruby
# frozen_string_literal: true

# Tools Example
#
# This example demonstrates how to create custom tools and add them to agents
# using the RAAF DSL.

require "raaf-core"
require "raaf-dsl"
require "json"

# Create a calculator tool using the DSL
calculator = RAAF::DSL::ToolBuilder.build do
  name "calculator"
  description "Performs basic mathematical operations"

  # Define parameters
  parameter :operation, type: :string, enum: %w[add subtract multiply divide], required: true
  parameter :a, type: :number, required: true
  parameter :b, type: :number, required: true

  # Define the execution logic
  execute do |operation:, a:, b:|
    result = case operation
             when "add" then a + b
             when "subtract" then a - b
             when "multiply" then a * b
             when "divide"
               b.zero? ? { error: "Division by zero" } : a.to_f / b
             end

    { result: result, operation: operation, a: a, b: b }
  end
end

# Create a weather tool (simulated)
weather_tool = RAAF::DSL::ToolBuilder.build do
  name "get_weather"
  description "Get current weather for a location"

  parameter :location, type: :string, required: true
  parameter :units, type: :string, enum: %w[celsius fahrenheit], default: "celsius"

  execute do |location:, units:|
    # Simulate weather data
    temp = rand(10..30)
    temp = ((temp * 9 / 5) + 32).round if units == "fahrenheit"

    {
      location: location,
      temperature: temp,
      units: units,
      conditions: ["sunny", "cloudy", "rainy", "partly cloudy"].sample,
      humidity: rand(40..80)
    }
  end
end

# Create an agent with these tools
agent = RAAF::DSL::AgentBuilder.build do
  name "ToolsAgent"
  instructions "You are an assistant that can perform calculations and check weather."
  model "gpt-4o"

  # Add the tools
  add_tool calculator
  add_tool weather_tool

  # You can also define tools inline using the DSL
  tool :time_in_timezone do
    description "Get current time in a specific timezone"
    parameter :timezone, type: :string, required: true, enum: %w[UTC EST PST CET JST]

    execute do |timezone:|
      # Simple timezone offset calculation (simplified)
      offsets = {
        "UTC" => 0,
        "EST" => -5,
        "PST" => -8,
        "CET" => 1,
        "JST" => 9
      }

      offset = offsets[timezone] || 0
      time = Time.now.utc + (offset * 3600)

      {
        timezone: timezone,
        time: time.strftime("%Y-%m-%d %H:%M:%S"),
        offset: offset
      }
    end
  end
end

puts "Created agent with #{agent.tools.size} tools:"
agent.tools.each_with_index do |tool, i|
  puts "  #{i + 1}. #{tool.name}: #{tool.description}"
  puts "     Class: #{tool.class}"
  puts "     Callable: #{tool.respond_to?(:call)}"
end

# Test the tools directly
puts "\nTesting calculator tool:"
begin
  result = calculator.call(operation: "multiply", a: 7, b: 8)
  puts "  7 × 8 = #{result[:result]}"
rescue StandardError => e
  puts "  Error: #{e.message}"
end

puts "\nTesting weather tool:"
begin
  weather = weather_tool.call(location: "New York", units: "fahrenheit")
  puts "  Weather in #{weather[:location]}: #{weather[:temperature]}°F, #{weather[:conditions]}"
rescue StandardError => e
  puts "  Error: #{e.message}"
end

# Create a runner and test with the agent
runner = RAAF::Runner.new(agent: agent)

puts "\n--- Agent Conversation ---"
result = runner.run("What's 25 times 4? Also, what's the weather like in Tokyo?")

# Display the result
puts "\nAgent response:"
puts result.messages.last[:content]
