#!/usr/bin/env ruby
# frozen_string_literal: true

# Direct test of OpenAI trace export

unless ENV["OPENAI_API_KEY"]
  puts "ERROR: OPENAI_API_KEY is required"
  exit 1
end

ENV["OPENAI_AGENTS_TRACE_DEBUG"] = "true"

require_relative "../lib/openai_agents"
require "securerandom"

# Create a test span manually
span = OpenAIAgents::Tracing::Span.new(
  name: "test.span",
  trace_id: "trace_#{SecureRandom.hex(16)}",
  kind: :agent
)

span.set_attribute("agent.name", "TestAgent")
span.set_attribute("agent.tools", ["tool1", "tool2"])
span.set_attribute("agent.handoffs", [])
span.set_attribute("agent.output_type", "text")
span.finish

puts "Created test span:"
puts "  Trace ID: #{span.trace_id}"
puts "  Span ID: #{span.span_id}"
puts "  Name: #{span.name}"

# Create OpenAI processor directly
processor = OpenAIAgents::Tracing::OpenAIProcessor.new

puts "\nExporting span directly to OpenAI..."
processor.export([span])

puts "\nCheck https://platform.openai.com/traces for the trace"