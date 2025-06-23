#!/usr/bin/env ruby
# frozen_string_literal: true

# Minimal test to send trace with exact headers like Python SDK

require "net/http"
require "json"
require "securerandom"

api_key = ENV["OPENAI_API_KEY"]
unless api_key
  puts "ERROR: OPENAI_API_KEY is required"
  exit 1
end

puts "Testing minimal trace request (Python SDK style)"
puts "API Key: #{api_key[0..10]}..."
puts "-" * 50

# Create minimal payload exactly like Python would
trace_id = "trace_#{SecureRandom.hex(16)}"
span_id = "span_#{SecureRandom.hex(12)}"

payload = {
  "data" => [
    # First item: trace object (without spans)
    {
      "object" => "trace",
      "id" => trace_id,
      "workflow_name" => "test",
      "metadata" => {
        "sdk.language" => "python",  # Pretend to be Python SDK
        "sdk.version" => "0.1.0"
      }
    },
    # Second item: span object
    {
      "object" => "trace.span",
      "id" => span_id,
      "trace_id" => trace_id,
      "started_at" => Time.now.utc.strftime('%Y-%m-%dT%H:%M:%S.%3NZ'),
      "ended_at" => Time.now.utc.strftime('%Y-%m-%dT%H:%M:%S.%3NZ'),
      "span_data" => {
        "type" => "agent",
        "name" => "test_agent",
        "handoffs" => [],
        "tools" => [],
        "output_type" => "text"
      }
    }
  ]
}

# Send request with ONLY the headers Python SDK would send
uri = URI("https://api.openai.com/v1/traces/ingest")
http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true

# Create request
request = Net::HTTP::Post.new(uri)

# Set ONLY the headers that Python SDK sets
request["Authorization"] = "Bearer #{api_key}"
request["Content-Type"] = "application/json"
request["OpenAI-Beta"] = "traces=v1"

# Python SDK also checks for these env vars
if ENV["OPENAI_ORG_ID"]
  request["OpenAI-Organization"] = ENV["OPENAI_ORG_ID"]
  puts "Adding OpenAI-Organization: #{ENV["OPENAI_ORG_ID"]}"
end

if ENV["OPENAI_PROJECT_ID"]
  request["OpenAI-Project"] = ENV["OPENAI_PROJECT_ID"]
  puts "Adding OpenAI-Project: #{ENV["OPENAI_PROJECT_ID"]}"
end

request.body = JSON.generate(payload)

puts "\nHeaders being sent:"
request.each_header { |k, v| puts "  #{k}: #{k.downcase == 'authorization' ? v[0..20] + '...' : v}" }

puts "\nPayload:"
puts JSON.pretty_generate(payload)

puts "\nSending request..."
response = http.request(request)

puts "\nResponse: #{response.code} #{response.message}"
if response.code != "200"
  puts "Body: #{response.body}"
end

puts "\n" + "-" * 50
puts "If this still gets 401, then:"
puts "1. The traces API requires special access"
puts "2. Project keys (sk-proj-) aren't supported"
puts "3. It's not about headers or format"