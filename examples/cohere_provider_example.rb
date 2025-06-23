#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/openai_agents"

# Example demonstrating Cohere provider integration

unless ENV["COHERE_API_KEY"]
  puts "ERROR: COHERE_API_KEY environment variable is required"
  puts "Please set it with: export COHERE_API_KEY='your-api-key'"
  puts "Get your API key from: https://dashboard.cohere.com/api-keys"
  exit 1
end

puts "=== Cohere Provider Example ==="
puts

# Create a Cohere provider
provider = OpenAIAgents::Models::CohereProvider.new

# Example 1: Basic chat completion
puts "1. Basic chat completion with Command R:"
response = provider.chat_completion(
  messages: [
    { role: "user", content: "What are the main differences between Ruby and Python?" }
  ],
  model: "command-r"
)

puts "Response: #{response.dig('choices', 0, 'message', 'content')}"
puts

# Example 2: Using tools with Cohere
puts "2. Using tools with Command R:"

# Define a weather tool
def get_weather(location:, unit: "celsius")
  # Simulated weather API response
  temperatures = {
    "New York" => { celsius: 15, fahrenheit: 59 },
    "London" => { celsius: 12, fahrenheit: 54 },
    "Tokyo" => { celsius: 18, fahrenheit: 64 }
  }
  
  temp = temperatures[location] || { celsius: 20, fahrenheit: 68 }
  temp_value = unit == "celsius" ? temp[:celsius] : temp[:fahrenheit]
  
  "The current temperature in #{location} is #{temp_value}°#{unit == 'celsius' ? 'C' : 'F'}"
end

# Create an agent with Cohere model
weather_agent = OpenAIAgents::Agent.new(
  name: "WeatherAssistant",
  instructions: "You are a helpful weather assistant. Use the weather tool to provide current temperatures.",
  model: "command-r"
)

weather_agent.add_tool(
  OpenAIAgents::FunctionTool.new(
    method(:get_weather),
    name: "get_weather",
    description: "Get the current weather for a location"
  )
)

# Create runner with Cohere provider
runner = OpenAIAgents::Runner.new(
  agent: weather_agent,
  provider: provider
)

messages = [{
  role: "user",
  content: "What's the weather like in Tokyo and New York?"
}]

result = runner.run(messages)
puts "Weather query response: #{result[:messages].last[:content]}"
puts

# Example 3: Multi-provider setup
puts "3. Multi-provider agent handoff:"

# Create agents with different providers
cohere_agent = OpenAIAgents::Agent.new(
  name: "CohereAnalyst",
  instructions: "You are an analyst using Cohere's Command R model. When asked about creative writing, handoff to CreativeWriter.",
  model: "command-r"
)

openai_agent = OpenAIAgents::Agent.new(
  name: "CreativeWriter", 
  instructions: "You are a creative writer using GPT-4. Write engaging stories and poems.",
  model: "gpt-4"
)

# Set up handoff
cohere_agent.add_handoff(openai_agent)

# Create runner with Cohere provider for initial agent
runner2 = OpenAIAgents::Runner.new(
  agent: cohere_agent,
  provider: provider
)

messages2 = [{
  role: "user",
  content: "I need help writing a short poem about artificial intelligence"
}]

puts "Starting with Cohere agent..."
result2 = runner2.run(messages2)
final_agent = result2[:agent]
puts "Final response from #{final_agent.name}: #{result2[:messages].last[:content]}"
puts

# Example 4: Streaming with Cohere
puts "4. Streaming response:"
puts "Streaming: "

provider.stream_completion(
  messages: [{ role: "user", content: "Count from 1 to 5 slowly" }],
  model: "command-r"
) do |chunk|
  if chunk["choices"] && chunk["choices"][0]["delta"]["content"]
    print chunk["choices"][0]["delta"]["content"]
    $stdout.flush
  end
end
puts "\n"

# Example 5: Using retryable provider wrapper
puts "5. Using retry logic with Cohere:"

retryable_provider = OpenAIAgents::Models::RetryableProviderWrapper.new(
  provider,
  max_attempts: 3,
  base_delay: 1.0
)

# This would retry on transient failures
response = retryable_provider.chat_completion(
  messages: [{ role: "user", content: "Hello!" }],
  model: "command-r"
)

puts "Response with retry wrapper: #{response.dig('choices', 0, 'message', 'content')}"
puts

puts "=== Example Complete ==="