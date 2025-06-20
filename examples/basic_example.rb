#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/openai_agents"

# Example: Basic agent with tools
def get_weather(city)
  # Simulate weather API call
  "The weather in #{city} is sunny with 22°C"
end

def calculate(expression)
  # Simple calculator - supports basic arithmetic operations
  # For security, only allow basic math operations
  cleaned_expr = expression.gsub(%r{[^0-9+\-*/\s\(\).]}, "")
  return "Invalid expression" if cleaned_expr != expression

  # Use a simple parser instead of eval for security
  begin
    result = calculate_safe(cleaned_expr)
    "The result is: #{result}"
  rescue StandardError
    "Invalid expression"
  end
end

def calculate_safe(expression)
  # Simple arithmetic evaluator - safer than eval
  # This is a basic implementation for demo purposes
  unless expression =~ %r{^\s*(\d+(?:\.\d+)?)\s*([+\-*/])\s*(\d+(?:\.\d+)?)\s*$}
    raise StandardError, "Complex expressions not supported"
  end

  left = Regexp.last_match(1).to_f
  operator = Regexp.last_match(2)
  right = Regexp.last_match(3).to_f

  case operator
  when "+" then left + right
  when "-" then left - right
  when "*" then left * right
  when "/" then right.zero? ? raise(StandardError, "Division by zero") : left / right
  else
    raise StandardError, "Unsupported operation"
  end
end

# Create an agent
agent = OpenAIAgents::Agent.new(
  name: "Assistant",
  instructions: "You are a helpful assistant that can get weather information and perform calculations.",
  model: "gpt-4"
)

# Add tools
agent.add_tool(method(:get_weather))
agent.add_tool(method(:calculate))

# Create a tracer with console output
tracer = OpenAIAgents::Tracer.new
tracer.add_processor(OpenAIAgents::ConsoleProcessor.new)

# Create runner
OpenAIAgents::Runner.new(agent: agent, tracer: tracer)

# Example conversation

puts "=== Basic Agent Example ==="
puts "Agent: #{agent.name}"
puts "Instructions: #{agent.instructions}"
puts "Tools: #{agent.tools.map(&:name).join(", ")}"
puts "\n=== Conversation ==="

begin
  # NOTE: This would require a valid OPENAI_API_KEY environment variable
  # result = runner.run(messages)

  # For demo purposes, let's show the structure
  puts "User: What's the weather like in Paris and what's 15 * 23?"
  puts "\nAgent would:"
  puts "1. Call get_weather(city: 'Paris')"
  puts "2. Call calculate(expression: '15 * 23')"
  puts "3. Respond with both results"

  # Demonstrate tool execution directly
  puts "\n=== Tool Execution Demo ==="
  puts "Weather result: #{agent.execute_tool("get_weather", city: "Paris")}"
  puts "Calculation result: #{agent.execute_tool("calculate", expression: "15 * 23")}"
rescue OpenAIAgents::Error => e
  puts "Error: #{e.message}"
end

puts "\n=== Agent Configuration ==="
puts agent.to_h.inspect
