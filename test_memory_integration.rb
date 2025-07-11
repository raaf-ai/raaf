#!/usr/bin/env ruby

# Test script for memory system integration with Agent class
require_relative 'lib/openai_agents'

puts "Testing Agent Memory System Integration"
puts "=" * 50

begin
  # Test 1: Agent creation with default memory store
  puts "\n1. Testing agent creation with default memory store..."
  agent = OpenAIAgents::Agent.new(
    name: "TestAgent",
    instructions: "You are a test assistant with memory capabilities",
    model: "gpt-4o"
  )
  
  puts "✓ Agent created successfully"
  puts "  Memory store type: #{agent.memory_store.class.name}"
  
  # Test 2: Basic memory operations
  puts "\n2. Testing basic memory operations..."
  
  # Store some memories
  key1 = agent.remember("User prefers Python programming", metadata: { type: "preference" })
  key2 = agent.remember("User is working on a web scraping project", 
                        metadata: { type: "context", project: "webscraper" },
                        conversation_id: "conv-123")
  key3 = agent.remember("User mentioned they use Django framework", 
                        metadata: { type: "tech_stack" })
  
  puts "✓ Stored 3 memories"
  puts "  Memory keys: #{[key1, key2, key3].map { |k| k[0..8] + "..." }.join(", ")}"
  
  # Test memory count
  count = agent.memory_count
  puts "✓ Memory count: #{count}"
  
  # Test has_memories?
  has_memories = agent.has_memories?
  puts "✓ Has memories: #{has_memories}"
  
  # Test 3: Memory retrieval
  puts "\n3. Testing memory retrieval..."
  
  # Search for programming related memories
  programming_memories = agent.recall("programming", limit: 5)
  puts "✓ Found #{programming_memories.length} programming-related memories"
  programming_memories.each_with_index do |memory, index|
    content = memory[:content] || memory["content"]
    puts "  #{index + 1}. #{content[0..50]}..."
  end
  
  # Search with conversation filter
  conv_memories = agent.recall("project", conversation_id: "conv-123")
  puts "✓ Found #{conv_memories.length} memories from conversation conv-123"
  
  # Test 4: Recent memories
  puts "\n4. Testing recent memories..."
  recent = agent.recent_memories(limit: 2)
  puts "✓ Retrieved #{recent.length} recent memories"
  recent.each_with_index do |memory, index|
    content = memory[:content] || memory["content"]
    timestamp = memory[:updated_at] || memory["updated_at"]
    puts "  #{index + 1}. #{content[0..40]}... (#{timestamp})"
  end
  
  # Test 5: Memory context generation
  puts "\n5. Testing memory context generation..."
  context = agent.memory_context("user", limit: 3)
  puts "✓ Generated memory context (#{context.length} characters)"
  puts "  Context preview: #{context[0..100]}..."
  
  # Test 6: Memory deletion
  puts "\n6. Testing memory deletion..."
  deleted = agent.forget(key1)
  puts "✓ Deleted memory: #{deleted}"
  
  new_count = agent.memory_count
  puts "✓ New memory count: #{new_count}"
  
  # Test 7: Clear all memories
  puts "\n7. Testing clear all memories..."
  agent.clear_memories
  final_count = agent.memory_count
  puts "✓ Cleared all memories, final count: #{final_count}"
  
  # Test 8: Agent cloning with memory store reference
  puts "\n8. Testing agent cloning with memory store..."
  cloned_agent = agent.clone(name: "ClonedAgent")
  puts "✓ Agent cloned successfully"
  puts "  Original memory store: #{agent.memory_store.object_id}"
  puts "  Cloned memory store: #{cloned_agent.memory_store.object_id}"
  puts "  Same memory store reference: #{agent.memory_store.object_id == cloned_agent.memory_store.object_id}"
  
  puts "\n" + "=" * 50
  puts "✅ ALL MEMORY INTEGRATION TESTS PASSED!"
  
rescue => e
  puts "\n❌ TEST FAILED: #{e.message}"
  puts "Error class: #{e.class.name}"
  puts "Backtrace:"
  puts e.backtrace[0..5].join("\n")
  exit 1
end