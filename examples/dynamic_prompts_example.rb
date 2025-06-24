#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "openai_agents"

# Example demonstrating dynamic prompts and instructions

# 1. Dynamic Instructions Example
puts "=== Example 1: Dynamic Instructions ==="

# Create an agent with dynamic instructions that change based on context
time_aware_agent = OpenAIAgents::Agent.new(
  name: "TimeAwareAssistant",
  instructions: -> (context, agent) {
    hour = Time.now.hour
    greeting = case hour
    when 0..11 then "Good morning"
    when 12..17 then "Good afternoon"
    else "Good evening"
    end
    
    # Access context information
    message_count = context.messages.size
    
    "#{greeting}! You are a helpful assistant. " \
    "This is message ##{message_count + 1} in our conversation. " \
    "Current time: #{Time.now.strftime("%I:%M %p")}. " \
    "Provide time-appropriate responses."
  },
  model: "gpt-4o-mini"
)

runner = OpenAIAgents::Runner.new(agent: time_aware_agent)

result = runner.run("What should I have for a meal?")
puts "Response: #{result.messages.last[:content]}\n\n"

# Follow-up to see message count change
result = runner.run([
  { role: "user", content: "What should I have for a meal?" },
  { role: "assistant", content: result.messages.last[:content] },
  { role: "user", content: "Any dessert suggestions?" }
])
puts "Follow-up response: #{result.messages.last[:content]}\n\n"

puts "=" * 50

# 2. Context-Aware Dynamic Instructions
puts "\n=== Example 2: Context-Aware Instructions ==="

# Agent that adapts based on conversation history
adaptive_agent = OpenAIAgents::Agent.new(
  name: "AdaptiveAssistant",
  instructions: -> (context, agent) {
    # Analyze conversation topics
    messages_text = context.messages.map { |m| m[:content] }.join(" ").downcase
    
    specialization = if messages_text.include?("code") || messages_text.include?("programming")
      "You are a programming expert. Provide code examples and technical explanations."
    elsif messages_text.include?("recipe") || messages_text.include?("cooking")
      "You are a culinary expert. Provide detailed recipes and cooking tips."
    elsif messages_text.include?("travel") || messages_text.include?("vacation")
      "You are a travel advisor. Provide destination recommendations and travel tips."
    else
      "You are a helpful general assistant."
    end
    
    "#{specialization} Adapt your expertise based on the user's needs."
  },
  model: "gpt-4o-mini"
)

runner = OpenAIAgents::Runner.new(agent: adaptive_agent)

# Test different topics
topics = [
  "How do I write a Python function?",
  "What's a good pasta recipe?",
  "Where should I travel in Europe?"
]

topics.each do |topic|
  result = runner.run(topic)
  puts "Q: #{topic}"
  puts "A: #{result.messages.last[:content][0..150]}..."
  puts "-" * 30
end

puts "=" * 50

# 3. Dynamic Prompts Example (for Responses API)
puts "\n=== Example 3: Dynamic Prompts (Responses API) ==="

# Create a dynamic prompt that changes based on user history
user_history = []

dynamic_prompt_agent = OpenAIAgents::Agent.new(
  name: "PersonalizedAssistant",
  instructions: "You are a personalized assistant that remembers user preferences.",
  model: "gpt-4o",
  prompt: -> (data) {
    # Access context and agent from data
    context = data.context
    agent = data.agent
    
    # Build user profile from history
    preferences = user_history.join(", ") unless user_history.empty?
    
    # Return a Prompt object
    OpenAIAgents::Prompt.new(
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

# Note: Dynamic prompts work with ResponsesProvider which supports the Responses API
runner = OpenAIAgents::Runner.new(
  agent: dynamic_prompt_agent,
  provider: OpenAIAgents::Models::ResponsesProvider.new
)

# Simulate user interactions
interactions = [
  "I love Italian food",
  "I'm planning a trip",
  "What restaurant should I visit?"
]

interactions.each_with_index do |message, i|
  puts "\nInteraction #{i + 1}: #{message}"
  
  # Update user history
  user_history << message if message.downcase.include?("love") || message.downcase.include?("like")
  
  result = runner.run(message)
  puts "Response: #{result.messages.last[:content][0..200]}..."
end

puts "\n=" * 50

# 4. Multi-Agent System with Dynamic Instructions
puts "\n=== Example 4: Multi-Agent Dynamic Handoffs ==="

# Create agents that dynamically adjust their handoff behavior
def create_dynamic_agent(name, specialties)
  OpenAIAgents::Agent.new(
    name: name,
    instructions: -> (context, agent) {
      # Check if we should suggest a handoff based on context
      last_message = context.messages.last[:content].downcase if context.messages.any?
      
      handoff_hints = agent.handoffs.map do |h|
        "- For #{specialties[h.name]}, say 'HANDOFF: #{h.name}'"
      end.join("\n")
      
      "You are #{name}, specializing in #{specialties[name]}. " \
      "Current conversation turn: #{context.current_turn}. " \
      "If asked about something outside your expertise:\n#{handoff_hints}"
    },
    model: "gpt-4o-mini"
  )
end

specialties = {
  "TechExpert" => "programming, software, and technology",
  "HealthAdvisor" => "health, fitness, and wellness",
  "FinanceGuru" => "finance, investing, and budgeting"
}

# Create agents
agents = specialties.keys.map { |name| create_dynamic_agent(name, specialties) }
tech_agent, health_agent, finance_agent = agents

# Set up handoffs
tech_agent.add_handoff(health_agent)
tech_agent.add_handoff(finance_agent)
health_agent.add_handoff(tech_agent)
health_agent.add_handoff(finance_agent)
finance_agent.add_handoff(tech_agent)
finance_agent.add_handoff(health_agent)

# Test multi-agent conversation
runner = OpenAIAgents::Runner.new(agent: tech_agent)

questions = [
  "How do I build a web app?",
  "What are good exercises for back pain?",
  "How should I invest my savings?"
]

conversation = []
current_question_index = 0

questions.each do |question|
  puts "\nUser: #{question}"
  
  if conversation.empty?
    result = runner.run(question)
  else
    conversation << { role: "user", content: question }
    result = runner.run(conversation)
  end
  
  response = result.messages.last[:content]
  puts "#{result.last_agent.name}: #{response[0..200]}..."
  
  conversation = result.messages
end

puts "\n=== Dynamic Prompts and Instructions Examples Complete ==="