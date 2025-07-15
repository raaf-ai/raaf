#!/usr/bin/env ruby
# frozen_string_literal: true

# This example demonstrates Cohere AI integration with OpenAI Agents Ruby.
# Cohere provides powerful language models like Command R for chat and generation tasks.
# The multi-provider architecture allows seamless switching between AI providers,
# enabling cost optimization, feature comparison, and provider redundancy.
# This integration maintains API compatibility while leveraging Cohere's strengths.

require_relative "../lib/openai_agents"

# Cohere requires an API key for authentication
# Sign up at https://cohere.com to get your key
unless ENV["COHERE_API_KEY"]
  puts "ERROR: COHERE_API_KEY environment variable is required"
  puts "Please set it with: export COHERE_API_KEY='your-api-key'"
  puts "Get your API key from: https://dashboard.cohere.com/api-keys"
  exit 1
end

puts "=== Cohere Provider Example ==="
puts

# Create a Cohere provider instance
# This provider translates between OpenAI's interface and Cohere's API
# Enables using Cohere models with the same code structure as OpenAI
provider = OpenAIAgents::Models::CohereProvider.new

# Example 1: Basic chat completion
# Demonstrates using Cohere's Command R model for general conversation
# Command R is Cohere's flagship model optimized for chat and RAG
puts "1. Basic chat completion with Command R:"

# Standard chat completion request using OpenAI's format
# The provider handles translation to Cohere's API structure
response = provider.chat_completion(
  messages: [
    { role: "user", content: "What are the main differences between Ruby and Python?" }
  ],
  model: "command-r"  # Cohere's conversational AI model
)

# Extract response using OpenAI's response structure
# Cohere's response is normalized to match OpenAI's format
puts "Response: #{response.dig("choices", 0, "message", "content")}"
puts

# Example 2: Using tools with Cohere
# Cohere supports function calling, enabling agents to use external tools
# This capability is essential for building interactive AI applications
puts "2. Using tools with Command R:"

# Define a weather tool that agents can call
# Tools extend AI capabilities beyond text generation
def get_weather(location:, unit: "celsius")
  # Simulated weather API response
  # In production: would call actual weather service
  temperatures = {
    "New York" => { celsius: 15, fahrenheit: 59 },
    "London" => { celsius: 12, fahrenheit: 54 },
    "Tokyo" => { celsius: 18, fahrenheit: 64 }
  }

  # Provide default temperature for unknown locations
  temp = temperatures[location] || { celsius: 20, fahrenheit: 68 }
  temp_value = unit == "celsius" ? temp[:celsius] : temp[:fahrenheit]

  # Return formatted weather information
  "The current temperature in #{location} is #{temp_value}°#{unit == "celsius" ? "C" : "F"}"
end

# Create an agent configured to use Cohere's Command R model
# The agent abstraction works identically across providers
weather_agent = OpenAIAgents::Agent.new(
  name: "WeatherAssistant",
  
  # Instructions guide the model's behavior and tool usage
  instructions: "You are a helpful weather assistant. Use the weather tool to provide current temperatures.",
  
  # Specify Cohere model - agent is provider-agnostic
  model: "command-r"
)

# Add the weather tool to the agent's capabilities
# FunctionTool wraps Ruby methods for AI consumption
weather_agent.add_tool(
  OpenAIAgents::FunctionTool.new(
    method(:get_weather),
    name: "get_weather",
    description: "Get the current weather for a location"
  )
)

# Create runner with explicit Cohere provider
# The runner manages conversation flow and tool execution
runner = OpenAIAgents::Runner.new(
  agent: weather_agent,
  provider: provider  # Use Cohere instead of default OpenAI
)

# Test tool usage with multiple location query
# Cohere will identify the need to call the weather tool
messages = [{
  role: "user",
  content: "What's the weather like in Tokyo and New York?"
}]

# Execute the conversation - Cohere handles tool calls transparently
result = runner.run(messages)
puts "Weather query response: #{result[:messages].last[:content]}"
puts

# Example 3: Multi-provider setup
# Demonstrates seamless handoff between Cohere and OpenAI agents
# This pattern enables using each provider's strengths
puts "3. Multi-provider agent handoff:"

# Create a Cohere-powered analyst agent
# Cohere excels at factual analysis and reasoning
cohere_agent = OpenAIAgents::Agent.new(
  name: "CohereAnalyst",
  
  # Instructions include handoff trigger for creative tasks
  instructions: "You are an analyst using Cohere's Command R model. When asked about creative writing, handoff to CreativeWriter.",
  
  model: "command-r"  # Cohere's model
)

# Create an OpenAI-powered creative agent
# GPT-4 excels at creative and nuanced writing
openai_agent = OpenAIAgents::Agent.new(
  name: "CreativeWriter",
  
  instructions: "You are a creative writer using GPT-4. Write engaging stories and poems.",
  
  model: "gpt-4"  # OpenAI's model
)

# Configure handoff capability from Cohere to OpenAI agent
# Enables intelligent routing based on task requirements
cohere_agent.add_handoff(openai_agent)

# Create runner starting with Cohere provider
# The runner will switch providers automatically during handoff
runner2 = OpenAIAgents::Runner.new(
  agent: cohere_agent,
  provider: provider  # Initial provider is Cohere
)

# Request triggers handoff from analytical to creative agent
# Demonstrates provider switching based on task type
messages2 = [{
  role: "user",
  content: "I need help writing a short poem about artificial intelligence"
}]

# Execute conversation with automatic provider switching
puts "Starting with Cohere agent..."
result2 = runner2.run(messages2)
final_agent = result2[:agent]
puts "Final response from #{final_agent.name}: #{result2[:messages].last[:content]}"
puts

# Example 4: Streaming with Cohere
# Streaming provides real-time response generation for better UX
# Users see output as it's generated rather than waiting
puts "4. Streaming response:"
puts "Streaming: "

# Stream completion for real-time output
# Essential for interactive applications and long responses
provider.stream_completion(
  messages: [{ role: "user", content: "Count from 1 to 5 slowly" }],
  model: "command-r"
) do |chunk|
  # Process streaming chunks as they arrive
  # Each chunk contains a piece of the response
  if chunk["choices"] && chunk["choices"][0]["delta"]["content"]
    # Print immediately for real-time display
    print chunk["choices"][0]["delta"]["content"]
    $stdout.flush  # Ensure immediate output
  end
end
puts "\n"

# Example 5: Using retryable provider wrapper
# Production systems need resilience against transient failures
# The retry wrapper adds automatic retry logic with exponential backoff
puts "5. Using retry logic with Cohere:"

# Wrap Cohere provider with retry capabilities
# Handles network issues, rate limits, and temporary outages
retryable_provider = OpenAIAgents::Models::RetryableProviderWrapper.new(
  provider,
  max_attempts: 3,     # Retry up to 3 times
  base_delay: 1.0      # Initial retry delay in seconds
)

# Requests through the wrapper automatically retry on failure
# Exponential backoff prevents overwhelming the service
response = retryable_provider.chat_completion(
  messages: [{ role: "user", content: "Hello!" }],
  model: "command-r"
)

# Response is identical but with added reliability
puts "Response with retry wrapper: #{response.dig("choices", 0, "message", "content")}"
puts

# Summary of Cohere integration capabilities
puts "=== Example Complete ==="
puts
puts "Key Cohere Integration Features:"
puts "1. Drop-in replacement for OpenAI with same API"
puts "2. Access to Command R models for chat and generation"
puts "3. Full tool/function calling support"
puts "4. Seamless multi-provider handoffs"
puts "5. Streaming responses for real-time output"
puts "6. Retry logic for production reliability"
puts
puts "Best Practices:"
puts "- Use Cohere for factual analysis and reasoning tasks"
puts "- Consider OpenAI for creative and nuanced content"
puts "- Implement retry logic for production systems"
puts "- Monitor costs across different providers"
puts "- Test provider-specific capabilities and limitations"
