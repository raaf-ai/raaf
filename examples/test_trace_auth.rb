#!/usr/bin/env ruby
# frozen_string_literal: true

# Test different authentication methods for traces API

require "net/http"
require "json"
require "uri"

api_key = ENV["OPENAI_API_KEY"]
alt_key = ENV["OPENAI_LEGACY_KEY"] # If you have a legacy sk- key

puts "Testing Traces API Authentication"
puts "=" * 50
puts

# Test payload (minimal valid trace)
payload = {
  "data" => [{
    "object" => "trace",
    "id" => "trace_#{SecureRandom.hex(16)}",
    "workflow_name" => "test",
    "metadata" => {},
    "spans" => []
  }]
}

def test_auth(description, api_key, extra_headers = {})
  puts "Test: #{description}"
  puts "Key type: #{api_key[0..7]}..."
  
  uri = URI("https://api.openai.com/v1/traces/ingest")
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  
  request = Net::HTTP::Post.new(uri)
  request["Authorization"] = "Bearer #{api_key}"
  request["Content-Type"] = "application/json"
  request["OpenAI-Beta"] = "traces=v1"
  
  extra_headers.each { |k, v| request[k] = v }
  
  request.body = JSON.generate(payload)
  
  response = http.request(request)
  
  puts "Response: #{response.code} #{response.message}"
  if response.code != "200"
    body = JSON.parse(response.body) rescue response.body
    puts "Error: #{body["error"]["message"] if body.is_a?(Hash)}"
  end
  puts
rescue => e
  puts "Exception: #{e.message}"
  puts
end

# Test 1: Current project key
test_auth("Project-scoped key", api_key)

# Test 2: With OpenAI-Project header
if api_key.start_with?("sk-proj-")
  # Extract potential project ID from key
  project_id = api_key.split("-")[2] # This is a guess
  test_auth(
    "Project key with OpenAI-Project header", 
    api_key,
    { "OpenAI-Project" => project_id }
  )
end

# Test 3: Legacy key if available
if alt_key && alt_key.start_with?("sk-")
  test_auth("Legacy API key", alt_key)
end

# Test 4: Check regular API with same key
puts "Comparison: Testing regular API with same key"
uri = URI("https://api.openai.com/v1/models")
http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true

request = Net::HTTP::Get.new(uri)
request["Authorization"] = "Bearer #{api_key}"

response = http.request(request)
puts "Models API: #{response.code} #{response.message}"
puts

puts "=" * 50
puts "Conclusions:"
puts "- 401 on traces API = Authentication issue, not format"
puts "- 200 on models API = Key is valid for regular APIs"
puts "- This confirms traces API has special access requirements"