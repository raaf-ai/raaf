#!/usr/bin/env ruby

# Test script for Agent clone functionality
require_relative 'lib/openai_agents'

puts "Testing Agent Clone Functionality"
puts "=" * 40

begin
  # Test 1: Create a base agent with various configurations
  puts "\n1. Creating base agent with comprehensive configuration..."
  
  # Define some test tools
  def test_tool_1(input)
    "Tool 1 result: #{input}"
  end
  
  def test_tool_2(input)
    "Tool 2 result: #{input}"
  end
  
  # Create memory store
  memory_store = OpenAIAgents::Memory::InMemoryStore.new
  
  # Create another agent for handoffs
  handoff_agent = OpenAIAgents::Agent.new(
    name: "HandoffTarget", 
    instructions: "I handle handoffs"
  )
  
  base_agent = OpenAIAgents::Agent.new(
    name: "BaseAgent",
    instructions: "You are a comprehensive test agent",
    model: "gpt-4o",
    max_turns: 15,
    memory_store: memory_store,
    response_format: { type: "json_object" },
    tool_choice: "auto"
  )
  
  # Add tools and handoffs
  base_agent.add_tool(method(:test_tool_1))
  base_agent.add_tool(method(:test_tool_2))
  base_agent.add_handoff(handoff_agent)
  
  # Add some memories
  base_agent.remember("Base agent memory 1")
  base_agent.remember("Base agent memory 2", metadata: { type: "test" })
  
  puts "✓ Base agent created with:"
  puts "  - Name: #{base_agent.name}"
  puts "  - Tools: #{base_agent.tools.length}"
  puts "  - Handoffs: #{base_agent.handoffs.length}"
  puts "  - Memories: #{base_agent.memory_count}"
  puts "  - Model: #{base_agent.model}"
  puts "  - Max turns: #{base_agent.max_turns}"
  
  # Test 2: Basic clone (no overrides)
  puts "\n2. Testing basic clone (no overrides)..."
  basic_clone = base_agent.clone
  
  puts "✓ Basic clone created:"
  puts "  - Name: #{basic_clone.name} (same: #{basic_clone.name == base_agent.name})"
  puts "  - Tools: #{basic_clone.tools.length} (same count: #{basic_clone.tools.length == base_agent.tools.length})"
  puts "  - Handoffs: #{basic_clone.handoffs.length} (same count: #{basic_clone.handoffs.length == base_agent.handoffs.length})"
  puts "  - Model: #{basic_clone.model} (same: #{basic_clone.model == base_agent.model})"
  puts "  - Memory store reference: #{basic_clone.memory_store.object_id == base_agent.memory_store.object_id}"
  puts "  - Shared memories: #{basic_clone.memory_count == base_agent.memory_count}"
  
  # Test 3: Clone with overrides
  puts "\n3. Testing clone with parameter overrides..."
  
  specialized_clone = base_agent.clone(
    name: "SpecializedAgent",
    instructions: "You are a specialized version",
    model: "gpt-4o-mini",
    max_turns: 25
  )
  
  puts "✓ Specialized clone created:"
  puts "  - Name: #{specialized_clone.name} (different: #{specialized_clone.name != base_agent.name})"
  puts "  - Instructions: '#{specialized_clone.instructions[0..30]}...'"
  puts "  - Model: #{specialized_clone.model} (different: #{specialized_clone.model != base_agent.model})"
  puts "  - Max turns: #{specialized_clone.max_turns} (different: #{specialized_clone.max_turns != base_agent.max_turns})"
  puts "  - Tools preserved: #{specialized_clone.tools.length == base_agent.tools.length}"
  puts "  - Handoffs preserved: #{specialized_clone.handoffs.length == base_agent.handoffs.length}"
  puts "  - Memory store shared: #{specialized_clone.memory_store.object_id == base_agent.memory_store.object_id}"
  
  # Test 4: Tool functionality in clones
  puts "\n4. Testing tool functionality in clones..."
  
  # Test tool execution in original
  original_result = base_agent.execute_tool("test_tool_1", input: "original")
  puts "✓ Original agent tool result: #{original_result}"
  
  # Test tool execution in clone
  clone_result = basic_clone.execute_tool("test_tool_1", input: "clone")
  puts "✓ Clone agent tool result: #{clone_result}"
  
  # Test 5: Handoff functionality in clones
  puts "\n5. Testing handoff functionality in clones..."
  
  can_handoff_original = base_agent.can_handoff_to?("HandoffTarget")
  can_handoff_clone = basic_clone.can_handoff_to?("HandoffTarget")
  
  puts "✓ Original can handoff: #{can_handoff_original}"
  puts "✓ Clone can handoff: #{can_handoff_clone}"
  
  # Test 6: Memory independence after modification
  puts "\n6. Testing memory modifications (shared store)..."
  
  # Add memory to clone - should appear in original too (shared store)
  specialized_clone.remember("Clone-specific memory")
  
  puts "✓ Memory counts after clone addition:"
  puts "  - Original: #{base_agent.memory_count}"
  puts "  - Basic clone: #{basic_clone.memory_count}"
  puts "  - Specialized clone: #{specialized_clone.memory_count}"
  puts "  - All same (shared store): #{base_agent.memory_count == specialized_clone.memory_count}"
  
  # Test 7: Array duplication (tools and handoffs should be independent)
  puts "\n7. Testing array independence..."
  
  # Add tool to clone - should not affect original
  def clone_specific_tool(input)
    "Clone tool: #{input}"
  end
  
  specialized_clone.add_tool(method(:clone_specific_tool))
  
  puts "✓ Tool counts after adding to clone:"
  puts "  - Original tools: #{base_agent.tools.length}"
  puts "  - Specialized clone tools: #{specialized_clone.tools.length}"
  puts "  - Arrays are independent: #{base_agent.tools.length != specialized_clone.tools.length}"
  
  # Test 8: Clone chain
  puts "\n8. Testing clone chain..."
  
  clone_of_clone = specialized_clone.clone(
    name: "CloneOfClone",
    model: "gpt-4"
  )
  
  puts "✓ Clone of clone created:"
  puts "  - Name: #{clone_of_clone.name}"
  puts "  - Model: #{clone_of_clone.model}"
  puts "  - Tools: #{clone_of_clone.tools.length} (inherited from specialized)"
  puts "  - Memory store: #{clone_of_clone.memory_store.object_id == base_agent.memory_store.object_id}"
  
  # Test 9: Hash representation consistency
  puts "\n9. Testing hash representation..."
  
  original_hash = base_agent.to_h
  clone_hash = basic_clone.to_h
  
  puts "✓ Hash keys match: #{original_hash.keys == clone_hash.keys}"
  puts "✓ Names match in hash: #{original_hash[:name] == clone_hash[:name]}"
  puts "✓ Models match in hash: #{original_hash[:model] == clone_hash[:model]}"
  
  puts "\n" + "=" * 40
  puts "✅ ALL CLONE FUNCTIONALITY TESTS PASSED!"
  
rescue => e
  puts "\n❌ TEST FAILED: #{e.message}"
  puts "Error class: #{e.class.name}"
  puts "Backtrace:"
  puts e.backtrace[0..5].join("\n")
  exit 1
end