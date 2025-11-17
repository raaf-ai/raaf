#!/usr/bin/env ruby
# frozen_string_literal: true

# Simple token tracking debug script
# Traces usage data from Gemini provider through to final result

# Add RAAF to load path
raaf_root = File.expand_path(__dir__)
$LOAD_PATH.unshift File.join(raaf_root, "core/lib")
$LOAD_PATH.unshift File.join(raaf_root, "providers/lib")

# Load minimal dependencies
require "json"
require "net/http"
require "uri"

puts "=" * 80
puts "SIMPLE TOKEN DEBUG - Gemini Provider"
puts "=" * 80
puts

# Create minimal test without loading full RAAF
# Try to read from ProspectsRadar .env file if ENV not set
api_key = ENV["GOOGLE_API_KEY"]
if api_key.nil? || api_key.empty?
  env_file = "/Users/hajee/Enterprise Modules Dropbox/Bert Hajee/enterprisemodules/work/prospects_radar/.env"
  if File.exist?(env_file)
    env_content = File.read(env_file)
    if env_content =~ /GOOGLE_API_KEY=(.+)/
      api_key = $1.strip.split(/\s+#/).first.strip  # Remove comments
      puts "📝 Using GOOGLE_API_KEY from .env file"
    end
  end
end

if api_key.nil? || api_key.empty?
  puts "ERROR: GOOGLE_API_KEY not found in environment or .env file"
  puts "Expected location: #{env_file}"
  exit 1
end

# Direct API call to Gemini with usage tracking
url = URI("https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-exp:generateContent?key=#{api_key}")

payload = {
  "contents" => [
    {
      "parts" => [
        { "text" => "Say hello and tell me your model name." }
      ],
      "role" => "user"
    }
  ],
  "generationConfig" => {
    "temperature" => 1.0,
    "maxOutputTokens" => 100
  }
}

puts "1. Making API request to Gemini..."
puts "   URL: #{url}"
puts

http = Net::HTTP.new(url.host, url.port)
http.use_ssl = true

request = Net::HTTP::Post.new(url)
request["Content-Type"] = "application/json"
request.body = payload.to_json

response = http.request(request)

if response.code != "200"
  puts "ERROR: API request failed"
  puts "Status: #{response.code}"
  puts "Body: #{response.body}"
  exit 1
end

response_json = JSON.parse(response.body)

puts "2. API RESPONSE RECEIVED"
puts "   Response keys: #{response_json.keys.inspect}"
puts

if response_json["usageMetadata"]
  puts "3. ✅ USAGE METADATA FOUND IN RAW API RESPONSE"
  usage = response_json["usageMetadata"]
  puts "   Keys: #{usage.keys.inspect}"
  puts "   promptTokenCount: #{usage["promptTokenCount"]}"
  puts "   candidatesTokenCount: #{usage["candidatesTokenCount"]}"
  puts "   totalTokenCount: #{usage["totalTokenCount"]}"
else
  puts "3. ❌ NO USAGE METADATA in raw API response"
  puts "   This means Gemini API didn't return usage data"
end

puts
puts "=" * 80
puts "ANALYSIS:"
puts "=" * 80

if response_json["usageMetadata"]
  usage = response_json["usageMetadata"]
  puts "✅ The Gemini API returned usage metadata."
  puts "✅ promptTokenCount: #{usage["promptTokenCount"]}"
  puts "✅ candidatesTokenCount: #{usage["candidatesTokenCount"]}"
  puts "✅ totalTokenCount: #{usage["totalTokenCount"]}"
  puts
  puts "The issue is likely in how RAAF processes this response."
  puts "Next step: Check GeminiProvider's normalize_response method."
  puts "Location: providers/lib/raaf/providers/gemini_provider.rb"
  puts
  puts "Look for the normalize_response method and verify it extracts:"
  puts "- usage_metadata from the API response"
  puts "- Converts it to :usage in the returned hash"
  puts "- Properly maps the token field names"
else
  puts "❌ The Gemini API did NOT return usage metadata."
  puts "❌ This might be a model-specific issue."
  puts
  puts "Possible causes:"
  puts "1. gemini-2.0-flash-exp doesn't return usage (try gemini-2.5-flash)"
  puts "2. API configuration issue"
  puts "3. This is expected behavior for experimental models"
end
