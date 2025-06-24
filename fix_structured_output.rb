#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "lib/openai_agents"
require "json"

puts "=== Fix for Structured Output ==="
puts "Current issue: output_schema is not passed to OpenAI API as response_format"
puts

# Check if we can fix this by modifying the runner
puts "1. Testing current behavior:"

# Create agent with schema
schema = {
  type: "object",
  properties: {
    name: { type: "string" },
    age: { type: "integer" },
    city: { type: "string" }
  },
  required: ["name", "age"]
}

agent = OpenAIAgents::Agent.new(
  name: "TestAgent",
  instructions: "Return user info as JSON matching the schema exactly.",
  model: "gpt-4o",
  output_schema: schema
)

puts "Agent has output_schema: #{!agent.output_schema.nil?}"

# Show what needs to be fixed
puts "\n2. The fix needed:"
puts "In Runner#run, we need to:"
puts "- Add agent.output_schema to model_params as response_format"
puts "- Convert schema to OpenAI's format: { type: 'json_schema', json_schema: { ... } }"

puts "\n3. Example of correct API call format:"
correct_format = {
  type: "json_schema",
  json_schema: {
    name: "user_info",
    strict: true,
    schema: schema
  }
}

puts "response_format: #{JSON.pretty_generate(correct_format)}"

puts "\n4. Current workaround using RunConfig:"

# We can work around this by manually adding response_format to model_kwargs
config = OpenAIAgents::RunConfig.new(
  temperature: 0.3,
  response_format: correct_format
)

puts "Using RunConfig with manual response_format"
puts "Config model_params: #{config.to_model_params}"

puts "\n=== Proposed Fix ==="
puts "Add this to Runner class in the run method:"
puts

fix_code = <<~RUBY
  # In Runner#run method, after line ~205:
  model_params = config.to_model_params
  
  # Add structured output support
  if current_agent.output_schema
    model_params[:response_format] = {
      type: "json_schema",
      json_schema: {
        name: current_agent.name&.downcase&.gsub(/[^a-z0-9_]/, '_') || 'schema',
        strict: true,
        schema: current_agent.output_schema
      }
    }
  end
RUBY

puts fix_code

puts "\n=== Test the workaround ==="

if ENV["OPENAI_API_KEY"] && ENV["OPENAI_API_KEY"].start_with?("sk-")
  puts "Testing with real API key..."
  
  runner = OpenAIAgents::Runner.new(agent: agent)
  
  begin
    result = runner.run(
      [{ role: "user", content: "My name is John, I'm 30 years old, and I live in New York" }],
      config: config
    )
    
    response_content = result.messages.last[:content]
    puts "Response: #{response_content}"
    
    # Try to parse as JSON
    begin
      parsed = JSON.parse(response_content)
      puts "✅ Valid JSON returned: #{parsed}"
    rescue JSON::ParserError
      puts "❌ Response is not valid JSON"
    end
    
  rescue => e
    puts "❌ Error: #{e.message}"
  end
else
  puts "⚠️  Set OPENAI_API_KEY to test with real API"
end