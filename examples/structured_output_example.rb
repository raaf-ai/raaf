#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/openai_agents"

# Example demonstrating structured output and RunConfig features

unless ENV["OPENAI_API_KEY"]
  puts "ERROR: OPENAI_API_KEY environment variable is required"
  puts "Please set it with: export OPENAI_API_KEY='your-api-key'"
  exit 1
end

puts "=== Structured Output Example ==="
puts

# Define a schema for product information
product_schema = OpenAIAgents::StructuredOutput::ObjectSchema.build do
  string :name, required: true, minLength: 1
  string :description, required: true
  number :price, required: true, minimum: 0
  string :category, enum: ["electronics", "clothing", "food", "other"], required: true
  array :features, items: { type: "string" }, minItems: 1, required: true
  boolean :in_stock, required: true
end

# Create an agent with structured output
product_agent = OpenAIAgents::Agent.new(
  name: "ProductAnalyzer",
  instructions: <<~INSTRUCTIONS,
    You are a product information analyzer. When asked about a product, 
    respond ONLY with a JSON object matching the required schema.
    The schema includes: name, description, price, category, features array, and in_stock boolean.
  INSTRUCTIONS
  model: "gpt-4",
  output_schema: product_schema.to_h
)

# Create runner
runner = OpenAIAgents::Runner.new(agent: product_agent)

# Example 1: Basic structured output
puts "1. Testing basic structured output:"
messages = [{
  role: "user",
  content: "Tell me about the iPhone 15 Pro"
}]

result = runner.run(messages)
puts "Response: #{result[:messages].last[:content]}"
puts

# Example 2: Using RunConfig for customization
puts "2. Testing with RunConfig:"

config = OpenAIAgents::RunConfig.new(
  temperature: 0.3,  # Lower temperature for more consistent output
  max_tokens: 500,
  trace_include_sensitive_data: false,  # Redact sensitive data in traces
  metadata: { example: "structured_output" }
)

messages2 = [{
  role: "user",
  content: "Describe a Tesla Model 3"
}]

result2 = runner.run(messages2, config: config)
puts "Response: #{result2[:messages].last[:content]}"
puts

# Example 3: Agent with tools and structured output
puts "3. Testing agent with tools:"

# Add a price lookup tool
def lookup_price(product_name:)
  # Simulated price lookup
  prices = {
    "macbook pro" => 2499.99,
    "airpods pro" => 249.99,
    "ipad air" => 599.99
  }
  
  price = prices[product_name.downcase] || 999.99
  "The current price for #{product_name} is $#{price}"
end

smart_agent = OpenAIAgents::Agent.new(
  name: "SmartProductAgent",
  instructions: <<~INSTRUCTIONS,
    You are a smart product analyzer. Use the price lookup tool to get accurate prices.
    Always respond with a JSON object matching the product schema.
  INSTRUCTIONS
  model: "gpt-4",
  output_schema: product_schema.to_h
)

smart_agent.add_tool(
  OpenAIAgents::FunctionTool.new(
    method(:lookup_price),
    name: "lookup_price",
    description: "Look up the current price for a product"
  )
)

runner2 = OpenAIAgents::Runner.new(agent: smart_agent)

messages3 = [{
  role: "user",
  content: "Tell me about the MacBook Pro with current pricing"
}]

# Use config that shows tool calls but redacts sensitive data
config2 = OpenAIAgents::RunConfig.new(
  trace_include_sensitive_data: false,
  workflow_name: "Product Analysis Workflow"
)

result3 = runner2.run(messages3, config: config2)
puts "Response: #{result3[:messages].last[:content]}"
puts

# Example 4: Invalid output handling
puts "4. Testing invalid output handling:"

# Create an agent that might produce invalid output
unreliable_agent = OpenAIAgents::Agent.new(
  name: "UnreliableAgent",
  instructions: "You sometimes make mistakes with JSON formatting.",
  model: "gpt-4",
  output_schema: product_schema.to_h
)

runner3 = OpenAIAgents::Runner.new(agent: unreliable_agent)

messages4 = [{
  role: "user",
  content: "Quick, tell me about any product but make the response very brief"
}]

result4 = runner3.run(messages4)
puts "Response: #{result4[:messages].last[:content]}"
puts

puts "=== Example Complete ==="

# Force flush traces
OpenAIAgents::Tracing::TraceProvider.force_flush if defined?(OpenAIAgents::Tracing::TraceProvider)