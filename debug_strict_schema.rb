#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "lib/openai_agents"
require "json"

puts "=== Debug Strict Schema ==="

# Test schema
original_schema = {
  type: "object",
  properties: {
    name: { type: "string" },
    age: { type: "integer", minimum: 0, maximum: 150 },
    email: { type: "string" },
    city: { type: "string" },
    occupation: { type: "string" },
    interests: {
      type: "array",
      items: { type: "string" }
    }
  },
  required: %w[name age city],
  additionalProperties: false
}

puts "Original schema:"
puts JSON.pretty_generate(original_schema)

# Test strict schema conversion
strict_schema = OpenAIAgents::StrictSchema.ensure_strict_json_schema(original_schema)

puts "\nStrict schema:"
puts JSON.pretty_generate(strict_schema)

puts "\nRequired fields:"
puts "Original: #{original_schema[:required]}"
puts "Strict: #{strict_schema["required"]}"

puts "\nAll properties keys:"
puts original_schema[:properties].keys
puts strict_schema["properties"].keys

# Test that it includes email in required
if strict_schema["required"].include?("email")
  puts "✅ Email is now required in strict schema"
else
  puts "❌ Email is missing from required in strict schema"
end
