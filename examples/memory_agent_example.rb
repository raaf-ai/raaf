#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/openai_agents"
require_relative "../lib/openai_agents/memory"

# Example: Agent with Memory Capabilities
#
# This example demonstrates how to create agents with persistent memory,
# allowing them to remember information across conversations and sessions.

# Ensure you have your OpenAI API key set
unless ENV["OPENAI_API_KEY"]
  puts "Please set OPENAI_API_KEY environment variable"
  exit 1
end

puts "=== OpenAI Agents Memory System Example ==="
puts

# Example 1: Basic In-Memory Storage
puts "Example 1: Agent with In-Memory Storage"
puts "-" * 40

# Create an in-memory store (data persists only during runtime)
memory_store = OpenAIAgents::Memory::InMemoryStore.new

# Create an agent with memory
assistant = OpenAIAgents::Agent.new(
  name: "MemoryAssistant",
  instructions: "You are a helpful assistant who remembers previous conversations. " \
                "Use your memory to provide personalized responses.",
  model: "gpt-4o-mini",
  memory_store: memory_store
)

# Simulate a conversation
puts "Storing user preferences..."
assistant.remember("User's name is Alice", metadata: { type: "user_info" })
assistant.remember("User prefers Python programming", metadata: { type: "preference" })
assistant.remember("User is working on a web scraping project", metadata: { type: "project" })

# Recall information
puts "\nRecalling information about programming:"
programming_memories = assistant.recall("programming")
programming_memories.each do |memory|
  puts "- #{memory[:content]}"
end

# Get recent memories
puts "\nRecent memories:"
recent = assistant.recent_memories(3)
recent.each do |memory|
  puts "- #{memory[:content]} (#{memory[:created_at]})"
end

# Example 2: Persistent File Storage
puts "\n\nExample 2: Agent with Persistent File Storage"
puts "-" * 40

# Create a file-based store (data persists between runs)
file_store = OpenAIAgents::Memory::FileStore.new("./agent_memories")

# Create a customer service agent with persistent memory
service_agent = OpenAIAgents::Agent.new(
  name: "CustomerServiceBot",
  instructions: "You are a customer service agent. Remember customer issues and preferences.",
  model: "gpt-4o-mini",
  memory_store: file_store
)

# Simulate customer interactions
conversation_id = "ticket-12345"

puts "Recording customer interaction..."
service_agent.remember(
  "Customer reported login issues with error code 401",
  conversation_id: conversation_id,
  metadata: { severity: "high", category: "authentication" }
)

service_agent.remember(
  "Resolved by resetting password and clearing cache",
  conversation_id: conversation_id,
  metadata: { status: "resolved" }
)

# Search for similar issues
puts "\nSearching for authentication issues:"
auth_issues = service_agent.recall("authentication", limit: 5)
auth_issues.each do |issue|
  puts "- #{issue[:content]}"
  puts "  Conversation: #{issue[:conversation_id]}" if issue[:conversation_id]
end

# Example 3: Multi-Agent Memory Sharing
puts "\n\nExample 3: Multi-Agent Memory Sharing"
puts "-" * 40

# Create a shared memory store
shared_store = OpenAIAgents::Memory::InMemoryStore.new

# Create specialized agents sharing the same memory
research_agent = OpenAIAgents::Agent.new(
  name: "ResearchAgent",
  instructions: "You research technical topics and store findings.",
  memory_store: shared_store
)

writing_agent = OpenAIAgents::Agent.new(
  name: "WritingAgent",
  instructions: "You write articles based on research findings.",
  memory_store: shared_store
)

# Research agent stores findings
puts "Research agent storing findings..."
research_agent.remember("Ruby 3.3 introduces new YJIT compiler improvements")
research_agent.remember("YJIT provides up to 40% performance improvement for Rails apps")
research_agent.remember("Memory usage has been optimized in Ruby 3.3")

# Writing agent can access research
puts "\nWriting agent accessing research:"
ruby_research = writing_agent.recall("Ruby 3.3")
puts "Found #{ruby_research.size} research items"

# But agents only see their own memories by default
puts "\nResearch agent memories: #{research_agent.memory_count}"
puts "Writing agent memories: #{writing_agent.memory_count}"

# Example 4: Memory Context in Prompts
puts "\n\nExample 4: Using Memory Context in Prompts"
puts "-" * 40

# Create an agent that uses memory context
contextual_agent = OpenAIAgents::Agent.new(
  name: "ContextualAssistant",
  instructions: "You are an assistant that uses previous context to provide better help.",
  memory_store: memory_store
)

# Add some context
contextual_agent.remember("User is learning Ruby on Rails")
contextual_agent.remember("User completed the routing tutorial")
contextual_agent.remember("User had trouble with ActiveRecord associations")

# Get formatted context for prompts
context = contextual_agent.memory_context("Rails", limit: 3)
puts "Memory context for 'Rails':"
puts context

# Example 5: Memory Management
puts "\n\nExample 5: Memory Management"
puts "-" * 40

# Create an agent with memory manager
manager = OpenAIAgents::Memory::MemoryManager.new(
  max_tokens: 500,
  summary_threshold: 0.8
)

managed_agent = OpenAIAgents::Agent.new(
  name: "ManagedMemoryAgent",
  instructions: "You help with coding questions.",
  memory_store: memory_store
)

# Add many memories
puts "Adding multiple memories..."
10.times do |i|
  managed_agent.remember("Technical tip ##{i + 1}: Important coding practice")
end

puts "Total memories: #{managed_agent.memory_count}"

# Build context within token limits
all_memories = managed_agent.recent_memories(10)
limited_context = manager.build_context(all_memories)
puts "\nToken-limited context (first 200 chars):"
puts limited_context[0..200] + "..."

# Example 6: Clearing and Managing Memories
puts "\n\nExample 6: Memory Lifecycle"
puts "-" * 40

lifecycle_agent = OpenAIAgents::Agent.new(
  name: "LifecycleAgent",
  memory_store: memory_store
)

# Add memories with tags
key1 = lifecycle_agent.remember("Temporary info", metadata: { tags: ["temp"] })
key2 = lifecycle_agent.remember("Important info", metadata: { tags: ["important"] })

puts "Added memories: #{lifecycle_agent.memory_count}"

# Forget specific memory
lifecycle_agent.forget(key1)
puts "After forgetting one: #{lifecycle_agent.memory_count}"

# Check if agent has memories
puts "Has memories? #{lifecycle_agent.has_memories?}"

# Clear all memories for this agent
lifecycle_agent.clear_memories
puts "After clearing: #{lifecycle_agent.memory_count}"

# Cleanup
puts "\n\nExample completed!"
puts "File-based memories are stored in: ./agent_memories"
puts "You can delete this directory to clear all persistent memories."
