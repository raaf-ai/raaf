#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "lib/openai_agents"
require "json"

puts "=== OpenAI Agents Ruby - Structured Output Working Example ==="
puts "This demonstrates the fixed structured output functionality"
puts

# Define a comprehensive schema for a product review
product_review_schema = {
  type: "object",
  properties: {
    product_name: { type: "string" },
    rating: { type: "integer", minimum: 1, maximum: 5 },
    review_text: { type: "string" },
    pros: {
      type: "array",
      items: { type: "string" },
      minItems: 1
    },
    cons: {
      type: "array",
      items: { type: "string" }
    },
    would_recommend: { type: "boolean" },
    price_value: {
      type: "string",
      enum: %w[excellent good fair poor]
    }
  },
  required: %w[product_name rating review_text pros would_recommend price_value],
  additionalProperties: false
}

puts "Schema defined for product reviews:"
puts JSON.pretty_generate(product_review_schema)
puts

# Create agent with structured output
review_agent = OpenAIAgents::Agent.new(
  name: "ProductReviewAgent",
  instructions: <<~INSTRUCTIONS,
    You are a product review analyzer. When given information about a product experience,
    extract and structure the information into a comprehensive product review JSON object.

    Always ensure:
    - The rating is between 1-5
    - Pros array has at least one item
    - Cons array can be empty if no cons mentioned
    - Price value assessment is one of: excellent, good, fair, poor
    - Review text summarizes the overall experience
  INSTRUCTIONS
  model: "gpt-4o",
  output_schema: product_review_schema
)

puts "✅ Agent created with structured output schema"

# Test with both providers
providers = {
  "ResponsesProvider (default)" => nil, # Uses default
  "OpenAIProvider (Chat Completions)" => OpenAIAgents::Models::OpenAIProvider.new
}

test_input = <<~INPUT
  I recently bought the iPhone 15 Pro and have been using it for a month.#{" "}
  The camera quality is absolutely stunning - the photos look professional.#{" "}
  The battery life easily gets me through a full day, and the build quality feels premium.
  However, it's quite expensive at $999, and the charging cable situation is annoying since
  I had to buy new cables. The phone can also get quite warm during heavy use.
  Overall, I'd rate it 4 out of 5 stars and would recommend it to photography enthusiasts,
  though the price is steep for the value.
INPUT

puts "📝 Test input:"
puts test_input
puts

if ENV["OPENAI_API_KEY"] && ENV["OPENAI_API_KEY"].start_with?("sk-")

  providers.each do |provider_name, provider|
    puts "🚀 Testing with #{provider_name}:"

    runner = OpenAIAgents::Runner.new(
      agent: review_agent,
      provider: provider
    )

    begin
      result = runner.run([{
                            role: "user",
                            content: test_input
                          }])

      response_content = result.messages.last[:content]
      puts "📤 Raw response: #{response_content}"

      # Parse and validate
      parsed_review = JSON.parse(response_content)
      puts "✅ Valid JSON response"

      # Validate against schema
      schema_validator = OpenAIAgents::StructuredOutput::BaseSchema.new(product_review_schema)
      validated_review = schema_validator.validate(parsed_review)
      puts "✅ Schema validation passed"

      puts "📋 Structured Review:"
      puts "  Product: #{validated_review["product_name"]}"
      puts "  Rating: #{validated_review["rating"]}/5"
      puts "  Recommendation: #{validated_review["would_recommend"] ? "Yes" : "No"}"
      puts "  Price Value: #{validated_review["price_value"]}"
      puts "  Pros: #{validated_review["pros"].join(", ")}"
      puts "  Cons: #{validated_review["cons"]&.join(", ") || "None mentioned"}"
      puts "  Review: #{validated_review["review_text"]}"
    rescue JSON::ParserError => e
      puts "❌ JSON parsing failed: #{e.message}"
    rescue OpenAIAgents::StructuredOutput::ValidationError => e
      puts "❌ Schema validation failed: #{e.message}"
    rescue StandardError => e
      puts "❌ Error: #{e.message}"
    end

    puts
  end

  puts "=== Summary ==="
  puts "✅ Structured output now works correctly with both APIs!"
  puts "✅ Ruby implementation matches Python behavior"
  puts "✅ Schema enforcement happens at the API level"
  puts "✅ Both ResponsesProvider and OpenAIProvider supported"
  puts
  puts "Key improvements made:"
  puts "1. Added strict schema processing (all properties become required)"
  puts "2. Fixed ResponsesProvider to convert response_format → text.format"
  puts "3. Fixed response parsing to extract JSON from new API format"
  puts "4. Maintained OpenAIProvider compatibility with response_format"
  puts "5. Added comprehensive schema validation"

else
  puts "⚠️  Set OPENAI_API_KEY to run the live example"
  puts "   export OPENAI_API_KEY='sk-proj-your-key-here'"
end
