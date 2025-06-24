#!/usr/bin/env ruby
# frozen_string_literal: true

# Debug the raw response from OpenAI Responses API

require_relative "lib/openai_agents"
require "json"

provider = OpenAIAgents::Models::ResponsesProvider.new

schema = {
  "type" => "object",
  "properties" => {
    "name" => { "type" => "string" },
    "age" => { "type" => "integer" }
  },
  "required" => ["name", "age"],
  "additionalProperties" => false
}

response_format = {
  type: "json_schema",
  json_schema: {
    name: "final_output",
    strict: true,
    schema: schema
  }
}

if ENV["OPENAI_API_KEY"]
  puts "=== Making raw API call ==="
  
  raw_response = provider.send(:call_responses_api,
    model: "gpt-4o",
    input: "My name is John and I'm 30 years old",
    instructions: "Return valid JSON only.",
    response_format: response_format
  )
  
  puts "Raw response structure:"
  puts JSON.pretty_generate(raw_response)
  
  puts "\n=== Conversion test ==="
  converted = provider.send(:convert_response_to_chat_format, raw_response)
  
  puts "Converted response:"
  puts JSON.pretty_generate(converted)
  
  puts "\nContent field:"
  puts converted.dig("choices", 0, "message", "content").inspect
else
  puts "Set OPENAI_API_KEY to test"
end