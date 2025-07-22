#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/raaf-core"
require_relative "../lib/raaf/models/provider_adapter"
require_relative "../lib/raaf/models/enhanced_interface"
require_relative "../lib/raaf/models/capability_detector"

##
# Universal Handoff Support Example
#
# This example demonstrates how handoff support works across different
# provider types using the new universal handoff architecture.
#

puts "=" * 60
puts "RAAF Universal Handoff Support Example"
puts "=" * 60

# Example 1: Third-party provider that only implements chat_completion
class ThirdPartyProvider < RAAF::Models::ModelInterface

  def chat_completion(messages:, model:, tools: nil, stream: false, **_kwargs)
    # Simulate a third-party provider that supports function calling
    # but doesn't know about the Responses API

    puts "🔷 ThirdPartyProvider: Received chat_completion request"
    puts "   Messages: #{messages.size}"
    puts "   Tools: #{tools&.size || 0}"

    # Simulate response with tool call (for handoff)
    {
      "choices" => [{
        "message" => {
          "role" => "assistant",
          "content" => "I need to transfer you to a specialist.",
          "tool_calls" => if tools&.any?
                            [{
                              "id" => "call_123",
                              "type" => "function",
                              "function" => {
                                "name" => "transfer_to_specialist",
                                "arguments" => "{}"
                              }
                            }]
                          end
        }
      }],
      "usage" => {
        "prompt_tokens" => 50,
        "completion_tokens" => 20,
        "total_tokens" => 70
      }
    }
  end

  def supported_models
    ["third-party-model-v1"]
  end

  def provider_name
    "ThirdPartyProvider"
  end

end

# Example 2: Enhanced provider that inherits handoff support
class EnhancedProvider < RAAF::Models::EnhancedModelInterface

  def chat_completion(messages:, model:, tools: nil, stream: false, **_kwargs)
    puts "🔶 EnhancedProvider: Received chat_completion request"
    puts "   Messages: #{messages.size}"
    puts "   Tools: #{tools&.size || 0}"

    # This provider automatically gets handoff support!
    {
      "choices" => [{
        "message" => {
          "role" => "assistant",
          "content" => "Let me help you with that.",
          "tool_calls" => if tools&.any?
                            [{
                              "id" => "call_456",
                              "type" => "function",
                              "function" => {
                                "name" => "transfer_to_billing",
                                "arguments" => "{}"
                              }
                            }]
                          end
        }
      }],
      "usage" => {
        "prompt_tokens" => 40,
        "completion_tokens" => 15,
        "total_tokens" => 55
      }
    }
  end

  def supported_models
    ["enhanced-model-v1"]
  end

  def provider_name
    "EnhancedProvider"
  end

end

# Example 3: Legacy provider that doesn't support function calling
class LegacyProvider < RAAF::Models::ModelInterface

  def chat_completion(messages:, model:, stream: false, **_kwargs)
    # NOTE: No tools parameter - doesn't support function calling
    puts "🔸 LegacyProvider: Received chat_completion request (no tools support)"

    {
      "choices" => [{
        "message" => {
          "role" => "assistant",
          "content" => "I can help with basic questions but cannot handle handoffs."
        }
      }],
      "usage" => {
        "prompt_tokens" => 30,
        "completion_tokens" => 10,
        "total_tokens" => 40
      }
    }
  end

  def supported_models
    ["legacy-model-v1"]
  end

  def provider_name
    "LegacyProvider"
  end

end

# Demonstrate capability detection
puts "\n🔍 CAPABILITY DETECTION EXAMPLES\n"

providers = [
  ThirdPartyProvider.new,
  EnhancedProvider.new,
  LegacyProvider.new
]

providers.each do |provider|
  puts "\n--- #{provider.provider_name} ---"

  detector = RAAF::Models::CapabilityDetector.new(provider)
  report = detector.generate_report

  puts "Handoff Support: #{report[:handoff_support]}"
  puts "Optimal Usage: #{report[:optimal_usage]}"

  report[:capabilities].each do |capability|
    status = capability[:supported] ? "✅" : "❌"
    priority = capability[:priority] == :high ? "🔴" : "🟡"
    puts "  #{status} #{priority} #{capability[:name]}: #{capability[:description]}"
  end

  next unless report[:recommendations].any?

  puts "\nRecommendations:"
  report[:recommendations].each do |rec|
    icon = case rec[:type]
           when :success then "✅"
           when :warning then "⚠️"
           when :critical then "🚨"
           else "ℹ️"
           end
    puts "  #{icon} #{rec[:message]}"
  end
end

# Demonstrate universal handoff support
puts "\n\n🚀 UNIVERSAL HANDOFF EXAMPLES\n"

# Create agents with handoff capability
specialist_agent = RAAF::Agent.new(
  name: "Specialist",
  instructions: "You are a specialist who can help with complex issues."
)

billing_agent = RAAF::Agent.new(
  name: "Billing",
  instructions: "You handle billing and payment questions."
)

main_agent = RAAF::Agent.new(
  name: "MainAgent",
  instructions: "You are the main agent who can handoff to specialists."
)

# Add handoffs
main_agent.add_handoff(specialist_agent)
main_agent.add_handoff(billing_agent)

# Test with different provider types
test_providers = [
  { name: "ThirdPartyProvider", provider: ThirdPartyProvider.new },
  { name: "EnhancedProvider", provider: EnhancedProvider.new },
  { name: "LegacyProvider", provider: LegacyProvider.new }
]

test_providers.each do |provider_info|
  puts "\n--- Testing #{provider_info[:name]} ---"

  begin
    # Wrap provider with adapter for universal handoff support
    adapter = RAAF::Models::ProviderAdapter.new(provider_info[:provider])

    # Create runner with adapted provider
    runner = RAAF::Runner.new(
      agent: main_agent,
      provider: adapter,
      agents: [main_agent, specialist_agent, billing_agent]
    )

    # Test the handoff flow
    puts "Testing handoff capability..."

    # Check if handoffs are supported
    if adapter.supports_handoffs?
      puts "✅ Handoffs supported! Tools available: #{runner.send(:get_all_tools_for_api, main_agent)&.size || 0}"

      # Simulate a conversation that would trigger handoff
      # (In real usage, this would be determined by the AI model)
      puts "🔄 Handoff tools registered and ready for use"

    else
      puts "❌ Handoffs not supported - limited functionality"
    end
  rescue StandardError => e
    puts "❌ Error: #{e.message}"
  end
end

puts "\n#{"=" * 60}"
puts "SUMMARY"
puts "=" * 60
puts "✅ ThirdPartyProvider: Works with ProviderAdapter"
puts "✅ EnhancedProvider: Works natively with handoff support"
puts "⚠️  LegacyProvider: Limited functionality (no function calling)"
puts "\n💡 Key Benefits:"
puts "   • Universal handoff support across all provider types"
puts "   • Automatic capability detection and adaptation"
puts "   • Zero breaking changes to existing code"
puts "   • Clear migration path for provider authors"
puts "   • Comprehensive error handling and debugging"

puts "\n🎯 Next Steps:"
puts "   • Integrate ProviderAdapter into Runner by default"
puts "   • Update documentation with new provider patterns"
puts "   • Add comprehensive test coverage"
puts "   • Create migration guide for existing providers"
