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

# Create an agent using the new Python-aligned defaults
agent = OpenAIAgents::Agent.new(
  name: "Assistant",
  instructions: "You are a helpful assistant that can get weather information and perform calculations.",
  model: "gpt-4o"
)

# Add tools
agent.add_tool(method(:get_weather))
agent.add_tool(method(:calculate))

# Create a tracer (now uses ResponsesProvider by default, matching Python)
tracer = OpenAIAgents.tracer

# Create runner
runner = OpenAIAgents::Runner.new(agent: agent, tracer: tracer)

# Example conversation

puts "=== Basic Agent Example ==="
puts "Agent: #{agent.name}"
puts "Instructions: #{agent.instructions}"
puts "Tools: #{agent.tools.map(&:name).join(", ")}"
puts "\n=== Conversation ==="

begin
  # Run a conversation (requires OPENAI_API_KEY environment variable)
  messages = [{ role: "user", content: "What's the weather like in Paris and what's 15 * 23?" }]
  result = runner.run(messages)
  
  puts "User: What's the weather like in Paris and what's 15 * 23?"
  puts "Assistant: #{result.final_output}"
  puts "\nTurns: #{result.turns}"
  puts "Agent: #{result.agent_name}"
rescue OpenAIAgents::Error => e
  puts "Error: #{e.message}"
  puts "\n=== Demo Mode ==="
  puts "User: What's the weather like in Paris and what's 15 * 23?"
  puts "\nAgent would:"
  puts "1. Call get_weather(city: 'Paris')"
  puts "2. Call calculate(expression: '15 * 23')"
  puts "3. Respond with both results"

  # Demonstrate tool execution directly
  puts "\n=== Tool Execution Demo ==="
  puts "Weather result: #{get_weather("Paris")}"
  puts "Calculation result: #{calculate("15 * 23")}"
end

puts "\n=== Agent Configuration ==="
puts agent.to_h.inspect
