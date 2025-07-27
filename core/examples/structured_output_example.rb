#!/usr/bin/env ruby
# frozen_string_literal: true

# This example demonstrates structured output in RAAF (Ruby AI Agents Factory).
# Structured output ensures AI responses match specific data formats,
# essential for building reliable applications that parse AI-generated data.
# The Ruby implementation uses response_format for universal provider support,
# matching OpenAI's standard while adapting to other providers automatically.

require "raaf-core"

# ============================================================================
# STRUCTURED OUTPUT EXAMPLES
# ============================================================================

# API key validation - structured output requires a valid OpenAI API key
# The response_format feature is a paid API feature
return if ENV["OPENAI_API_KEY"] && !ENV["OPENAI_API_KEY"].empty?

puts "⚠️  OPENAI_API_KEY environment variable is required for full execution"
puts "Demonstrating schema creation without API calls..."
puts "Set API key with: export OPENAI_API_KEY='your-api-key'"
puts "Get your API key from: https://platform.openai.com/api-keys"
puts

puts "=== RAAF (Ruby AI Agents Factory) - Structured Output Example ==="
puts "Demonstrates modern response_format approach for universal structured output"
puts

# ============================================================================
# SCHEMA DEFINITION
# ============================================================================
# Define a JSON Schema for product information using Ruby DSL.
# This schema enforces data structure, types, and validation rules.
# The DSL provides a clean, readable way to define complex schemas.

product_schema = RAAF::StructuredOutput::ObjectSchema.build do
  # String field with minimum length validation
  # required: true means this field must be present in the output
  string :name, required: true, minLength: 1

  # Basic required string field for product description
  string :description, required: true

  # Number field with minimum value constraint
  # Ensures prices are never negative
  number :price, required: true, minimum: 0

  # Enum field restricts values to a specific set
  # Perfect for categorization with known options
  string :category, enum: %w[electronics clothing food other], required: true

  # Array field with typed items and minimum count
  # Ensures at least one feature is always provided
  array :features, items: { type: "string" }, minItems: 1, required: true

  # Boolean field for binary states
  boolean :in_stock, required: true
end

# ============================================================================
# EXAMPLE 1: BASIC STRUCTURED OUTPUT
# ============================================================================
# Create an agent that always returns JSON matching our schema.
# The response_format parameter is the key to structured output.

product_agent = RAAF::Agent.new(
  name: "ProductAnalyzer",

  # Instructions guide the AI on how to extract and format data
  # Clear instructions improve accuracy and consistency
  instructions: <<~INSTRUCTIONS,
    You are a product information analyzer. Extract product information from user input
    and return it as a JSON object that exactly matches the provided schema.

    Be accurate with pricing information and categorize products appropriately.
    If you don't know specific details, make reasonable estimates.
  INSTRUCTIONS

  model: "gpt-4o",

  # response_format ensures structured output at the model level
  # This is more reliable than asking for JSON in the prompt
  response_format: {
    type: "json_schema",     # Tells the model to output JSON
    json_schema: {
      name: "product_info",  # Schema name for identification
      strict: true,          # Strict mode enforces exact compliance
      schema: product_schema.to_h # Convert our DSL schema to hash
    }
  }
)

# Display the schema that will be enforced
# This shows the JSON Schema format sent to the API
puts "Schema enforced by agent:"
puts JSON.pretty_generate(product_schema.to_h)
puts

# Create runner to execute conversations with the agent
# The runner handles the API calls and response processing
runner = RAAF::Runner.new(agent: product_agent)

# Test basic structured output functionality
# The AI will analyze the input and return structured JSON
puts "1. Testing structured output with response_format:"
puts "Input: 'Tell me about the iPhone 15 Pro'"

# Run the agent with a simple product query
# The response will be forced to match our schema
result = runner.run([{
                      role: "user",
                      content: "Tell me about the iPhone 15 Pro"
                    }])

# Extract the response content (will be JSON string)
response_content = result.messages.last[:content]
puts "✅ Raw JSON response: #{response_content}"

# Parse and validate the response
# This demonstrates the full validation pipeline
begin
  # Step 1: Parse JSON string to Ruby hash
  parsed_product = JSON.parse(response_content)
  puts "✅ Successfully parsed JSON"

  # Step 2: Validate against our schema
  # This ensures all required fields are present and valid
  validator = RAAF::StructuredOutput::BaseSchema.new(product_schema.to_h)
  validated_product = validator.validate(parsed_product)
  puts "✅ Schema validation passed"

  # Step 3: Use the validated data safely
  # We know these fields exist and have the right types
  puts "📱 Product Details:"
  puts "   Name: #{validated_product["name"]}"
  puts "   Price: $#{validated_product["price"]}"
  puts "   Category: #{validated_product["category"]}"
  puts "   In Stock: #{validated_product["in_stock"] ? "Yes" : "No"}"
  puts "   Features: #{validated_product["features"].join(", ")}"
rescue JSON::ParserError => e
  # Handle malformed JSON (rare with response_format)
  puts "❌ JSON parsing failed: #{e.message}"
rescue RAAF::StructuredOutput::ValidationError => e
  # Handle schema validation failures
  puts "❌ Schema validation failed: #{e.message}"
end
puts

# ============================================================================
# EXAMPLE 2: RUNCONFIG CUSTOMIZATION
# ============================================================================
# Shows how to customize agent behavior per-request using RunConfig.
# This allows fine-tuning without modifying the agent itself.

puts "2. Testing with RunConfig customization:"

# RunConfig provides per-request customization options
config = RAAF::RunConfig.new(
  # Lower temperature for more deterministic, consistent output
  # Important for structured data extraction
  temperature: 0.3,

  # Limit response length to control costs
  max_tokens: 500,

  # Security: redact sensitive data in traces
  # Useful for production environments
  trace_include_sensitive_data: false,

  # Metadata for tracking and debugging
  metadata: { example: "structured_output" }
)

# Test with different product and custom configuration
messages2 = [{
  role: "user",
  content: "Describe a Tesla Model 3"
}]

# Run with custom config - notice lower temperature effect
result2 = runner.run(messages2, config: config)
puts "Response: #{result2.messages.last[:content]}"
puts

# ============================================================================
# EXAMPLE 3: COMBINING TOOLS WITH STRUCTURED OUTPUT
# ============================================================================
# Demonstrates how agents can use tools to gather data
# before formatting it according to the schema.

puts "3. Testing agent with tools and structured output:"

# Define a tool for price lookups
# In production, this would query a database or API
def lookup_price(product_name:)
  # Simulated price database
  # Real implementation would query inventory system
  prices = {
    "macbook pro" => 2499.99,
    "airpods pro" => 249.99,
    "ipad air" => 599.99
  }

  # Lookup with fallback for unknown products
  price = prices[product_name.downcase] || 999.99
  "The current price for #{product_name} is $#{price}"
end

# Create an agent that combines tool usage with structured output
# This pattern is powerful for data enrichment workflows
smart_agent = RAAF::Agent.new(
  name: "SmartProductAgent",

  # Instructions tell the agent to use tools before responding
  instructions: <<~INSTRUCTIONS,
    You are a smart product analyzer. Use the price lookup tool to get accurate prices.
    Always respond with a JSON object matching the product schema.
  INSTRUCTIONS

  model: "gpt-4o",

  # Same response_format ensures tool-enriched data is structured
  response_format: {
    type: "json_schema",
    json_schema: {
      name: "product_info",
      strict: true,
      schema: product_schema.to_h
    }
  }
)

# Add the price lookup tool to the agent
# The agent will call this tool when it needs price information
smart_agent.add_tool(
  RAAF::FunctionTool.new(
    method(:lookup_price),
    name: "lookup_price",
    description: "Look up the current price for a product"
  )
)

# Create runner for the tool-enabled agent
runner2 = RAAF::Runner.new(agent: smart_agent)

# Request that specifically asks for current pricing
# This will trigger the tool usage
messages3 = [{
  role: "user",
  content: "Tell me about the MacBook Pro with current pricing"
}]

# Configuration for production-like settings
config2 = RAAF::RunConfig.new(
  # Redact sensitive data in traces for security
  trace_include_sensitive_data: false,

  # Name the workflow for better observability
  workflow_name: "Product Analysis Workflow"
)

# The agent will:
# 1. Call lookup_price tool
# 2. Get the price information
# 3. Format everything as structured JSON
result3 = runner2.run(messages3, config: config2)
puts "Response: #{result3.messages.last[:content]}"
puts

# ============================================================================
# EXAMPLE 4: ERROR HANDLING AND EDGE CASES
# ============================================================================
# Shows how response_format handles edge cases and ensures reliability.
# Even with poor instructions, the model is forced to comply with the schema.

puts "4. Testing invalid output handling:"

# Create an agent with vague instructions
# This tests the robustness of response_format
unreliable_agent = RAAF::Agent.new(
  name: "UnreliableAgent",

  # Intentionally vague instructions to test schema enforcement
  instructions: "You sometimes make mistakes with JSON formatting.",

  model: "gpt-4o",

  # Despite poor instructions, response_format ensures valid output
  response_format: {
    type: "json_schema",
    json_schema: {
      name: "product_info",
      strict: true, # Strict mode prevents schema violations
      schema: product_schema.to_h
    }
  }
)

runner3 = RAAF::Runner.new(agent: unreliable_agent)

# Request that encourages brief, potentially incomplete responses
messages4 = [{
  role: "user",
  content: "Quick, tell me about any product but make the response very brief"
}]

# Even with pressure for brevity, the schema is enforced
# All required fields will be present
result4 = runner3.run(messages4)
puts "Response: #{result4.messages.last[:content]}"
puts

# ============================================================================
# SUMMARY AND BEST PRACTICES
# ============================================================================

puts "\n=== Structured Output Features ==="

# Key benefits of using response_format
puts "\n🎯 response_format Benefits:"
puts "• Works with ALL providers (OpenAI, Anthropic, Cohere, Groq, etc.)"
puts "• Uses OpenAI-standard format"
puts "• Automatic provider-specific adaptations"
puts "• Guaranteed JSON schema compliance"
puts "• Type-safe structured output"

# Provider compatibility matrix
# The Ruby SDK handles provider differences transparently
puts "\n🌆 Provider Compatibility:"
puts "✓ OpenAI: Native JSON schema support"
puts "✓ Groq: Direct response_format passthrough"
puts "✓ Anthropic: Enhanced system prompts with schema"
puts "✓ Cohere: JSON object mode + schema instructions"
puts "✓ Others: Intelligent prompt enhancement"

puts "\n📚 Best Practices:"
puts "1. Always validate output even with response_format"
puts "2. Use strict: true for production applications"
puts "3. Provide clear instructions alongside schemas"
puts "4. Test edge cases and error handling"
puts "5. Consider using tools for data enrichment"

puts "\n⚠️ Common Pitfalls:"
puts "• Don't rely on prompt alone - use response_format"
puts "• Avoid overly complex nested schemas"
puts "• Remember that enum values are case-sensitive"
puts "• Test with different temperature settings"

puts "\n=== Example Complete ==="
puts "Universal structured output across all providers! 🎉"
