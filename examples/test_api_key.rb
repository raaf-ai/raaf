#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/openai_agents"

# Test if the API key works for regular OpenAI API calls

api_key = ENV["OPENAI_API_KEY"]
puts "Testing OpenAI API key: #{api_key[0..10]}..."
puts "-" * 50

# Test 1: Regular chat completion
puts "\n1. Testing regular chat completion:"
begin
  provider = OpenAIAgents::Models::OpenAIProvider.new(api_key: api_key)
  response = provider.chat_completion(
    messages: [{ role: "user", content: "Say 'Hello, API key works!'" }],
    model: "gpt-3.5-turbo",
    max_tokens: 20
  )
  
  if response["choices"]
    puts "✅ SUCCESS: #{response['choices'][0]['message']['content']}"
    puts "   Model: #{response['model']}"
    puts "   Usage: #{response['usage']['total_tokens']} tokens"
  else
    puts "❌ FAILED: Unexpected response format"
  end
rescue => e
  puts "❌ FAILED: #{e.message}"
end

# Test 2: List models (different endpoint)
puts "\n2. Testing models endpoint:"
begin
  require 'net/http'
  require 'json'
  
  uri = URI('https://api.openai.com/v1/models')
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  
  request = Net::HTTP::Get.new(uri)
  request['Authorization'] = "Bearer #{api_key}"
  
  response = http.request(request)
  
  if response.code == "200"
    data = JSON.parse(response.body)
    puts "✅ SUCCESS: Found #{data['data'].length} models"
    puts "   Sample models: #{data['data'][0..2].map { |m| m['id'] }.join(', ')}"
  else
    puts "❌ FAILED: HTTP #{response.code}"
    puts "   Error: #{response.body}"
  end
rescue => e
  puts "❌ FAILED: #{e.message}"
end

# Test 3: Create embedding (another endpoint)
puts "\n3. Testing embeddings endpoint:"
begin
  uri = URI('https://api.openai.com/v1/embeddings')
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  
  request = Net::HTTP::Post.new(uri)
  request['Authorization'] = "Bearer #{api_key}"
  request['Content-Type'] = 'application/json'
  request.body = JSON.generate({
    model: "text-embedding-ada-002",
    input: "Test embedding"
  })
  
  response = http.request(request)
  
  if response.code == "200"
    data = JSON.parse(response.body)
    puts "✅ SUCCESS: Created embedding"
    puts "   Model: #{data['model']}"
    puts "   Dimensions: #{data['data'][0]['embedding'].length}"
  else
    puts "❌ FAILED: HTTP #{response.code}"
    puts "   Error: #{response.body}"
  end
rescue => e
  puts "❌ FAILED: #{e.message}"
end

puts "\n" + "-" * 50
puts "Summary:"
puts "- If the above tests pass, your API key is valid for regular OpenAI APIs"
puts "- The traces API may require special access or different authentication"
puts "- Project-scoped keys (sk-proj-) have known issues with some endpoints"
puts
puts "Possible solutions:"
puts "1. The traces API might be limited to OpenAI's official SDKs only"
puts "2. You might need a legacy API key (sk-) instead of project key (sk-proj-)"
puts "3. The traces feature might require special beta access from OpenAI"