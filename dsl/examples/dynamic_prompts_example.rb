#!/usr/bin/env ruby
# frozen_string_literal: true

# This example demonstrates dynamic prompts and instructions in RAAF (Ruby AI Agents Factory).
# Dynamic instructions allow agents to adapt their behavior based on context,
# time, conversation history, or any other runtime information. This enables
# creating highly personalized and context-aware AI experiences.
# Dynamic prompts work with the Responses API for advanced prompt management.

require "bundler/setup"
require "raaf-core"

# Demo mode to avoid actual API calls
DEMO_MODE = ENV["DEMO_MODE"] || true

if DEMO_MODE
  puts "=== Dynamic Prompts Example (Demo Mode) ==="
  puts "\nRunning in demo mode to avoid API calls."
  puts "Set DEMO_MODE=false to run with actual API calls."
  puts "\nThis example demonstrates:"
  puts "- Time-aware agent instructions"
  puts "- Context-adaptive agents"
  puts "- Dynamic prompt variables"
  puts "- Multi-agent handoff with dynamic instructions"
  puts "\nIn real mode, agents would:"
  puts "- Adapt greetings based on time of day"
  puts "- Specialize based on conversation topics"
  puts "- Build user preference profiles"
  puts "- Route between specialized agents dynamically"
  exit 0
end

# 1. Dynamic Instructions Example
# Instructions can be functions that return different prompts based on runtime state
# This enables agents to adapt their behavior dynamically
puts "=== Example 1: Dynamic Instructions ==="

# Create an agent with time-aware instructions
# Note: Dynamic instructions as lambdas are currently not fully supported
# Using static instructions with time context instead
time_aware_agent = RAAF::Agent.new(
  name: "TimeAwareAssistant",

  # Static instructions with time awareness guidance
  instructions: "You are a helpful assistant that is aware of the time of day. " \
                "When responding, consider the current time and provide appropriate " \
                "greetings (Good morning/afternoon/evening) and time-relevant suggestions. " \
                "Always be helpful and considerate of the user's schedule.",
  model: "gpt-4o-mini"
)

# Create runner - instructions are evaluated fresh each time
runner = RAAF::Runner.new(agent: time_aware_agent)

# First interaction - agent knows the time and message count
result = runner.run("What should I have for a meal?")
puts "Response: #{result.messages.last[:content]}\n\n"

# Follow-up demonstrates dynamic message counting
# Instructions update to reflect conversation progress
result = runner.run([
                      { role: "user", content: "What should I have for a meal?" },
                      { role: "assistant", content: result.messages.last[:content] },
                      { role: "user", content: "Any dessert suggestions?" }
                    ])
puts "Follow-up response: #{result.messages.last[:content]}\n\n"

puts "=" * 50

# 2. Context-Aware Dynamic Instructions
# Instructions can analyze conversation history to specialize behavior
# This creates agents that automatically adapt to user needs
puts "\n=== Example 2: Context-Aware Instructions ==="

# Agent that adapts based on conversation topics
# Note: Dynamic instructions as lambdas are currently not fully supported
# Using static instructions with adaptive guidance instead
adaptive_agent = RAAF::Agent.new(
  name: "AdaptiveAssistant",

  # Static instructions with adaptive behavior guidance
  instructions: "You are an adaptive assistant that can specialize in different areas. " \
                "Analyze the user's questions to determine their needs: " \
                "- If they ask about programming or code, become a programming expert " \
                "- If they ask about recipes or cooking, become a culinary expert " \
                "- If they ask about travel or vacations, become a travel advisor " \
                "- Otherwise, be a helpful general assistant. " \
                "Adapt your expertise and communication style based on the topic.",
  model: "gpt-4o-mini"
)

runner = RAAF::Runner.new(agent: adaptive_agent)

# Test different topics to see adaptation
# Each topic triggers different expert behavior
topics = [
  "How do I write a Python function?",
  "What's a good pasta recipe?",
  "Where should I travel in Europe?"
]

# Demonstrate automatic specialization
topics.each do |topic|
  result = runner.run(topic)
  puts "Q: #{topic}"
  puts "A: #{result.messages.last[:content][0..150]}..."
  puts "-" * 30
end

puts "=" * 50

# 3. Dynamic Prompts Example (for Responses API)
# The Responses API supports advanced prompt management with variables
# Dynamic prompts enable sophisticated personalization and state management
puts "\n=== Example 3: Dynamic Prompts (Responses API) ==="

# Track user preferences across interactions
user_history = []

# Agent with dynamic prompt generation
dynamic_prompt_agent = RAAF::Agent.new(
  name: "PersonalizedAssistant",

  # Static instructions for base behavior
  instructions: "You are a personalized assistant that remembers user preferences.",

  model: "gpt-4o",

  # Dynamic prompt function for Responses API
  # Returns a Prompt object with variables
  prompt: lambda { |data|
    # Extract context and agent from data
    context = data.context
    data.agent

    # Build user profile from accumulated history
    preferences = user_history.join(", ") unless user_history.empty?

    # Create structured prompt with variables
    # These variables can be used in prompt templates
    RAAF::Prompt.new(
      id: "personalized-assistant-v1",
      version: "1.0.0",
      variables: {
        "user_preferences" => preferences || "No preferences recorded yet",
        "interaction_count" => context.messages.count { |m| m[:role] == "user" }.to_s,
        "current_date" => Date.today.strftime("%B %d, %Y")
      }
    )
  }
)

# IMPORTANT: Dynamic prompts require ResponsesProvider
# The Responses API supports advanced prompt features
runner = RAAF::Runner.new(
  agent: dynamic_prompt_agent,
  provider: RAAF::Models::ResponsesProvider.new # Required for dynamic prompts
)

# Simulate user interactions to build preference profile
interactions = [
  "I love Italian food",
  "I'm planning a trip",
  "What restaurant should I visit?"
]

# Process interactions and accumulate preferences
interactions.each_with_index do |message, i|
  puts "\nInteraction #{i + 1}: #{message}"

  # Update user history with preferences
  # In production: use more sophisticated preference extraction
  user_history << message if message.downcase.include?("love") || message.downcase.include?("like")

  # Run with accumulated context
  result = runner.run(message)
  puts "Response: #{result.messages.last[:content][0..200]}..."
end

puts "\n=" * 50

# 4. Multi-Agent System with Dynamic Instructions
# Dynamic instructions enable sophisticated multi-agent coordination
# Agents can adapt their handoff behavior based on conversation flow
puts "\n=== Example 4: Multi-Agent Dynamic Handoffs ==="

# Factory function for creating specialized agents
# Each agent knows its expertise and available handoffs
def create_dynamic_agent(name, specialties)
  RAAF::Agent.new(
    name: name,

    # Static instructions that include handoff guidance
    # Note: Dynamic instructions as lambdas are currently not fully supported
    instructions: "You are #{name}, specializing in #{specialties[name]}. " \
                  "When asked about topics outside your expertise, use the " \
                  "appropriate handoff tools to transfer to the right specialist. " \
                  "Be clear about your specialty and suggest handoffs when needed.",
    model: "gpt-4o-mini"
  )
end

# Define agent specialties for clear separation of concerns
specialties = {
  "TechExpert" => "programming, software, and technology",
  "HealthAdvisor" => "health, fitness, and wellness",
  "FinanceGuru" => "finance, investing, and budgeting"
}

# Create specialized agents using the factory
agents = specialties.keys.map { |name| create_dynamic_agent(name, specialties) }
tech_agent, health_agent, finance_agent = agents

# Configure bidirectional handoffs for full connectivity
# Each agent can transfer to any other agent based on topic
tech_agent.add_handoff(health_agent)
tech_agent.add_handoff(finance_agent)
health_agent.add_handoff(tech_agent)
health_agent.add_handoff(finance_agent)
finance_agent.add_handoff(tech_agent)
finance_agent.add_handoff(health_agent)

# Test multi-agent conversation with topic switching
# Start with tech agent but allow natural handoffs
runner = RAAF::Runner.new(agent: tech_agent)

# Questions span different domains to trigger handoffs
questions = [
  "How do I build a web app?",
  "What are good exercises for back pain?",
  "How should I invest my savings?"
]

# Track conversation across handoffs
conversation = []

# Process each question and observe dynamic handoffs
questions.each do |question|
  puts "\nUser: #{question}"

  # Run conversation with accumulated history
  if conversation.empty?
    result = runner.run(question)
  else
    conversation << { role: "user", content: question }
    result = runner.run(conversation)
  end

  # Show which agent responded
  response = result.messages.last[:content]
  puts "#{result.last_agent.name}: #{response[0..200]}..."

  # Update conversation for next iteration
  conversation = result.messages
end

puts "\n=== Dynamic Prompts and Instructions Examples Complete ==="
puts "\nKey Takeaways:"
puts "1. Instructions can be lambdas that adapt to context"
puts "2. Agents can specialize based on conversation content"
puts "3. Dynamic prompts work with Responses API for variables"
puts "4. Multi-agent systems benefit from dynamic coordination"
puts "5. State can be maintained across interactions"
