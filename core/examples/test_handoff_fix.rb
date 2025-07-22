#!/usr/bin/env ruby
# frozen_string_literal: true

# Quick test to verify handoff fixes are working

require "bundler/setup"
require_relative "../lib/raaf-core"

puts "=== Testing Handoff Fixes ==="

# Create agents
support_agent = RAAF::Agent.new(
  name: "SupportAgent",
  instructions: "You handle technical support questions. Be helpful and thorough.",
  model: "gpt-4o-mini"
)

billing_agent = RAAF::Agent.new(
  name: "BillingAgent",
  instructions: "You handle billing and payment questions. Be precise with numbers.",
  model: "gpt-4o-mini"
)

# Create triage agent
triage_agent = RAAF::Agent.new(
  name: "TriageAgent",
  instructions: "You are a triage agent. For technical issues like login problems, handoff to SupportAgent. For billing issues like payments, handoff to BillingAgent.",
  model: "gpt-4o-mini"
)

# Add handoffs
triage_agent.add_handoff(support_agent)
triage_agent.add_handoff(billing_agent)

runner = RAAF::Runner.new(agent: triage_agent)

puts "\n1. Testing technical issue (should handoff to SupportAgent):"
result1 = runner.run("I can't login to my account")
puts "Initial agent: TriageAgent"
puts "Final agent: #{result1.last_agent.name}"
puts "Response: #{result1.messages.last[:content]}"

puts "\n#{"=" * 60}"

puts "\n2. Testing billing issue (should handoff to BillingAgent):"
result2 = runner.run("I was charged twice for my subscription")
puts "Initial agent: TriageAgent"
puts "Final agent: #{result2.last_agent.name}"
puts "Response: #{result2.messages.last[:content]}"

puts "\n#{"=" * 60}"
puts "\nHandoff fixes are working!" if result1.last_agent.name == "SupportAgent" && result2.last_agent.name == "BillingAgent"
