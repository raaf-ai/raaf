#!/usr/bin/env ruby

require_relative "lib/openai_agents"

# Test simple handoff scenario without debug output
ENV["OPENAI_AGENTS_LOG_LEVEL"] = "error"

# Create agents
support_agent = OpenAIAgents::Agent.new(
  name: "SupportAgent",
  instructions: "You help with support issues.",
  model: "gpt-4o-mini"
)

triage_agent = OpenAIAgents::Agent.new(
  name: "TriageAgent",
  instructions: "You route requests. Use transfer_to_supportagent for login issues.",
  model: "gpt-4o-mini"
)

triage_agent.add_handoff(support_agent)

puts "Testing simple handoff..."

begin
  runner = OpenAIAgents::Runner.new(agent: triage_agent)
  result = runner.run("I can't log in")
  puts "✅ Success: #{result.last_agent.name}"
rescue StandardError => e
  puts "❌ Error: #{e.message}"
  puts "Error class: #{e.class}"

  # Show more details for duplicate item error
  if e.message.include?("Duplicate item")
    puts "\nThis is a duplicate item issue - likely related to conversation state management"
  end
end
