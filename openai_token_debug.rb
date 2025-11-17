#!/usr/bin/env ruby
# frozen_string_literal: true

# Simple token tracking debug script for OpenAI
# Traces usage data from OpenAI provider through to final result

# Add RAAF to load path
raaf_root = File.expand_path(__dir__)
$LOAD_PATH.unshift File.join(raaf_root, "core/lib")
$LOAD_PATH.unshift File.join(raaf_root, "providers/lib")

# Load minimal dependencies
require "json"
require "net/http"
require "uri"

puts "=" * 80
puts "TOKEN DEBUG - OpenAI Provider"
puts "=" * 80
puts

# Read API key from .env file
env_file = "/Users/hajee/Enterprise Modules Dropbox/Bert Hajee/enterprisemodules/work/prospects_radar/.env"
api_key = ENV["OPENAI_API_KEY"]

if api_key.nil? || api_key.empty?
  if File.exist?(env_file)
    env_content = File.read(env_file)
    if env_content =~ /OPENAI_API_KEY=(.+)/
      api_key = $1.strip.split(/\s+#/).first.strip
      puts "📝 Using OPENAI_API_KEY from .env file"
    end
  end
end

if api_key.nil? || api_key.empty?
  puts "ERROR: OPENAI_API_KEY not found"
  exit 1
end

# Direct API call to OpenAI with usage tracking
url = URI("https://api.openai.com/v1/chat/completions")

payload = {
  "model" => "gpt-4o-mini",
  "messages" => [
    {
      "role" => "user",
      "content" => "Say hello and tell me your model name."
    }
  ],
  "max_tokens" => 100
}

puts "1. Making API request to OpenAI..."
puts "   Model: gpt-4o-mini"
puts

http = Net::HTTP.new(url.host, url.port)
http.use_ssl = true

request = Net::HTTP::Post.new(url)
request["Content-Type"] = "application/json"
request["Authorization"] = "Bearer #{api_key}"
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

if response_json["usage"]
  puts "3. ✅ USAGE DATA FOUND IN RAW API RESPONSE"
  usage = response_json["usage"]
  puts "   Keys: #{usage.keys.inspect}"
  puts "   prompt_tokens: #{usage["prompt_tokens"]}"
  puts "   completion_tokens: #{usage["completion_tokens"]}"
  puts "   total_tokens: #{usage["total_tokens"]}"

  if usage["completion_tokens_details"]
    puts "   completion_tokens_details: #{usage["completion_tokens_details"].inspect}"
  end
else
  puts "3. ❌ NO USAGE DATA in raw API response"
end

puts
puts "=" * 80
puts "NOW TESTING WITH RAAF"
puts "=" * 80
puts

# Now test with RAAF
require "raaf-core"
require "raaf/providers/openai_provider"

puts "4. Creating RAAF agent with OpenAI..."
agent = RAAF::Agent.new(
  name: "TestAgent",
  instructions: "You are a helpful assistant.",
  model: "gpt-4o-mini"
)

# Patch OpenAIProvider to add debug output
module RAAF
  module Models
    class OpenAIProvider
      alias_method :original_chat_completion, :chat_completion

      def chat_completion(messages:, model:, **kwargs)
        puts "\n5. OpenAIProvider.chat_completion called"
        result = original_chat_completion(messages: messages, model: model, **kwargs)

        puts "\n6. OpenAIProvider response:"
        puts "   Response class: #{result.class}"
        puts "   Response keys: #{result.keys}" if result.is_a?(Hash)

        if result[:usage]
          puts "\n7. ✅ PROVIDER LEVEL - Usage found:"
          puts "   usage keys: #{result[:usage].keys}"
          puts "   prompt_tokens: #{result[:usage][:prompt_tokens]}"
          puts "   completion_tokens: #{result[:usage][:completion_tokens]}"
          puts "   total_tokens: #{result[:usage][:total_tokens]}"
        else
          puts "\n7. ❌ PROVIDER LEVEL - NO usage field!"
        end

        result
      end
    end
  end
end

# Patch Runner to see what it receives
module RAAF
  class Runner
    alias_method :original_run, :run

    def run(message = nil, **kwargs)
      puts "\n8. Runner.run called"
      result = original_run(message, **kwargs)

      puts "\n9. Runner result:"
      puts "   Result class: #{result.class}"

      if result.respond_to?(:usage)
        puts "\n10. ✅ FINAL RESULT - Usage accessible via method:"
        usage = result.usage
        puts "   Usage: #{usage.inspect}"
      else
        puts "\n10. ❌ FINAL RESULT - No usage method!"
      end

      if result.respond_to?(:[]) && result[:usage]
        puts "\n11. ✅ FINAL RESULT - Usage accessible via hash key:"
        puts "   prompt_tokens: #{result[:usage][:prompt_tokens]}"
        puts "   completion_tokens: #{result[:usage][:completion_tokens]}"
        puts "   total_tokens: #{result[:usage][:total_tokens]}"
      else
        puts "\n11. ❌ FINAL RESULT - NO usage via hash key!"
      end

      result
    end
  end
end

provider = RAAF::Models::OpenAIProvider.new
runner = RAAF::Runner.new(agent: agent, provider: provider)
result = runner.run("Say hello and tell me your model name.")

puts "\n" + "=" * 80
puts "DEBUG COMPLETE"
puts "=" * 80
