#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/raaf"
require "raaf/memory"
require "raaf/memory_manager"

# Example: Using Runner with Memory Manager for Context-Aware Conversations
# 
# This example demonstrates how to use the integrated memory functionality
# in the Runner to create agents that remember past conversations and use
# that context to provide more relevant responses.

# Create an agent
agent = RAAF::Agent.new(
  name: "MemoryAssistant",
  instructions: "You are a helpful assistant that remembers past conversations. 
                 Use the context provided to give consistent and relevant answers.",
  model: "gpt-4o"
)

# Set up memory manager with file-based storage for persistence
memory_store = RAAF::Memory.create(:file, file_path: "conversations.json")
memory_manager = RAAF::MemoryManager.new(
  store: memory_store,
  token_limit: 4000  # Limit memory context to prevent token overflow
)

# Create runner with memory manager
runner = RAAF::Runner.new(
  agent: agent,
  memory_manager: memory_manager
)

# Helper function to run a conversation
def run_conversation(runner, message, session = nil)
  session ||= RAAF::Session.new
  
  puts "\n" + "="*60
  puts "User: #{message}"
  puts "-"*60
  
  result = runner.run(
    [{ role: "user", content: message }],
    session: session
  )
  
  response = result.messages.last[:content]
  puts "Assistant: #{response}"
  puts "="*60
  
  [result, session]
end

# Example 1: First conversation - Teaching the assistant
puts "\n🧠 MEMORY-ENABLED AGENT EXAMPLE"
puts "\nFirst, let's teach the assistant some information..."

session1 = RAAF::Session.new
result1, session1 = run_conversation(
  runner,
  "I'm working on a Ruby project called 'WeatherBot'. It's a chatbot that provides weather information using the OpenWeatherMap API.",
  session1
)

result2, session1 = run_conversation(
  runner,
  "The main features of WeatherBot are: 1) Current weather lookup, 2) 5-day forecast, 3) Weather alerts, and 4) Location-based recommendations.",
  session1
)

# Example 2: New conversation that uses memory
puts "\n\nNow let's start a NEW conversation and see if it remembers..."

session2 = RAAF::Session.new
result3, session2 = run_conversation(
  runner,
  "What can you tell me about my Ruby project?",
  session2
)

# Example 3: More specific question using memory
result4, session2 = run_conversation(
  runner,
  "What API does my project use, and what are its main features?",
  session2
)

# Example 4: Demonstrate memory persistence
puts "\n\nLet's simulate restarting the application..."
puts "(Creating a new runner with the same memory store)"

# Create a new runner instance (simulating app restart)
new_runner = RAAF::Runner.new(
  agent: agent,
  memory_manager: RAAF::MemoryManager.new(
    store: memory_store,  # Same store, so memories persist
    token_limit: 4000
  )
)

session3 = RAAF::Session.new
result5, session3 = run_conversation(
  new_runner,
  "I forgot - what was the name of my chatbot project again?",
  session3
)

# Show memory statistics
puts "\n📊 MEMORY STATISTICS:"
puts "Total memories stored: #{memory_store.count}"
puts "Memory storage type: #{memory_store.class.name.split('::').last}"

# Clean up example by showing how to clear memories
print "\nWould you like to clear the memory store? (y/n): "
if gets.chomp.downcase == 'y'
  memory_store.clear
  puts "✅ Memory cleared!"
else
  puts "💾 Memory preserved for future conversations."
end

puts "\n✨ Example complete!"
puts "\nKey takeaways:"
puts "1. The Runner now accepts a memory_manager parameter"
puts "2. Memory context is automatically added to conversations"
puts "3. Q&A pairs are stored after each interaction"
puts "4. Memory persists across sessions and even app restarts"
puts "5. No changes to the core Runner API - fully backward compatible!"