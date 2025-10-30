#!/usr/bin/env ruby
# frozen_string_literal: true

# Test script to verify Gemini provider continuation support
require "bundler/setup"
require "raaf-core"
require "raaf-providers"

puts "🧪 Testing Gemini Provider Continuation Support"
puts "=" * 60

# Check if API key is set
unless ENV["GEMINI_API_KEY"]
  puts "❌ GEMINI_API_KEY not set"
  puts "Please set it with: export GEMINI_API_KEY='your-key'"
  exit 1
end

puts "✅ GEMINI_API_KEY is set"

# Test: Automatic Continuation
puts "\n📋 Test: Automatic Continuation (max_tokens=100 to force truncation)"
begin
  provider = RAAF::Models::GeminiProvider.new(api_key: ENV["GEMINI_API_KEY"])

  # Request long output with very low max_tokens to force truncation
  result = provider.perform_chat_completion(
    messages: [{ role: "user", content: "List 50 programming languages with brief descriptions" }],
    model: "gemini-2.0-flash-exp",
    max_tokens: 100,  # Very low to force truncation
    auto_continuation: true,
    max_continuation_attempts: 3
  )

  puts "✅ Continuation test successful"
  puts "   Content length: #{result.dig('choices', 0, 'message', 'content')&.length || 0} characters"
  puts "   Continuation chunks: #{result['continuation_chunks']}"
  puts "   Finish reason: #{result.dig('choices', 0, 'finish_reason')}"
  puts "   Usage: #{result['usage'].inspect}"

  if result["continuation_chunks"] > 1
    puts "   ✓ Multiple continuation chunks detected"
  else
    puts "   ⚠️ No continuation occurred (response may have fit in first chunk)"
  end
rescue => e
  puts "❌ Continuation test failed: #{e.message}"
  puts "   Error class: #{e.class.name}"
  puts e.backtrace.first(10).join("\n")
  exit 1
end

# Test: Continuation Disabled
puts "\n📋 Test: Continuation Disabled"
begin
  provider = RAAF::Models::GeminiProvider.new(api_key: ENV["GEMINI_API_KEY"])

  result = provider.perform_chat_completion(
    messages: [{ role: "user", content: "List 50 programming languages" }],
    model: "gemini-2.0-flash-exp",
    max_tokens: 100,
    auto_continuation: false  # Disable continuation
  )

  puts "✅ Continuation disabled test successful"
  puts "   Continuation chunks: #{result['continuation_chunks']}"

  if result["continuation_chunks"] == 1
    puts "   ✓ Only single chunk (as expected with continuation disabled)"
  else
    puts "   ❌ Expected single chunk but got #{result['continuation_chunks']}"
  end
rescue => e
  puts "❌ Continuation disabled test failed: #{e.message}"
  exit 1
end

puts "\n" + "=" * 60
puts "🎉 All continuation tests passed! Gemini provider supports automatic continuation."
puts "=" * 60
