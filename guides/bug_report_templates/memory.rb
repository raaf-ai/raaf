# frozen_string_literal: true

require "bundler/inline"

gemfile(true) do
  source "https://rubygems.org"

  gem "raaf"
  gem "rspec"
  # If you want to test against edge RAAF replace the raaf line with this:
  # gem "raaf", github: "enterprisemodules/raaf", branch: "main"
end

require "raaf"
require "rspec/autorun"

RSpec.describe "RAAF Memory Bug Report" do
  it "creates memory manager with configuration" do
    memory_store = RAAF::Memory::InMemoryStore.new
    memory_manager = RAAF::Memory::MemoryManager.new(
      store: memory_store,
      max_tokens: 1000,
      pruning_strategy: :sliding_window
    )
    
    expect(memory_manager).to be_a(RAAF::Memory::MemoryManager)
    expect(memory_manager.max_tokens).to eq(1000)
  end

  it "persists memory across sessions" do
    memory_store = RAAF::Memory::InMemoryStore.new
    memory_manager = RAAF::Memory::MemoryManager.new(store: memory_store)
    
    session_id = "test_session_123"
    
    # Add messages to memory
    memory_manager.add_message(
      session_id: session_id,
      role: "user",
      content: "Hello, how are you?"
    )
    
    memory_manager.add_message(
      session_id: session_id,
      role: "assistant", 
      content: "I'm doing well, thank you!"
    )
    
    # Retrieve messages
    messages = memory_manager.get_messages(session_id: session_id)
    
    expect(messages.length).to eq(2)
    expect(messages.first[:role]).to eq("user")
    expect(messages.first[:content]).to eq("Hello, how are you?")
  end

  it "prunes memory when token limits are exceeded" do
    memory_store = RAAF::Memory::InMemoryStore.new
    memory_manager = RAAF::Memory::MemoryManager.new(
      store: memory_store,
      max_tokens: 100,  # Very low limit to trigger pruning
      pruning_strategy: :sliding_window
    )
    
    session_id = "test_session_pruning"
    
    # Add many messages to trigger pruning
    10.times do |i|
      memory_manager.add_message(
        session_id: session_id,
        role: "user",
        content: "This is message number #{i} with some content to reach token limits"
      )
    end
    
    messages = memory_manager.get_messages(session_id: session_id)
    
    # Should have fewer than 10 messages due to pruning
    expect(messages.length).to be < 10
  end

  it "integrates memory with agent runner" do
    memory_store = RAAF::Memory::InMemoryStore.new
    memory_manager = RAAF::Memory::MemoryManager.new(store: memory_store)
    
    agent = RAAF::Agent.new(
      name: "MemoryAgent",
      instructions: "You remember previous conversations",
      model: "gpt-4o-mini"
    )
    
    runner = RAAF::Runner.new(
      agent: agent,
      memory_manager: memory_manager
    )
    
    session_id = "conversation_123"
    
    # This would require actual API calls to test fully
    # Add your specific memory-related test case here
    expect(runner).to be_a(RAAF::Runner)
  end

  # Add your specific test case here that demonstrates the bug
  it "reproduces your specific memory bug case" do
    # Replace this with your specific test case that demonstrates the memory bug
    expect(true).to be true # Replace this with your actual test case
  end
end