#!/usr/bin/env ruby
# frozen_string_literal: true

# Test script for reasoning_effort DSL method
# This verifies the end-to-end functionality without requiring an API key

# Add lib directories to load path
$LOAD_PATH.unshift File.expand_path("core/lib", __dir__)
$LOAD_PATH.unshift File.expand_path("dsl/lib", __dir__)

require "raaf-core"
require "raaf-dsl"

puts "Testing reasoning_effort DSL method..."
puts "=" * 60

# Test 1: Agent with minimal reasoning_effort
puts "\n1. Creating agent with reasoning_effort: 'minimal'"
class MinimalReasoningAgent < RAAF::DSL::Agent
  agent_name "MinimalReasoningAgent"
  model "gpt-5"
  reasoning_effort "minimal"
  static_instructions "Cost-aware agent"
end

agent = MinimalReasoningAgent.new
puts "✓ Agent created successfully"
puts "  - Class reasoning_effort: #{MinimalReasoningAgent.reasoning_effort}"

# Test 2: Access to model_settings
puts "\n2. Checking model_settings configuration"
core_agent = agent.send(:create_openai_agent_instance)
if core_agent.model_settings
  puts "✓ model_settings created"
  puts "  - reasoning config: #{core_agent.model_settings.reasoning.inspect}"
else
  puts "✗ model_settings NOT created (expected for reasoning_effort)"
  exit 1
end

# Test 3: Agent with high reasoning_effort (symbol)
puts "\n3. Creating agent with reasoning_effort: :high (symbol)"
class HighReasoningAgent < RAAF::DSL::Agent
  agent_name "HighReasoningAgent"
  model "o1-preview"
  reasoning_effort :high  # Symbol notation
  static_instructions "Deep thinking agent"
end

agent2 = HighReasoningAgent.new
puts "✓ Agent created successfully"
puts "  - Class reasoning_effort: #{HighReasoningAgent.reasoning_effort}"

core_agent2 = agent2.send(:create_openai_agent_instance)
if core_agent2.model_settings
  puts "✓ model_settings created"
  puts "  - reasoning config: #{core_agent2.model_settings.reasoning.inspect}"
else
  puts "✗ model_settings NOT created"
  exit 1
end

# Test 4: Agent without reasoning_effort (should not create model_settings)
puts "\n4. Creating agent WITHOUT reasoning_effort"
class DefaultAgent < RAAF::DSL::Agent
  agent_name "DefaultAgent"
  model "gpt-4o"
  static_instructions "Regular agent"
end

agent3 = DefaultAgent.new
puts "✓ Agent created successfully"
puts "  - Class reasoning_effort: #{DefaultAgent.reasoning_effort.inspect}"

core_agent3 = agent3.send(:create_openai_agent_instance)
if core_agent3.model_settings.nil?
  puts "✓ model_settings correctly NOT created (no reasoning_effort configured)"
else
  puts "✗ model_settings created when it shouldn't be"
  exit 1
end

# Test 5: All effort levels
puts "\n5. Testing all reasoning effort levels"
effort_levels = ["minimal", "low", "medium", "high"]

effort_levels.each do |level|
  agent_class = Class.new(RAAF::DSL::Agent) do
    agent_name "TestAgent_#{level}"
    model "gpt-5"
    reasoning_effort level
    static_instructions "Test agent for #{level}"
  end

  test_agent = agent_class.new
  core = test_agent.send(:create_openai_agent_instance)

  if core.model_settings && core.model_settings.reasoning == { reasoning_effort: level }
    puts "  ✓ Level '#{level}' works correctly"
  else
    puts "  ✗ Level '#{level}' FAILED"
    exit 1
  end
end

puts "\n" + "=" * 60
puts "✅ All tests passed!"
puts "\nThe reasoning_effort DSL method is working correctly:"
puts "  - Accepts both string and symbol values"
puts "  - Creates model_settings with proper reasoning configuration"
puts "  - Correctly handles agents without reasoning_effort"
puts "  - Supports all effort levels: minimal, low, medium, high"
puts "\nUsage example:"
puts "  class MyCostAwareAgent < RAAF::DSL::Agent"
puts "    agent_name \"MyCostAwareAgent\""
puts "    model \"gpt-5\""
puts "    reasoning_effort \"minimal\"  # Control reasoning token costs"
puts "    static_instructions \"Answer efficiently\""
puts "  end"
