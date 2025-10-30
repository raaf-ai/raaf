#!/usr/bin/env ruby
# frozen_string_literal: true

# Test script to verify Gemini provider integration
require "bundler/setup"
require "raaf-core"
require "raaf-providers"

puts "🧪 Testing Gemini Provider Integration"
puts "=" * 60

# Check if API key is set
unless ENV["GEMINI_API_KEY"]
  puts "❌ GEMINI_API_KEY not set"
  puts "Please set it with: export GEMINI_API_KEY='your-key'"
  exit 1
end

puts "✅ GEMINI_API_KEY is set"

# Test 1: Provider Registry Detection
puts "\n📋 Test 1: Provider Registry Detection"
detected_provider = RAAF::ProviderRegistry.detect("gemini-2.0-flash-exp")
if detected_provider == :gemini
  puts "✅ Model auto-detection works: gemini-2.0-flash-exp → :gemini"
else
  puts "❌ Model auto-detection failed: got #{detected_provider.inspect}"
  exit 1
end

# Test 2: Provider Creation
puts "\n📋 Test 2: Provider Creation"
begin
  provider = RAAF::ProviderRegistry.create(:gemini, api_key: ENV["GEMINI_API_KEY"])
  puts "✅ Provider created successfully"
  puts "   Provider name: #{provider.provider_name}"
  puts "   Supported models: #{provider.supported_models.join(', ')}"
rescue => e
  puts "❌ Provider creation failed: #{e.message}"
  puts e.backtrace.first(5).join("\n")
  exit 1
end

# Test 3: Basic Chat Completion
puts "\n📋 Test 3: Basic Chat Completion"
begin
  agent = RAAF::Agent.new(
    name: "TestAgent",
    instructions: "You are a helpful assistant. Respond concisely.",
    model: "gemini-2.0-flash-exp"
  )

  gemini_provider = RAAF::Models::GeminiProvider.new(api_key: ENV["GEMINI_API_KEY"])
  runner = RAAF::Runner.new(agent: agent, provider: gemini_provider)

  puts "   Sending test message: 'Say OK'"
  result = runner.run("Say OK")

  response_content = result.messages.last[:content]
  puts "✅ Chat completion successful"
  puts "   Response: #{response_content}"
  puts "   Usage: #{result.usage.inspect}"
rescue => e
  puts "❌ Chat completion failed: #{e.message}"
  puts "   Error class: #{e.class.name}"
  puts e.backtrace.first(10).join("\n")
  exit 1
end

# Test 4: Message Format Conversion
puts "\n📋 Test 4: Message Format Conversion"
begin
  messages = [
    { role: "system", content: "You are helpful" },
    { role: "user", content: "Hello" },
    { role: "assistant", content: "Hi there" }
  ]

  system_instruction, contents = provider.send(:extract_system_instruction, messages)

  if system_instruction == "You are helpful" && contents.length == 2
    puts "✅ Message format conversion works"
    puts "   System instruction: #{system_instruction}"
    puts "   Contents count: #{contents.length}"
    puts "   User role preserved: #{contents[0][:role] == 'user'}"
    puts "   Assistant → model: #{contents[1][:role] == 'model'}"
  else
    puts "❌ Message format conversion failed"
    exit 1
  end
rescue => e
  puts "❌ Message format test failed: #{e.message}"
  exit 1
end

# Test 5: Tool Conversion
puts "\n📋 Test 5: Tool Conversion"
begin
  tools = [{
    type: "function",
    function: {
      name: "get_weather",
      description: "Get weather",
      parameters: { type: "object", properties: { location: { type: "string" } } }
    }
  }]

  gemini_tools = provider.send(:convert_tools_to_gemini, tools)

  if gemini_tools[0][:functionDeclarations]
    func_decl = gemini_tools[0][:functionDeclarations][0]
    if func_decl[:name] == "get_weather"
      puts "✅ Tool conversion works"
      puts "   Function name: #{func_decl[:name]}"
      puts "   Has parameters: #{!func_decl[:parameters].nil?}"
    else
      puts "❌ Tool conversion failed"
      exit 1
    end
  else
    puts "❌ Tool conversion failed - no functionDeclarations"
    exit 1
  end
rescue => e
  puts "❌ Tool conversion test failed: #{e.message}"
  exit 1
end

puts "\n" + "=" * 60
puts "🎉 All tests passed! Gemini provider is working correctly."
puts "=" * 60
