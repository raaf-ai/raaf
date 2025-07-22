#!/usr/bin/env ruby
# frozen_string_literal: true

# This example demonstrates advanced agent handoff patterns in RAAF (Ruby AI Agents Factory).
# Handoffs allow agents to delegate tasks to specialized agents, creating powerful
# multi-agent workflows. Handoff objects provide fine-grained control over how
# agents transfer control, validate inputs, and manage conversation context.
# This is essential for building customer service systems, expert networks, and
# complex AI workflows.

require "bundler/setup"
require_relative "../lib/raaf-core"

# ============================================================================
# HANDOFF OBJECTS EXAMPLES
# ============================================================================

puts "=== Handoff Objects Example ==="
puts "This example shows how to use handoff objects for advanced agent delegation"
puts

# ============================================================================
# EXAMPLE 1: BASIC HANDOFF PATTERN
# ============================================================================
# Shows the simplest form of agent handoff where one agent can transfer
# control to specialized agents based on the conversation context.

puts "=== Example 1: Basic Handoff ==="

# Create specialized agents with specific expertise
# Each agent has a focused role and instructions

# Technical support specialist
support_agent = RAAF::Agent.new(
  name: "SupportAgent",

  # Clear instructions for the agent's role
  instructions: "You handle technical support questions. Be helpful and thorough.",

  model: "gpt-4o-mini", # Using smaller model for examples

  # handoff_description helps other agents understand when to transfer
  handoff_description: "Handles technical issues and troubleshooting"
)

# Billing specialist
billing_agent = RAAF::Agent.new(
  name: "BillingAgent",

  instructions: "You handle billing and payment questions. Be precise with numbers.",

  model: "gpt-4o-mini",

  handoff_description: "Handles billing, payments, and subscription issues"
)

# Create triage agent that routes to specialists
# This agent acts as the entry point and router
triage_agent = RAAF::Agent.new(
  name: "TriageAgent",

  # Instructions emphasize routing responsibility with clear decision criteria
  instructions: "You are a triage agent. For login issues, bugs, or technical problems, handoff to SupportAgent. For payment issues, refunds, or subscriptions, handoff to BillingAgent. If you're unsure or the issue doesn't clearly fit either category, provide a brief helpful response yourself.",

  model: "gpt-4o-mini"
)

# Add handoff capabilities to the triage agent
# The agent can now transfer to these specialists
triage_agent.add_handoff(support_agent)
triage_agent.add_handoff(billing_agent)

# Create runner to execute conversations
runner = RAAF::Runner.new(agent: triage_agent)

# Test the handoff with a technical issue
# The triage agent should recognize this as a support issue
result = runner.run("I can't login to my account")
puts "Response: #{result.messages.last[:content]}"
puts "Final agent: #{result.last_agent.name}\n\n"

puts "=" * 50

# ============================================================================
# EXAMPLE 2: CUSTOM HANDOFF DESCRIPTIONS
# ============================================================================
# Handoff objects allow customizing how agents appear to other agents.
# This improves routing accuracy by providing detailed transfer criteria.

puts "\n=== Example 2: Custom Handoff Descriptions ==="

# Create handoff objects with enhanced descriptions
# These provide more context than the agent's default description

# Support handoff with specific trigger examples
support_handoff = RAAF.handoff(
  support_agent,
  # Override the tool description for better routing
  # This helps the AI understand exactly when to use this handoff
  tool_description_override: "Transfer to technical support for login issues, bugs, or technical problems"
)

# Billing handoff with clear scope
billing_handoff = RAAF.handoff(
  billing_agent,
  tool_description_override: "Transfer to billing for payment issues, refunds, or subscription questions"
)

# Create an improved triage agent using handoff objects
smart_triage = RAAF::Agent.new(
  name: "SmartTriage",
  instructions: "Route users to the appropriate department. Use SupportAgent for technical issues like login problems or bugs. Use BillingAgent for payment or subscription issues. If the request doesn't clearly fit either category, provide a helpful response yourself.",
  model: "gpt-4o-mini"
)

# Add handoff objects instead of direct agent references
# This provides better control and clearer routing logic
smart_triage.add_handoff(support_handoff)
smart_triage.add_handoff(billing_handoff)

runner = RAAF::Runner.new(agent: smart_triage)

# Test with a billing issue
# The enhanced description should help route correctly
result = runner.run("I was charged twice for my subscription")
puts "Response: #{result.messages.last[:content]}"
puts "Final agent: #{result.last_agent.name}\n\n"

puts "=" * 50

# ============================================================================
# EXAMPLE 3: HANDOFF WITH INPUT VALIDATION
# ============================================================================
# Shows how to ensure proper data is passed during handoffs.
# Essential for maintaining data integrity in complex workflows.

puts "\n=== Example 3: Handoff with Input Schema ==="

# Create an escalation specialist that needs structured input
escalation_agent = RAAF::Agent.new(
  name: "EscalationAgent",

  # Instructions indicate expected input format
  instructions: "You handle escalated issues. You receive a priority level and description.",

  model: "gpt-4o-mini"
)

# Create handoff with validation logic
# This ensures the escalation has required information
escalation_handoff = RAAF.handoff(
  escalation_agent,
  # Clear description of required inputs
  tool_description_override: "Escalate to senior support with priority and description",

  # Expect structured input (Hash) not just text
  input_type: Hash,

  # Validation callback runs before handoff
  on_handoff: lambda { |_context, input|
    # Validate required fields are present
    raise "Escalation requires priority and description" unless input["priority"] && input["description"]

    # Log escalation for audit trail
    puts "[ESCALATION] Priority: #{input["priority"]}, Description: #{input["description"]}"

    # Additional processing: notifications, ticket creation, etc.
    # Return true to allow handoff
    true
  }
)

# Create frontline agent that can escalate issues
frontline_agent = RAAF::Agent.new(
  name: "FrontlineAgent",

  # Instructions explain escalation protocol with clear criteria
  instructions: "You are frontline support. For system outages, critical bugs, or issues you cannot resolve, escalate with priority (low/medium/high) and description. Otherwise, try to help the user yourself first.",

  model: "gpt-4o-mini"
)

# Add the validated escalation handoff
frontline_agent.add_handoff(escalation_handoff)

runner = RAAF::Runner.new(agent: frontline_agent)

# Test with a critical issue requiring escalation
puts "Testing escalation handoff..."
result = runner.run("The entire system is down and no one can access the platform!")
puts "Response: #{result.messages.last[:content]}"
puts "Final agent: #{result.last_agent.name}\n\n"

puts "=" * 50

# ============================================================================
# EXAMPLE 4: CONDITIONAL HANDOFF
# ============================================================================
# Demonstrates business logic in handoffs - transfers only happen when
# certain conditions are met. Critical for access control and routing rules.

puts "\n=== Example 4: Conditional Handoff ==="

# Create premium support agent for VIP customers
vip_agent = RAAF::Agent.new(
  name: "VIPSupport",
  instructions: "You provide premium support to VIP customers.",
  model: "gpt-4o-mini"
)

# Create handoff with access control logic
vip_handoff = RAAF.handoff(
  vip_agent,
  # Description hints at restriction
  tool_description_override: "Transfer to VIP support (only for premium customers)",

  # Conditional logic in handoff callback
  on_handoff: lambda { |_context|
    # In production: check customer database, subscription status, etc.
    # For demo: simulate VIP check - force false to demonstrate the error handling
    is_vip = false

    if is_vip
      # Log successful VIP verification
      puts "[VIP CHECK] Customer is VIP - transferring to premium support"
      true # Allow handoff
    else
      # Block non-VIP transfers - return false instead of raising error
      puts "[VIP CHECK] Customer is not VIP - cannot transfer"
      false # Block handoff
    end
  }
)

# Create standard support agent that attempts VIP transfers
regular_support = RAAF::Agent.new(
  name: "RegularSupport",

  # Instructions mention attempting VIP transfer with fallback
  instructions: "You provide standard support. For premium account questions, you can try to transfer VIP customers to premium support, but if the transfer fails, provide helpful standard support instead. Do not repeatedly attempt failed transfers.",

  model: "gpt-4o-mini"
)

# Add conditional VIP handoff
regular_support.add_handoff(vip_handoff)

runner = RAAF::Runner.new(agent: regular_support)

# Test conditional handoff
puts "Testing conditional VIP handoff..."
result = runner.run("I need help with my premium account features")
puts "Response: #{result.messages.last[:content]}"
puts "Final agent: #{result.last_agent.name}"

puts "\n#{"=" * 50}"

puts "\nNote: Examples 1-4 demonstrate core handoff object patterns."
puts "Complex multi-agent routing has been simplified to prevent loops."
puts "See complete_features_showcase.rb for more advanced examples."

# ============================================================================
# SUMMARY
# ============================================================================

puts "=== Handoff Objects Examples Complete ==="
puts
puts "Key takeaways:"
puts "1. Handoff objects provide more control than simple agent handoffs"
puts "2. You can customize tool descriptions for better routing"
puts "3. Input validation ensures proper data is passed between agents"
puts "4. Conditional handoffs enable business logic in routing"
puts "5. Input filters allow controlling conversation context"

puts "\nBest Practices:"
puts "- Use clear handoff descriptions to improve routing accuracy"
puts "- Validate inputs to maintain data integrity"
puts "- Implement access control for restricted agents"
puts "- Filter context to optimize token usage"
puts "- Enable bidirectional handoffs for flexible workflows"
puts "- Log handoff events for debugging and analytics"

puts "\nCommon Use Cases:"
puts "- Customer service routing and escalation"
puts "- Expert consultation networks"
puts "- Multi-stage approval workflows"
puts "- Department-based task distribution"
puts "- Tiered support systems"
