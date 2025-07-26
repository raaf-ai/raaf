#!/usr/bin/env ruby
# frozen_string_literal: true

# Debugging Example
#
# This example demonstrates the debugging and inspection tools
# available in the RAAF DSL.

require_relative "../lib/raaf-dsl"
require "logger"

# Create a complex agent for debugging
agent = RAAF::DSL::AgentBuilder.build do
  name "DebugExampleAgent"
  instructions "You are a helpful assistant for demonstrating debugging features."
  model "gpt-4o"
  
  config do
    temperature 0.7
    max_turns 3
    timeout 30
  end
  
  tool :process_data do |data|
    { processed: data.upcase, length: data.length }
  end
  
  tool :calculate do |x, y|
    { sum: x + y, product: x * y }
  end
end

puts "=== Agent Inspection ==="

# Use the context inspector
inspector = RAAF::DSL::Debugging::ContextInspector.new
inspector.inspect_agent(agent)

puts inspector.format_report

# Use the prompt inspector
prompt_inspector = RAAF::DSL::Debugging::PromptInspector.new

# Create a test prompt for inspection
class DebugPrompt < RAAF::DSL::Prompts::Base
  required :task_name, :priority
  optional :deadline
  
  def system
    "You are managing task: #{task_name} with #{priority} priority."
  end
  
  def user
    msg = "Process this task."
    msg += " Deadline: #{deadline}" if deadline
    msg
  end
end

puts "\n=== Prompt Inspection ==="

test_prompt = DebugPrompt.new(
  task_name: "Debug Feature",
  priority: "high",
  deadline: "Tomorrow"
)

prompt_report = prompt_inspector.inspect(test_prompt)
puts prompt_inspector.format_report(prompt_report)

# Use the LLM interceptor for API call debugging
puts "\n=== LLM Call Interception ==="

interceptor = RAAF::DSL::Debugging::LLMInterceptor.new
interceptor.start

# This would normally make an API call
# For demonstration, we'll show what would be logged
puts "Interceptor is active. API calls would be logged with:"
puts "  - Request details (model, messages, tools)"
puts "  - Response data"
puts "  - Timing information"
puts "  - Token usage"

# Example of what the interceptor captures:
example_capture = {
  timestamp: Time.now,
  model: "gpt-4o",
  messages: [
    { role: "system", content: "You are a helpful assistant." },
    { role: "user", content: "Hello!" }
  ],
  response_time: 1.23,
  tokens: { prompt: 15, completion: 10, total: 25 }
}

puts "\nExample intercepted data:"
puts interceptor.format_call(example_capture)

# Debugging with detailed logging
puts "\n=== Debug Logging Example ==="

# Create a logger with debug level
logger = Logger.new(STDOUT)
logger.level = Logger::DEBUG

# Temporarily enable debug logging
original_log_level = ENV["RAAF_LOG_LEVEL"]
ENV["RAAF_LOG_LEVEL"] = "debug"

# Create another agent with logging
logged_agent = RAAF::DSL::AgentBuilder.build do
  name "LoggedAgent"
  instructions "Agent with debug logging enabled"
  model "gpt-4o"
  
  tool :debug_tool do |input|
    logger.debug "Tool called with input: #{input}"
    { result: "processed", input: input }
  end
end

puts "Created agent with debug logging enabled"
puts "Check the logs above for detailed information"

# Restore original log level
ENV["RAAF_LOG_LEVEL"] = original_log_level

# Memory debugging (if an agent uses memory features)
puts "\n=== Debugging Memory Usage ==="

memory_agent = RAAF::DSL::AgentBuilder.build do
  name "MemoryAgent"
  instructions "Agent with memory capabilities"
  
  memory(
    type: :conversation,
    max_messages: 10,
    summarize_after: 5
  )
end

puts "Memory configuration:"
puts "  Type: #{memory_agent.config[:memory][:type]}"
puts "  Max messages: #{memory_agent.config[:memory][:max_messages]}"
puts "  Summarize after: #{memory_agent.config[:memory][:summarize_after]}"

# Performance debugging
puts "\n=== Performance Monitoring ==="

require "benchmark"

# Measure agent creation time
creation_time = Benchmark.measure do
  100.times do
    RAAF::DSL::AgentBuilder.build do
      name "PerfTestAgent"
      instructions "Performance test agent"
    end
  end
end

puts "Created 100 agents in #{creation_time.real.round(3)} seconds"
puts "Average: #{(creation_time.real / 100 * 1000).round(2)}ms per agent"

# Tool execution performance
tool = agent.tools.first
execution_time = Benchmark.measure do
  1000.times do
    tool.call("test data")
  end
end

puts "\nExecuted tool 1000 times in #{execution_time.real.round(3)} seconds"
puts "Average: #{(execution_time.real / 1000 * 1000).round(2)}ms per call"

puts "\n=== Debug Tips ==="
puts "1. Set RAAF_LOG_LEVEL=debug for detailed logging"
puts "2. Use context inspector to examine agent configuration"
puts "3. Use prompt inspector to debug prompt rendering"
puts "4. Use LLM interceptor to monitor API calls"
puts "5. Add custom logging to your tools for debugging"
puts "6. Use benchmark to identify performance bottlenecks"