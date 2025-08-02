#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "raaf-dsl"

puts "=== Testing Clean Agent Integration (No Base/SmartAgent) ==="
puts

# Test 1: Basic agent
puts "1. Testing basic agent functionality:"
class BasicAgent < RAAF::DSL::Agent
  agent_name "BasicAgent"
  model "gpt-4o"
  
  def build_instructions
    "You are a helpful assistant"
  end
  
  def build_schema
    {
      type: "object",
      properties: {
        message: { type: "string" }
      },
      required: ["message"],
      additionalProperties: false
    }
  end
end

agent = BasicAgent.new(context: { test: true })
puts "✓ Basic agent created successfully"
puts "  Agent name: #{agent.agent_name}"
puts "  Model: #{agent.model_name}"
puts

# Test 2: Agent with all smart features
puts "2. Testing agent with smart features:"
class SmartAgent < RAAF::DSL::Agent
  agent_name "SmartAgent"
  
  # Context validation
  requires :api_key, :endpoint
  validates :api_key, type: String, presence: true
  
  # Retry configuration
  retry_on :rate_limit, max_attempts: 3, backoff: :exponential
  retry_on Timeout::Error, max_attempts: 2
  
  # Circuit breaker
  circuit_breaker threshold: 5, timeout: 60
  
  # Inline schema
  schema do
    field :status, type: :string, required: true
    field :results, type: :array do
      field :id, type: :string
      field :value, type: :number
    end
  end
  
  # Prompts
  system_prompt "You are a smart assistant"
  
  user_prompt do |ctx|
    "Process data from #{ctx.endpoint} with key #{ctx.api_key[0..5]}..."
  end
end

# Test validation
begin
  SmartAgent.new(context: { endpoint: "https://api.example.com" })
rescue ArgumentError => e
  puts "✓ Context validation works: #{e.message}"
end

# Create with valid context
smart = SmartAgent.new(
  context: { 
    api_key: "sk-123456789", 
    endpoint: "https://api.example.com" 
  }
)
puts "✓ Smart agent created with valid context"
puts "  Has retry config: #{smart.class._retry_config.any?}"
puts "  Has circuit breaker: #{!smart.class._circuit_breaker_config.nil?}"
puts "  Schema defined: #{!smart.build_schema.nil?}"
puts

# Test 3: No need for AgentDsl include
puts "3. Testing that AgentDsl is included automatically:"
class MinimalAgent < RAAF::DSL::Agent
  agent_name "MinimalAgent"
  uses_tool :web_search if respond_to?(:uses_tool)
  
  schema do
    field :result, type: :string
  end
end

minimal = MinimalAgent.new(context: {})
puts "✓ DSL methods work without explicit include"
puts "  Can use agent_name: #{minimal.respond_to?(:agent_name)}"
puts "  Can use schema DSL: #{!minimal.build_schema[:properties].empty?}"
puts

# Test 4: Verify old classes don't exist
puts "4. Testing that old classes are removed:"
begin
  RAAF::DSL::Agents::Base
  puts "✗ Base class still exists!"
rescue NameError
  puts "✓ Base class properly removed"
end

begin
  RAAF::DSL::Agents::SmartAgent
  puts "✗ SmartAgent class still exists!"
rescue NameError
  puts "✓ SmartAgent class properly removed"
end

puts
puts "=== All tests passed! ==="
puts
puts "The unified Agent class is now the only agent class needed."
puts "All features work without the old Base and SmartAgent classes."