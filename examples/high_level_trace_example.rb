#!/usr/bin/env ruby
# frozen_string_literal: true

# Disable debug output for cleaner demo
ENV["OPENAI_AGENTS_TRACE_DEBUG"] = "false"

require_relative "../lib/openai_agents"

# Example showing high-level trace functionality
#
# This demonstrates how to use the trace() function to group multiple
# agent runs under a single trace, similar to the Python implementation

# Create agents
joke_agent = OpenAIAgents::Agent.new(
  name: "Joke Generator",
  instructions: "You are a comedian who tells funny jokes. Keep them short and witty.",
  model: "gpt-4o-mini"
)

critic_agent = OpenAIAgents::Agent.new(
  name: "Joke Critic",
  instructions: "You are a comedy critic who rates jokes on a scale of 1-10 and provides brief feedback.",
  model: "gpt-4o-mini"
)

runner = OpenAIAgents::Runner.new(agent: joke_agent)
critic_runner = OpenAIAgents::Runner.new(agent: critic_agent)

puts "=== High-Level Trace Example ==="
puts "Creating a trace that encompasses multiple agent runs...\n\n"

# Use trace to group multiple agent runs
OpenAIAgents.trace("Comedy Workflow", 
                   trace_id: "trace_comedy_#{Time.now.to_i}",
                   metadata: { type: "demo", session: "example" }) do
  
  puts "1. Generating a joke..."
  joke_result = runner.run([
    { role: "user", content: "Tell me a joke about programming" }
  ])
  
  joke = joke_result[:messages].last[:content]
  puts "Joke: #{joke}\n\n"
  
  puts "2. Getting critic's opinion..."
  critic_result = critic_runner.run([
    { role: "user", content: "Rate this joke and provide feedback: #{joke}" }
  ])
  
  feedback = critic_result[:messages].last[:content]
  puts "Critic's feedback: #{feedback}\n\n"
  
  # Use custom span for additional tracking
  tracer = OpenAIAgents.tracer
  if tracer.respond_to?(:custom_span)
    tracer.custom_span("workflow_summary", 
                      { joke_count: 1, critic_count: 1 },
                      "summary.type" => "comedy") do |span|
      span.set_attribute("summary.joke_length", joke.length)
      span.set_attribute("summary.feedback_length", feedback.length)
      puts "3. Created custom span for workflow summary"
    end
  end
end

puts "\n=== Nested Trace Example ==="
puts "You can also manually manage traces...\n\n"

# Manual trace management
trace = OpenAIAgents::Tracing::Trace.new("Manual Comedy Workflow",
                                        group_id: "comedy_session_123")
trace.start

begin
  joke_result2 = runner.run([
    { role: "user", content: "Tell me another joke, this time about AI" }
  ])
  
  joke2 = joke_result2[:messages].last[:content]
  puts "Second joke: #{joke2}"
ensure
  trace.finish
end

puts "\n=== Example Complete ==="
puts "Check your OpenAI dashboard at https://platform.openai.com/traces to see the traces!"
puts "\nNote: Traces may take a few seconds to appear in the dashboard."

# Force flush to ensure traces are sent
OpenAIAgents::Tracing.force_flush
sleep(1) # Give it a moment to send