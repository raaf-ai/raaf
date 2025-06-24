#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "lib/openai_agents"
require "json"

# Simple test to debug the exact response content
schema = {
  type: "object",
  properties: {
    name: { type: "string" },
    age: { type: "integer" }
  },
  required: %w[name age],
  additionalProperties: false
}

agent = OpenAIAgents::Agent.new(
  name: "TestAgent",
  instructions: "Return valid JSON only.",
  model: "gpt-4o",
  output_schema: schema
)

runner = OpenAIAgents::Runner.new(agent: agent)

if ENV["OPENAI_API_KEY"] && ENV["OPENAI_API_KEY"].start_with?("sk-")
  result = runner.run([{
                        role: "user",
                        content: "My name is John and I'm 30 years old"
                      }])

  response_content = result.messages.last[:content]
  puts "=== Debug Response Content ==="
  puts "Raw content: #{response_content.inspect}"
  puts "Content class: #{response_content.class}"
  puts "Content length: #{response_content.length}"
  puts "First 50 chars: #{response_content[0..50].inspect}"

  # Try to parse character by character to find the issue
  response_content.each_char.with_index do |char, i|
    puts "#{i}: #{char.inspect} (#{char.ord})" if i < 10
  end
else
  puts "Set OPENAI_API_KEY to test"
end
