#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/raaf-core"

# Universal Response Format Example
#
# This example demonstrates the response_format feature which provides
# structured output that works consistently across ALL providers:
# - OpenAI (native JSON schema support)
# - Anthropic (enhanced system prompts)
# - Cohere (JSON object mode with schema)
# - Groq (direct parameter passthrough)
# - LiteLLM (universal support)

puts "🚀 RAAF (Ruby AI Agents Factory) - Universal Response Format Example"
puts "=" * 60

# Define a user information schema
USER_SCHEMA = {
  type: "json_schema",
  json_schema: {
    name: "user_info",
    strict: true,
    schema: {
      type: "object",
      properties: {
        name: { type: "string" },
        age: { type: "integer", minimum: 0, maximum: 150 },
        email: { type: "string" },
        occupation: { type: "string" },
        interests: {
          type: "array",
          items: { type: "string" },
          minItems: 1
        }
      },
      required: %w[name age email occupation interests],
      additionalProperties: false
    }
  }
}.freeze

# Product analysis schema
PRODUCT_SCHEMA = {
  type: "json_schema",
  json_schema: {
    name: "product_analysis",
    strict: true,
    schema: {
      type: "object",
      properties: {
        product_name: { type: "string" },
        price: { type: "number", minimum: 0 },
        category: {
          type: "string",
          enum: %w[electronics clothing food books other]
        },
        features: {
          type: "array",
          items: { type: "string" },
          minItems: 1
        },
        pros: {
          type: "array",
          items: { type: "string" }
        },
        cons: {
          type: "array",
          items: { type: "string" }
        },
        rating: { type: "integer", minimum: 1, maximum: 5 },
        in_stock: { type: "boolean" }
      },
      required: %w[product_name price category features pros cons rating in_stock],
      additionalProperties: false
    }
  }
}.freeze

def run_example_with_provider(provider_class, provider_name, api_key_env = nil)
  puts "\n📊 Testing with #{provider_name}"
  puts "-" * 40

  begin
    # Check API key
    api_key = ENV.fetch(api_key_env, nil) if api_key_env
    if api_key_env && !api_key
      puts "⚠️  Skipping #{provider_name} - #{api_key_env} not set"
      return
    end

    # Create provider instance
    provider = if api_key_env
                 provider_class.new(api_key: api_key)
               else
                 provider_class.new
               end

    # User information extraction agent
    user_agent = RAAF::Agent.new(
      name: "UserExtractor",
      instructions: "Extract user information from the input text and return it as structured JSON.",
      model: get_model_for_provider(provider_name),
      response_format: USER_SCHEMA
    )

    runner = RAAF::Runner.new(agent: user_agent, provider: provider)

    puts "🔄 Extracting user information..."
    user_input = "Hi! I'm Alice Johnson, 28 years old. My email is alice@example.com and I work as a software engineer. I love reading, hiking, and photography."

    result = runner.run(user_input)
    response = result.messages.last[:content]

    puts "✅ Raw response: #{response}"

    # Parse and validate the JSON
    user_data = JSON.parse(response)
    puts "📋 Parsed data:"
    puts "   Name: #{user_data["name"]}"
    puts "   Age: #{user_data["age"]}"
    puts "   Email: #{user_data["email"]}" if user_data["email"]
    puts "   Occupation: #{user_data["occupation"]}" if user_data["occupation"]
    puts "   Interests: #{user_data["interests"]&.join(", ")}" if user_data["interests"]
  rescue StandardError => e
    puts "❌ Error with #{provider_name}: #{e.message}"
    puts "   This might be due to missing API key or provider configuration"
  end
end

def get_model_for_provider(provider_name)
  case provider_name
  when "Anthropic"
    "claude-3-5-sonnet-20241022"
  when "Cohere"
    "command-r"
  when "Groq"
    "llama-3.1-70b-versatile"
  else
    "gpt-4o"
  end
end

def demonstrate_response_format
  puts "\n🎯 Universal Structured Output with response_format"
  puts "=" * 55

  puts "\n🆕 Modern response_format approach:"
  RAAF::Agent.new(
    name: "ModernAgent",
    instructions: "Extract user info as JSON",
    model: "gpt-4o",
    response_format: {
      type: "json_schema",
      json_schema: {
        name: "user_info",
        strict: true,
        schema: {
          type: "object",
          properties: {
            name: { type: "string" },
            age: { type: "integer" }
          },
          required: %w[name age],
          additionalProperties: false
        }
      }
    }
  )

  puts "   Agent created with response_format parameter"
  puts "   ✅ Works with ALL providers (OpenAI, Anthropic, Cohere, Groq, etc.)"
  puts "   ✅ Follows OpenAI standard format"
  puts "   ✅ Automatic provider-specific adaptations"
  puts "   ✅ Guaranteed JSON schema compliance"
end

def demonstrate_complex_schema
  puts "\n🧩 Complex Schema Example"
  puts "=" * 30

  # Create an agent for product analysis
  product_agent = RAAF::Agent.new(
    name: "ProductAnalyzer",
    instructions: "Analyze the given product and provide detailed structured information.",
    model: "gpt-4o",
    response_format: PRODUCT_SCHEMA
  )

  # Use ResponsesProvider (default)
  runner = RAAF::Runner.new(agent: product_agent)

  puts "🔄 Analyzing product..."
  product_input = "The MacBook Pro 16-inch with M3 chip costs $2499. It's a powerful laptop for developers and creators with features like the Liquid Retina XDR display, up to 128GB unified memory, and excellent build quality. Some downsides include the high price and limited ports."

  begin
    result = runner.run(product_input)
    response = result.messages.last[:content]

    puts "✅ Raw response: #{response}"

    # Parse and display structured data
    product_data = JSON.parse(response)
    puts "📊 Product Analysis:"
    puts "   Name: #{product_data["product_name"]}"
    puts "   Price: $#{product_data["price"]}"
    puts "   Category: #{product_data["category"]}"
    puts "   Rating: #{product_data["rating"]}/5"
    puts "   In Stock: #{product_data["in_stock"] ? "Yes" : "No"}"
    puts "   Features: #{product_data["features"]&.join(", ")}"
    puts "   Pros: #{product_data["pros"]&.join(", ")}" if product_data["pros"]
    puts "   Cons: #{product_data["cons"]&.join(", ")}" if product_data["cons"]
  rescue StandardError => e
    puts "❌ Error: #{e.message}"
  end
end

# Main execution
begin
  # Demonstrate response_format approach
  demonstrate_response_format

  # Show complex schema usage
  demonstrate_complex_schema

  puts "\n🌍 Cross-Provider Compatibility Test"
  puts "=" * 40
  puts "Testing response_format with different providers..."
  puts "Note: You need to set appropriate API keys for each provider"

  # Test with available providers
  providers_to_test = [
    [RAAF::Models::ResponsesProvider, "ResponsesProvider (Default)"],
    [RAAF::Models::OpenAIProvider, "OpenAI", "OPENAI_API_KEY"],
    [RAAF::Models::AnthropicProvider, "Anthropic", "ANTHROPIC_API_KEY"],
    [RAAF::Models::CohereProvider, "Cohere", "COHERE_API_KEY"],
    [RAAF::Models::GroqProvider, "Groq", "GROQ_API_KEY"]
  ]

  providers_to_test.each do |provider_class, provider_name, api_key_env|
    run_example_with_provider(provider_class, provider_name, api_key_env)
  end

  puts "\n✨ Key Benefits of response_format:"
  puts "   🔄 Universal compatibility across ALL providers"
  puts "   📝 OpenAI-standard format"
  puts "   🔧 Automatic provider-specific adaptations"
  puts "   📊 Guaranteed structured output"
  puts "   🏗️  Type-safe JSON schema validation"

  puts "\n🎯 Usage Recommendations:"
  puts "   ✅ Use response_format for all structured output needs"
  puts "   🌍 Works with any provider configuration"
  puts "   📚 Follows OpenAI standard conventions"
  puts "   🚀 Future-proof and actively maintained"
  puts "   🔒 Essential for production systems"
rescue StandardError => e
  puts "❌ Example failed: #{e.message}"
  puts "   Make sure OPENAI_API_KEY is set in your environment"
  puts "   Backtrace: #{e.backtrace.first(3).join('\n   ')}"
end

puts "\n🎉 Response Format example completed!"
puts "Check the documentation for more advanced usage patterns."
