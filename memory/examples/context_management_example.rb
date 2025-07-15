#!/usr/bin/env ruby
# frozen_string_literal: true

# This example demonstrates context management in OpenAI Agents Ruby.
# Context management is crucial for handling long conversations that exceed
# model token limits. It automatically truncates conversations while preserving
# important messages, preventing errors and reducing costs. The system uses
# intelligent strategies to maintain conversation coherence.

require_relative "../lib/openai_agents"

# ============================================================================
# CONTEXT MANAGEMENT EXAMPLES
# ============================================================================

# ============================================================================
# AGENT SETUP
# ============================================================================
# Create a standard agent that will handle long conversations.
# The context manager will be attached to the runner, not the agent.

agent = OpenAIAgents::Agent.new(
  name: "Assistant",
  
  # Simple instructions - agent doesn't need to know about context management
  instructions: "You are a helpful assistant. Help the user with their questions.",
  
  # Using GPT-4o which has a 128k token context window
  model: "gpt-4o"
)

# ============================================================================
# CONTEXT MANAGER CONFIGURATION
# ============================================================================
# The ContextManager handles automatic conversation truncation to stay within
# token limits while preserving conversation continuity.

# Option 1: Default settings with model-aware limits
# The manager automatically knows token limits for common models
context_manager = OpenAIAgents::ContextManager.new(
  model: "gpt-4o",        # Auto-configures for 128k token limit
  
  preserve_system: true,  # System messages contain critical instructions
                         # Always preserved to maintain agent behavior
  
  preserve_recent: 5      # Keep last N messages regardless of truncation
                         # Ensures recent context is always available
)

# Option 2: Custom configuration for specific needs
# Use when you need different limits or preservation strategies
custom_context_manager = OpenAIAgents::ContextManager.new(
  model: "gpt-4o",
  
  max_tokens: 50_000,     # Custom limit (less than model maximum)
                          # Useful for: cost control, faster responses
  
  preserve_system: true,
  
  preserve_recent: 10     # Keep more recent context
                         # Better for: complex conversations, multi-step tasks
)

# ============================================================================
# RUNNER WITH CONTEXT MANAGEMENT
# ============================================================================
# Attach the context manager to the runner, not the agent.
# This allows different runners to use different context strategies.

runner = OpenAIAgents::Runner.new(
  agent: agent,
  
  # Enable automatic context management
  # The runner will apply truncation before each API call
  context_manager: context_manager
)

# ============================================================================
# EXAMPLE 1: SIMULATING LONG CONVERSATIONS
# ============================================================================
# Demonstrates automatic context truncation as conversation grows.
# Watch how the context manager maintains conversation quality.

# Start with empty conversation
conversation = []

puts "Simulating a long conversation..."

# Generate many exchanges to exceed token limits
20.times do |i|
  # Create detailed requests that consume many tokens
  user_message = "Tell me fact ##{i + 1} about Ruby programming. Make it detailed with examples."
  
  # Run conversation with new message
  # Context manager automatically truncates if needed
  result = runner.run(conversation + [{ role: "user", content: user_message }])
  
  # Update conversation history
  conversation = result.messages
  
  # Monitor conversation growth
  total_messages = conversation.count { |msg| msg[:role] != "system" }
  puts "\nConversation now has #{total_messages} messages"
  
  # Detect when context manager activates
  # It adds system messages to explain truncation
  truncation_messages = conversation.select do |msg| 
    msg[:role] == "system" && msg[:content]&.include?("[Note:")
  end
  
  if truncation_messages.any?
    puts "Context manager activated: #{truncation_messages.last[:content]}"
  end
end

# ============================================================================
# EXAMPLE 2: TOKEN USAGE ANALYSIS
# ============================================================================
# Understanding token usage helps optimize costs and performance.
# The context manager provides detailed token counting capabilities.

puts "\n" + ("=" * 60)
puts "Token Usage Analysis"
puts "=" * 60

# Calculate total tokens in conversation
# This uses the same tokenizer as the model
total_tokens = context_manager.count_total_tokens(conversation)
puts "Final conversation tokens: #{total_tokens}"
puts "Token limit: #{context_manager.max_tokens}"
puts "Usage: #{(total_tokens.to_f / context_manager.max_tokens * 100).round(2)}%"

# Analyze individual message sizes
# Helps identify which messages consume most tokens
puts "\nMessage token breakdown:"
conversation.last(5).each_with_index do |msg, _i|
  # Count tokens for each message
  tokens = context_manager.count_message_tokens(msg)
  role = msg[:role]
  
  # Show preview of content
  content_preview = msg[:content].to_s[0..50].gsub("\n", " ")
  
  puts "  #{role.ljust(10)} (#{tokens} tokens): #{content_preview}..."
end

# ============================================================================
# EXAMPLE 3: MANUAL CONTEXT MANAGEMENT
# ============================================================================
# Sometimes you need to manage context before sending to the API.
# This is useful for preprocessing or custom truncation strategies.

puts "\n" + ("=" * 60)
puts "Manual Context Management"
puts "=" * 60

# Create an artificially long conversation
# Simulates loading historical conversation from storage
long_conversation = conversation * 3  # Triple size to exceed limits

puts "Original conversation: #{long_conversation.length} messages"

# Apply context management manually
# This truncates while preserving important messages
managed_conversation = context_manager.manage_context(long_conversation)
puts "After management: #{managed_conversation.length} messages"

# Examine what the manager kept
# Shows the truncation strategy in action
puts "\nKept messages:"
managed_conversation.each_with_index do |msg, i|
  # Skip internal system messages
  next if msg[:role] == "system" && !msg[:content].include?("[Note:")

  content_preview = msg[:content].to_s[0..60].gsub("\n", " ")
  puts "  #{i}: [#{msg[:role]}] #{content_preview}..."
end

# ============================================================================
# SUMMARY
# ============================================================================

puts "\nContext management ensures your conversations stay within model limits!"
puts "This prevents errors and reduces costs while maintaining conversation continuity."

puts "\nKey Benefits:"
puts "1. Automatic truncation prevents token limit errors"
puts "2. Preserves recent context for coherent responses"
puts "3. Keeps system messages to maintain agent behavior"
puts "4. Reduces API costs by limiting token usage"
puts "5. Transparent to users - adds explanatory notes"

puts "\nBest Practices:"
puts "- Set appropriate preserve_recent based on conversation type"
puts "- Use custom limits for cost control"
puts "- Monitor token usage to optimize settings"
puts "- Consider summarization for very long conversations"
puts "- Test truncation behavior with your specific use case"
