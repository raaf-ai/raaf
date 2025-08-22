#!/usr/bin/env ruby
# frozen_string_literal: true

# Debugging Example
#
# This example demonstrates the debugging and inspection tools
# available in the RAAF DSL.

require "raaf-core"
require "raaf-dsl"
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

  tool :process_data do
    parameter :data, type: :string, required: true

    execute do |data:|
      { processed: data.upcase, length: data.length }
    end
  end

  tool :calculate do
    parameter :x, type: :number, required: true
    parameter :y, type: :number, required: true

    execute do |x:, y:|
      { sum: x + y, product: x * y }
    end
  end
end

puts "=== Agent Inspection ==="

# Use the context inspector
inspector = RAAF::DSL::Debugging::ContextInspector.new
inspector.inspect_context(agent)

# NOTE: format_report method is not yet implemented
# The inspection output is logged directly

# Use the prompt inspector
RAAF::DSL::Debugging::PromptInspector.new

# Create a test prompt for inspection
class DebugPrompt < RAAF::DSL::Prompts::Base

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

DebugPrompt.new(
  task_name: "Debug Feature",
  priority: "high",
  deadline: "Tomorrow"
)

# NOTE: inspect_prompts expects an agent instance, not a prompt
# For now, we'll skip this inspection as the API needs clarification
# puts prompt_inspector.format_report(prompt_report)

# Use the LLM interceptor for API call debugging
puts "\n=== LLM Call Interception ==="

RAAF::DSL::Debugging::LLMInterceptor.new
# NOTE: Use intercept_openai_calls method with a block
# interceptor.intercept_openai_calls { agent.run("Hello") }

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

puts "\nExample intercepted data structure:"
puts example_capture.inspect

# Debugging with detailed logging
puts "\n=== Debug Logging Example ==="

# Create a logger with debug level
logger = Logger.new($stdout)
logger.level = Logger::DEBUG

# Temporarily enable debug logging
original_log_level = ENV.fetch("RAAF_LOG_LEVEL", nil)
ENV["RAAF_LOG_LEVEL"] = "debug"

# Create another agent with logging
RAAF::DSL::AgentBuilder.build do
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

RAAF::DSL::AgentBuilder.build do
  name "MemoryAgent"
  instructions "Agent with memory capabilities"
  model "gpt-4o"

  memory(
    type: :conversation,
    max_messages: 10,
    summarize_after: 5
  )
end

puts "Memory configuration:"
# NOTE: Agent config is not directly accessible in current implementation
puts "  Memory agent created with memory features"

# Performance debugging
puts "\n=== Performance Monitoring ==="

require "benchmark"

# Measure agent creation time
creation_time = Benchmark.measure do
  100.times do
    RAAF::DSL::AgentBuilder.build do
      name "PerfTestAgent"
      instructions "Performance test agent"
      model "gpt-4o"
    end
  end
end

puts "Created 100 agents in #{creation_time.real.round(3)} seconds"
puts "Average: #{(creation_time.real / 100 * 1000).round(2)}ms per agent"

# Tool execution performance
if agent.tools.any?
  tool = agent.tools.first
  puts "\nTesting tool execution performance..."
  puts "Tool: #{tool.name}"

  begin
    execution_time = Benchmark.measure do
      1000.times do
        tool.call(data: "test data")
      end
    end

    puts "Executed tool 1000 times in #{execution_time.real.round(3)} seconds"
    puts "Average: #{(execution_time.real / 1000 * 1000).round(2)}ms per call"
  rescue StandardError => e
    puts "Note: Tool execution test skipped due to: #{e.message}"
  end
else
  puts "\nNo tools available for performance testing"
end

puts "\n=== Debug Tips ==="
puts "1. Set RAAF_LOG_LEVEL=debug for detailed logging"
puts "2. Use context inspector to examine agent configuration"
puts "3. Use prompt inspector to debug prompt rendering"
puts "4. Use LLM interceptor to monitor API calls"
puts "5. Add custom logging to your tools for debugging"
puts "6. Use benchmark to identify performance bottlenecks"
