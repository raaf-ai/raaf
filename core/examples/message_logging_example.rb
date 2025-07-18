#!/usr/bin/env ruby
# frozen_string_literal: true

# Example demonstrating provider-independent message logging
# This shows how to enable detailed logging of messages sent to and received from LLM endpoints

require_relative '../lib/raaf'

puts "=== RAAF Message Logging Example ==="
puts

# Enable API debug logging to see all message details
ENV['RAAF_DEBUG_CATEGORIES'] = 'api'
ENV['RAAF_LOG_LEVEL'] = 'debug'

puts "Debug categories enabled: #{ENV['RAAF_DEBUG_CATEGORIES']}"
puts "Log level: #{ENV['RAAF_LOG_LEVEL']}"
puts

# Create a support agent
support_agent = RAAF::Agent.new(
  name: "SupportAgent",
  instructions: "You are a helpful customer support agent. When users need billing help, transfer them to the billing department.",
  model: "gpt-4o"
)

# Create a billing agent for handoffs
billing_agent = RAAF::Agent.new(
  name: "BillingAgent", 
  instructions: "You are a billing specialist. Help users with billing questions and payment issues.",
  model: "gpt-4o"
)

# Set up handoff capability
support_agent.add_handoff(billing_agent)

# Create runner with default provider (will use ProviderAdapter internally)
runner = RAAF::Runner.new(agent: support_agent)

puts "=== Example 1: Basic Message Logging ==="
puts "This will show detailed request/response logging for a simple query"
puts

begin
  result = runner.run("Hello, can you help me with my account?")
  puts "Agent Response: #{result.messages.last[:content]}"
rescue => e
  puts "Error: #{e.message}"
end

puts
puts "=== Example 2: Handoff Message Logging ==="
puts "This will show detailed logging including handoff tool calls"
puts

begin
  result = runner.run("I need help with my billing statement")
  puts "Agent Response: #{result.messages.last[:content]}"
rescue => e
  puts "Error: #{e.message}"
end

puts
puts "=== Example 3: Provider-Independent Logging ==="
puts "The logging works the same regardless of the underlying provider"
puts

# Example of different provider types that would all show the same logging format
provider_examples = [
  {
    name: "ResponsesProvider (default)",
    description: "Uses OpenAI Responses API - shows native format"
  },
  {
    name: "OpenAI Chat Completions",
    description: "Uses Chat Completions API - shows format conversion"
  },
  {
    name: "Third-party providers",
    description: "Any provider - shows universal adapter logging"
  }
]

provider_examples.each do |example|
  puts "#{example[:name]}: #{example[:description]}"
end

puts
puts "=== Message Logging Features ==="
puts "✅ Provider-independent logging format"
puts "✅ Detailed request/response inspection"
puts "✅ Message content previews and lengths"
puts "✅ Tool call details and function names"
puts "✅ Usage statistics and token counts"
puts "✅ API format conversion tracking"
puts "✅ Handoff detection and processing"
puts "✅ Error handling and debugging"
puts
puts "=== How to Enable Message Logging ==="
puts "Set environment variables:"
puts "  RAAF_DEBUG_CATEGORIES=api     # Enable API debug logging"
puts "  RAAF_LOG_LEVEL=debug          # Set log level to debug"
puts
puts "Or programmatically:"
puts "  RAAF::Logging.configure do |config|"
puts "    config.debug_categories = [:api]"
puts "    config.log_level = :debug"
puts "  end"
puts
puts "=== Log Message Types ==="
puts "📤 PROVIDER REQUEST  - Messages sent to LLM endpoint"
puts "📥 PROVIDER RESPONSE - Messages received from LLM endpoint"
puts "🔄 PROVIDER ADAPTER  - Format conversion and normalization"
puts "🚀 RUNNER           - High-level request preparation"
puts "🎯 HANDOFF          - Agent handoff processing"
puts
puts "Example complete! Check the debug output above for detailed message logging."