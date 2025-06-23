#!/usr/bin/env ruby

require_relative "lib/openai_agents"
require "logger"

# Enable debug tracing
ENV["OPENAI_AGENTS_TRACE_DEBUG"] = "true"

# Create a simple agent with tracing
agent = OpenAIAgents::Agent.new(
  name: "TestAgent",
  instructions: "You are a helpful assistant.",
  model: "gpt-4"
)

# Add a simple tool
def get_time
  Time.now.strftime("%Y-%m-%d %H:%M:%S")
end

agent.add_tool(method(:get_time))

# Set up tracing with OpenAI processor
tracer = OpenAIAgents::Tracing::SpanTracer.new
openai_processor = OpenAIAgents::Tracing::OpenAIProcessor.new(
  workflow_name: "header-test-workflow"
)
tracer.add_processor(openai_processor)

# Create runner with tracer
runner = OpenAIAgents::Runner.new(agent: agent, tracer: tracer)

puts "Testing OpenAI traces API with updated headers..."
puts "=" * 80
puts "Note: The key difference from the Python SDK is that we do NOT set a User-Agent header"
puts "=" * 80
puts

begin
  # Run a simple conversation
  result = runner.run(messages: [
    { role: "user", content: "What time is it?" }
  ])
  
  puts "\nAgent response: #{result.messages.last[:content]}"
  
  # Force flush to ensure traces are sent
  tracer.force_flush
  
  puts "\n" + "=" * 80
  puts "Test complete. Check the debug output above for HTTP headers."
  puts "The request should NOT include a User-Agent header."
  puts "=" * 80
rescue => e
  puts "Error: #{e.message}"
  puts e.backtrace.first(5).join("\n")
end