#!/usr/bin/env ruby
# frozen_string_literal: true

# Test script for new RAAF features

require_relative 'lib/raaf-core'

# Set up test environment
ENV['OPENAI_API_KEY'] = 'test-key'
ENV['RAAF_LOG_LEVEL'] = 'info'

puts "=== Testing New RAAF Features ==="

# Test 1: Model Settings Processing
puts "\n1. Testing Model Settings Processing..."

begin
  # Create model settings with validation
  settings = RAAF::ModelSettings.new(
    temperature: 0.7,
    max_tokens: 1000,
    top_p: 0.9,
    frequency_penalty: 0.1
  )
  
  puts "✓ Model settings created successfully"
  puts "  - Temperature: #{settings.temperature}"
  puts "  - Max tokens: #{settings.max_tokens}"
  puts "  - Top P: #{settings.top_p}"
  
  # Test validation
  begin
    invalid_settings = RAAF::ModelSettings.new(temperature: 5.0)  # Should fail
    puts "✗ Validation failed - should have rejected temperature > 2.0"
  rescue ArgumentError => e
    puts "✓ Validation working: #{e.message}"
  end
  
  # Test with agent
  agent = RAAF::Agent.new(
    name: "TestAgent",
    instructions: "Test agent",
    model_settings: {
      temperature: 0.5,
      max_tokens: 500
    }
  )
  
  puts "✓ Agent created with model settings"
  puts "  - Settings class: #{agent.model_settings.class.name}"
  puts "  - Temperature: #{agent.model_settings.temperature}"
  
rescue => e
  puts "✗ Model Settings test failed: #{e.message}"
  puts e.backtrace.first(3)
end

# Test 2: Session Implementation
puts "\n2. Testing Session Implementation..."

begin
  # Create session
  session = RAAF::Session.new(
    metadata: { user_id: "123", session_type: "test" }
  )
  
  puts "✓ Session created successfully"
  puts "  - ID: #{session.id}"
  puts "  - Metadata: #{session.metadata}"
  
  # Add messages
  session.add_message(role: "user", content: "Hello!")
  session.add_message(role: "assistant", content: "Hi there!")
  
  puts "✓ Messages added to session"
  puts "  - Message count: #{session.message_count}"
  puts "  - Last message: #{session.last_message[:content]}"
  
  # Test session stores
  in_memory_store = RAAF::InMemorySessionStore.new
  in_memory_store.store(session)
  
  retrieved = in_memory_store.retrieve(session.id)
  puts "✓ Session stored and retrieved from InMemorySessionStore"
  puts "  - Retrieved messages: #{retrieved.message_count}"
  
  # Test file store
  file_store = RAAF::FileSessionStore.new(directory: "/tmp/raaf_test_sessions")
  file_store.store(session)
  
  retrieved_file = file_store.retrieve(session.id)
  puts "✓ Session stored and retrieved from FileSessionStore"
  puts "  - Retrieved messages: #{retrieved_file.message_count}"
  
  # Cleanup
  file_store.clear
  
rescue => e
  puts "✗ Session test failed: #{e.message}"
  puts e.backtrace.first(3)
end

# Test 3: Context Type Safety
puts "\n3. Testing Context Type Safety..."

begin
  # Define test context class
  class TestContext
    attr_accessor :user_id, :session_id, :preferences
    
    def initialize(user_id:, session_id: nil, preferences: {})
      @user_id = user_id
      @session_id = session_id
      @preferences = preferences
    end
    
    def to_h
      {
        user_id: @user_id,
        session_id: @session_id,
        preferences: @preferences
      }
    end
  end
  
  # Create typed context wrapper
  context = RAAF::RunContext.new(messages: [])
  typed_wrapper = RAAF::TypedRunContextWrapper.new(context, TestContext)
  
  puts "✓ TypedRunContextWrapper created"
  puts "  - Type class: #{typed_wrapper.type_class.name}"
  puts "  - Has typed context: #{typed_wrapper.typed_context?}"
  
  # Set typed context
  test_context = TestContext.new(user_id: 123, preferences: { theme: "dark" })
  typed_wrapper.typed_context = test_context
  
  puts "✓ Typed context set successfully"
  puts "  - User ID: #{typed_wrapper.typed_context.user_id}"
  puts "  - Preferences: #{typed_wrapper.typed_context.preferences}"
  
  # Test type validation
  begin
    typed_wrapper.typed_context = "invalid_type"  # Should fail
    puts "✗ Type validation failed - should have rejected string"
  rescue TypeError => e
    puts "✓ Type validation working: #{e.message}"
  end
  
  # Test context conversion
  context_hash = typed_wrapper.typed_context_to_h
  puts "✓ Context converted to hash"
  puts "  - Hash keys: #{context_hash.keys}"
  
rescue => e
  puts "✗ Context Type Safety test failed: #{e.message}"
  puts e.backtrace.first(3)
end

# Test 4: Integration Test
puts "\n4. Testing Integration..."

begin
  # Create agent with model settings
  agent = RAAF::Agent.new(
    name: "IntegrationAgent",
    instructions: "Test integration",
    model_settings: {
      temperature: 0.8,
      max_tokens: 800
    }
  )
  
  # Create session
  session = RAAF::Session.new(metadata: { test: "integration" })
  session.add_message(role: "user", content: "Test message")
  
  # Test would require actual API call, so just verify setup
  puts "✓ Integration setup successful"
  puts "  - Agent: #{agent.name}"
  puts "  - Model settings: #{agent.model_settings.class.name}"
  puts "  - Session: #{session.id}"
  puts "  - Session messages: #{session.message_count}"
  
rescue => e
  puts "✗ Integration test failed: #{e.message}"
  puts e.backtrace.first(3)
end

puts "\n=== All Tests Complete ==="