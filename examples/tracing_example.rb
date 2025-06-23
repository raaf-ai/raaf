#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/openai_agents"

# Example demonstrating the tracing functionality
# This shows how tracing is automatically integrated with agent execution

# Ensure API key is set
unless ENV["OPENAI_API_KEY"]
  puts "ERROR: OPENAI_API_KEY environment variable is required"
  puts "Please set it with: export OPENAI_API_KEY='your-api-key'"
  exit 1
end

# Configure tracing (optional - it's enabled by default with OpenAI processor)
OpenAIAgents.configure_tracing do |config|
  # Add console processor for development
  config.add_processor(OpenAIAgents::Tracing::ConsoleSpanProcessor.new)
  
  # Add file processor to save traces
  config.add_processor(OpenAIAgents::Tracing::FileSpanProcessor.new("traces.jsonl"))
end
# Create a simple agent with a tool
agent = OpenAIAgents::Agent.new(
  name: "MathAssistant",
  instructions: "You are a helpful math assistant. Use the calculator tool for calculations.",
  model: "gpt-4"
)

# Add a calculator tool
def calculate(expression:)
  begin
    # Simple eval for demo - in production use a proper math parser
    result = eval(expression)
    "The result of #{expression} is #{result}"
  rescue => e
    "Error calculating #{expression}: #{e.message}"
  end
end

agent.add_tool(
  OpenAIAgents::FunctionTool.new(
    method(:calculate),
    name: "calculator",
    description: "Calculate a mathematical expression"
  )
)

# Create runner with tracing enabled (default)
runner = OpenAIAgents::Runner.new(agent: agent)

puts "Running agent with tracing enabled..."
puts "Watch for [SPAN START] and [SPAN END] messages"
puts "-" * 50

# Run a conversation that will use the tool
messages = [
  { role: "user", content: "What is 25 * 37 + 142?" }
]

result = runner.run(messages)

puts "-" * 50
puts "\nFinal response:"
puts result[:messages].last[:content]

# Access trace summary
tracer = OpenAIAgents.tracer
if tracer.respond_to?(:trace_summary)
  summary = tracer.trace_summary
  puts "\nTrace Summary:"
  puts "Total spans: #{summary[:total_spans]}"
  puts "Total duration: #{summary[:total_duration_ms]}ms"
  puts "Trace ID: #{summary[:trace_id]}"
end

# Example of manual tracing
puts "\n" + "-" * 50
puts "Manual tracing example:"

tracer = OpenAIAgents.tracer
tracer.span("custom_operation", type: :internal) do |span|
  span.set_attribute("operation.type", "demo")
  span.add_event("Starting custom work")
  
  # Simulate some work
  sleep(0.1)
  
  span.add_event("Work completed")
end

# Example with OpenTelemetry compatibility (if gems are installed)
begin
  require "opentelemetry/exporter/otlp"
  
  puts "\nConfiguring OpenTelemetry OTLP exporter..."
  OpenAIAgents::Tracing::OTelBridge.configure_otlp(
    endpoint: "http://localhost:4318/v1/traces"
  )
  puts "OTLP exporter configured (sending to localhost:4318)"
rescue LoadError
  puts "\nOpenTelemetry gems not installed. Skipping OTLP configuration."
  puts "To enable OTLP export, run: gem install opentelemetry-exporter-otlp"
end

# Force flush traces to ensure they're sent before exit
puts "\nFlushing traces..."
OpenAIAgents::Tracing::TraceProvider.force_flush
sleep(1) # Give time for the flush to complete

puts "\nTracing example complete!"
puts "Check 'traces.jsonl' for detailed trace data"
puts "Check https://platform.openai.com/traces for OpenAI dashboard traces"