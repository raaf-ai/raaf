#!/usr/bin/env ruby
# frozen_string_literal: true

# Simple test to verify traces are being sent to OpenAI

unless ENV["OPENAI_API_KEY"]
  puts "ERROR: OPENAI_API_KEY is required"
  exit 1
end

# Enable debug mode and force small batch (must be before require)
ENV["OPENAI_AGENTS_TRACE_DEBUG"] = "true"
ENV["OPENAI_AGENTS_TRACE_BATCH_SIZE"] = "1"  # Force immediate export
ENV["OPENAI_AGENTS_TRACE_FLUSH_INTERVAL"] = "0.5"  # Quick flush

require_relative "../lib/openai_agents"

puts "Testing OpenAI trace export..."
puts "API Key: #{ENV["OPENAI_API_KEY"][0..10]}..."
puts "-" * 50

# Get the tracer
tracer = OpenAIAgents.tracer

# Create a simple trace
tracer.agent_span("TestAgent") do |agent_span|
  agent_span.set_attribute("test", "true")
  agent_span.set_attribute("agent.name", "TestAgent")
  agent_span.set_attribute("agent.tools", ["tool1", "tool2"])
  agent_span.set_attribute("agent.handoffs", [])
  agent_span.set_attribute("agent.output_type", "text")
  
  puts "Created test span"
  sleep(0.1) # Simulate some work
end

puts "\nForcing flush..."
OpenAIAgents::Tracing::TraceProvider.force_flush

puts "\nWaiting for traces to be sent..."
sleep(2)

puts "\nTest complete. Check https://platform.openai.com/traces"