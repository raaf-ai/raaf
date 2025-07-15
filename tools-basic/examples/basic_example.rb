#!/usr/bin/env ruby
# frozen_string_literal: true

# This example demonstrates the core functionality of OpenAI Agents in Ruby.
# It shows the simplest way to create an AI agent that can use custom tools
# to extend its capabilities beyond text generation.

require_relative "../lib/openai_agents"

# ============================================================================
# TOOL DEFINITIONS
# ============================================================================

# Weather lookup tool that simulates an external API call.
# In a real application, this would integrate with a weather service API
# like OpenWeatherMap or WeatherAPI. The tool demonstrates how agents
# can interact with external data sources to provide real-time information.
#
# The parameter is defined as a keyword argument (city:) to match
# how the OpenAI API calls tools with named parameters.
def get_weather(city:)
  # For demonstration purposes, we return simulated weather data.
  # A production implementation would include:
  # - API authentication
  # - HTTP request to weather service
  # - Error handling for network issues
  # - Response parsing and formatting
  "The weather in #{city} is sunny with 22°C"
end

# Calculator tool that safely evaluates arithmetic expressions.
# This demonstrates how to create tools that process user input securely.
# The implementation avoids using eval() which could execute arbitrary code,
# instead using a safe parser that only handles mathematical operations.
#
# Like get_weather, this uses a keyword argument (expression:) to ensure
# compatibility with how OpenAI's API calls tools.
def calculate(expression:)
  # Security is paramount when processing user input.
  # This regex removes any characters that aren't part of basic math,
  # keeping only: digits (0-9), operators (+, -, *, /), decimal points,
  # spaces, and parentheses for grouping.
  cleaned_expr = expression.gsub(%r{[^0-9+\-*/\s\(\).]}, "")
  
  # If the cleaning process changed the expression, it means the user
  # tried to include invalid characters (possibly malicious code).
  # We reject such input immediately for security.
  return "Invalid expression" if cleaned_expr != expression

  # Instead of using Ruby's eval() which would execute any Ruby code,
  # we use our custom safe calculator that only handles math.
  begin
    result = calculate_safe(cleaned_expr)
    "The result is: #{result}"
  rescue StandardError => e
    "Invalid expression: #{e.message}"
  end
end

# Safe arithmetic evaluator that parses simple mathematical expressions.
# This is a security-focused alternative to eval() that prevents code injection.
# The parser only handles basic binary operations (two numbers and an operator)
# which covers most common calculation needs while maintaining security.
def calculate_safe(expression)
  # The regex pattern breaks down as follows:
  # ^\s*           - Start of string, optional whitespace
  # (\d+(?:\.\d+)?) - First number (integer or decimal)
  # \s*            - Optional whitespace
  # ([+\-*/])      - One of four basic operators
  # \s*            - Optional whitespace  
  # (\d+(?:\.\d+)?) - Second number (integer or decimal)
  # \s*$           - Optional whitespace, end of string
  #
  # This pattern ensures we only process simple, safe expressions
  # like "5 + 3", "10.5 * 2", or "100 / 4"
  unless expression =~ %r{^\s*(\d+(?:\.\d+)?)\s*([+\-*/])\s*(\d+(?:\.\d+)?)\s*$}
    raise StandardError, "Complex expressions not supported (use format: 'number operator number')"
  end

  # Extract the components from the regex match groups
  left = Regexp.last_match(1).to_f    # First number as float
  operator = Regexp.last_match(2)      # Mathematical operator
  right = Regexp.last_match(3).to_f    # Second number as float

  # Perform the appropriate calculation based on the operator.
  # Using a case statement ensures only our allowed operators work.
  case operator
  when "+" then left + right
  when "-" then left - right
  when "*" then left * right
  when "/" 
    # Division requires special handling to prevent division by zero errors
    # which would crash the program. We check first and provide a clear error.
    raise(StandardError, "Division by zero") if right.zero?
    left / right
  else
    # This shouldn't happen with our regex, but we include it for completeness
    raise StandardError, "Unsupported operation"
  end
end

# ============================================================================
# AGENT SETUP
# ============================================================================

# Create an AI agent with specific capabilities and personality.
# The agent configuration defines how the AI will behave and what it can do.
# This uses the new Python-aligned defaults where ResponsesProvider is the
# default, ensuring compatibility between Ruby and Python implementations.
agent = OpenAIAgents::Agent.new(
  # The agent's name is used for identification in multi-agent scenarios
  # and appears in traces and logs for debugging purposes.
  name: "Assistant",
  
  # Instructions define the agent's personality and capabilities.
  # This is the system prompt that guides the AI's behavior throughout
  # the conversation. Be specific about what the agent should do.
  instructions: "You are a helpful assistant that can get weather information and perform calculations.",
  
  # Model selection determines the AI's capabilities and cost.
  # gpt-4o is the latest optimized version with better performance.
  # Other options: gpt-4-turbo, gpt-3.5-turbo (faster/cheaper)
  model: "gpt-4o"
)

# Register our tool functions with the agent.
# Tools extend the agent's capabilities beyond text generation,
# allowing it to interact with external systems and perform computations.
# The agent will automatically call these tools when appropriate based
# on the conversation context and user requests.

# Ruby's method() function creates a Method object from our function,
# which the agent can then call with appropriate parameters.
# The agent introspects the method signature to understand what
# parameters are required.
agent.add_tool(method(:get_weather))
agent.add_tool(method(:calculate))

# ============================================================================
# TRACING SETUP
# ============================================================================

# Create a tracer for monitoring and debugging agent execution.
# The tracer collects performance metrics, API calls, and execution flow.
# This uses the global tracer which sends data to OpenAI for dashboard viewing.
# The Ruby implementation now defaults to ResponsesProvider, matching Python.
tracer = OpenAIAgents.tracer

# ============================================================================
# RUNNER SETUP
# ============================================================================

# The Runner orchestrates the conversation between user and agent.
# It handles the request/response cycle, tool execution, and error handling.
# By attaching a tracer, we enable monitoring of all agent activities.
runner = OpenAIAgents::Runner.new(agent: agent, tracer: tracer)

# ============================================================================
# EXAMPLE CONVERSATION
# ============================================================================

puts "=== Basic Agent Example ==="
puts "Agent: #{agent.name}"
puts "Instructions: #{agent.instructions}"
puts "Tools: #{agent.tools.map(&:name).join(", ")}"
puts "\n=== Conversation ==="

begin
  # Run a conversation that demonstrates both tool capabilities.
  # The agent will recognize it needs to:
  # 1. Call the weather tool for Paris weather
  # 2. Call the calculator tool for the math problem
  # 3. Combine both results in a natural response
  #
  # Note: This requires the OPENAI_API_KEY environment variable to be set.
  # You can get an API key from https://platform.openai.com/api-keys
  messages = [{ role: "user", content: "What's the weather like in Paris and what's 15 * 23?" }]
  result = runner.run(messages)
  
  puts "User: What's the weather like in Paris and what's 15 * 23?"
  puts "Assistant: #{result.final_output}"
  puts "\nTurns: #{result.turns}"
  puts "Agent: #{result.agent_name}"
rescue OpenAIAgents::Error => e
  # If the API call fails (usually due to missing API key), we demonstrate
  # how the tools would work by calling them directly. This helps users
  # understand the flow even without an API key.
  puts "Error: #{e.message}"
  puts "\n=== Demo Mode (No API Key) ==="
  puts "User: What's the weather like in Paris and what's 15 * 23?"
  puts "\nThe agent would perform these steps:"
  puts "1. Recognize the user is asking for two pieces of information"
  puts "2. Call get_weather(city: 'Paris') to get weather data"
  puts "3. Call calculate(expression: '15 * 23') to solve the math"
  puts "4. Combine both results into a natural response"

  # Demonstrate the actual tool execution so users can see the output
  puts "\n=== Direct Tool Execution Demo ==="
  puts "Weather tool result: #{get_weather(city: "Paris")}"
  puts "Calculator tool result: #{calculate(expression: "15 * 23")}"
  puts "\nThe agent would combine these into something like:"
  puts "\"The weather in Paris is sunny with 22°C, and 15 * 23 equals 345.\""
end

# ============================================================================
# CONFIGURATION DISPLAY
# ============================================================================

# Display the agent's configuration for debugging and verification.
# This shows all settings including tools, model, and instructions.
# The to_h method converts the agent to a hash representation that
# can be serialized or inspected.
puts "\n=== Agent Configuration ==="
puts agent.to_h.inspect
