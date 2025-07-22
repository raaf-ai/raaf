#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require_relative "../lib/raaf-core"
require "json"

# Example demonstrating output type validation with TypeAdapter

# Output type validation enables reliable AI integration
puts "=== Output Type Validation Example ==="
puts "This example shows how to use output_type for structured output validation"
puts

# 1. Basic String Output (default)
puts "=== Example 1: Basic String Output ==="

basic_agent = RAAF::Agent.new(
  name: "BasicAgent",
  instructions: "You are a helpful assistant.",
  model: "gpt-4o-mini"
  # output_type defaults to String
)

runner = RAAF::Runner.new(agent: basic_agent)
result = runner.run("What is 2 + 2?")
puts "Response: #{result.messages.last[:content]}"
puts "Response class: #{result.messages.last[:content].class}\n\n"

puts "=" * 50

# 2. Structured Output with Hash
puts "\n=== Example 2: Hash Output Type ==="

# Define a simple data structure
class UserInfo

  attr_accessor :name, :age, :email

  def initialize(data = {})
    @name = data["name"] || data[:name]
    @age = data["age"] || data[:age]
    @email = data["email"] || data[:email]
  end

  def self.json_schema
    {
      type: "object",
      properties: {
        name: { type: "string" },
        age: { type: "integer", minimum: 0 },
        email: { type: "string", format: "email" }
      },
      required: %w[name age email],
      additionalProperties: false
    }
  end

  def self.from_json(data)
    new(data)
  end

  def to_h
    { name: @name, age: @age, email: @email }
  end

end

structured_agent = RAAF::Agent.new(
  name: "StructuredAgent",
  instructions: "Extract user information and return it in the specified format.",
  model: "gpt-4o-mini",
  output_type: Hash
)

runner = RAAF::Runner.new(agent: structured_agent)
result = runner.run("Extract info from: John Doe, 30 years old, john.doe@example.com")
puts "Response: #{result.messages.last[:content]}"
puts "Response class: #{result.messages.last[:content].class}\n\n"

puts "=" * 50

# 3. Custom Class Output Type
puts "\n=== Example 3: Custom Class Output Type ==="

user_agent = RAAF::Agent.new(
  name: "UserAgent",
  instructions: "Extract user information and return it as a UserInfo object.",
  model: "gpt-4o-mini",
  output_type: UserInfo
)

runner = RAAF::Runner.new(agent: user_agent)
result = runner.run("Parse: Jane Smith, age 25, email jane@example.com")
content = result.messages.last[:content]
puts "Raw response: #{content}"

# The content should be JSON that can be parsed into UserInfo
if content.is_a?(String) && content.start_with?("{")
  begin
    data = JSON.parse(content)
    user = UserInfo.from_json(data)
    puts "Parsed user: Name=#{user.name}, Age=#{user.age}, Email=#{user.email}"
  rescue StandardError => e
    puts "Parse error: #{e.message}"
  end
end

puts "\n#{"=" * 50}"

# 4. Array Output Type
puts "\n=== Example 4: Array Output Type ==="

list_agent = RAAF::Agent.new(
  name: "ListAgent",
  instructions: "Extract items as a JSON array.",
  model: "gpt-4o-mini",
  output_type: Array
)

runner = RAAF::Runner.new(agent: list_agent)
result = runner.run("List the primary colors: red, green, blue")
puts "Response: #{result.messages.last[:content]}"
puts "Response class: #{result.messages.last[:content].class}\n\n"

puts "=" * 50

# 5. Custom AgentOutputSchema
puts "\n=== Example 5: Custom AgentOutputSchema ==="

# Create a custom output schema with non-strict validation
class FlexibleOutputSchema < RAAF::AgentOutputSchemaBase

  def initialize
    super
    @schema = {
      type: "object",
      properties: {
        status: { type: "string", enum: %w[success error pending] },
        data: { type: "object", additionalProperties: true },
        timestamp: { type: "string" }
      },
      required: ["status"],
      additionalProperties: true
    }
  end

  def plain_text?
    false
  end

  def name
    "FlexibleOutput"
  end

  def json_schema
    @schema
  end

  def strict_json_schema?
    false # Allow flexible validation
  end

  def validate_json(json_str)
    data = JSON.parse(json_str)

    # Basic validation
    unless data.is_a?(Hash) && data["status"]
      raise RAAF::ModelBehaviorError,
            "Missing required 'status' field"
    end

    raise RAAF::ModelBehaviorError, "Invalid status: #{data["status"]}" unless %w[success error pending].include?(data["status"])

    data
  rescue JSON::ParserError => e
    raise RAAF::ModelBehaviorError, "Invalid JSON: #{e.message}"
  end

end

flexible_agent = RAAF::Agent.new(
  name: "FlexibleAgent",
  instructions: "Process the request and return a status response.",
  model: "gpt-4o-mini",
  output_type: FlexibleOutputSchema.new
)

runner = RAAF::Runner.new(agent: flexible_agent)
result = runner.run("Process this task and return success status with current time")
puts "Response: #{result.messages.last[:content]}\n\n"

puts "=" * 50

# 6. Validation with AgentOutputSchema
puts "\n=== Example 6: Strict Validation with AgentOutputSchema ==="

# Create a product schema
class Product

  attr_accessor :name, :price, :in_stock

  def self.json_schema
    {
      type: "object",
      properties: {
        name: { type: "string", minLength: 1 },
        price: { type: "number", minimum: 0 },
        in_stock: { type: "boolean" }
      },
      required: %w[name price in_stock],
      additionalProperties: false
    }
  end

end

# Create agent with strict output schema
product_schema = RAAF::AgentOutputSchema.new(Product, strict_json_schema: true)

product_agent = RAAF::Agent.new(
  name: "ProductAgent",
  instructions: "Extract product information in the exact format specified.",
  model: "gpt-4o-mini",
  output_type: product_schema
)

runner = RAAF::Runner.new(agent: product_agent)

puts "Testing product extraction..."
result = runner.run("Product: iPhone 15, costs $999, currently available")
puts "Response: #{result.messages.last[:content]}"

# Validate the output
begin
  content = result.messages.last[:content]
  if content.is_a?(String)
    validated = product_schema.validate_json(content)
    puts "Validation passed! Product data: #{validated}"
  end
rescue RAAF::ModelBehaviorError => e
  puts "Validation failed: #{e.message}"
end

puts "\n=== Output Type Validation Examples Complete ==="
puts
puts "Key takeaways:"
puts "1. Use output_type to specify expected output format"
puts "2. Basic types (String, Hash, Array) work out of the box"
puts "3. Custom classes can provide json_schema method"
puts "4. AgentOutputSchema provides strict validation"
puts "5. Create custom AgentOutputSchemaBase for flexible validation"
