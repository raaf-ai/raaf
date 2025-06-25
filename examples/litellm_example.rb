#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "openai_agents"

# Example demonstrating LiteLLM integration for 100+ model providers
# Make sure you have LiteLLM running locally: litellm --model gpt-3.5-turbo

puts "=== LiteLLM Integration Example ==="
puts "This example shows how to use any model via LiteLLM proxy"
puts

# 1. Basic LiteLLM Usage
puts "=== Example 1: Basic LiteLLM Usage ==="

# Create an agent using LiteLLM (default localhost:8000)
litellm_agent = OpenAIAgents::Agent.new(
  name: "LiteLLMAssistant",
  instructions: "You are a helpful assistant powered by LiteLLM.",
  model: "gpt-3.5-turbo" # LiteLLM will route this to the configured provider
)

# Create runner with LiteLLM provider
litellm_provider = OpenAIAgents::Models::LitellmProvider.new(
  model: "gpt-3.5-turbo",
  base_url: "http://localhost:8000" # Default LiteLLM proxy URL
)

runner = OpenAIAgents::Runner.new(
  agent: litellm_agent,
  provider: litellm_provider
)

begin
  result = runner.run("What are the benefits of using LiteLLM?")
  puts "Response: #{result.messages.last[:content]}\n\n"
rescue => e
  puts "Error: #{e.message}"
  puts "Make sure LiteLLM is running: litellm --model gpt-3.5-turbo\n\n"
end

puts "=" * 50

# 2. Using Different Providers via LiteLLM
puts "\n=== Example 2: Multiple Providers via LiteLLM ==="

# Example with Anthropic via LiteLLM
claude_provider = OpenAIAgents::Models::LitellmProvider.new(
  model: "anthropic/claude-3-haiku-20240307"
)

claude_agent = OpenAIAgents::Agent.new(
  name: "ClaudeAssistant",
  instructions: "You are Claude, accessed via LiteLLM.",
  model: "anthropic/claude-3-haiku-20240307"
)

runner = OpenAIAgents::Runner.new(agent: claude_agent, provider: claude_provider)

begin
  result = runner.run("Tell me about yourself in one sentence.")
  puts "Claude response: #{result.messages.last[:content]}\n\n"
rescue => e
  puts "Claude error: #{e.message}\n\n"
end

# Example with Gemini via LiteLLM
gemini_provider = OpenAIAgents::Models::LitellmProvider.new(
  model: "gemini/gemini-pro"
)

gemini_agent = OpenAIAgents::Agent.new(
  name: "GeminiAssistant",
  instructions: "You are Gemini, accessed via LiteLLM.",
  model: "gemini/gemini-pro"
)

runner = OpenAIAgents::Runner.new(agent: gemini_agent, provider: gemini_provider)

begin
  result = runner.run("What's unique about the Gemini model?")
  puts "Gemini response: #{result.messages.last[:content]}\n\n"
rescue => e
  puts "Gemini error: #{e.message}\n\n"
end

puts "=" * 50

# 3. Using Convenience Methods
puts "\n=== Example 3: LiteLLM Convenience Methods ==="

# Use the convenience class to create providers
gpt4_provider = OpenAIAgents::Models::LiteLLM.provider(:gpt4)
claude_provider = OpenAIAgents::Models::LiteLLM.provider(:claude3_opus)
llama_provider = OpenAIAgents::Models::LiteLLM.provider(:llama2_70b)

# List available model shortcuts
puts "Available model shortcuts:"
OpenAIAgents::Models::LiteLLM::MODELS.each do |key, value|
  puts "  :#{key} => '#{value}'"
end
puts

puts "=" * 50

# 4. Tool Calling via LiteLLM
puts "\n=== Example 4: Tool Calling via LiteLLM ==="

def get_weather(location)
  "The weather in #{location} is sunny and 75°F"
end

tool_agent = OpenAIAgents::Agent.new(
  name: "WeatherAssistant",
  instructions: "You help with weather queries.",
  model: "gpt-3.5-turbo"
)

tool_agent.add_tool(method(:get_weather))

runner = OpenAIAgents::Runner.new(
  agent: tool_agent,
  provider: OpenAIAgents::Models::LitellmProvider.new(model: "gpt-3.5-turbo")
)

begin
  result = runner.run("What's the weather in San Francisco?")
  puts "Tool response: #{result.messages.last[:content]}\n\n"
rescue => e
  puts "Tool error: #{e.message}\n\n"
end

puts "=" * 50

# 5. Multi-Agent with Different Models
puts "\n=== Example 5: Multi-Agent System with Different Models ==="

# Research agent using GPT-4
research_agent = OpenAIAgents::Agent.new(
  name: "Researcher",
  instructions: "You research topics in depth. For coding questions, handoff to the Coder.",
  model: "openai/gpt-4"
)

# Coding agent using Claude
coding_agent = OpenAIAgents::Agent.new(
  name: "Coder",
  instructions: "You write code. For general questions, handoff to the Researcher.",
  model: "anthropic/claude-3-sonnet-20240229"
)

# Set up handoffs
research_agent.add_handoff(coding_agent)
coding_agent.add_handoff(research_agent)

# Create runners with appropriate providers
research_runner = OpenAIAgents::Runner.new(
  agent: research_agent,
  provider: OpenAIAgents::Models::LiteLLM.provider("openai/gpt-4")
)

begin
  result = research_runner.run("Write a Python function to calculate fibonacci numbers")
  puts "Multi-agent response:"
  puts result.messages.last[:content]
  puts "\nLast agent: #{result.last_agent.name}\n\n"
rescue => e
  puts "Multi-agent error: #{e.message}\n\n"
end

puts "=" * 50

# 6. Local Models via Ollama/LiteLLM
puts "\n=== Example 6: Local Models via Ollama/LiteLLM ==="

# Use a local model through LiteLLM
local_provider = OpenAIAgents::Models::LitellmProvider.new(
  model: "ollama/llama2"
)

local_agent = OpenAIAgents::Agent.new(
  name: "LocalAssistant",
  instructions: "You are a helpful assistant running locally via Ollama.",
  model: "ollama/llama2"
)

runner = OpenAIAgents::Runner.new(agent: local_agent, provider: local_provider)

begin
  result = runner.run("What are the advantages of running models locally?")
  puts "Local model response: #{result.messages.last[:content]}\n\n"
rescue => e
  puts "Local model error: #{e.message}"
  puts "Make sure Ollama is running and llama2 is pulled\n\n"
end

puts "=== LiteLLM Examples Complete ==="
puts
puts "To run these examples:"
puts "1. Install LiteLLM: pip install litellm"
puts "2. Start LiteLLM proxy: litellm --model gpt-3.5-turbo"
puts "3. For specific providers, set up API keys:"
puts "   - export OPENAI_API_KEY=your-key"
puts "   - export ANTHROPIC_API_KEY=your-key"
puts "   - export GEMINI_API_KEY=your-key"
puts "4. For local models, install Ollama and pull models"
puts
puts "LiteLLM supports 100+ providers including:"
puts "- OpenAI, Anthropic, Google (Gemini, Vertex AI)"
puts "- AWS Bedrock, Azure OpenAI"
puts "- Cohere, Replicate, Hugging Face"
puts "- Together AI, Anyscale, Perplexity"
puts "- Local models via Ollama, vLLM"
puts "- And many more!"