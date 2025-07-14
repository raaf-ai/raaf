#!/usr/bin/env ruby
# frozen_string_literal: true

# This example demonstrates LiteLLM integration, enabling access to 100+ different
# language model providers through a unified OpenAI-compatible API. LiteLLM acts as
# a proxy that translates requests between different provider APIs, allowing you to
# switch between models from OpenAI, Anthropic, Google, AWS, Azure, and many others
# without changing your code. This is essential for multi-cloud deployments, vendor
# flexibility, and comparing model performance across providers.

require "bundler/setup"
require "openai_agents"

# LiteLLM must be running as a proxy server to handle requests
# Install: pip install litellm
# Start proxy: litellm --model gpt-3.5-turbo
# The proxy standardizes all provider APIs to match OpenAI's format

puts "=== LiteLLM Integration Example ==="
puts "This example shows how to use any model via LiteLLM proxy"
puts

# ============================================================================
# EXAMPLE 1: BASIC LITELLM USAGE
# ============================================================================
# Shows the fundamental pattern of using LiteLLM as a provider. The LiteLLM
# proxy handles API translation, authentication, and routing to the actual
# model provider. This abstraction enables seamless provider switching.

puts "=== Example 1: Basic LiteLLM Usage ==="

# Create an agent that will use LiteLLM for model access
# The agent configuration remains the same regardless of the underlying provider
litellm_agent = OpenAIAgents::Agent.new(
  name: "LiteLLMAssistant",
  instructions: "You are a helpful assistant powered by LiteLLM.",
  
  # Model name as understood by LiteLLM
  # LiteLLM routes this to the appropriate provider based on configuration
  model: "gpt-3.5-turbo"
)

# Create the LiteLLM provider instance
# This provider communicates with the LiteLLM proxy server
litellm_provider = OpenAIAgents::Models::LitellmProvider.new(
  model: "gpt-3.5-turbo",
  
  # URL where LiteLLM proxy is running
  # Default port 8000 is standard for LiteLLM
  base_url: "http://localhost:8000"
)

# Create runner with the LiteLLM provider
# The runner manages the conversation flow and API interactions
runner = OpenAIAgents::Runner.new(
  agent: litellm_agent,
  provider: litellm_provider
)

# Test the LiteLLM integration
# Error handling is important since the proxy might not be running
begin
  result = runner.run("What are the benefits of using LiteLLM?")
  puts "Response: #{result.messages.last[:content]}\n\n"
rescue StandardError => e
  # Common errors: proxy not running, invalid API keys, model not available
  puts "Error: #{e.message}"
  puts "Make sure LiteLLM is running: litellm --model gpt-3.5-turbo\n\n"
end

puts "=" * 50

# ============================================================================
# EXAMPLE 2: MULTIPLE PROVIDERS VIA LITELLM
# ============================================================================
# Demonstrates accessing different model providers through the same LiteLLM
# proxy. Each provider has its own model naming convention, but LiteLLM
# handles the API translation transparently. This enables A/B testing and
# gradual migration between providers.

puts "\n=== Example 2: Multiple Providers via LiteLLM ==="

# Anthropic models via LiteLLM
# Model name format: anthropic/model-name
# LiteLLM translates OpenAI-style requests to Anthropic's API format
claude_provider = OpenAIAgents::Models::LitellmProvider.new(
  model: "anthropic/claude-3-haiku-20240307"
)

# Create an agent configured for Claude
# The agent doesn't know about LiteLLM - it just uses the model name
claude_agent = OpenAIAgents::Agent.new(
  name: "ClaudeAssistant",
  instructions: "You are Claude, accessed via LiteLLM.",
  model: "anthropic/claude-3-haiku-20240307"
)

runner = OpenAIAgents::Runner.new(agent: claude_agent, provider: claude_provider)

# Test Anthropic model access
# LiteLLM handles API key management and request translation
begin
  result = runner.run("Tell me about yourself in one sentence.")
  puts "Claude response: #{result.messages.last[:content]}\n\n"
rescue StandardError => e
  # Requires ANTHROPIC_API_KEY environment variable
  puts "Claude error: #{e.message}\n\n"
end

# Google Gemini models via LiteLLM
# Model name format: gemini/model-name
# Supports both Gemini Pro and Ultra variants
gemini_provider = OpenAIAgents::Models::LitellmProvider.new(
  model: "gemini/gemini-pro"
)

gemini_agent = OpenAIAgents::Agent.new(
  name: "GeminiAssistant",
  instructions: "You are Gemini, accessed via LiteLLM.",
  model: "gemini/gemini-pro"
)

runner = OpenAIAgents::Runner.new(agent: gemini_agent, provider: gemini_provider)

# Test Google model access
# LiteLLM converts between OpenAI and Google AI formats
begin
  result = runner.run("What's unique about the Gemini model?")
  puts "Gemini response: #{result.messages.last[:content]}\n\n"
rescue StandardError => e
  # Requires GEMINI_API_KEY or Google Cloud credentials
  puts "Gemini error: #{e.message}\n\n"
end

puts "=" * 50

# ============================================================================
# EXAMPLE 3: LITELLM CONVENIENCE METHODS
# ============================================================================
# The library provides convenience methods for common model configurations,
# reducing boilerplate code. These shortcuts map to full model names and
# include optimal settings for each provider.

puts "\n=== Example 3: LiteLLM Convenience Methods ==="

# Convenience methods create pre-configured providers
# These shortcuts make code more readable and reduce errors
gpt4_provider = OpenAIAgents::Models::LiteLLM.provider(:gpt4)
claude_provider = OpenAIAgents::Models::LiteLLM.provider(:claude3_opus)
llama_provider = OpenAIAgents::Models::LiteLLM.provider(:llama2_70b)

# Display all available model shortcuts
# These shortcuts are maintained for popular models across providers
puts "Available model shortcuts:"
OpenAIAgents::Models::LiteLLM::MODELS.each do |key, value|
  puts "  :#{key} => '#{value}'"
end
puts

puts "=" * 50

# ============================================================================
# EXAMPLE 4: TOOL CALLING VIA LITELLM
# ============================================================================
# Tool calling (function calling) support varies by provider. LiteLLM
# standardizes the tool calling interface across providers that support it.
# This enables consistent tool usage regardless of the underlying model.

puts "\n=== Example 4: Tool Calling via LiteLLM ==="

# Define a simple tool function
# LiteLLM ensures tool calls work consistently across providers
def get_weather(location)
  "The weather in #{location} is sunny and 75°F"
end

# Create agent with tool capabilities
# Not all models support tools - LiteLLM handles compatibility
tool_agent = OpenAIAgents::Agent.new(
  name: "WeatherAssistant",
  instructions: "You help with weather queries.",
  model: "gpt-3.5-turbo"  # OpenAI models have full tool support
)

# Add the tool to the agent
# LiteLLM translates tool schemas for each provider's format
tool_agent.add_tool(method(:get_weather))

# Create runner with LiteLLM provider
runner = OpenAIAgents::Runner.new(
  agent: tool_agent,
  provider: OpenAIAgents::Models::LitellmProvider.new(model: "gpt-3.5-turbo")
)

# Test tool calling through LiteLLM
# The model should recognize the weather query and call the tool
begin
  result = runner.run("What's the weather in San Francisco?")
  puts "Tool response: #{result.messages.last[:content]}\n\n"
rescue StandardError => e
  # Some providers don't support tools or require specific configurations
  puts "Tool error: #{e.message}\n\n"
end

puts "=" * 50

# ============================================================================
# EXAMPLE 5: MULTI-AGENT SYSTEM WITH DIFFERENT MODELS
# ============================================================================
# Showcases a sophisticated multi-agent system where different agents use
# different model providers. This pattern enables using the best model for
# each task while maintaining a unified interface through LiteLLM.

puts "\n=== Example 5: Multi-Agent System with Different Models ==="

# Research agent using GPT-4 for deep analysis
# GPT-4 excels at research, reasoning, and complex queries
research_agent = OpenAIAgents::Agent.new(
  name: "Researcher",
  instructions: "You research topics in depth. For coding questions, handoff to the Coder.",
  
  # Full model path for clarity
  # LiteLLM knows this is an OpenAI model
  model: "openai/gpt-4"
)

# Coding agent using Claude for code generation
# Claude Sonnet is known for strong coding capabilities
coding_agent = OpenAIAgents::Agent.new(
  name: "Coder",
  instructions: "You write code. For general questions, handoff to the Researcher.",
  
  # Anthropic's Claude 3 Sonnet model
  # LiteLLM handles the API translation
  model: "anthropic/claude-3-sonnet-20240229"
)

# Configure bidirectional handoffs
# Agents can delegate to each other based on task type
research_agent.add_handoff(coding_agent)
coding_agent.add_handoff(research_agent)

# Create runner for the research agent entry point
# Each agent can use a different provider through LiteLLM
research_runner = OpenAIAgents::Runner.new(
  agent: research_agent,
  
  # Use the convenience method for cleaner code
  provider: OpenAIAgents::Models::LiteLLM.provider("openai/gpt-4")
)

# Test the multi-agent system
# The request should trigger a handoff from researcher to coder
begin
  result = research_runner.run("Write a Python function to calculate fibonacci numbers")
  puts "Multi-agent response:"
  puts result.messages.last[:content]
  puts "\nLast agent: #{result.last_agent.name}\n\n"
rescue StandardError => e
  # Requires both OPENAI_API_KEY and ANTHROPIC_API_KEY
  puts "Multi-agent error: #{e.message}\n\n"
end

puts "=" * 50

# ============================================================================
# EXAMPLE 6: LOCAL MODELS VIA OLLAMA/LITELLM
# ============================================================================
# Demonstrates running models locally for privacy, offline access, or cost
# savings. LiteLLM supports local model servers like Ollama, vLLM, and
# local transformers. This enables hybrid deployments mixing cloud and edge.

puts "\n=== Example 6: Local Models via Ollama/LiteLLM ==="

# Configure LiteLLM to use a local Ollama instance
# Model name format: ollama/model-name
# Ollama must be running: ollama serve
local_provider = OpenAIAgents::Models::LitellmProvider.new(
  model: "ollama/llama2"
)

# Create agent for local inference
# The agent configuration is identical to cloud models
local_agent = OpenAIAgents::Agent.new(
  name: "LocalAssistant",
  instructions: "You are a helpful assistant running locally via Ollama.",
  model: "ollama/llama2"
)

runner = OpenAIAgents::Runner.new(agent: local_agent, provider: local_provider)

# Test local model execution
# Response times depend on hardware capabilities
begin
  result = runner.run("What are the advantages of running models locally?")
  puts "Local model response: #{result.messages.last[:content]}\n\n"
rescue StandardError => e
  # Common issues: Ollama not running, model not downloaded
  puts "Local model error: #{e.message}"
  puts "Make sure Ollama is running and llama2 is pulled\n\n"
end

# ============================================================================
# SUMMARY AND SETUP INSTRUCTIONS
# ============================================================================

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

# Best practices for production LiteLLM deployments:
# 1. Run LiteLLM as a service with proper monitoring
# 2. Configure rate limiting and retry logic
# 3. Use environment-specific model routing
# 4. Implement fallback strategies for provider outages
# 5. Monitor costs across different providers
# 6. Cache responses where appropriate
# 7. Use load balancing for high availability
