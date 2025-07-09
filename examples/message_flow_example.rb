#!/usr/bin/env ruby
# frozen_string_literal: true

# Example demonstrating how messages flow between agent and LLM in OpenAI Agents Ruby

require_relative "../lib/openai_agents"

# Enable debug output to see the message flow
ENV["OPENAI_AGENTS_DEBUG_CONVERSATION"] = "true"

# Create a simple agent
agent = OpenAIAgents::Agent.new(
  name: "Assistant",
  instructions: "You are a helpful assistant. Keep your responses brief.",
  model: "gpt-4o"
)

# Add a simple tool to demonstrate tool calling flow
def get_current_time
  Time.now.strftime("%Y-%m-%d %H:%M:%S %Z")
end

agent.add_tool(method(:get_current_time))

# Create a runner - by default uses ResponsesProvider (Responses API)
runner = OpenAIAgents::Runner.new(agent: agent)

puts "=== Message Flow Example ==="
puts "This example shows how messages are passed between the agent and LLM\n\n"

# Example 1: Simple text message
puts "1. Simple Text Message Flow:"
puts "-" * 50
result = runner.run("Hello! What time is it?")
puts "\nFinal Response: #{result.messages.last[:content]}\n\n"

# Example 2: Using legacy Chat Completions API for comparison
puts "2. Using Chat Completions API (Legacy):"
puts "-" * 50
legacy_runner = OpenAIAgents::Runner.new(
  agent: agent,
  provider: OpenAIAgents::Models::OpenAIProvider.new
)
result = legacy_runner.run("Hello! What time is it?")
puts "\nFinal Response: #{result.messages.last[:content]}\n\n"

# Detailed explanation of the flow
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

# Show the actual message structure
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

puts "\nChat Completions API Format:"
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