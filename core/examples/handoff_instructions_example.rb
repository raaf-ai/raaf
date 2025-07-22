#!/usr/bin/env ruby
# frozen_string_literal: true

# Example demonstrating the new OpenAI Agents SDK handoff functionality in RAAF Core
#
# This example shows:
# 1. How to use RAAF::RECOMMENDED_PROMPT_PREFIX
# 2. How to use RAAF.prompt_with_handoff_instructions
# 3. How automatic handoff instructions work in agents with handoffs
# 4. Compatibility with OpenAI Agents SDK patterns

require_relative "../lib/raaf-core"

puts "=== OpenAI Agents SDK Handoff Instructions Example ==="
puts

# 1. Using RECOMMENDED_PROMPT_PREFIX directly
puts "1. Using RECOMMENDED_PROMPT_PREFIX directly:"
puts RAAF::RECOMMENDED_PROMPT_PREFIX
puts "=" * 50
puts

# 2. Using prompt_with_handoff_instructions function
puts "2. Using prompt_with_handoff_instructions function:"
custom_instructions = "You are a helpful customer service agent. Be polite and professional."
full_instructions = RAAF.prompt_with_handoff_instructions(custom_instructions)
puts full_instructions
puts "=" * 50
puts

# 3. Creating agents with handoff instructions
puts "3. Creating agents with handoff instructions:"

# Create specialized agents
support_agent = RAAF::Agent.new(
  name: "SupportAgent",
  instructions: RAAF.prompt_with_handoff_instructions(
    "You are a technical support specialist. Help users with technical issues."
  )
)

billing_agent = RAAF::Agent.new(
  name: "BillingAgent",
  instructions: RAAF.prompt_with_handoff_instructions(
    "You are a billing specialist. Handle payment and subscription issues."
  )
)

# Create main customer service agent
customer_service = RAAF::Agent.new(
  name: "CustomerService",
  instructions: RAAF.prompt_with_handoff_instructions(
    "You are the main customer service agent. Route customers to appropriate specialists."
  )
)

# Add handoffs
customer_service.add_handoff(support_agent)
customer_service.add_handoff(billing_agent)

puts "Customer Service Agent created with handoffs to:"
customer_service.handoffs.each do |handoff|
  agent_name = handoff.is_a?(RAAF::Agent) ? handoff.name : handoff.agent_name
  puts "  - #{agent_name}"
end
puts

# 4. Demonstrate automatic handoff instructions
puts "4. Automatic handoff instructions in action:"

# Create an agent WITHOUT explicit handoff instructions
basic_agent = RAAF::Agent.new(
  name: "BasicAgent",
  instructions: "You are a basic agent."
)

# Add handoffs - this will trigger automatic handoff instructions
basic_agent.add_handoff(support_agent)

# Simulate the automatic handoff instructions behavior
puts "When an agent with handoffs is used in a Runner, the system automatically adds"
puts "handoff instructions to the agent's instructions if they're not already present."
puts
puts "BasicAgent original instructions:"
puts "  \"#{basic_agent.instructions}\""
puts
puts "After adding handoffs and using in Runner (simulated):"
puts "  The system would automatically prepend the handoff instructions."
puts
puts "Simulated system prompt for BasicAgent:"
enhanced_instructions = RAAF.prompt_with_handoff_instructions(basic_agent.instructions)
puts enhanced_instructions
puts "=" * 50
puts

# 5. Show that duplication is prevented
puts "5. Preventing duplication of handoff instructions:"

# Create agent with handoff instructions already included
agent_with_existing_instructions = RAAF::Agent.new(
  name: "ExistingAgent",
  instructions: RAAF.prompt_with_handoff_instructions("You are a specialized agent.")
)

# Add handoffs
agent_with_existing_instructions.add_handoff(support_agent)

# Show that handoff instructions are not duplicated
puts "ExistingAgent instructions (already includes handoff instructions):"
puts agent_with_existing_instructions.instructions
puts
puts "The system detects existing handoff instructions and doesn't duplicate them."

puts "=" * 50
puts

# 6. Compatibility demonstration
puts "6. OpenAI Agents SDK compatibility:"
puts "The following patterns work exactly like the Python SDK:"
puts
puts "# Python SDK:"
puts "from agents import Agent, prompt_with_handoff_instructions"
puts "agent = Agent(instructions=prompt_with_handoff_instructions('You are helpful'))"
puts
puts "# RAAF (Ruby):"
puts "agent = RAAF::Agent.new(instructions: RAAF.prompt_with_handoff_instructions('You are helpful'))"
puts
puts "Both create agents with the same handoff context and behavior!"
puts

puts "=== Example Complete ==="
