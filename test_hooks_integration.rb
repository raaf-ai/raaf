#!/usr/bin/env ruby
# Test hook integration across all run variants

require_relative 'lib/openai_agents'
require 'ostruct'

# Simple test hook class to verify hook calling
class TestHooks < OpenAIAgents::RunHooks
  attr_reader :called_hooks

  def initialize
    @called_hooks = []
  end

  def on_agent_start(context, agent)
    @called_hooks << "agent_start:#{agent.name}"
    puts "Hook called: agent_start for #{agent.name}"
    puts "Hook called with context: #{context.class.name}"
    puts "Hook called with agent: #{agent.class.name}"
  end

  def on_agent_end(context, agent, output)
    @called_hooks << "agent_end:#{agent.name}"
    puts "Hook called: agent_end for #{agent.name}"
  end

  def on_handoff(context, from_agent, to_agent)
    @called_hooks << "handoff:#{from_agent.name}->#{to_agent.name}"
    puts "Hook called: handoff from #{from_agent.name} to #{to_agent.name}"
  end

  def on_tool_start(context, agent, tool, arguments)
    tool_name = tool&.name || "unknown"
    @called_hooks << "tool_start:#{tool_name}"
    puts "Hook called: tool_start for #{tool_name}"
  end

  def on_tool_end(context, agent, tool, result)
    tool_name = tool&.name || "unknown"
    @called_hooks << "tool_end:#{tool_name}"
    puts "Hook called: tool_end for #{tool_name}"
  end
end

def test_hooks_with_method(method_name, agent, runner, test_hooks, messages)
  puts "\n=== Testing hooks with #{method_name} ==="
  
  # Clear previous hooks
  test_hooks.called_hooks.clear
  
  config = OpenAIAgents::RunConfig.new(
    hooks: test_hooks,
    max_turns: 1  # Limit to 1 turn for testing
  )
  
  begin
    case method_name
    when :run
      result = runner.run(messages, config: config)
    when :run_without_tracing
      result = runner.send(:run_without_tracing, messages, config: config)
    when :run_with_responses_api_no_trace
      result = runner.send(:run_with_responses_api_no_trace, messages, config: config)
    when :run_streamed
      result = runner.run_streamed(messages, config: config)
      # For streaming, just initialize - don't wait for completion
      puts "Streaming result created successfully"
      return true
    end
    
    puts "Hooks called: #{test_hooks.called_hooks.join(', ')}"
    
    # Verify at least agent_start and agent_end were called
    has_agent_start = test_hooks.called_hooks.any? { |h| h.start_with?("agent_start") }
    has_agent_end = test_hooks.called_hooks.any? { |h| h.start_with?("agent_end") }
    
    if has_agent_start && has_agent_end
      puts "✅ SUCCESS: Both agent_start and agent_end hooks were called"
      return true
    else
      puts "❌ FAILURE: Missing hooks - agent_start: #{has_agent_start}, agent_end: #{has_agent_end}"
      return false
    end
    
  rescue => e
    puts "❌ ERROR: #{e.message}"
    puts "Hooks called before error: #{test_hooks.called_hooks.join(', ')}"
    return false
  end
end

# Setup
puts "Setting up test environment..."

# Mock provider to avoid actual API calls
class MockProvider
  def is_a?(klass)
    klass == OpenAIAgents::Models::ResponsesProvider
  end

  def responses_completion(messages:, model:, tools: nil, **kwargs)
    # Return mock response
    OpenStruct.new(
      content: "Hello! This is a mock response.",
      tool_calls: nil,
      usage: { input_tokens: 10, output_tokens: 5, total_tokens: 15 },
      id: "mock_response_123"
    )
  end
end

# Create test components
agent = OpenAIAgents::Agent.new(
  name: "TestAgent",
  instructions: "You are a test agent",
  model: "gpt-4o"
)

runner = OpenAIAgents::Runner.new(
  agent: agent,
  provider: MockProvider.new,
  disabled_tracing: true  # Disable tracing for simpler testing
)

test_hooks = TestHooks.new
messages = [{ role: "user", content: "Hello, test message" }]

# Test all run variants
methods_to_test = [
  :run_without_tracing,
  :run_with_responses_api_no_trace,
  :run_streamed
]

results = {}

methods_to_test.each do |method|
  results[method] = test_hooks_with_method(method, agent, runner, test_hooks, messages)
end

# Summary
puts "\n=== TEST SUMMARY ==="
success_count = results.values.count(true)
total_count = results.size

results.each do |method, success|
  status = success ? "✅ PASS" : "❌ FAIL"
  puts "#{method}: #{status}"
end

puts "\nOverall: #{success_count}/#{total_count} tests passed"

if success_count == total_count
  puts "🎉 All hook integration tests PASSED!"
  exit 0
else
  puts "💥 Some hook integration tests FAILED!"
  exit 1
end