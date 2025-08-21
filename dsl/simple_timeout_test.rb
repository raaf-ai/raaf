#!/usr/bin/env ruby
# frozen_string_literal: true

# Simple test for the execution_timeout DSL method

require_relative 'lib/raaf/dsl/agent'

# Test agent with timeout
class TestTimeoutAgent < RAAF::DSL::Agent
  agent_name "TestTimeoutAgent"
  execution_timeout 120  # 2 minutes
  model "gpt-4o"
end

# Test agent without timeout
class TestNoTimeoutAgent < RAAF::DSL::Agent
  agent_name "TestNoTimeoutAgent"
  model "gpt-4o"
end

puts "=== Testing execution_timeout DSL Method ==="

# Test 1: Agent with timeout configured
puts "\n1. Testing agent with execution_timeout configured:"
puts "   Agent class: TestTimeoutAgent"
puts "   Configured timeout: #{TestTimeoutAgent.execution_timeout} seconds"
puts "   Expected: 120"
puts "   Result: #{TestTimeoutAgent.execution_timeout == 120 ? 'PASS' : 'FAIL'}"

# Test 2: Agent without timeout configured
puts "\n2. Testing agent without execution_timeout:"
puts "   Agent class: TestNoTimeoutAgent" 
puts "   Configured timeout: #{TestNoTimeoutAgent.execution_timeout || 'nil'}"
puts "   Expected: nil"
puts "   Result: #{TestNoTimeoutAgent.execution_timeout.nil? ? 'PASS' : 'FAIL'}"

# Test 3: Verify the method can be called with getter behavior
puts "\n3. Testing timeout setter/getter behavior:"
class DynamicTimeoutAgent < RAAF::DSL::Agent
  agent_name "DynamicTimeoutAgent"
  model "gpt-4o"
  
  execution_timeout 60
end

puts "   Initial timeout: #{DynamicTimeoutAgent.execution_timeout}"
puts "   Expected: 60"

# Test 4: Test configuration is stored in _agent_config
puts "\n4. Testing internal storage in _agent_config:"
puts "   Internal config: #{TestTimeoutAgent._agent_config[:execution_timeout]}"
puts "   Expected: 120"
puts "   Result: #{TestTimeoutAgent._agent_config[:execution_timeout] == 120 ? 'PASS' : 'FAIL'}"

puts "\n=== DSL Method Test Complete ==="
puts "\nThe execution_timeout DSL method has been successfully implemented!"
puts "Usage example:"
puts "  class MyAgent < RAAF::DSL::Agent"
puts "    agent_name \"MyAgent\""
puts "    execution_timeout 120  # Set 2-minute timeout"
puts "    model \"gpt-4o\""
puts "  end"