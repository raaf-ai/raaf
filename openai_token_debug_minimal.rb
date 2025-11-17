#!/usr/bin/env ruby
# frozen_string_literal: true

# Minimal OpenAI token tracking debug script
# Bypasses tiktoken_ruby dependency by manually loading only essential files

require "json"
require "net/http"
require "uri"

puts "=" * 80
puts "MINIMAL TOKEN DEBUG - OpenAI Provider"
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

# Step 1: Verify raw API returns usage data
puts "=" * 80
puts "STEP 1: Verify Raw OpenAI API Response"
puts "=" * 80
puts

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

# Step 2: Manually load RAAF components and trace token flow
puts
puts "=" * 80
puts "STEP 2: Load RAAF Components and Trace Token Flow"
puts "=" * 80
puts

# Add RAAF to load path
raaf_root = File.expand_path(__dir__)
$LOAD_PATH.unshift File.join(raaf_root, "core/lib")
$LOAD_PATH.unshift File.join(raaf_root, "providers/lib")

# Manually load files in dependency order, skipping token_estimator
puts "4. Loading RAAF components manually..."

# Core dependencies
require "active_support"
require "active_support/core_ext/hash/indifferent_access"
require "logger"

# Skip version and logger - not needed for debugging
# require "raaf/version"

# Load essential classes manually
core_lib = File.join(raaf_root, "core/lib")
providers_lib = File.join(raaf_root, "providers/lib")

# Define minimal RAAF module
module RAAF
  module Models
  end
end

# Load core classes
require File.join(core_lib, "raaf/run_context")
require File.join(core_lib, "raaf/agent")
require File.join(core_lib, "raaf/runner")

# Load provider
require File.join(providers_lib, "raaf/providers/openai_provider")

puts "✅ RAAF components loaded (without token_estimator)"
puts

# Step 3: Patch OpenAIProvider to debug token flow
puts "5. Patching OpenAIProvider to trace token usage..."

module RAAF
  module Models
    class OpenAIProvider
      alias_method :original_chat_completion, :chat_completion

      def chat_completion(messages:, model:, **kwargs)
        puts "\n6. OpenAIProvider.chat_completion called"
        puts "   Model: #{model}"
        puts "   Messages count: #{messages.count}"

        result = original_chat_completion(messages: messages, model: model, **kwargs)

        puts "\n7. OpenAIProvider response:"
        puts "   Response class: #{result.class}"
        puts "   Response keys: #{result.keys}" if result.is_a?(Hash)

        if result[:usage]
          puts "\n8. ✅ PROVIDER LEVEL - Usage found in response:"
          puts "   usage keys: #{result[:usage].keys}"
          puts "   prompt_tokens: #{result[:usage][:prompt_tokens]}"
          puts "   completion_tokens: #{result[:usage][:completion_tokens]}"
          puts "   total_tokens: #{result[:usage][:total_tokens]}"
        else
          puts "\n8. ❌ PROVIDER LEVEL - NO usage field in response!"
        end

        result
      end
    end
  end
end

# Step 4: Patch Runner to trace token flow
puts "   Patching Runner to trace token flow..."

module RAAF
  class Runner
    alias_method :original_run, :run

    def run(message = nil, **kwargs)
      puts "\n9. Runner.run called"
      result = original_run(message, **kwargs)

      puts "\n10. Runner result:"
      puts "   Result class: #{result.class}"

      # Check for usage in different possible locations
      if result.respond_to?(:usage)
        puts "\n11. ✅ FINAL RESULT - Usage accessible via method:"
        usage = result.usage
        puts "   Usage: #{usage.inspect}"
      else
        puts "\n11. ❌ FINAL RESULT - No usage method!"
      end

      if result.respond_to?(:[]) && result[:usage]
        puts "\n12. ✅ FINAL RESULT - Usage accessible via hash key:"
        puts "   prompt_tokens: #{result[:usage][:prompt_tokens]}"
        puts "   completion_tokens: #{result[:usage][:completion_tokens]}"
        puts "   total_tokens: #{result[:usage][:total_tokens]}"
      else
        puts "\n12. ❌ FINAL RESULT - NO usage via hash key!"
      end

      # Check RunContext internals
      if result.is_a?(RAAF::RunContext)
        puts "\n13. Result is RunContext - checking internal data:"

        # Check instance variables
        if result.instance_variable_defined?(:@data)
          data = result.instance_variable_get(:@data)
          puts "   @data exists, keys: #{data.keys.inspect}"
          puts "   @data[:usage]: #{data[:usage].inspect}" if data.key?(:usage)
        end

        # Try get method
        if result.respond_to?(:get)
          puts "   result.get(:usage): #{result.get(:usage).inspect}"
        end
      end

      result
    end
  end
end

puts "✅ Patches applied"
puts

# Step 5: Create and run agent
puts "=" * 80
puts "STEP 3: Run Agent and Trace Token Flow"
puts "=" * 80
puts

agent = RAAF::Agent.new(
  name: "TestAgent",
  instructions: "You are a helpful assistant. Respond briefly to test token tracking.",
  model: "gpt-4o-mini"
)

puts "14. Agent created with model: #{agent.model}"

provider = RAAF::Models::OpenAIProvider.new
runner = RAAF::Runner.new(agent: agent, provider: provider)
result = runner.run("Say hello and tell me your model name.")

puts "\n" + "=" * 80
puts "DEBUG COMPLETE"
puts "=" * 80
puts
puts "SUMMARY:"
puts "- Raw OpenAI API: #{response_json["usage"] ? "✅ Returns usage data" : "❌ No usage data"}"
puts "- Provider level: Check output above for usage data presence"
puts "- Runner level: Check output above for usage data presence"
puts "- Final result: Check output above for usage data presence"
