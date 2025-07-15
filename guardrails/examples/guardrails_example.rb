#!/usr/bin/env ruby
# frozen_string_literal: true

# This example demonstrates the comprehensive guardrails system in OpenAI Agents.
# Guardrails provide safety, compliance, and quality control for AI applications.
# They can validate inputs before processing, check outputs before returning them,
# and enforce business rules, security policies, and content standards.
# The Ruby implementation maintains compatibility with Python's guardrails API.

require "bundler/setup"
require "openai_agents"

# ============================================================================
# GUARDRAILS EXAMPLES
# ============================================================================

# ============================================================================
# EXAMPLE 1: BASIC INPUT/OUTPUT GUARDRAILS
# ============================================================================
# Demonstrates built-in guardrails for common safety and compliance needs.
# Input guardrails run before the AI processes the message.
# Output guardrails run after the AI generates a response but before returning it.

puts "=== Example 1: Basic Input/Output Guardrails ==="

# Create an agent with multiple guardrails for safety and compliance
safe_agent = OpenAIAgents::Agent.new(
  name: "SafeAssistant",
  instructions: "You are a helpful assistant that provides safe, appropriate responses.",
  model: "gpt-4o-mini",  # Using smaller model for faster examples
  
  # Input guardrails prevent problematic content from reaching the AI
  input_guardrails: [
    # Profanity filter - blocks offensive language
    OpenAIAgents::Guardrails.profanity_guardrail,
    
    # PII detector - prevents accidental exposure of sensitive data
    # Detects: SSN, credit cards, phone numbers, emails, etc.
    OpenAIAgents::Guardrails.pii_guardrail
  ],
  
  # Output guardrails ensure responses meet quality standards
  output_guardrails: [
    # Length limiter - prevents overly long responses
    # Useful for: chat interfaces, SMS, cost control
    OpenAIAgents::Guardrails.length_guardrail(max_length: 500)
  ]
)

runner = OpenAIAgents::Runner.new(agent: safe_agent)

# Test Case 1: Clean input passes through without issues
puts "\nTest 1: Clean input..."
begin
  result = runner.run("Hello, how can I learn Ruby programming?")
  puts "✓ Response: #{result.messages.last[:content][0..100]}...\n"
rescue => e
  puts "✗ Unexpected error: #{e.message}\n"
end

# Test Case 2: PII detection prevents data leakage
puts "Test 2: Input containing PII..."
begin
  # This will trigger the PII guardrail before reaching the AI
  result = runner.run("My SSN is 123-45-6789, can you help me?")
  puts "✗ PII guardrail failed to trigger!\n"
rescue OpenAIAgents::Guardrails::InputGuardrailTripwireTriggered => e
  puts "✓ PII Guardrail triggered successfully!"
  puts "  - Guardrail: #{e.triggered_by}"
  puts "  - Reason: #{e.message}"
  puts "  - Detected PII: #{e.metadata[:detected_pii] || 'SSN pattern'}\n"
end

puts "=" * 50

# ============================================================================
# EXAMPLE 2: CUSTOM BUSINESS LOGIC GUARDRAILS
# ============================================================================
# Shows how to create custom guardrails for business-specific rules.
# Custom guardrails can enforce any policy or requirement unique to your application.

puts "\n=== Example 2: Custom Guardrails ==="

# Custom Input Guardrail: Competitor mention detection
# Prevents users from asking about competitor products
# Useful for: customer service bots, internal tools
no_competitor_guardrail = OpenAIAgents::Guardrails.input_guardrail(name: "competitor_check") do |_context, _agent, input|
  # Define competitor names to watch for
  competitors = %w[ChatGPT Claude Gemini Copilot]
  input_text = input.to_s.downcase
  
  # Check if any competitors are mentioned
  mentioned = competitors.select { |c| input_text.include?(c.downcase) }
  
  if mentioned.any?
    # Return a tripwire result - this will block the request
    OpenAIAgents::Guardrails::GuardrailFunctionOutput.new(
      output_info: { 
        competitors_mentioned: mentioned,
        message: "Input mentions competitor products",
        suggestion: "Please ask about our products instead"
      },
      tripwire_triggered: true  # This causes an exception
    )
  else
    # Return success - request continues normally
    OpenAIAgents::Guardrails::GuardrailFunctionOutput.new(
      output_info: { checked: true, competitors_found: 0 },
      tripwire_triggered: false
    )
  end
end

# Custom Output Guardrail: Sentiment enforcement
# Ensures responses maintain a positive, helpful tone
# Useful for: customer-facing bots, brand voice consistency
sentiment_guardrail = OpenAIAgents::Guardrails.output_guardrail(name: "positive_sentiment") do |_context, _agent, output|
  # Simple sentiment check using keyword analysis
  # In production, integrate with sentiment analysis APIs like:
  # - AWS Comprehend, Google Natural Language API, Azure Text Analytics
  negative_words = %w[sorry cannot unable impossible error fail unfortunately]
  output_text = output.to_s.downcase
  
  # Count negative indicators
  negative_count = negative_words.count { |word| output_text.include?(word) }
  
  # Business rule: More than 2 negative words = too negative
  if negative_count > 2
    OpenAIAgents::Guardrails::GuardrailFunctionOutput.new(
      output_info: { 
        negative_words_count: negative_count,
        message: "Response tone is too negative",
        detected_words: negative_words.select { |w| output_text.include?(w) }
      },
      tripwire_triggered: true  # Blocks this response
    )
  else
    OpenAIAgents::Guardrails::GuardrailFunctionOutput.new(
      output_info: { 
        negative_words_count: negative_count,
        sentiment: "acceptable",
        tone: negative_count == 0 ? "positive" : "neutral"
      },
      tripwire_triggered: false  # Allows response
    )
  end
end

# Create agent and add guardrails dynamically
business_agent = OpenAIAgents::Agent.new(
  name: "BusinessAssistant",
  instructions: "You are a business assistant. Never mention competitors.",
  model: "gpt-4o-mini"
)

# Guardrails can be added after agent creation
# This allows dynamic configuration based on user roles, settings, etc.
business_agent.add_input_guardrail(no_competitor_guardrail)
business_agent.add_output_guardrail(sentiment_guardrail)

runner = OpenAIAgents::Runner.new(agent: business_agent)

# Test custom guardrails
puts "\nTest: Competitor mention detection..."
begin
  result = runner.run("How does our product compare to ChatGPT?")
  puts "✗ Competitor guardrail failed to trigger!\n"
rescue OpenAIAgents::Guardrails::InputGuardrailTripwireTriggered => e
  puts "✓ Competitor guardrail triggered!"
  puts "  - Competitors detected: #{e.metadata[:competitors_mentioned]}"
  puts "  - Suggestion: #{e.metadata[:suggestion]}\n"
end

puts "=" * 50

# ============================================================================
# EXAMPLE 3: STRUCTURED OUTPUT WITH SCHEMA VALIDATION
# ============================================================================
# Demonstrates how to ensure AI outputs match a specific data structure.
# Essential for APIs, data pipelines, and system integrations.

puts "\n=== Example 3: JSON Schema Output Validation ==="

# Define the expected output structure using JSON Schema
# This ensures the AI returns data in exactly the format we need
user_schema = {
  type: "object",
  required: %w[name age email],  # All fields are mandatory
  properties: {
    name: { 
      type: "string",
      minLength: 1,
      maxLength: 100
    },
    age: { 
      type: "integer", 
      minimum: 0,      # No negative ages
      maximum: 150     # Reasonable upper limit
    },
    email: { 
      type: "string",
      pattern: "^[\\w\\.-]+@[\\w\\.-]+\\.\\w+$"  # Basic email pattern
    }
  },
  additionalProperties: false  # No extra fields allowed
}

# Create an agent that extracts structured data
data_agent = OpenAIAgents::Agent.new(
  name: "DataAgent",
  instructions: "You extract user data and return it as JSON. Always extract name, age, and email.",
  model: "gpt-4o-mini",
  
  # response_format ensures the AI outputs valid JSON matching our schema
  # This is enforced at the model level for reliability
  response_format: {
    type: "json_schema",
    json_schema: {
      name: "user_info",
      strict: true,       # Strict mode enforces exact compliance
      schema: user_schema
    }
  },
  
  # Additional validation layer for extra safety
  output_guardrails: [
    OpenAIAgents::Guardrails.json_schema_guardrail(schema: user_schema)
  ]
)

runner = OpenAIAgents::Runner.new(agent: data_agent)

puts "\nTest: Structured data extraction..."
begin
  result = runner.run("Extract user data from: John Doe, 25 years old, john@example.com")
  
  # Parse and display the structured output
  json_output = JSON.parse(result.messages.last[:content])
  puts "✓ Successfully extracted structured data:"
  puts "  - Name: #{json_output['name']}"
  puts "  - Age: #{json_output['age']}"
  puts "  - Email: #{json_output['email']}\n"
rescue => e
  puts "✗ Failed to extract data: #{e.message}\n"
end

puts "=" * 50

# ============================================================================
# EXAMPLE 4: TOPIC RELEVANCE ENFORCEMENT
# ============================================================================
# Ensures conversations stay on-topic and within scope.
# Critical for specialized bots and preventing scope creep.

puts "\n=== Example 4: Topic Relevance Guardrail ==="

# Create a specialized agent that only handles technical topics
support_agent = OpenAIAgents::Agent.new(
  name: "TechSupport",
  instructions: "You are a technical support agent. Only answer technical questions.",
  model: "gpt-4o-mini",
  
  input_guardrails: [
    # Topic filter ensures agent only processes relevant questions
    # This prevents: off-topic questions, prompt injection, scope creep
    OpenAIAgents::Guardrails.topic_relevance_guardrail(
      allowed_topics: %w[
        software hardware technical computer programming 
        bug error crash issue problem troubleshoot
        install update configure settings network
      ],
      min_relevance_score: 0.3  # Threshold for topic matching
    )
  ]
)

runner = OpenAIAgents::Runner.new(agent: support_agent)

# Test Case 1: On-topic technical question
puts "\nTest 1: On-topic question..."
begin
  result = runner.run("How do I fix a software bug in my Python code?")
  puts "✓ On-topic question accepted"
  puts "  Response preview: #{result.messages.last[:content][0..80]}...\n"
rescue => e
  puts "✗ Unexpected rejection: #{e.message}\n"
end

# Test Case 2: Off-topic question should be blocked
puts "Test 2: Off-topic question..."
begin
  result = runner.run("What's a good recipe for chocolate cake?")
  puts "✗ Topic filter failed - off-topic question was accepted!\n"
rescue OpenAIAgents::Guardrails::InputGuardrailTripwireTriggered => e
  puts "✓ Topic filter working correctly!"
  puts "  - Reason: Question not related to allowed topics"
  puts "  - Allowed topics: technical, software, hardware, etc.\n"
end

puts "=" * 50

# ============================================================================
# EXAMPLE 5: DYNAMIC RUN-LEVEL GUARDRAILS
# ============================================================================
# Shows how to apply guardrails per-request instead of per-agent.
# Useful for: user-specific rules, A/B testing, feature flags.

puts "\n=== Example 5: Run-level Guardrails ==="

# Create a basic agent without any built-in guardrails
# This agent is flexible and guardrails are applied per-request
simple_agent = OpenAIAgents::Agent.new(
  name: "SimpleAgent",
  instructions: "You are a helpful assistant.",
  model: "gpt-4o-mini"
)

runner = OpenAIAgents::Runner.new(agent: simple_agent)

# Run with guardrails specific to this request
# These override or supplement agent-level guardrails
puts "\nTest: Dynamic guardrails per request..."
begin
  result = runner.run(
    "Tell me about Ruby programming",
    # Input guardrails for this run only
    input_guardrails: [
      OpenAIAgents::Guardrails.profanity_guardrail
    ],
    # Output guardrails for this run only
    output_guardrails: [
      # Strict length limit for this specific request
      OpenAIAgents::Guardrails.length_guardrail(max_length: 200)
    ]
  )
  
  response = result.messages.last[:content]
  puts "✓ Response generated with run-level guardrails"
  puts "  - Length: #{response.length} characters (max: 200)"
  puts "  - Preview: #{response[0..100]}...\n"
rescue => e
  puts "✗ Error: #{e.message}\n"
end

puts "=" * 50

# ============================================================================
# EXAMPLE 6: ASYNC GUARDRAILS (ADVANCED)
# ============================================================================
# Demonstrates guardrails in asynchronous contexts.
# Useful for: high-throughput applications, non-blocking I/O.

puts "\n=== Example 6: Async Guardrails ==="

if defined?(Async)
  # Create guardrail that performs async operations
  # Examples: API calls, database lookups, external validations
  async_guardrail = OpenAIAgents::Guardrails.input_guardrail(name: "async_validation") do |_context, _agent, input|
    # Simulate async operation (e.g., checking against external service)
    # In production: HTTP request, database query, cache lookup
    sleep(0.1)  # Simulate network latency
    
    # Return validation result
    OpenAIAgents::Guardrails::GuardrailFunctionOutput.new(
      output_info: { 
        async_check: true,
        validation_time_ms: 100,
        validated_at: Time.now.iso8601
      },
      tripwire_triggered: false  # Validation passed
    )
  end

  # Create async-enabled agent
  async_agent = OpenAIAgents::Async.agent(
    name: "AsyncAgent",
    instructions: "You are an async assistant with external validation.",
    model: "gpt-4o-mini",
    input_guardrails: [async_guardrail]
  )

  # Run in async context
  Async do
    runner = OpenAIAgents::Async.runner(agent: async_agent)
    result = runner.run_async("Hello from async!").wait
    puts "✓ Async response: #{result.messages.last[:content]}"
  end
else
  puts "ℹ️  Async gem not available - skipping async example"
  puts "  To enable: Add 'gem async' to your Gemfile"
end

# ============================================================================
# SUMMARY
# ============================================================================

puts "\n=== Guardrails Examples Complete! ==="
puts "\nKey Takeaways:"
puts "1. Input guardrails validate/filter before AI processing"
puts "2. Output guardrails ensure response quality and compliance"
puts "3. Custom guardrails enforce business-specific rules"
puts "4. Schema validation ensures structured data integrity"
puts "5. Run-level guardrails provide per-request flexibility"
puts "6. All guardrails support async operations"
puts "\nBest Practices:"
puts "- Layer multiple guardrails for defense in depth"
puts "- Log guardrail triggers for monitoring and improvement"
puts "- Test guardrails thoroughly with edge cases"
puts "- Consider performance impact of complex validations"
