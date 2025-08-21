#!/usr/bin/env ruby
# frozen_string_literal: true

# Test script for the new execution_timeout DSL feature

require_relative 'lib/raaf/dsl/agent'

# Create a test agent that takes too long
class SlowAgent < RAAF::DSL::Agent
  agent_name "SlowAgent"
  execution_timeout 3  # 3 second timeout
  model "gpt-4o"
  static_instructions "You are a slow agent for testing timeouts"
  
  private
  
  # Override direct_run to simulate slow execution
  def direct_run(context: nil, input_context_variables: nil, stop_checker: nil)
    puts "Starting slow operation..."
    sleep(5)  # Sleep for 5 seconds (longer than 3 second timeout)
    { success: true, message: "This should not be reached due to timeout" }
  end
end

# Create a fast agent with timeout
class FastAgent < RAAF::DSL::Agent
  agent_name "FastAgent"
  execution_timeout 10  # 10 second timeout
  model "gpt-4o"
  static_instructions "You are a fast agent for testing timeouts"
  
  private
  
  def direct_run(context: nil, input_context_variables: nil, stop_checker: nil)
    puts "Starting fast operation..."
    sleep(1)  # Sleep for 1 second (well under timeout)
    { success: true, message: "Fast operation completed successfully" }
  end
end

# Create an agent without timeout
class NoTimeoutAgent < RAAF::DSL::Agent
  agent_name "NoTimeoutAgent"
  model "gpt-4o"
  static_instructions "You are an agent without timeout"
  
  private
  
  def direct_run(context: nil, input_context_variables: nil, stop_checker: nil)
    puts "Starting operation without timeout..."
    sleep(2)
    { success: true, message: "Operation completed without timeout" }
  end
end

def test_execution_timeout
  puts "=== Testing execution_timeout DSL feature ==="
  
  context = RAAF::DSL::ContextVariables.new({ test: "data" }, debug: true)
  
  # Test 1: Agent with timeout that should timeout
  puts "\n1. Testing SlowAgent (should timeout after 3 seconds):"
  slow_agent = SlowAgent.new(context: context)
  
  # Verify the timeout is configured
  puts "   Configured timeout: #{SlowAgent.execution_timeout} seconds"
  
  start_time = Time.now
  result = slow_agent.run
  end_time = Time.now
  
  puts "   Execution time: #{(end_time - start_time).round(2)} seconds"
  puts "   Result: #{result.inspect}"
  puts "   Success: #{result[:success] ? 'YES' : 'NO'}"
  puts "   Error type: #{result[:error_type]}" if result[:error_type]
  
  # Test 2: Agent with timeout that should complete successfully
  puts "\n2. Testing FastAgent (should complete within 10 seconds):"
  fast_agent = FastAgent.new(context: context)
  
  puts "   Configured timeout: #{FastAgent.execution_timeout} seconds"
  
  start_time = Time.now
  result = fast_agent.run
  end_time = Time.now
  
  puts "   Execution time: #{(end_time - start_time).round(2)} seconds"
  puts "   Result: #{result.inspect}"
  puts "   Success: #{result[:success] ? 'YES' : 'NO'}"
  
  # Test 3: Agent without timeout
  puts "\n3. Testing NoTimeoutAgent (no timeout configured):"
  no_timeout_agent = NoTimeoutAgent.new(context: context)
  
  puts "   Configured timeout: #{NoTimeoutAgent.execution_timeout || 'None'}"
  
  start_time = Time.now
  result = no_timeout_agent.run
  end_time = Time.now
  
  puts "   Execution time: #{(end_time - start_time).round(2)} seconds"
  puts "   Result: #{result.inspect}"
  puts "   Success: #{result[:success] ? 'YES' : 'NO'}"
  
  puts "\n=== Test completed ==="
end

if __FILE__ == $0
  test_execution_timeout
end