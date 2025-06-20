#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/openai_agents"

# Example: Multi-agent system with handoffs

# Weather agent tools
def get_weather(city)
  "The weather in #{city} is sunny with 22°C"
end

def get_forecast(city, days = 3)
  "#{days}-day forecast for #{city}: Sunny, Cloudy, Rainy"
end

# Math agent tools
def calculate(expression)
  # Simple calculator - supports basic arithmetic operations
  # For security, only allow basic math operations
  cleaned_expr = expression.gsub(%r{[^0-9+\-*/\s\(\).]}, "")
  return "Invalid expression" if cleaned_expr != expression

  # Use a simple parser instead of eval for security
  begin
    result = calculate_safe(expression)
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

def solve_equation(equation)
  "Solution for #{equation}: This would solve the equation"
end

# Create specialized agents
weather_agent = OpenAIAgents::Agent.new(
  name: "WeatherAgent",
  instructions: "You are a weather specialist. You can provide weather information and forecasts. " \
                "If asked about math, handoff to MathAgent.",
  model: "gpt-4"
)

math_agent = OpenAIAgents::Agent.new(
  name: "MathAgent",
  instructions: "You are a math specialist. You can perform calculations and solve equations. " \
                "If asked about weather, handoff to WeatherAgent.",
  model: "gpt-4"
)

# Add tools to agents
weather_agent.add_tool(method(:get_weather))
weather_agent.add_tool(method(:get_forecast))

math_agent.add_tool(method(:calculate))
math_agent.add_tool(method(:solve_equation))

# Set up handoffs
weather_agent.add_handoff(math_agent)
math_agent.add_handoff(weather_agent)

# Create tracer
tracer = OpenAIAgents::Tracer.new
tracer.add_processor(OpenAIAgents::ConsoleProcessor.new)

# Create runner starting with weather agent
OpenAIAgents::Runner.new(agent: weather_agent, tracer: tracer)

puts "=== Multi-Agent System Example ==="
puts "Weather Agent Tools: #{weather_agent.tools.map(&:name).join(", ")}"
puts "Math Agent Tools: #{math_agent.tools.map(&:name).join(", ")}"
puts "Handoffs: WeatherAgent ↔ MathAgent"

puts "\n=== Demo Conversation ==="
puts "User: What's the weather in Tokyo and what's 25 * 14?"
puts "\nThis would:"
puts "1. Start with WeatherAgent"
puts "2. Get weather for Tokyo"
puts "3. Recognize math question and handoff to MathAgent"
puts "4. MathAgent calculates 25 * 14"
puts "5. Return combined response"

puts "\n=== Tool Demonstrations ==="
puts "Weather: #{weather_agent.execute_tool("get_weather", city: "Tokyo")}"
puts "Forecast: #{weather_agent.execute_tool("get_forecast", city: "Tokyo", days: 5)}"
puts "Math: #{math_agent.execute_tool("calculate", expression: "25 * 14")}"

puts "\n=== Agent Capabilities ==="
puts "WeatherAgent can handoff to: #{weather_agent.handoffs.map(&:name).join(", ")}"
puts "MathAgent can handoff to: #{math_agent.handoffs.map(&:name).join(", ")}"
puts "WeatherAgent can handoff to MathAgent: #{weather_agent.can_handoff_to?("MathAgent")}"
