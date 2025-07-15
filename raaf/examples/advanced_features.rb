#!/usr/bin/env ruby
# frozen_string_literal: true

require "raaf"

##
# Advanced RAAF Features Example
#
# This example demonstrates advanced features including:
# - Tracing and monitoring
# - Guardrails
# - Memory management
# - Streaming responses
#

puts "=== Advanced RAAF Features Example ==="
puts

# 1. Set up tracing
puts "Setting up tracing..."
tracer = RubyAIAgentsFactory::Tracing::SpanTracer.new
tracer.add_processor(RubyAIAgentsFactory::Tracing::ConsoleProcessor.new)

# 2. Set up guardrails
puts "Setting up guardrails..."
input_guardrail = RubyAIAgentsFactory::Guardrails::InputGuardrail.new do |input|
  # Reject inputs that are too long
  if input.length > 500
    { allowed: false, reason: "Input too long" }
  else
    { allowed: true }
  end
end

output_guardrail = RubyAIAgentsFactory::Guardrails::OutputGuardrail.new do |output|
  # Reject outputs containing sensitive information
  if output.downcase.include?("password") || output.downcase.include?("secret")
    { allowed: false, reason: "Contains sensitive information" }
  else
    { allowed: true }
  end
end

# 3. Set up memory
puts "Setting up memory..."
memory = RubyAIAgentsFactory::Memory::InMemoryStore.new

# 4. Create advanced agent
agent = RubyAIAgentsFactory::Agent.new(
  name: "AdvancedAssistant",
  instructions: "You are an advanced AI assistant with comprehensive capabilities.",
  model: "gpt-4o",
  guardrails: [input_guardrail, output_guardrail],
  memory: memory
)

puts "Created advanced agent: #{agent.name}"
puts "Features enabled: tracing, guardrails, memory"
puts

# 5. Create runner with advanced features
runner = RubyAIAgentsFactory::Runner.new(
  agent: agent,
  tracer: tracer,
  context_config: RubyAIAgentsFactory::ContextConfig.new(
    max_context_length: 4000,
    context_management_strategy: :sliding_window
  )
)

# 6. Test advanced features
puts "Testing advanced features..."
puts

# Test 1: Normal conversation with tracing
puts "Test 1: Normal conversation with tracing"
result = runner.run("Explain the concept of machine learning in simple terms.")
puts "Response: #{result.messages.last[:content]}"
puts

# Test 2: Input guardrail (should pass)
puts "Test 2: Input guardrail (normal input)"
result = runner.run("What is the capital of France?")
puts "Response: #{result.messages.last[:content]}"
puts

# Test 3: Memory usage
puts "Test 3: Memory usage"
result = runner.run("Remember that my favorite color is blue.")
puts "Response: #{result.messages.last[:content]}"

result = runner.run("What's my favorite color?")
puts "Response: #{result.messages.last[:content]}"
puts

# Test 4: Show memory contents
puts "Test 4: Memory contents"
puts "Memory entries: #{memory.size}"
puts

# Test 5: Configuration
puts "Test 5: Global configuration"
RubyAIAgentsFactory.configure do |config|
  config.default_model = "gpt-4o"
  config.tracing_enabled = true
  config.log_level = :debug
end

puts "Default model: #{RubyAIAgentsFactory.configuration.default_model}"
puts "Tracing enabled: #{RubyAIAgentsFactory.configuration.tracing_enabled}"
puts

puts "=== Example Complete ==="