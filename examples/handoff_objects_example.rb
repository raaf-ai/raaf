#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "openai_agents"

# Example demonstrating handoff objects with JSON schemas

puts "=== Handoff Objects Example ==="
puts "This example shows how to use handoff objects for advanced agent delegation"
puts

# 1. Basic Handoff Example
puts "=== Example 1: Basic Handoff ==="

# Create specialized agents
support_agent = OpenAIAgents::Agent.new(
  name: "SupportAgent",
  instructions: "You handle technical support questions. Be helpful and thorough.",
  model: "gpt-4o-mini",
  handoff_description: "Handles technical issues and troubleshooting"
)

billing_agent = OpenAIAgents::Agent.new(
  name: "BillingAgent",
  instructions: "You handle billing and payment questions. Be precise with numbers.",
  model: "gpt-4o-mini",
  handoff_description: "Handles billing, payments, and subscription issues"
)

# Create triage agent with simple handoffs
triage_agent = OpenAIAgents::Agent.new(
  name: "TriageAgent",
  instructions: "You are a triage agent. Determine if the user needs technical support or billing help, then handoff appropriately.",
  model: "gpt-4o-mini"
)

# Add simple handoffs
triage_agent.add_handoff(support_agent)
triage_agent.add_handoff(billing_agent)

runner = OpenAIAgents::Runner.new(agent: triage_agent)

# Test basic handoff
result = runner.run("I can't login to my account")
puts "Response: #{result.messages.last[:content]}"
puts "Final agent: #{result.last_agent.name}\n\n"

puts "=" * 50

# 2. Handoff Objects with Custom Descriptions
puts "\n=== Example 2: Custom Handoff Descriptions ==="

# Create handoff objects with custom descriptions
support_handoff = OpenAIAgents.handoff(
  support_agent,
  tool_description_override: "Transfer to technical support for login issues, bugs, or technical problems"
)

billing_handoff = OpenAIAgents.handoff(
  billing_agent,
  tool_description_override: "Transfer to billing for payment issues, refunds, or subscription questions"
)

# Create new triage agent with handoff objects
smart_triage = OpenAIAgents::Agent.new(
  name: "SmartTriage",
  instructions: "Route users to the appropriate department based on their needs.",
  model: "gpt-4o-mini"
)

smart_triage.add_handoff(support_handoff)
smart_triage.add_handoff(billing_handoff)

runner = OpenAIAgents::Runner.new(agent: smart_triage)

result = runner.run("I was charged twice for my subscription")
puts "Response: #{result.messages.last[:content]}"
puts "Final agent: #{result.last_agent.name}\n\n"

puts "=" * 50

# 3. Handoff with Input Validation
puts "\n=== Example 3: Handoff with Input Schema ==="

# Create an escalation agent that requires specific information
escalation_agent = OpenAIAgents::Agent.new(
  name: "EscalationAgent",
  instructions: "You handle escalated issues. You receive a priority level and description.",
  model: "gpt-4o-mini"
)

# Create handoff with input validation
escalation_handoff = OpenAIAgents.handoff(
  escalation_agent,
  tool_description_override: "Escalate to senior support with priority and description",
  input_type: Hash,
  on_handoff: lambda { |_context, input|
    # Validate the input
    raise "Escalation requires priority and description" unless input["priority"] && input["description"]
    
    # Log the escalation
    puts "[ESCALATION] Priority: #{input["priority"]}, Description: #{input["description"]}"
    
    # Could do additional processing here
    true
  }
)

# Create agent that can escalate
frontline_agent = OpenAIAgents::Agent.new(
  name: "FrontlineAgent",
  instructions: "You are frontline support. For complex issues, escalate with priority (low/medium/high) and description.",
  model: "gpt-4o-mini"
)

frontline_agent.add_handoff(escalation_handoff)

runner = OpenAIAgents::Runner.new(agent: frontline_agent)

puts "Testing escalation handoff..."
result = runner.run("The entire system is down and no one can access the platform!")
puts "Response: #{result.messages.last[:content]}"
puts "Final agent: #{result.last_agent.name}\n\n"

puts "=" * 50

# 4. Conditional Handoff
puts "\n=== Example 4: Conditional Handoff ==="

# Create VIP support agent
vip_agent = OpenAIAgents::Agent.new(
  name: "VIPSupport",
  instructions: "You provide premium support to VIP customers.",
  model: "gpt-4o-mini"
)

# Create conditional handoff that checks VIP status
vip_handoff = OpenAIAgents.handoff(
  vip_agent,
  tool_description_override: "Transfer to VIP support (only for premium customers)",
  on_handoff: lambda { |_context|
    # In real app, would check customer status
    # For demo, simulate VIP check
    is_vip = rand > 0.5
    
    if is_vip
      puts "[VIP CHECK] Customer is VIP - transferring to premium support"
      true
    else
      puts "[VIP CHECK] Customer is not VIP - cannot transfer"
      raise OpenAIAgents::HandoffError, "Customer is not eligible for VIP support"
    end
  }
)

regular_support = OpenAIAgents::Agent.new(
  name: "RegularSupport",
  instructions: "You provide standard support. Try to transfer VIP customers to premium support.",
  model: "gpt-4o-mini"
)

regular_support.add_handoff(vip_handoff)

runner = OpenAIAgents::Runner.new(agent: regular_support)

puts "Testing conditional VIP handoff..."
begin
  result = runner.run("I need help with my premium account features")
  puts "Response: #{result.messages.last[:content]}"
  puts "Final agent: #{result.last_agent.name}"
rescue OpenAIAgents::HandoffError => e
  puts "Handoff blocked: #{e.message}"
end

puts "\n" + ("=" * 50)

# 5. Complex Multi-Agent System with Handoff Objects
puts "\n=== Example 5: Complex Multi-Agent System ==="

# Create department agents
sales_agent = OpenAIAgents::Agent.new(
  name: "Sales",
  instructions: "You handle sales inquiries and product information.",
  model: "gpt-4o-mini"
)

technical_agent = OpenAIAgents::Agent.new(
  name: "Technical",
  instructions: "You handle technical questions and troubleshooting.",
  model: "gpt-4o-mini"
)

# Create handoffs with context filtering
def create_filtered_handoff(agent, filter_old_messages: false)
  OpenAIAgents.handoff(
    agent,
    input_filter: lambda { |handoff_data|
      if filter_old_messages
        # Keep only recent messages
        recent_items = handoff_data.new_items.last(3)
        OpenAIAgents::HandoffInputData.new(
          input_history: handoff_data.input_history,
          pre_handoff_items: [],
          new_items: recent_items
        )
      else
        handoff_data
      end
    }
  )
end

# Create router agent with filtered handoffs
router_agent = OpenAIAgents::Agent.new(
  name: "Router",
  instructions: "Route inquiries to the appropriate department.",
  model: "gpt-4o-mini"
)

router_agent.add_handoff(create_filtered_handoff(sales_agent, filter_old_messages: false))
router_agent.add_handoff(create_filtered_handoff(technical_agent, filter_old_messages: true))

# Allow agents to transfer back to router
sales_agent.add_handoff(router_agent)
technical_agent.add_handoff(router_agent)

runner = OpenAIAgents::Runner.new(agent: router_agent)

puts "Testing complex routing..."
result = runner.run("I want to buy your product but I'm having technical issues with the demo")
puts "Response: #{result.messages.last[:content]}"
puts "Final agent: #{result.last_agent.name}\n\n"

puts "=== Handoff Objects Examples Complete ==="
puts
puts "Key takeaways:"
puts "1. Handoff objects provide more control than simple agent handoffs"
puts "2. You can customize tool descriptions for better routing"
puts "3. Input validation ensures proper data is passed between agents"
puts "4. Conditional handoffs enable business logic in routing"
puts "5. Input filters allow controlling conversation context"
