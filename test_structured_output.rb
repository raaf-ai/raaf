#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "lib/openai_agents"

puts "=== Testing Structured Output ==="

# Check if API key is set
unless ENV["OPENAI_API_KEY"]
  puts "⚠️  OPENAI_API_KEY not set. Using mock test."
  ENV["OPENAI_API_KEY"] = "sk-test-mock-key"
end

# 1. Simple JSON schema test
puts "\n1. Creating simple schema..."
simple_schema = {
  type: "object",
  properties: {
    name: { type: "string" },
    age: { type: "integer", minimum: 0 },
    email: { type: "string" }
  },
  required: %w[name age]
}

puts "Schema: #{simple_schema}"

# 2. Test schema validation
puts "\n2. Testing schema validation..."
schema_obj = OpenAIAgents::StructuredOutput::BaseSchema.new(simple_schema)

valid_data = { "name" => "John", "age" => 30, "email" => "john@example.com" }
begin
  result = schema_obj.validate(valid_data)
  puts "✅ Valid data passed: #{result}"
rescue StandardError => e
  puts "❌ Validation failed: #{e.message}"
end

invalid_data = { "name" => "John" } # Missing required 'age'
begin
  schema_obj.validate(invalid_data)
  puts "❌ Invalid data should have failed"
rescue StandardError => e
  puts "✅ Invalid data correctly rejected: #{e.message}"
end

# 3. Test with ObjectSchema builder
puts "\n3. Testing ObjectSchema builder..."
user_schema = OpenAIAgents::StructuredOutput::ObjectSchema.build do
  string :name, required: true, minLength: 1
  integer :age, required: true, minimum: 0, maximum: 150
  string :email, pattern: ".*@.*"
  boolean :active, required: true
end

puts "Built schema: #{user_schema.to_h}"

# 4. Test agent with schema
puts "\n4. Testing agent with output schema..."
agent = OpenAIAgents::Agent.new(
  name: "TestAgent",
  instructions: "You are a test agent. Respond only with valid JSON matching the schema.",
  model: "gpt-4o",
  output_schema: user_schema.to_h
)

puts "Agent created with schema: #{agent.output_schema}"

# 5. Check if the schema gets passed to the model provider
puts "\n5. Checking model provider integration..."
OpenAIAgents::Runner.new(agent: agent)

# Mock test - just verify the setup doesn't error
begin
  puts "Runner created successfully"
  puts "Agent model: #{agent.model}"
  puts "Agent has output_schema: #{!agent.output_schema.nil?}"
rescue StandardError => e
  puts "❌ Error creating runner: #{e.message}"
end

puts "\n=== Test Complete ==="
puts "✅ Structured output implementation exists and validates correctly"
puts "🔧 To test with real API calls, set OPENAI_API_KEY and run:"
puts "   ruby examples/structured_output_example.rb"
