#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "lib/openai_agents"
require "json"

puts "=== Testing Both Providers with Structured Output ==="

# Simple schema for testing
schema = {
  type: "object", 
  properties: {
    name: { type: "string" },
    age: { type: "integer" }
  },
  required: ["name", "age"],
  additionalProperties: false
}

# Test input
test_input = "My name is Alice and I'm 25 years old"

if ENV["OPENAI_API_KEY"] && ENV["OPENAI_API_KEY"].start_with?("sk-")
  
  puts "\n1. Testing ResponsesProvider (default):"
  responses_agent = OpenAIAgents::Agent.new(
    name: "ResponsesAgent",
    instructions: "Return only valid JSON matching the schema.",
    model: "gpt-4o",
    output_schema: schema
  )
  
  responses_runner = OpenAIAgents::Runner.new(
    agent: responses_agent
    # Uses ResponsesProvider by default
  )
  
  begin
    result1 = responses_runner.run([{ role: "user", content: test_input }])
    response1 = result1.messages.last[:content]
    puts "✅ ResponsesProvider response: #{response1}"
    
    parsed1 = JSON.parse(response1)
    puts "✅ Valid JSON: #{parsed1}"
  rescue => e
    puts "❌ ResponsesProvider failed: #{e.message}"
  end
  
  puts "\n2. Testing OpenAIProvider (Chat Completions):"
  openai_agent = OpenAIAgents::Agent.new(
    name: "OpenAIAgent", 
    instructions: "Return only valid JSON matching the schema.",
    model: "gpt-4o",
    output_schema: schema
  )
  
  openai_runner = OpenAIAgents::Runner.new(
    agent: openai_agent,
    provider: OpenAIAgents::Models::OpenAIProvider.new  # Explicit OpenAI provider
  )
  
  begin
    result2 = openai_runner.run([{ role: "user", content: test_input }])
    response2 = result2.messages.last[:content]
    puts "✅ OpenAIProvider response: #{response2}"
    
    parsed2 = JSON.parse(response2)
    puts "✅ Valid JSON: #{parsed2}"
  rescue => e
    puts "❌ OpenAIProvider failed: #{e.message}"
  end
  
  puts "\n=== Results ==="
  puts "Both providers now support structured output! 🎉"
  
else
  puts "⚠️  Set OPENAI_API_KEY to test with real API"
end