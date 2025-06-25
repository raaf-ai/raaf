#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "openai_agents"

# Example demonstrating enhanced guardrails matching Python SDK

# 1. Basic Guardrails Example
puts "=== Example 1: Basic Input/Output Guardrails ==="

# Create an agent with built-in guardrails
safe_agent = OpenAIAgents::Agent.new(
  name: "SafeAssistant",
  instructions: "You are a helpful assistant that provides safe, appropriate responses.",
  model: "gpt-4o-mini",
  input_guardrails: [
    # Check for profanity
    OpenAIAgents::Guardrails.profanity_guardrail,
    # Check for PII
    OpenAIAgents::Guardrails.pii_guardrail
  ],
  output_guardrails: [
    # Limit response length
    OpenAIAgents::Guardrails.length_guardrail(max_length: 500)
  ]
)

runner = OpenAIAgents::Runner.new(agent: safe_agent)

# Test with clean input
puts "Testing with clean input..."
result = runner.run("Hello, how can I learn Ruby programming?")
puts "Response: #{result.messages.last[:content]}\n\n"

# Test with problematic input (will trigger guardrail)
puts "Testing with PII input..."
begin
  result = runner.run("My SSN is 123-45-6789, can you help me?")
rescue OpenAIAgents::Guardrails::InputGuardrailTripwireTriggered => e
  puts "Guardrail triggered: #{e.message}"
  puts "Triggered by: #{e.triggered_by}"
  puts "Metadata: #{e.metadata.inspect}\n\n"
end

puts "=" * 50

# 2. Custom Guardrails Example
puts "\n=== Example 2: Custom Guardrails ==="

# Create custom input guardrail
no_competitor_guardrail = OpenAIAgents::Guardrails.input_guardrail(name: "competitor_check") do |_context, _agent, input|
  competitors = %w[ChatGPT Claude Gemini Copilot]
  input_text = input.to_s.downcase
  
  mentioned = competitors.select { |c| input_text.include?(c.downcase) }
  
  if mentioned.any?
    OpenAIAgents::Guardrails::GuardrailFunctionOutput.new(
      output_info: { 
        competitors_mentioned: mentioned,
        message: "Input mentions competitor products"
      },
      tripwire_triggered: true
    )
  else
    OpenAIAgents::Guardrails::GuardrailFunctionOutput.new(
      output_info: { checked: true },
      tripwire_triggered: false
    )
  end
end

# Create custom output guardrail
sentiment_guardrail = OpenAIAgents::Guardrails.output_guardrail(name: "positive_sentiment") do |_context, _agent, output|
  # Simple sentiment check (in production, use proper sentiment analysis)
  negative_words = %w[sorry cannot unable impossible error fail]
  output_text = output.to_s.downcase
  
  negative_count = negative_words.count { |word| output_text.include?(word) }
  
  if negative_count > 2
    OpenAIAgents::Guardrails::GuardrailFunctionOutput.new(
      output_info: { 
        negative_words_count: negative_count,
        message: "Response is too negative"
      },
      tripwire_triggered: true
    )
  else
    OpenAIAgents::Guardrails::GuardrailFunctionOutput.new(
      output_info: { 
        negative_words_count: negative_count,
        sentiment: "acceptable"
      },
      tripwire_triggered: false
    )
  end
end

business_agent = OpenAIAgents::Agent.new(
  name: "BusinessAssistant",
  instructions: "You are a business assistant. Never mention competitors.",
  model: "gpt-4o-mini"
)

# Add guardrails after creation
business_agent.add_input_guardrail(no_competitor_guardrail)
business_agent.add_output_guardrail(sentiment_guardrail)

runner = OpenAIAgents::Runner.new(agent: business_agent)

# Test custom guardrails
puts "Testing competitor mention..."
begin
  result = runner.run("How does our product compare to ChatGPT?")
rescue OpenAIAgents::Guardrails::InputGuardrailTripwireTriggered => e
  puts "Custom guardrail triggered: #{e.message}"
  puts "Details: #{e.metadata.inspect}\n\n"
end

puts "=" * 50

# 3. JSON Schema Validation Guardrail
puts "\n=== Example 3: JSON Schema Output Validation ==="

# Define expected output schema
user_schema = {
  type: "object",
  required: %w[name age email],
  properties: {
    name: { type: "string" },
    age: { type: "integer", minimum: 0, maximum: 150 },
    email: { type: "string" }
  }
}

data_agent = OpenAIAgents::Agent.new(
  name: "DataAgent",
  instructions: "You extract user data and return it as JSON.",
  model: "gpt-4o-mini",
  output_schema: user_schema, # This ensures structured output
  output_guardrails: [
    OpenAIAgents::Guardrails.json_schema_guardrail(schema: user_schema)
  ]
)

runner = OpenAIAgents::Runner.new(agent: data_agent)

result = runner.run("Extract user data from: John Doe, 25 years old, john@example.com")
puts "Structured output: #{result.messages.last[:content]}\n\n"

puts "=" * 50

# 4. Topic Relevance Guardrail
puts "\n=== Example 4: Topic Relevance Guardrail ==="

support_agent = OpenAIAgents::Agent.new(
  name: "TechSupport",
  instructions: "You are a technical support agent. Only answer technical questions.",
  model: "gpt-4o-mini",
  input_guardrails: [
    OpenAIAgents::Guardrails.topic_relevance_guardrail(
      allowed_topics: %w[software hardware technical computer programming bug error]
    )
  ]
)

runner = OpenAIAgents::Runner.new(agent: support_agent)

# On-topic question
puts "On-topic question..."
result = runner.run("How do I fix a software bug?")
puts "Response: #{result.messages.last[:content][0..100]}...\n\n"

# Off-topic question
puts "Off-topic question..."
begin
  result = runner.run("What's a good recipe for chocolate cake?")
rescue OpenAIAgents::Guardrails::InputGuardrailTripwireTriggered => e
  puts "Topic guardrail triggered: #{e.message}"
  puts "Details: #{e.metadata.inspect}\n\n"
end

puts "=" * 50

# 5. Run-level Guardrails
puts "\n=== Example 5: Run-level Guardrails ==="

# Create a simple agent without guardrails
simple_agent = OpenAIAgents::Agent.new(
  name: "SimpleAgent",
  instructions: "You are a helpful assistant.",
  model: "gpt-4o-mini"
)

# Add guardrails at run-time
runner = OpenAIAgents::Runner.new(agent: simple_agent)

# Run with specific guardrails for this execution only
result = runner.run(
  "Tell me about Ruby programming",
  input_guardrails: [
    OpenAIAgents::Guardrails.profanity_guardrail
  ],
  output_guardrails: [
    OpenAIAgents::Guardrails.length_guardrail(max_length: 200)
  ]
)

puts "Response with run-level guardrails: #{result.messages.last[:content]}\n\n"

puts "=" * 50

# 6. Async Guardrails Example
puts "\n=== Example 6: Async Guardrails (if async is available) ==="

if defined?(Async)
  # Create async-compatible guardrail
  async_guardrail = OpenAIAgents::Guardrails.input_guardrail(name: "async_check") do |_context, _agent, _input|
    # Simulate async operation
    sleep(0.1)
    OpenAIAgents::Guardrails::GuardrailFunctionOutput.new(
      output_info: { async_check: true },
      tripwire_triggered: false
    )
  end

  async_agent = OpenAIAgents::Async.agent(
    name: "AsyncAgent",
    instructions: "You are an async assistant.",
    model: "gpt-4o-mini",
    input_guardrails: [async_guardrail]
  )

  Async do
    runner = OpenAIAgents::Async.runner(agent: async_agent)
    result = runner.run_async("Hello from async!").wait
    puts "Async response: #{result.messages.last[:content]}"
  end
else
  puts "Async gem not available, skipping async example"
end

puts "\n=== Guardrails Examples Complete ==="
