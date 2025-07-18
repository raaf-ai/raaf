#!/usr/bin/env ruby
# frozen_string_literal: true

# Example demonstrating Python SDK compatibility for RAAF handoffs
# This matches the exact behavior of the OpenAI Python SDK

require_relative "../lib/raaf"

puts "=== RAAF Python SDK Compatibility Example ==="
puts "This example shows how RAAF now matches the Python SDK exactly"

# Example 1: Simple Direct Handoffs (matches Python SDK)
puts "\n1. Simple Direct Handoffs (Python SDK Style)"

# Create specialized agents
spanish_agent = RAAF::Agent.new(
  name: "Spanish agent",
  instructions: "You only speak Spanish.",
  handoff_description: "Use this agent for Spanish language requests"
)

english_agent = RAAF::Agent.new(
  name: "English agent", 
  instructions: "You only speak English",
  handoff_description: "Use this agent for English language requests"
)

# Create triage agent with handoffs (exactly like Python SDK)
triage_agent = RAAF::Agent.new(
  name: "Triage agent",
  instructions: "Handoff to the appropriate agent based on the language of the request.",
  handoffs: [spanish_agent, english_agent]  # Direct agents, auto-generates tools
)

puts "✅ Created triage agent with handoffs to Spanish and English agents"
puts "   Auto-generated tools: transfer_to_spanish_agent, transfer_to_english_agent"

# Example 2: Custom Handoffs with overrides (matches Python SDK)
puts "\n2. Custom Handoffs with Overrides"

# Create specialized agents
billing_agent = RAAF::Agent.new(
  name: "Billing agent",
  instructions: "Handle billing inquiries",
  handoff_description: "Use for billing and payment questions"
)

refund_agent = RAAF::Agent.new(
  name: "Refund agent",
  instructions: "Process refund requests",
  handoff_description: "Use for refund processing"
)

# Create triage agent with custom handoffs
customer_service_agent = RAAF::Agent.new(
  name: "Customer service",
  instructions: "Route customer inquiries to appropriate specialists",
  handoffs: [
    billing_agent,  # Simple handoff
    RAAF.handoff(    # Custom handoff with overrides
      refund_agent,
      overrides: { model: "gpt-4", temperature: 0.3 },
      tool_name_override: "escalate_to_refunds",
      tool_description_override: "Escalate to refund specialist for processing",
      on_handoff: proc { |data| puts "🔄 Escalating to refunds: #{data[:context]}" }
    )
  ]
)

puts "✅ Created customer service agent with mixed handoff types"
puts "   Tools: transfer_to_billing_agent, escalate_to_refunds"

# Example 3: Input Filters (matches Python SDK)
puts "\n3. Input Filters for Data Processing"

# Create agents with input filtering
support_agent = RAAF::Agent.new(
  name: "Support agent",
  instructions: "Provide technical support",
  handoff_description: "Use for technical support issues"
)

# Agent with input filter
filtered_agent = RAAF::Agent.new(
  name: "Filtered agent",
  instructions: "Route requests with data filtering",
  handoffs: [
    RAAF.handoff(
      support_agent,
      input_filter: proc do |data|
        # Filter sensitive information
        filtered_data = data.dup
        filtered_data[:context] = filtered_data[:context]&.gsub(/password:\s*\S+/i, "password: [REDACTED]")
        filtered_data[:sanitized] = true
        filtered_data
      end,
      on_handoff: proc { |data| puts "🔒 Data filtered before handoff: #{data[:sanitized]}" }
    )
  ]
)

puts "✅ Created agent with input filtering for sensitive data"

# Example 4: Demonstrate the execution flow (simulated)
puts "\n4. Execution Flow Simulation"

class SimulatedInput
  def initialize(data)
    @data = data
  end

  def to_json
    @data.to_json
  end
end

# Simulate what happens when LLM calls handoff tool
puts "\nSimulating LLM calling transfer_to_spanish_agent:"

# This is what the auto-generated tool does
handoff_proc = proc do |**args|
  puts "  📞 Tool called with args: #{args}"
  
  # Tool returns handoff request (matches Python SDK)
  result = {
    _handoff_requested: true,
    _target_agent: spanish_agent,
    _handoff_data: args,
    _handoff_reason: args[:context] || "Language-based handoff"
  }
  
  puts "  ✅ Handoff requested to: #{spanish_agent.name}"
  puts "  📋 Handoff data: #{args}"
  
  result.to_json
end

# Simulate LLM calling the tool
handoff_result = handoff_proc.call(context: "User spoke in Spanish")
puts "  📤 Tool response: #{handoff_result}"

# Example 5: Runner Compatibility
puts "\n5. Runner with Automatic Handoff Detection"

# Create a runner that handles handoffs automatically
runner = RAAF::Runner.new(agent: triage_agent)

puts "✅ Created runner with automatic handoff detection"
puts "   Runner will:"
puts "   - Detect handoff requests in tool calls"
puts "   - Switch to target agent automatically"
puts "   - Pass full conversation history to new agent"
puts "   - Continue conversation from target agent"

# Example 6: Context Preservation (Python SDK behavior)
puts "\n6. Context Preservation Simulation"

# Simulate conversation history
conversation_history = [
  { role: "user", content: "Hola, necesito ayuda" },
  { role: "assistant", content: "I'll transfer you to our Spanish agent" },
  { role: "assistant", content: "[Function call: transfer_to_spanish_agent]" },
  { role: "tool", content: '{"_handoff_requested": true}' }
]

puts "📝 Conversation history before handoff:"
conversation_history.each_with_index do |msg, i|
  puts "   #{i + 1}. #{msg[:role]}: #{msg[:content]}"
end

puts "\n🔄 After handoff, Spanish agent receives full conversation history"
puts "   This matches Python SDK behavior exactly"

# Example 7: Tool Name Generation
puts "\n7. Tool Name Generation (Python SDK Compatible)"

test_agents = [
  RAAF::Agent.new(name: "Customer Service Agent", instructions: "Help customers"),
  RAAF::Agent.new(name: "Technical Support", instructions: "Technical help"),
  RAAF::Agent.new(name: "Billing-Department", instructions: "Handle billing")
]

puts "Generated tool names (matches Python SDK conversion):"
test_agents.each do |agent|
  tool_name = "transfer_to_#{agent.name.downcase.gsub(/[^a-z0-9_]/, '_')}"
  puts "  #{agent.name} → #{tool_name}"
end

puts "\n🎉 Python SDK Compatibility Complete!"
puts "\nKey Features Implemented:"
puts "✅ Handoffs in agent constructor"
puts "✅ Automatic tool generation"
puts "✅ Context preservation during handoffs"
puts "✅ Custom handoff objects with overrides"
puts "✅ Input filters for data processing"
puts "✅ Callback functions (on_handoff)"
puts "✅ Tool name and description overrides"
puts "✅ Exact Python SDK handoff() function signature"
puts "✅ Compatible runner with automatic handoff detection"

puts "\nUsage Example:"
puts "```ruby"
puts "# Exactly like Python SDK"
puts "spanish_agent = RAAF::Agent.new(name: 'Spanish agent', instructions: '...')"
puts "english_agent = RAAF::Agent.new(name: 'English agent', instructions: '...')"
puts ""
puts "triage_agent = RAAF::Agent.new("
puts "  name: 'Triage agent',"
puts "  instructions: 'Route based on language',"
puts "  handoffs: [spanish_agent, english_agent]"
puts ")"
puts ""
puts "runner = RAAF::Runner.new(agent: triage_agent)"
puts "result = runner.run('Hola, necesito ayuda')"
puts "```"