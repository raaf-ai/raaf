#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/openai_agents"

# Example demonstrating structured output with both modern and legacy approaches
# Shows response_format (recommended) and output_schema (legacy) methods

unless ENV["OPENAI_API_KEY"]
  puts "ERROR: OPENAI_API_KEY environment variable is required"
  puts "Please set it with: export OPENAI_API_KEY='your-api-key'"
  exit 1
end

puts "=== OpenAI Agents Ruby - Structured Output Example ==="
puts "Demonstrates both modern response_format and legacy output_schema approaches"
puts

# Define a schema for product information
product_schema = OpenAIAgents::StructuredOutput::ObjectSchema.build do
  string :name, required: true, minLength: 1
  string :description, required: true
  number :price, required: true, minimum: 0
  string :category, enum: %w[electronics clothing food other], required: true
  array :features, items: { type: "string" }, minItems: 1, required: true
  boolean :in_stock, required: true
end

# Modern approach using response_format (RECOMMENDED)
modern_agent = OpenAIAgents::Agent.new(
  name: "ModernProductAnalyzer",
  instructions: <<~INSTRUCTIONS,
    You are a product information analyzer. Extract product information from user input
    and return it as a JSON object that exactly matches the provided schema.
    
    Be accurate with pricing information and categorize products appropriately.
    If you don't know specific details, make reasonable estimates.
  INSTRUCTIONS
  model: "gpt-4o",
  response_format: {
    type: "json_schema",
    json_schema: {
      name: "product_info",
      strict: true,
      schema: product_schema.to_h
    }
  }
)

# Legacy approach using output_schema (still supported)
legacy_agent = OpenAIAgents::Agent.new(
  name: "LegacyProductAnalyzer",
  instructions: <<~INSTRUCTIONS,
    You are a product information analyzer. Extract product information from user input
    and return it as a JSON object that exactly matches the provided schema.
    
    Be accurate with pricing information and categorize products appropriately.
    If you don't know specific details, make reasonable estimates.
  INSTRUCTIONS
  model: "gpt-4o",
  output_schema: product_schema.to_h
)

puts "Schema enforced by both agents:"
puts JSON.pretty_generate(product_schema.to_h)
puts

# Create runners for both approaches
modern_runner = OpenAIAgents::Runner.new(agent: modern_agent)
legacy_runner = OpenAIAgents::Runner.new(agent: legacy_agent)

# Example 1: Modern response_format approach
puts "1. Testing modern response_format approach:"
puts "Input: 'Tell me about the iPhone 15 Pro'"

result = modern_runner.run([{
                      role: "user",
                      content: "Tell me about the iPhone 15 Pro"
                    }])

response_content = result.messages.last[:content]
puts "✅ Raw JSON response: #{response_content}"

# Parse and validate the response
begin
  parsed_product = JSON.parse(response_content)
  puts "✅ Successfully parsed JSON"
  
  # Validate against our schema
  validator = OpenAIAgents::StructuredOutput::BaseSchema.new(product_schema.to_h)
  validated_product = validator.validate(parsed_product)
  puts "✅ Schema validation passed"
  
  puts "📱 Product Details:"
  puts "   Name: #{validated_product['name']}"
  puts "   Price: $#{validated_product['price']}"
  puts "   Category: #{validated_product['category']}"
  puts "   In Stock: #{validated_product['in_stock'] ? 'Yes' : 'No'}"
  puts "   Features: #{validated_product['features'].join(', ')}"
  
rescue JSON::ParserError => e
  puts "❌ JSON parsing failed: #{e.message}"
rescue OpenAIAgents::StructuredOutput::ValidationError => e
  puts "❌ Schema validation failed: #{e.message}"
end
puts

# Example 2: Legacy output_schema approach (for comparison)
puts "2. Testing legacy output_schema approach:"
puts "Input: 'Tell me about the MacBook Air'"

legacy_result = legacy_runner.run([{
                      role: "user",
                      content: "Tell me about the MacBook Air"
                    }])

legacy_content = legacy_result.messages.last[:content]
puts "✅ Legacy approach JSON: #{legacy_content}"

begin
  legacy_parsed = JSON.parse(legacy_content)
  puts "✅ Legacy approach also works! Both produce same structure."
  puts "📱 Legacy Product: #{legacy_parsed['name']} - $#{legacy_parsed['price']}"
rescue => e
  puts "❌ Legacy parsing failed: #{e.message}"
end
puts

# Example 3: Cross-provider compatibility
puts "3. Testing cross-provider compatibility:"
puts "Modern response_format works with ALL providers!"

# Test with different providers if available
if ENV['ANTHROPIC_API_KEY']
  puts "\n🧠 Testing with Anthropic provider:"
  anthropic_provider = OpenAIAgents::Models::AnthropicProvider.new
  anthropic_agent = OpenAIAgents::Agent.new(
    name: "AnthropicAnalyzer",
    instructions: modern_agent.instructions,
    model: "claude-3-5-sonnet-20241022",
    response_format: modern_agent.response_format
  )
  anthropic_runner = OpenAIAgents::Runner.new(agent: anthropic_agent, provider: anthropic_provider)
  
  begin
    anthropic_result = anthropic_runner.run([{ role: "user", content: "Tell me about AirPods Pro" }])
    anthropic_content = anthropic_result.messages.last[:content]
    puts "✅ Anthropic JSON: #{anthropic_content}"
    
    anthropic_parsed = JSON.parse(anthropic_content)
    puts "✅ Same schema works with Anthropic! Product: #{anthropic_parsed['name']}"
  rescue => e
    puts "⚠️  Anthropic test failed: #{e.message}"
  end
else
  puts "⚠️  Set ANTHROPIC_API_KEY to test Anthropic compatibility"
end

if ENV['COHERE_API_KEY']
  puts "\n🤖 Testing with Cohere provider:"
  cohere_provider = OpenAIAgents::Models::CohereProvider.new
  cohere_agent = OpenAIAgents::Agent.new(
    name: "CohereAnalyzer",
    instructions: modern_agent.instructions,
    model: "command-r",
    response_format: modern_agent.response_format
  )
  cohere_runner = OpenAIAgents::Runner.new(agent: cohere_agent, provider: cohere_provider)
  
  begin
    cohere_result = cohere_runner.run([{ role: "user", content: "Tell me about Tesla Model 3" }])
    cohere_content = cohere_result.messages.last[:content]
    puts "✅ Cohere JSON: #{cohere_content}"
    
    cohere_parsed = JSON.parse(cohere_content)
    puts "✅ Same schema works with Cohere! Product: #{cohere_parsed['name']}"
  rescue => e
    puts "⚠️  Cohere test failed: #{e.message}"
  end
else
  puts "⚠️  Set COHERE_API_KEY to test Cohere compatibility"
end
puts

# Example 4: Using RunConfig for customization
puts "4. Testing with RunConfig customization:"

config = OpenAIAgents::RunConfig.new(
  temperature: 0.3, # Lower temperature for more consistent output
  max_tokens: 500,
  trace_include_sensitive_data: false, # Redact sensitive data in traces
  metadata: { example: "structured_output" }
)

messages2 = [{
  role: "user",
  content: "Describe a Tesla Model 3"
}]

result2 = modern_runner.run(messages2, config: config)
puts "Response: #{result2.messages.last[:content]}"
puts

# Example 5: Agent with tools and structured output
puts "5. Testing agent with tools and modern response_format:"

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
  model: "gpt-4o",
  response_format: {
    type: "json_schema",
    json_schema: {
      name: "product_info",
      strict: true,
      schema: product_schema.to_h
    }
  }
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
puts "Response: #{result3.messages.last[:content]}"
puts

# Example 4: Invalid output handling
puts "4. Testing invalid output handling:"

# Create an agent that might produce invalid output
unreliable_agent = OpenAIAgents::Agent.new(
  name: "UnreliableAgent",
  instructions: "You sometimes make mistakes with JSON formatting.",
  model: "gpt-4o",
  output_schema: product_schema.to_h
)

runner3 = OpenAIAgents::Runner.new(agent: unreliable_agent)

messages4 = [{
  role: "user",
  content: "Quick, tell me about any product but make the response very brief"
}]

result4 = runner3.run(messages4)
puts "Response: #{result4.messages.last[:content]}"
puts

puts "\n=== Summary of Structured Output Approaches ==="
puts "\n🎯 Modern response_format (RECOMMENDED):"
puts "• Works with ALL providers (OpenAI, Anthropic, Cohere, Groq, etc.)"
puts "• Uses OpenAI-standard format for easy migration"
puts "• Automatic provider-specific adaptations"
puts "• Future-proof and actively maintained"
puts "• Better error handling and validation"

puts "\n📜 Legacy output_schema (DEPRECATED):"
puts "• Still works for backward compatibility"
puts "• Limited to specific providers"
puts "• Will be phased out in future versions"
puts "• Migrate to response_format when possible"

puts "\n🛣️ Migration Guide:"
puts "OLD: output_schema: { type: 'object', properties: {...} }"
puts "NEW: response_format: { type: 'json_schema', json_schema: { name: 'schema_name', strict: true, schema: {...} } }"

puts "\n🎆 Provider Compatibility Matrix:"
puts "✓ OpenAI: Native JSON schema support"
puts "✓ Groq: Direct response_format passthrough"
puts "✓ Anthropic: Enhanced system prompts with schema"
puts "✓ Cohere: JSON object mode + schema instructions"
puts "✓ Others: Intelligent prompt enhancement"

puts "\n=== Example Complete ==="
puts "Try setting ANTHROPIC_API_KEY or COHERE_API_KEY to test cross-provider compatibility!"
