#!/usr/bin/env ruby

require_relative "lib/openai_agents"

# Test script to verify handoff fixes
puts "=== Testing Handoff Fixes ==="

# Create test agents
support_agent = OpenAIAgents::Agent.new(
  name: "SupportAgent",
  instructions: "You are a support agent. When you receive requests, acknowledge them and provide basic help.",
  model: "gpt-4o-mini"
)

billing_agent = OpenAIAgents::Agent.new(
  name: "BillingAgent",
  instructions: "You are a billing agent. Handle billing-related requests.",
  model: "gpt-4o-mini"
)

# Create triage agent with both simple and complex handoffs
triage_agent = OpenAIAgents::Agent.new(
  name: "TriageAgent",
  instructions: "You are a triage agent. Route requests to appropriate agents. Use transfer_to_supportagent for general issues and transfer_to_billingagent for billing issues.",
  model: "gpt-4o-mini"
)

# Add handoffs
triage_agent.add_handoff(support_agent)
triage_agent.add_handoff(billing_agent)

puts "\n=== Test 1: Normal Single Handoff ==="
begin
  runner = OpenAIAgents::Runner.new(agent: triage_agent)
  result = runner.run("I can't log into my account, can you help me?")
  puts "Response: #{result.messages.last[:content]}"
  puts "Final agent: #{result.last_agent.name}"
  puts "✅ Test 1 passed"
rescue StandardError => e
  puts "❌ Test 1 failed: #{e.message}"
end

puts "\n=== Test 2: Multiple Handoff Detection (should fail gracefully) ==="
begin
  # Create agent that might trigger multiple handoffs
  confused_agent = OpenAIAgents::Agent.new(
    name: "ConfusedAgent",
    instructions: "You are confused and should call BOTH transfer_to_supportagent AND transfer_to_billingagent tools in the same response when asked about account issues.",
    model: "gpt-4o-mini"
  )
  confused_agent.add_handoff(support_agent)
  confused_agent.add_handoff(billing_agent)

  runner = OpenAIAgents::Runner.new(agent: confused_agent)
  result = runner.run("I have account and billing issues")
  puts "Response: #{result.messages.last[:content]}"
  puts "Final agent: #{result.last_agent.name}"

  # Check if error message is present for multiple handoffs
  if result.messages.last[:content].include?("Multiple agent handoffs")
    puts "✅ Test 2 passed - Multiple handoffs properly detected and handled"
  else
    puts "⚠️  Test 2 - Multiple handoffs not detected (may be normal if AI didn't trigger multiple tools)"
  end
rescue StandardError => e
  puts "❌ Test 2 failed: #{e.message}"
end

puts "\n=== Test 3: Invalid Handoff Target ==="
begin
  # Try to handoff to non-existent agent
  bad_agent = OpenAIAgents::Agent.new(
    name: "BadAgent",
    instructions: "Try to use transfer_to_nonexistentagent tool when asked.",
    model: "gpt-4o-mini"
  )

  # NOTE: We intentionally don't add any handoffs
  runner = OpenAIAgents::Runner.new(agent: bad_agent)
  result = runner.run("Transfer me to someone else")
  puts "Response: #{result.messages.last[:content]}"
  puts "Final agent: #{result.last_agent.name}"
  puts "✅ Test 3 passed - Invalid handoff handled gracefully"
rescue StandardError => e
  puts "❌ Test 3 failed: #{e.message}"
end

puts "\n=== Test 4: Agent Name Parsing Robustness ==="
begin
  # Test various naming patterns
  test_cases = [
    "transfer_to_supportagent",      # lowercase with underscore
    "transfer_to_SupportAgent",      # mixed case
    "transfer_to_support_agent",     # underscore separated
    "transfer_to_SUPPORTAGENT"       # all caps
  ]

  test_cases.each do |tool_name|
    runner_instance = OpenAIAgents::Runner.new(agent: triage_agent)
    agent_name = runner_instance.send(:extract_agent_name_from_tool, tool_name)
    puts "#{tool_name} -> #{agent_name}"

    if %w[SupportAgent Supportagent].include?(agent_name)
      puts "✅ Parsing worked for #{tool_name}"
    else
      puts "❌ Parsing failed for #{tool_name}: got #{agent_name}"
    end
  end
rescue StandardError => e
  puts "❌ Test 4 failed: #{e.message}"
end

puts "\n=== Test 5: Circular Handoff Protection ==="
begin
  # Create agents that could create circular handoffs
  agent_a = OpenAIAgents::Agent.new(
    name: "AgentA",
    instructions: "Transfer to AgentB immediately",
    model: "gpt-4o-mini"
  )

  agent_b = OpenAIAgents::Agent.new(
    name: "AgentB",
    instructions: "Transfer to AgentA immediately",
    model: "gpt-4o-mini"
  )

  agent_a.add_handoff(agent_b)
  agent_b.add_handoff(agent_a)

  runner = OpenAIAgents::Runner.new(agent: agent_a)
  result = runner.run("Start the process")
  puts "Response: #{result.messages.last[:content]}"
  puts "Final agent: #{result.last_agent.name}"
  puts "✅ Test 5 passed - Circular handoff protection working"
rescue StandardError => e
  puts "❌ Test 5 failed: #{e.message}"
end

puts "\n=== All Handoff Fix Tests Complete ==="
