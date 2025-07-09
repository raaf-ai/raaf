#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/openai_agents"

# Example: Using Context Management to handle long conversations
# This demonstrates how to enable the token-based sliding window strategy
# to automatically manage conversation context size

# Create an agent
agent = OpenAIAgents::Agent.new(
  name: "Assistant",
  instructions: "You are a helpful assistant. Help the user with their questions.",
  model: "gpt-4o"
)

# Option 1: Use default context management settings
context_manager = OpenAIAgents::ContextManager.new(
  model: "gpt-4o",  # Automatically sets appropriate token limits
  preserve_system: true,  # Always keep system messages
  preserve_recent: 5  # Always keep last 5 messages
)

# Option 2: Custom token limits
custom_context_manager = OpenAIAgents::ContextManager.new(
  model: "gpt-4o",
  max_tokens: 50_000,  # Custom limit (default for gpt-4o is 120k)
  preserve_system: true,
  preserve_recent: 10  # Keep more recent messages
)

# Create runner with context management enabled
runner = OpenAIAgents::Runner.new(
  agent: agent,
  context_manager: context_manager  # Enable automatic context management
)

# Simulate a long conversation
conversation = []

# Add many messages to simulate a long conversation
puts "Simulating a long conversation..."
20.times do |i|
  user_message = "Tell me fact ##{i + 1} about Ruby programming. Make it detailed with examples."
  
  # Run the conversation
  result = runner.run(conversation + [{ role: "user", content: user_message }])
  
  # Update conversation with the result
  conversation = result.messages
  
  # Show conversation size
  total_messages = conversation.count { |msg| msg[:role] != "system" }
  puts "\nConversation now has #{total_messages} messages"
  
  # Check if context manager kicked in
  truncation_messages = conversation.select { |msg| 
    msg[:role] == "system" && msg[:content]&.include?("[Note:")
  }
  
  if truncation_messages.any?
    puts "Context manager activated: #{truncation_messages.last[:content]}"
  end
end

# Demonstrate token counting
puts "\n" + "="*60
puts "Token Usage Analysis"
puts "="*60

# Count tokens in the final conversation
total_tokens = context_manager.count_total_tokens(conversation)
puts "Final conversation tokens: #{total_tokens}"
puts "Token limit: #{context_manager.max_tokens}"
puts "Usage: #{(total_tokens.to_f / context_manager.max_tokens * 100).round(2)}%"

# Show message breakdown
puts "\nMessage token breakdown:"
conversation.last(5).each_with_index do |msg, i|
  tokens = context_manager.count_message_tokens(msg)
  role = msg[:role]
  content_preview = msg[:content].to_s[0..50].gsub(/\n/, " ")
  puts "  #{role.ljust(10)} (#{tokens} tokens): #{content_preview}..."
end

# Example: Manual context management
puts "\n" + "="*60
puts "Manual Context Management"
puts "="*60

# You can also manually manage context before sending
long_conversation = conversation * 3  # Triple the conversation to exceed limits

puts "Original conversation: #{long_conversation.length} messages"

# Manually apply context management
managed_conversation = context_manager.manage_context(long_conversation)
puts "After management: #{managed_conversation.length} messages"

# Show what was kept
puts "\nKept messages:"
managed_conversation.each_with_index do |msg, i|
  next if msg[:role] == "system" && !msg[:content].include?("[Note:")
  content_preview = msg[:content].to_s[0..60].gsub(/\n/, " ")
  puts "  #{i}: [#{msg[:role]}] #{content_preview}..."
end

puts "\nContext management ensures your conversations stay within model limits!"
puts "This prevents errors and reduces costs while maintaining conversation continuity."