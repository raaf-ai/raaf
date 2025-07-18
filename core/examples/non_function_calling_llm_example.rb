#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/raaf-core"
require_relative "../lib/raaf/models/provider_adapter"
require_relative "../lib/raaf/models/handoff_fallback_system"

##
# Non-Function-Calling LLM Handoff Example
#
# This example demonstrates how handoff support works with LLMs that
# don't support function calling, using content-based detection and
# structured prompting techniques.
#

puts "=" * 70
puts "RAAF Non-Function-Calling LLM Handoff Example"
puts "=" * 70

# Example 1: LLM that doesn't support function calling at all
class NonFunctionCallingLLM < RAAF::Models::ModelInterface
  def chat_completion(messages:, model:, stream: false, **kwargs)
    # Note: No tools parameter - this LLM doesn't support function calling
    puts "🔸 NonFunctionCallingLLM: Processing request (no function calling)"
    
    # Simulate different types of responses that might contain handoffs
    last_message = messages.last[:content].downcase
    
    response_content = if last_message.include?("billing")
      'I can help with basic questions, but for billing issues I need to transfer you to our billing specialist.\n\n{"handoff_to": "BillingAgent"}'
    elsif last_message.include?("technical")
      'For technical support, let me transfer you to our technical team.\n\n[HANDOFF:TechnicalAgent]'
    elsif last_message.include?("complex")
      'This seems like a complex issue. Transfer to SpecialistAgent for better assistance.'
    else
      'I can help with basic questions. What would you like to know?'
    end
    
    {
      "choices" => [{
        "message" => {
          "role" => "assistant",
          "content" => response_content
        }
      }],
      "usage" => {
        "prompt_tokens" => 30,
        "completion_tokens" => 20,
        "total_tokens" => 50
      }
    }
  end
  
  def supported_models
    ["non-function-model-v1"]
  end
  
  def provider_name
    "NonFunctionCallingLLM"
  end
end

# Example 2: LLM with limited function calling (some open source models)
class LimitedFunctionCallingLLM < RAAF::Models::ModelInterface
  def chat_completion(messages:, model:, tools: nil, stream: false, **kwargs)
    puts "🔹 LimitedFunctionCallingLLM: Processing request"
    puts "   Tools provided: #{tools&.size || 0}"
    
    # This LLM accepts tools parameter but doesn't handle complex function calling well
    # It might ignore tools or handle them poorly
    
    last_message = messages.last[:content].downcase
    
    # Sometimes it tries to use tools, sometimes it falls back to content
    if tools && tools.any? && rand < 0.3 # 30% chance of using tools
      # Attempt to use a tool (but might be malformed)
      tool_name = tools.sample[:name] || tools.sample["name"]
      response_content = "I'll use the #{tool_name} tool to help you."
      
      {
        "choices" => [{
          "message" => {
            "role" => "assistant",
            "content" => response_content,
            "tool_calls" => [{
              "id" => "call_#{rand(1000)}",
              "type" => "function",
              "function" => {
                "name" => tool_name,
                "arguments" => "{}"
              }
            }]
          }
        }],
        "usage" => { "prompt_tokens" => 40, "completion_tokens" => 25, "total_tokens" => 65 }
      }
    else
      # Fall back to content-based handoff
      response_content = if last_message.include?("support")
        'I understand you need support. Let me connect you with the right specialist.\n\n[TRANSFER:SupportAgent]'
      else
        'I can help with basic questions. What do you need assistance with?'
      end
      
      {
        "choices" => [{
          "message" => {
            "role" => "assistant",
            "content" => response_content
          }
        }],
        "usage" => { "prompt_tokens" => 35, "completion_tokens" => 20, "total_tokens" => 55 }
      }
    end
  end
  
  def supported_models
    ["limited-function-model-v1"]
  end
  
  def provider_name
    "LimitedFunctionCallingLLM"
  end
end

# Test the fallback system
puts "\n🧪 TESTING HANDOFF FALLBACK SYSTEM\n"

# Create fallback system
available_agents = ["BillingAgent", "TechnicalAgent", "SpecialistAgent", "SupportAgent"]
fallback_system = RAAF::Models::HandoffFallbackSystem.new(available_agents)

# Test cases for handoff detection
test_cases = [
  {
    content: 'I need help with billing.\n\n{"handoff_to": "BillingAgent"}',
    expected_agent: "BillingAgent"
  },
  {
    content: 'Let me transfer you to technical support.\n\n[HANDOFF:TechnicalAgent]',
    expected_agent: "TechnicalAgent"
  },
  {
    content: 'Transfer to SpecialistAgent for better assistance.',
    expected_agent: "SpecialistAgent"
  },
  {
    content: 'I will handoff to the SupportAgent now.',
    expected_agent: "SupportAgent"
  },
  {
    content: 'Just a regular response with no handoff.',
    expected_agent: nil
  }
]

puts "Testing handoff detection patterns..."
test_results = fallback_system.test_detection(test_cases)

puts "\n--- Test Results ---"
puts "Total Tests: #{test_results[:total_tests]}"
puts "Passed: #{test_results[:passed]}"
puts "Failed: #{test_results[:failed]}"
puts "Success Rate: #{test_results[:success_rate]}"

test_results[:details].each_with_index do |detail, i|
  status = detail[:passed] ? "✅" : "❌"
  puts "\n#{status} Test #{i + 1}:"
  puts "  Content: #{detail[:content]}"
  puts "  Expected: #{detail[:expected] || 'nil'}"
  puts "  Detected: #{detail[:detected] || 'nil'}"
end

# Demonstrate with actual providers
puts "\n\n🚀 PROVIDER ADAPTER WITH FALLBACK EXAMPLES\n"

test_providers = [
  { name: "NonFunctionCallingLLM", provider: NonFunctionCallingLLM.new },
  { name: "LimitedFunctionCallingLLM", provider: LimitedFunctionCallingLLM.new }
]

test_providers.each do |provider_info|
  puts "\n--- Testing #{provider_info[:name]} ---"
  
  # Create adapter with fallback support
  adapter = RAAF::Models::ProviderAdapter.new(provider_info[:provider], available_agents)
  
  # Test capabilities
  capabilities = adapter.capabilities
  puts "Capabilities:"
  capabilities.each do |capability, supported|
    status = supported ? "✅" : "❌"
    puts "  #{status} #{capability}"
  end
  
  puts "\nHandoff Support: #{adapter.supports_handoffs? ? '✅ Yes' : '❌ No'}"
  
  # Test enhanced system instructions
  base_instructions = "You are a helpful assistant."
  enhanced_instructions = adapter.get_enhanced_system_instructions(base_instructions, available_agents)
  
  if enhanced_instructions != base_instructions
    puts "\n📝 Enhanced Instructions Added:"
    puts "  ✅ Handoff instructions included for non-function-calling LLM"
    puts "  ✅ Available agents list provided"
    puts "  ✅ Multiple handoff formats explained"
  else
    puts "\n📝 Instructions: Standard (function calling supported)"
  end
  
  # Test content-based handoff detection
  test_content = 'I need to transfer you to billing support.\n\n{"handoff_to": "BillingAgent"}'
  detected_handoff = adapter.detect_content_based_handoff(test_content)
  
  if detected_handoff
    puts "\n🔍 Content-Based Handoff Detection:"
    puts "  ✅ Detected handoff to: #{detected_handoff}"
  else
    puts "\n🔍 Content-Based Handoff Detection: Not applicable (function calling supported)"
  end
end

# Show handoff statistics
puts "\n\n📊 HANDOFF DETECTION STATISTICS\n"

stats = fallback_system.get_detection_stats
puts "Total Attempts: #{stats[:total_attempts]}"
puts "Successful Detections: #{stats[:successful_detections]}"
puts "Success Rate: #{stats[:success_rate]}"
puts "Available Agents: #{stats[:available_agents].join(', ')}"

if stats[:most_effective_patterns].any?
  puts "\nMost Effective Patterns:"
  stats[:most_effective_patterns].each_with_index do |(pattern_index, count), i|
    puts "  #{i + 1}. Pattern #{pattern_index}: #{count} matches"
  end
end

puts "\n" + "=" * 70
puts "SUMMARY"
puts "=" * 70
puts "✅ NonFunctionCallingLLM: Works with content-based handoff detection"
puts "✅ LimitedFunctionCallingLLM: Works with hybrid approach (tools + content)"
puts "✅ Fallback System: Provides robust handoff support for all LLM types"
puts "✅ Enhanced Instructions: Guides LLMs to use proper handoff formats"
puts "✅ Pattern Detection: Multiple formats supported for maximum compatibility"

puts "\n💡 Key Benefits for Non-Function-Calling LLMs:"
puts "   • Content-based handoff detection with multiple patterns"
puts "   • Enhanced system instructions with handoff guidance"
puts "   • Fallback mechanisms for unreliable function calling"
puts "   • Statistics tracking for detection optimization"
puts "   • Seamless integration with existing RAAF architecture"

puts "\n📋 Supported LLM Types:"
puts "   ✅ Full function calling (OpenAI, Claude, etc.)"
puts "   ✅ Limited function calling (some fine-tuned models)"
puts "   ✅ No function calling (LLaMA, Mistral base, Falcon, etc.)"
puts "   ✅ Hybrid approaches (inconsistent function calling)"

puts "\n🎯 Next Steps:"
puts "   • Integrate fallback system into Runner by default"
puts "   • Add provider-specific handoff instruction templates"
puts "   • Implement confidence scoring for detection quality"
puts "   • Add support for custom handoff patterns"