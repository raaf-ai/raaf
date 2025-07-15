#!/usr/bin/env ruby
# frozen_string_literal: true

# This example demonstrates multi-agent systems where specialized agents
# collaborate to handle different domains of expertise. Agents can "handoff"
# conversations to other agents when they encounter questions outside their specialty.
# This pattern is useful for building complex AI systems where different agents
# have different capabilities, tools, and knowledge domains.

require_relative "../lib/openai_agents"

# ============================================================================
# MULTI-AGENT SYSTEM WITH HANDOFFS
# ============================================================================

# ============================================================================
# WEATHER AGENT TOOLS
# ============================================================================

# Current weather tool for the weather specialist agent.
# In production, this would integrate with a weather API service.
# Note the use of keyword argument (city:) for OpenAI API compatibility.
def get_weather(city:)
  "The weather in #{city} is sunny with 22°C"
end

# Weather forecast tool providing multi-day predictions.
# Demonstrates tools with optional parameters - Ruby will handle
# both cases: with and without the days parameter.
def get_forecast(city:, days: 3)
  "#{days}-day forecast for #{city}: Sunny, Cloudy, Rainy"
end

# ============================================================================
# MATH AGENT TOOLS
# ============================================================================

# Calculator tool for the math specialist agent.
# This is the same safe calculator from basic_example.rb,
# demonstrating tool reuse across different agents.
def calculate(expression:)
  # Security: Remove any non-mathematical characters
  cleaned_expr = expression.gsub(%r{[^0-9+\-*/\s\(\).]}, "")
  return "Invalid expression" if cleaned_expr != expression

  # Use our safe parser instead of eval
  begin
    result = calculate_safe(expression)
    "The result is: #{result}"
  rescue StandardError => e
    "Invalid expression: #{e.message}"
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

# Equation solver tool for more complex mathematical problems.
# In a real implementation, this might use a symbolic math library
# like SymPy (Python) or similar Ruby alternatives.
def solve_equation(equation:)
  "Solution for #{equation}: This would solve the equation using symbolic math"
end

# ============================================================================
# AGENT CREATION
# ============================================================================

# Create specialized agents, each with their own expertise and tools.
# The instructions explicitly mention when to handoff to other agents,
# helping the AI understand when to delegate to another specialist.

# Weather specialist agent
weather_agent = OpenAIAgents::Agent.new(
  name: "WeatherAgent",
  # Instructions define the agent's role and handoff criteria
  instructions: "You are a weather specialist. You can provide weather information and forecasts. " \
                "If asked about math, calculations, or equations, handoff to MathAgent.",
  model: "gpt-4o"  # Uses ResponsesProvider by default for Python compatibility
)

# Mathematics specialist agent
math_agent = OpenAIAgents::Agent.new(
  name: "MathAgent",
  # Clear instructions about capabilities and when to delegate
  instructions: "You are a math specialist. You can perform calculations and solve equations. " \
                "If asked about weather, temperature, or forecasts, handoff to WeatherAgent.",
  model: "gpt-4o"
)

# ============================================================================
# TOOL REGISTRATION
# ============================================================================

# Add domain-specific tools to each agent.
# Each agent only has access to tools relevant to their specialty,
# enforcing separation of concerns.

# Weather agent gets weather-related tools
weather_agent.add_tool(method(:get_weather))
weather_agent.add_tool(method(:get_forecast))

# Math agent gets calculation tools
math_agent.add_tool(method(:calculate))
math_agent.add_tool(method(:solve_equation))

# ============================================================================
# HANDOFF CONFIGURATION
# ============================================================================

# Configure bidirectional handoffs between agents.
# This creates a "transfer_to_MathAgent" tool for weather_agent
# and a "transfer_to_WeatherAgent" tool for math_agent.
# The AI will use these tools automatically when appropriate.
weather_agent.add_handoff(math_agent)
math_agent.add_handoff(weather_agent)

# ============================================================================
# RUNNER SETUP
# ============================================================================

# Create a tracer for monitoring agent interactions and handoffs.
# This will show how agents collaborate in the trace output.
tracer = OpenAIAgents.tracer

# Create runner starting with the weather agent.
# The runner will automatically handle handoffs between agents,
# maintaining conversation context across agent transitions.
runner = OpenAIAgents::Runner.new(agent: weather_agent, tracer: tracer)

# ============================================================================
# EXAMPLE EXECUTION
# ============================================================================

puts "=== Multi-Agent System Example ==="
puts "\nAgent Configuration:"
puts "- Weather Agent Tools: #{weather_agent.tools.map(&:name).join(", ")}"
puts "- Math Agent Tools: #{math_agent.tools.map(&:name).join(", ")}"
puts "- Handoff Configuration: WeatherAgent ↔ MathAgent"

# Demonstrate the handoff flow
puts "\n=== Demo Conversation Flow ==="
puts "User: What's the weather in Tokyo and what's 25 * 14?"
puts "\nExpected agent collaboration:"
puts "1. WeatherAgent receives the question (starting agent)"
puts "2. WeatherAgent calls get_weather(city: 'Tokyo')"
puts "3. WeatherAgent recognizes the math question"
puts "4. WeatherAgent calls transfer_to_MathAgent tool"
puts "5. MathAgent receives context and calls calculate(expression: '25 * 14')"
puts "6. Both results are combined in the final response"

# Try to run the actual conversation
begin
  messages = [{ role: "user", content: "What's the weather in Tokyo and what's 25 * 14?" }]
  result = runner.run(messages)
  
  puts "\n=== Actual Response ==="
  puts "Assistant: #{result.final_output}"
  puts "\nAgent transitions: #{result.agent_name}"
  puts "Total turns: #{result.turns}"
rescue OpenAIAgents::Error => e
  puts "\n=== Demo Mode (No API Key) ==="
  puts "Error: #{e.message}"
  
  # Demonstrate tools directly
  puts "\n=== Direct Tool Execution Demo ==="
  puts "Weather tool: #{get_weather(city: "Tokyo")}"
  puts "Forecast tool: #{get_forecast(city: "Tokyo", days: 5)}"
  puts "Calculate tool: #{calculate(expression: "25 * 14")}"
  puts "Solve tool: #{solve_equation(equation: "x^2 + 5x + 6 = 0")}"
end

# Show agent capabilities
puts "\n=== Agent Capabilities Summary ==="
puts "WeatherAgent:"
puts "  - Tools: #{weather_agent.tools.select(&:callable?).map(&:name).join(", ")}"
puts "  - Can handoff to: #{weather_agent.handoffs.map(&:name).join(", ")}"
puts "\nMathAgent:"
puts "  - Tools: #{math_agent.tools.select(&:callable?).map(&:name).join(", ")}"
puts "  - Can handoff to: #{math_agent.handoffs.map(&:name).join(", ")}"

# Verify handoff configuration
puts "\n=== Handoff Configuration Details ==="
# In the Responses API, handoffs are handled through special tool functions
# that are created dynamically when agents execute handoffs
puts "WeatherAgent handoffs configured: #{weather_agent.handoffs.size} agent(s)"
puts "  - Can handoff to: #{weather_agent.handoffs.map(&:name).join(', ')}"
puts "MathAgent handoffs configured: #{math_agent.handoffs.size} agent(s)"
puts "  - Can handoff to: #{math_agent.handoffs.map(&:name).join(', ')}"
