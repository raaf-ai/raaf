#!/usr/bin/env ruby
# frozen_string_literal: true

# This example demonstrates the integrated memory system for RAAF (Ruby AI Agents Factory).
# Memory systems are crucial for creating intelligent agents that can learn,
# personalize responses, and maintain context over time. The Agent class now
# includes full memory integration with built-in methods for storing, retrieving,
# and managing memories. This example shows how to use the memory system for
# persistent context, knowledge accumulation, and multi-agent collaboration.

require "raaf"
require_relative "../lib/openai_agents/memory"

# ============================================================================
# MEMORY SYSTEM DEMONSTRATION
# ============================================================================

puts "=== RAAF Memory System Components ==="
puts

# ============================================================================
# EXAMPLE 1: IN-MEMORY STORE
# ============================================================================
# The InMemoryStore provides fast, ephemeral storage for agent memories.
# Data is stored in RAM and lost when the program exits. This storage type
# is ideal for chatbots, session-based assistants, and scenarios where
# persistence isn't required. The store uses hash tables for O(1) lookups
# and supports full-text search through memory content.

puts "1. In-Memory Store Demonstration:"
puts "-" * 40

# Create an in-memory store instance
# Internally uses Ruby hashes for efficient storage and retrieval
# Thread-safe implementation for concurrent access
memory_store = RAAF::Memory::InMemoryStore.new

# Create memory objects with structured data
# Each memory represents a discrete piece of information
# The Memory class encapsulates content with metadata for rich querying
memory1 = RAAF::Memory::Memory.new(
  content: "User prefers Python for data science projects",
  agent_name: "assistant_1",  # Links memory to specific agent
  metadata: {                  # Metadata enables filtering and categorization
    category: "preference",    # Type of information stored
    language: "python"         # Additional context for search
  }
)

memory2 = RAAF::Memory::Memory.new(
  content: "User is working on a machine learning model",
  agent_name: "assistant_1",
  metadata: { category: "project", field: "ml" }
)

# Store memories in the in-memory store
# Each memory needs a unique key for retrieval
# The key format includes agent name and memory ID for organization
puts "Storing memories..."
memory_store.store("#{memory1.agent_name}:#{memory1.id}", memory1)
memory_store.store("#{memory2.agent_name}:#{memory2.id}", memory2)

# Retrieve all memories for a specific agent
# Search with empty query returns all memories for the agent
# Results are sorted by most recent first
puts "\nAll memories for assistant_1:"
memories = memory_store.search("", agent_name: "assistant_1")
memories.each do |mem|
  puts "- #{mem[:content]}"
end

# Search memories by content using text matching
# The search function performs case-insensitive substring matching
# Future versions may support semantic search with embeddings
puts "\nSearching for 'Python':"
results = memory_store.search("Python", agent_name: "assistant_1")
results.each do |mem|
  puts "- #{mem[:content]}"
end

# ============================================================================
# EXAMPLE 2: FILE STORE
# ============================================================================
# The FileStore provides persistent storage that survives program restarts.
# Memories are saved as JSON files on disk, enabling long-term knowledge
# retention. This is essential for customer service bots, personal assistants,
# and any application requiring memory across sessions. The store creates a
# directory structure organized by agent name for efficient file management.

puts "\n2. File Store Demonstration:"
puts "-" * 40

# Create a file store with a specified directory
# The directory is created if it doesn't exist
# Each agent gets a subdirectory for organization
file_store = RAAF::Memory::FileStore.new("./agent_memories")

# Create a support ticket memory with rich metadata
# Conversation IDs group related memories together
# Metadata provides context for filtering and reporting
memory3 = RAAF::Memory::Memory.new(
  content: "Customer reported issue with login functionality",
  agent_name: "support_bot",
  conversation_id: "ticket_123",    # Groups memories by support ticket
  metadata: { 
    severity: "high",               # Priority for triage and escalation
    category: "authentication",     # Issue categorization for routing
    resolved: false                 # Status tracking for follow-up
  }
)

# Store memory to disk as JSON file
# File path: ./agent_memories/support_bot/{memory_id}.json
# JSON format ensures human readability and easy backup/restore
puts "Storing memory to disk..."
file_store.store("#{memory3.agent_name}:#{memory3.id}", memory3)

# Retrieve memory by key
# Demonstrates persistence - data survives program restart
# Returns nil if memory not found (deleted or invalid ID)
puts "\nRetrieved from disk:"
retrieved = file_store.retrieve("#{memory3.agent_name}:#{memory3.id}")
if retrieved
  puts "- Content: #{retrieved[:content]}"
  puts "- Metadata: #{retrieved[:metadata]}"
end

# ============================================================================
# EXAMPLE 3: MEMORY SEARCH AND FILTERING
# ============================================================================
# Demonstrate advanced search capabilities with metadata filtering.
# The search system supports content matching and metadata-based filtering
# for precise memory retrieval.

puts "\n3. Advanced Memory Search:"
puts "-" * 40

# Add memories with rich metadata for filtering
memory_store.store("doc:1", RAAF::Memory::Memory.new(
  content: "API rate limit is 100 requests per minute",
  agent_name: "assistant_1",
  metadata: { category: "technical", type: "limit", api: "openai" }
))

memory_store.store("doc:2", RAAF::Memory::Memory.new(
  content: "User interface should be responsive and mobile-friendly",
  agent_name: "assistant_1", 
  metadata: { category: "design", type: "requirement", priority: "high" }
))

# Search by metadata
puts "Searching for technical memories:"
tech_memories = memory_store.search("", agent_name: "assistant_1", metadata: { category: "technical" })
tech_memories.each { |m| puts "- #{m[:content]}" }

puts "\nTotal memories for assistant_1: #{memory_store.list_keys(agent_name: 'assistant_1').length}"

# ============================================================================
# EXAMPLE 4: SIMULATED AGENT WITH MEMORY
# ============================================================================
# This demonstrates how memory could enhance agent capabilities by maintaining
# context across conversations. The wrapper pattern shows how to add memory
# to existing agents until native integration is available. This approach
# enables personalization, learning from past interactions, and building
# long-term relationships with users.

puts "\n4. Simulated Agent Memory Usage:"
puts "-" * 40

# Create a standard agent without built-in memory
# The agent operates normally but lacks persistence
agent = RAAF::Agent.new(
  name: "ContextualAssistant",
  instructions: "You are a helpful assistant.",
  model: "gpt-4o-mini"
)

# Create a wrapper class that adds memory capabilities to any agent
# This pattern demonstrates how memory enhances agent intelligence
# The wrapper intercepts interactions to store and retrieve context
class MemoryEnhancedAgent
  def initialize(agent, memory_store)
    @agent = agent
    @memory_store = memory_store
    @agent_name = agent.name
  end

  # Store new information in memory with metadata
  # This method mimics the proposed agent.remember API
  # Metadata enables rich querying and categorization
  def remember(content, metadata = {})
    memory = RAAF::Memory::Memory.new(
      content: content,
      agent_name: @agent_name,
      metadata: metadata
    )
    @memory_store.store("#{@agent_name}:#{memory.id}", memory)
    puts "Remembered: #{content}"
  end

  # Retrieve relevant memories based on semantic similarity
  # Currently uses text matching, future versions will use embeddings
  # The limit parameter controls memory context size
  def recall(query, limit = 5)
    memories = @memory_store.search(query, agent_name: @agent_name, limit: limit)
    puts "Recalling memories about '#{query}':"
    memories.each { |m| puts "- #{m[:content]}" }
    memories
  end

  # Format memories as context for inclusion in prompts
  # This context helps the AI provide personalized, informed responses
  # The formatted string can be prepended to user messages
  def get_context(query)
    memories = recall(query, 3)
    return "" if memories.empty?

    "\nRelevant context from memory:\n" +
    memories.map { |m| "- #{m[:content]}" }.join("\n")
  end
end

# Create memory-enhanced wrapper
enhanced_agent = MemoryEnhancedAgent.new(agent, memory_store)

# Simulate storing information
puts "Simulating memory storage..."
enhanced_agent.remember("User is learning Ruby programming")
enhanced_agent.remember("User completed the basics tutorial")
enhanced_agent.remember("User is interested in web development with Rails")

# Simulate recall
puts "\n"
enhanced_agent.recall("Ruby")

# Show how context could be used
puts "\nContext that could be added to prompts:"
context = enhanced_agent.get_context("programming")
puts context

# ============================================================================
# CLEANUP AND SUMMARY
# ============================================================================

puts "\n=== Summary ==="
puts "\nMemory System Components:"
puts "1. BaseStore - Abstract interface for memory storage"
puts "2. InMemoryStore - Fast, ephemeral storage in RAM"
puts "3. FileStore - Persistent storage on disk"
puts "4. Memory - Individual memory objects with metadata"
puts "5. MemoryManager - Token limit and context management"

puts "\nPotential Use Cases:"
puts "- Personalization: Remember user preferences"
puts "- Context: Maintain conversation history"
puts "- Knowledge: Build up domain expertise"
puts "- Support: Track customer issues and resolutions"
puts "- Collaboration: Share knowledge between agents"

# ============================================================================
# EXAMPLE 5: NATIVE AGENT MEMORY INTEGRATION
# ============================================================================
# The Agent class now includes built-in memory methods! This is the recommended
# approach for using memory in your agents.

puts "\n5. Native Agent Memory Integration:"
puts "-" * 40

# Create an agent with automatic memory store
# The agent gets a default InMemoryStore if none specified
agent_with_memory = RAAF::Agent.new(
  name: "MemoryAgent",
  instructions: "You are an assistant with memory capabilities",
  model: "gpt-4o-mini"
)

# Store information using the agent's remember method
puts "Using agent.remember() to store information..."
key1 = agent_with_memory.remember("User enjoys hiking and outdoor activities", 
                                  metadata: { type: "hobby" })
key2 = agent_with_memory.remember("User is learning Ruby programming", 
                                  metadata: { type: "skill", level: "beginner" })
key3 = agent_with_memory.remember("User prefers email communications over phone",
                                  metadata: { type: "preference", channel: "email" })

puts "✓ Stored #{agent_with_memory.memory_count} memories"

# Search for memories using the agent's recall method
puts "\nUsing agent.recall() to search memories..."
hobby_memories = agent_with_memory.recall("hiking", limit: 5)
puts "Found #{hobby_memories.length} memories about hiking:"
hobby_memories.each { |m| puts "  - #{m[:content]}" }

programming_memories = agent_with_memory.recall("programming")
puts "\nFound #{programming_memories.length} memories about programming:"
programming_memories.each { |m| puts "  - #{m[:content]}" }

# Get recent memories
puts "\nUsing agent.recent_memories() to get latest information..."
recent = agent_with_memory.recent_memories(limit: 2)
recent.each_with_index do |memory, index|
  content = memory[:content]
  timestamp = memory[:updated_at]
  puts "#{index + 1}. #{content} (#{timestamp})"
end

# Generate memory context for prompts
puts "\nUsing agent.memory_context() to generate prompt context..."
context = agent_with_memory.memory_context("user", limit: 3)
puts "Generated context:"
puts context

# Demonstrate memory management
puts "\nUsing agent memory management methods..."
puts "Has memories? #{agent_with_memory.has_memories?}"
puts "Memory count: #{agent_with_memory.memory_count}"

# Forget a specific memory
if agent_with_memory.forget(key1)
  puts "✓ Forgot memory: #{key1[0..12]}..."
  puts "New memory count: #{agent_with_memory.memory_count}"
end

# Create agent with persistent file store
puts "\nCreating agent with persistent file storage..."
file_store = RAAF::Memory::FileStore.new("./persistent_memories")
persistent_agent = RAAF::Agent.new(
  name: "PersistentAgent",
  instructions: "You maintain persistent memories",
  model: "gpt-4o-mini",
  memory_store: file_store
)

# Store persistent memory
persistent_agent.remember("Important: System maintenance scheduled for Sunday",
                         metadata: { type: "system", priority: "high" })
puts "✓ Stored persistent memory (survives restart)"

# ============================================================================
# EXAMPLE 6: AGENT CLONING WITH MEMORY
# ============================================================================

puts "\n6. Agent Cloning with Shared Memory:"
puts "-" * 40

# Clone the memory agent - they share the same memory store
specialized_agent = agent_with_memory.clone(
  name: "SpecializedAgent",
  instructions: "You are a specialized version with shared memories"
)

puts "Original agent memories: #{agent_with_memory.memory_count}"
puts "Cloned agent memories: #{specialized_agent.memory_count}"
puts "Same memory store? #{agent_with_memory.memory_store.object_id == specialized_agent.memory_store.object_id}"

# Add memory to clone - appears in both
specialized_agent.remember("Clone-specific insight about user behavior")
puts "\nAfter adding memory to clone:"
puts "Original agent memories: #{agent_with_memory.memory_count}"
puts "Cloned agent memories: #{specialized_agent.memory_count}"

puts "\n=== Updated Summary ==="
puts "\nNative Agent Memory Methods:"
puts "• agent.remember(content, metadata:, conversation_id:) - Store information"
puts "• agent.recall(query, limit:, conversation_id:, tags:) - Search memories"
puts "• agent.memory_count - Get number of stored memories"
puts "• agent.has_memories? - Check if agent has any memories"
puts "• agent.forget(memory_key) - Delete specific memory"
puts "• agent.clear_memories - Delete all agent memories"
puts "• agent.recent_memories(limit:, conversation_id:) - Get recent memories"
puts "• agent.memory_context(query, limit:, conversation_id:) - Generate prompt context"

puts "\nMemory Store Options:"
puts "• InMemoryStore (default) - Fast, temporary storage"
puts "• FileStore - Persistent storage on disk"
puts "• Custom stores - Implement BaseStore interface"

puts "\nBest Practices:"
puts "• Use metadata for categorization and filtering"
puts "• Include conversation_id for multi-conversation agents"
puts "• Use memory_context() to enhance prompts with relevant history"
puts "• Consider token limits when building context"
puts "• Use persistent stores for long-term applications"

puts "\nPersistent memories stored in: ./persistent_memories/"
puts "Delete this directory to clear persistent memories."