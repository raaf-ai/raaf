#!/usr/bin/env ruby
# frozen_string_literal: true

# This example demonstrates the comprehensive tracing capabilities of OpenAI Agents.
# Tracing provides visibility into agent execution, tool calls, and performance metrics.
# It's essential for debugging, monitoring, and optimizing agent behavior in production.
# The Ruby implementation maintains exact parity with Python's trace format for
# compatibility with OpenAI's dashboard and monitoring tools.

require_relative "../lib/openai_agents"

# ============================================================================
# TRACING EXAMPLE
# ============================================================================

# API key validation - required for OpenAI API calls and trace submission.
# Traces are automatically sent to OpenAI's monitoring dashboard where you can
# view agent performance, debug issues, and analyze usage patterns.
unless ENV["OPENAI_API_KEY"]
  puts "ERROR: OPENAI_API_KEY environment variable is required"
  puts "Please set it with: export OPENAI_API_KEY='your-api-key'"
  puts "Get your API key from: https://platform.openai.com/api-keys"
  exit 1
end

# ============================================================================
# TRACING CONFIGURATION
# ============================================================================

# Configure additional trace processors beyond the default OpenAI processor.
# The OpenAI processor is always active and sends traces to the OpenAI dashboard.
# Note: Custom processors can be added if implemented in your application.
# For example:
# - ConsoleSpanProcessor: Outputs spans to STDOUT
# - FileSpanProcessor: Saves traces to a local file
# - CustomProcessor: Send to your monitoring system
#
# Example configuration (if processors are implemented):
# OpenAIAgents.configure_tracing do |config|
#   config.add_processor(MyApp::ConsoleSpanProcessor.new)
#   config.add_processor(MyApp::FileSpanProcessor.new("traces.jsonl"))
# end
# ============================================================================
# AGENT AND TOOL SETUP
# ============================================================================

# Create an agent that will generate traceable execution spans.
# Every agent action, tool call, and response is automatically traced.
agent = OpenAIAgents::Agent.new(
  name: "MathAssistant",
  instructions: "You are a helpful math assistant. Use the calculator tool for calculations.",
  model: "gpt-4o"
)

# Calculator tool that will appear in traces.
# Each tool execution creates a span showing input, output, and timing.
# WARNING: This uses eval() for simplicity - NEVER use eval() with untrusted input!
# In production, use a proper math expression parser for security.
def calculate(expression:)
  # For demo purposes only - eval is dangerous with user input!
  # In production, use a safe math parser like:
  # - https://github.com/rubysolo/dentaku
  # - https://github.com/codegram/calculo
  result = eval(expression)
  "The result of #{expression} is #{result}"
rescue StandardError => e
  "Error calculating #{expression}: #{e.message}"
end

# Register the tool with explicit metadata.
# This metadata appears in traces, helping identify tool usage patterns.
agent.add_tool(
  OpenAIAgents::FunctionTool.new(
    method(:calculate),
    name: "calculator",
    description: "Calculate a mathematical expression"
  )
)

# ============================================================================
# TRACED EXECUTION
# ============================================================================

# Create runner - tracing is enabled by default.
# The global tracer automatically captures all agent activities.
runner = OpenAIAgents::Runner.new(agent: agent)

puts "=== Tracing Example ==="
puts "\nRunning agent with tracing enabled..."
puts "Console output will show [SPAN START] and [SPAN END] messages"
puts "These indicate the beginning and end of traced operations"
puts "-" * 50

# Execute a conversation that triggers tool usage.
# This generates a trace hierarchy:
# 1. Root agent span (parent_id: null)
# 2. Tool execution span (child of agent)
# 3. Response generation span
messages = [
  { role: "user", content: "What is 25 * 37 + 142?" }
]

# The run method automatically creates spans for:
# - Overall agent execution
# - Each tool call
# - Response generation
result = runner.run(messages)

puts "-" * 50
puts "\nFinal response:"
puts result.final_output

# ============================================================================
# TRACE ANALYSIS
# ============================================================================

# Access trace metadata for performance analysis.
# The tracer collects metrics about execution time, span count, and more.
tracer = OpenAIAgents.tracer
if tracer.respond_to?(:trace_summary)
  summary = tracer.trace_summary
  puts "\n=== Trace Summary ==="
  puts "Total spans created: #{summary[:total_spans]}"
  puts "Total execution time: #{summary[:total_duration_ms]}ms"
  puts "Trace ID: #{summary[:trace_id]}"
  puts "\nView full trace at: https://platform.openai.com/traces/#{summary[:trace_id]}"
end

# ============================================================================
# MANUAL TRACING
# ============================================================================

# Create custom spans for your own operations.
# This is useful for tracing business logic, external API calls,
# or any operation you want to monitor.
puts "\n" + ("-" * 50)
puts "\n=== Manual Tracing Example ==="

tracer = OpenAIAgents.tracer

# Create a custom span with attributes and events
tracer.span("custom_operation", type: :internal) do |span|
  # Add attributes for filtering and analysis in trace viewers
  span.set_attribute("operation.type", "demo")
  span.set_attribute("operation.category", "example")
  
  # Add events to mark important moments within the span
  span.add_event("Starting custom work")

  # Simulate some work that takes time
  sleep(0.1)
  
  # Nested spans for sub-operations
  tracer.span("sub_operation", type: :internal) do |sub_span|
    sub_span.set_attribute("parent.operation", "custom_operation")
    sleep(0.05)
  end

  span.add_event("Work completed")
end

puts "Custom span created and traced"

# ============================================================================
# OPENTELEMETRY INTEGRATION (OPTIONAL)
# ============================================================================

# OpenAI Agents supports OpenTelemetry for integration with APM tools
# like Jaeger, Zipkin, DataDog, New Relic, etc.
# This allows you to see AI agent traces alongside your other application traces.
begin
  require "opentelemetry/exporter/otlp"

  puts "\n=== OpenTelemetry Integration ==="
  puts "Configuring OTLP exporter for external trace collection..."
  
  # Configure OTLP exporter to send traces to your observability platform
  OpenAIAgents::Tracing::OTelBridge.configure_otlp(
    endpoint: "http://localhost:4318/v1/traces"  # Standard OTLP gRPC port
  )
  puts "✓ OTLP exporter configured"
  puts "  Traces will be sent to: http://localhost:4318/v1/traces"
  puts "  Compatible with: Jaeger, Zipkin, Datadog, New Relic, etc."
rescue LoadError
  puts "\n=== OpenTelemetry Integration ==="
  puts "ℹ️  OpenTelemetry gems not installed - skipping OTLP configuration"
  puts "\nTo enable OpenTelemetry integration:"
  puts "1. Add to Gemfile: gem 'opentelemetry-exporter-otlp'"
  puts "2. Run: bundle install"
  puts "3. Start your trace collector (e.g., Jaeger)"
end

# ============================================================================
# TRACE FINALIZATION
# ============================================================================

# Force flush ensures all traces are sent before the program exits.
# This is important for short-lived scripts where traces might be buffered.
puts "\n=== Finalizing Traces ==="
puts "Flushing trace buffers..."
OpenAIAgents::Tracing::TraceProvider.force_flush

# Give processors time to complete network requests
sleep(1)

puts "\n=== Tracing Example Complete! ==="
puts "\nTrace data available at:"
puts "1. OpenAI Dashboard: https://platform.openai.com/traces"
puts "2. Debug output: HTTP trace requests shown above"
puts "\nThe trace shows:"
puts "- Agent execution hierarchy (agent spans with parent_id: null)"
puts "- Tool call details with inputs/outputs"
puts "- Timing information for performance analysis"
puts "- Custom spans for business logic"
puts "- Python-compatible trace format for cross-SDK consistency"
