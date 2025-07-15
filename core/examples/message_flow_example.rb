#!/usr/bin/env ruby
# frozen_string_literal: true

# This example demonstrates how messages flow between agents and language models
# in OpenAI Agents Ruby. Understanding message flow is crucial for debugging,
# optimizing performance, and building complex conversational systems. The library
# supports two API modes: the modern Responses API (default) and the legacy Chat
# Completions API. Each has different message formats and flow characteristics.
# This example visualizes both approaches and explains their trade-offs.

require_relative "../lib/openai_agents"

# Enable debug output to visualize the complete message flow
# This flag shows the raw API requests and responses for learning
# In production, set this to false to reduce log verbosity
ENV["OPENAI_AGENTS_DEBUG_CONVERSATION"] = "true"

# Create a simple agent with minimal configuration
# The agent's behavior is defined by instructions and available tools
agent = OpenAIAgents::Agent.new(
  name: "Assistant",
  
  # Instructions shape the agent's personality and behavior
  # Brief instructions help reduce token usage and improve response time
  instructions: "You are a helpful assistant. Keep your responses brief.",
  
  # Model selection affects capabilities and cost
  # gpt-4o provides high quality with reasonable speed
  model: "gpt-4o"
)

# Define a simple tool function to demonstrate tool calling flow
# Tools extend agent capabilities beyond text generation
# The tool signature and return value are automatically handled
def get_current_time
  # Return formatted time string that the agent can include in responses
  Time.now.strftime("%Y-%m-%d %H:%M:%S %Z")
end

# Register the tool with the agent
# The agent can now call this function when needed
# Tool metadata is automatically extracted from the method
agent.add_tool(method(:get_current_time))

# Create a runner with default ResponsesProvider
# The runner orchestrates the conversation flow between user, agent, and LLM
# ResponsesProvider uses the modern Responses API for efficiency
runner = OpenAIAgents::Runner.new(agent: agent)

puts "=== Message Flow Example ==="
puts "This example shows how messages are passed between the agent and LLM\n\n"

# ============================================================================
# EXAMPLE 1: SIMPLE TEXT MESSAGE WITH RESPONSES API
# ============================================================================
# Demonstrates the default message flow using the modern Responses API.
# Watch the debug output to see how messages are converted to "items" format
# and how tool calls are handled transparently.

puts "1. Simple Text Message Flow:"
puts "-" * 50

# Execute a conversation that triggers tool usage
# The agent will recognize the time query and call get_current_time
result = runner.run("Hello! What time is it?")

# Extract and display the final response
# The response includes the tool result integrated into natural language
puts "\nFinal Response: #{result.messages.last[:content]}\n\n"

# ============================================================================
# EXAMPLE 2: LEGACY CHAT COMPLETIONS API COMPARISON
# ============================================================================
# Shows the same conversation using the older Chat Completions API.
# This API is more familiar but less efficient for multi-turn conversations.
# Compare the debug output to see the different message formats.

puts "2. Using Chat Completions API (Legacy):"
puts "-" * 50

# Create a runner with explicit OpenAIProvider for legacy API
# This provider uses the traditional /v1/chat/completions endpoint
legacy_runner = OpenAIAgents::Runner.new(
  agent: agent,
  provider: OpenAIAgents::Models::OpenAIProvider.new  # Forces legacy API
)

# Run the same query to compare message handling
# The result should be functionally identical despite different internals
result = legacy_runner.run("Hello! What time is it?")
puts "\nFinal Response: #{result.messages.last[:content]}\n\n"

# ============================================================================
# MESSAGE FLOW EXPLANATION
# ============================================================================
# Understanding the differences between API modes helps in choosing the right
# approach for your use case and debugging issues effectively.

puts "=== Message Flow Explanation ==="
puts <<~EXPLANATION
  
  The Ruby implementation supports two API modes:
  
  1. **Responses API (Default - matches Python)**:
     - Uses POST /v1/responses endpoint
     - Messages are converted to "items" format:
       * User messages → { type: "user_text", text: "..." }
       * Assistant messages → { type: "text", text: "..." }
       * Tool calls → { type: "function_call", name: "...", arguments: "..." }
       * Tool results → { type: "function_call_output", call_id: "...", output: "..." }
     - Maintains conversation continuity with previous_response_id
     - Better for multi-turn conversations with tools
  
  2. **Chat Completions API (Legacy)**:
     - Uses POST /v1/chat/completions endpoint
     - Traditional message format:
       * { role: "system", content: "..." }
       * { role: "user", content: "..." }
       * { role: "assistant", content: "...", tool_calls: [...] }
       * { role: "tool", tool_call_id: "...", content: "..." }
     - Each request sends full conversation history
     - More familiar but less efficient for long conversations
  
  The flow in both cases:
  1. Runner prepares messages/items based on the provider
  2. Provider makes HTTP call to appropriate OpenAI endpoint
  3. Response is processed (tool calls executed if needed)
  4. Conversation continues until no more tool calls or max turns reached
  
EXPLANATION

# ============================================================================
# MESSAGE STRUCTURE EXAMPLES
# ============================================================================
# These examples show the exact JSON structures sent to OpenAI's APIs.
# Understanding these formats is essential for debugging and custom integrations.

puts "=== Message Structure Examples ==="
puts "\nResponses API Input Format:"
puts <<~JSON
  {
    "model": "gpt-4o",
    "input": [
      { "type": "user_text", "text": "Hello! What time is it?" }
    ],
    "instructions": "You are a helpful assistant. Keep your responses brief.",
    "tools": [
      {
        "type": "function",
        "name": "get_current_time",
        "description": "Get the current time",
        "parameters": { "type": "object", "properties": {}, "required": [] }
      }
    ]
  }
JSON

puts "\nChat Completions API Format (Legacy):"
puts <<~JSON
  {
    "model": "gpt-4o",
    "messages": [
      { "role": "system", "content": "You are a helpful assistant..." },
      { "role": "user", "content": "Hello! What time is it?" }
    ],
    "tools": [
      {
        "type": "function",
        "function": {
          "name": "get_current_time",
          "description": "Get the current time",
          "parameters": { "type": "object", "properties": {}, "required": [] }
        }
      }
    ]
  }
JSON
