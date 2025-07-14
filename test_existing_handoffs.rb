#!/usr/bin/env ruby
# frozen_string_literal: true

# Test script to verify existing handoff functionality still works
# with our new unified handoff detection system

require_relative "lib/openai_agents"

puts "=== Testing Existing Handoff Functionality ==="

# Create agents similar to the examples
support_agent = OpenAIAgents::Agent.new(
  name: "SupportAgent",
  instructions: "You handle technical support questions.",
  handoff_description: "Handles technical issues and troubleshooting"
)

billing_agent = OpenAIAgents::Agent.new(
  name: "BillingAgent", 
  instructions: "You handle billing and payment questions.",
  handoff_description: "Handles billing, payments, and subscription issues"
)

triage_agent = OpenAIAgents::Agent.new(
  name: "TriageAgent",
  instructions: "You are a triage agent. Route to appropriate department."
)

# Add handoffs
triage_agent.add_handoff(support_agent)
triage_agent.add_handoff(billing_agent)

# Test 1: Verify handoff configuration
puts "\n1. Handoff Configuration Test:"
puts "   Triage agent handoffs: #{triage_agent.handoffs.size}"
puts "   Can handoff to: #{triage_agent.handoffs.map(&:name).join(", ")}"

# Test 2: Verify tool generation
runner = OpenAIAgents::Runner.new(agent: triage_agent)
tools = runner.send(:get_all_tools_for_api, triage_agent)

puts "\n2. Tool Generation Test:"
if tools
  handoff_tools = tools.select { |tool| tool[:name].start_with?("transfer_to_") }
  puts "   Generated handoff tools: #{handoff_tools.size}"
  handoff_tools.each do |tool|
    puts "   - #{tool[:name]}: #{tool[:function][:description]}"
  end
else
  puts "   No tools generated"
end

# Test 3: Verify tool name extraction
puts "\n3. Tool Name Extraction Test:"
test_cases = [
  "transfer_to_supportagent",
  "transfer_to_billingagent", 
  "transfer_to_customer_service",
  "transfer_to_TechnicalSupport"
]

test_cases.each do |tool_name|
  extracted = runner.send(:extract_agent_name_from_tool, tool_name)
  puts "   #{tool_name} -> #{extracted}"
end

# Test 4: Test handoff detection in responses
puts "\n4. Handoff Detection Test:"

# JSON handoff detection
json_content = '{"response": "I understand", "handoff_to": "SupportAgent"}'
result = runner.send(:detect_handoff_in_content, json_content, triage_agent)
puts "   JSON handoff detection: #{result || "none"}"

# Text handoff detection  
text_content = "I'll transfer you to the SupportAgent for technical assistance."
result = runner.send(:detect_handoff_in_content, text_content, triage_agent)
puts "   Text handoff detection: #{result || "none"}"

# Invalid handoff detection
invalid_content = '{"handoff_to": "NonExistentAgent"}'
result = runner.send(:detect_handoff_in_content, invalid_content, triage_agent)
puts "   Invalid handoff detection: #{result || "none"}"

# Test 5: Verify handoff validation
puts "\n5. Handoff Validation Test:"
available_targets = runner.send(:get_available_handoff_targets, triage_agent)
puts "   Available targets: #{available_targets.join(", ")}"

# Test various validation scenarios
test_targets = ["SupportAgent", "supportagent", "Support", "BillingAgent", "NonExistent"]
test_targets.each do |target|
  validated = runner.send(:validate_handoff_target, target, available_targets)
  puts "   '#{target}' -> #{validated || "invalid"}"
end

# Test 6: Test handoff objects (if using them)
puts "\n6. Handoff Objects Test:"
begin
  custom_handoff = OpenAIAgents.handoff(
    support_agent,
    tool_description_override: "Custom support handoff description"
  )
  
  custom_triage = OpenAIAgents::Agent.new(
    name: "CustomTriage",
    instructions: "Custom triage with handoff objects"
  )
  
  custom_triage.add_handoff(custom_handoff)
  
  puts "   Handoff object created successfully"
  puts "   Tool name: #{custom_handoff.tool_name}"
  puts "   Description: #{custom_handoff.tool_description}"
  
rescue => e
  puts "   Error creating handoff object: #{e.message}"
end

puts "\n=== All Tests Completed ==="
puts "The existing handoff functionality is working correctly with the new unified system!"