# frozen_string_literal: true

require "spec_helper"
require "openai_agents/agent"
require "openai_agents/memory/in_memory_store"

RSpec.describe "Agent Memory Integration" do
  let(:memory_store) { OpenAIAgents::Memory::InMemoryStore.new }
  let(:agent) do
    OpenAIAgents::Agent.new(
      name: "MemoryAgent",
      instructions: "You are a helpful assistant with memory",
      memory_store: memory_store
    )
  end

  describe "memory initialization" do
    it "accepts memory store in constructor" do
      expect(agent.memory_store).to eq(memory_store)
    end

    it "works without memory store" do
      agent_without_memory = OpenAIAgents::Agent.new(
        name: "NoMemoryAgent",
        instructions: "No memory needed"
      )
      
      expect(agent_without_memory.memory_store).to be_nil
      expect(agent_without_memory.remember("test")).to be_nil
      expect(agent_without_memory.recall("test")).to eq([])
    end
  end

  describe "#remember" do
    it "stores memory with agent name" do
      key = agent.remember("Important information")
      
      expect(key).not_to be_nil
      
      stored = memory_store.retrieve(key)
      expect(stored[:content]).to eq("Important information")
      expect(stored[:agent_name]).to eq("MemoryAgent")
    end

    it "accepts conversation ID" do
      key = agent.remember("Conversation memory", conversation_id: "conv-123")
      
      stored = memory_store.retrieve(key)
      expect(stored[:conversation_id]).to eq("conv-123")
    end

    it "accepts metadata" do
      key = agent.remember("Tagged memory", metadata: { priority: "high", tags: ["important"] })
      
      stored = memory_store.retrieve(key)
      expect(stored[:metadata][:priority]).to eq("high")
      expect(stored[:metadata][:tags]).to include("important")
    end
  end

  describe "#recall" do
    before do
      agent.remember("Ruby programming tips")
      agent.remember("Python basics")
      agent.remember("Ruby on Rails guide")
      
      # Add memory from another agent
      other_memory = OpenAIAgents::Memory::Memory.new(
        content: "Other agent's Ruby knowledge",
        agent_name: "OtherAgent"
      )
      memory_store.store("other", other_memory)
    end

    it "searches only agent's own memories by default" do
      results = agent.recall("Ruby")
      
      expect(results.size).to eq(2)
      expect(results.all? { |r| r[:agent_name] == "MemoryAgent" }).to be true
    end

    it "accepts search options" do
      agent.remember("Limited memory", conversation_id: "conv-456")
      
      results = agent.recall("memory", conversation_id: "conv-456")
      
      expect(results.size).to eq(1)
      expect(results.first[:content]).to eq("Limited memory")
    end
  end

  describe "#recent_memories" do
    before do
      agent.remember("Old memory")
      sleep 0.01
      agent.remember("Middle memory")
      sleep 0.01
      agent.remember("Recent memory")
      
      # Add another agent's memory
      other_memory = OpenAIAgents::Memory::Memory.new(
        content: "Other agent memory",
        agent_name: "OtherAgent"
      )
      memory_store.store("other", other_memory)
    end

    it "returns agent's recent memories" do
      recent = agent.recent_memories(2)
      
      expect(recent.size).to eq(2)
      expect(recent.first[:content]).to eq("Recent memory")
      expect(recent.last[:content]).to eq("Middle memory")
      expect(recent.all? { |r| r[:agent_name] == "MemoryAgent" }).to be true
    end
  end

  describe "#forget" do
    it "deletes specific memory" do
      key = agent.remember("Memory to forget")
      
      expect(agent.forget(key)).to be true
      expect(memory_store.retrieve(key)).to be_nil
    end
  end

  describe "#clear_memories" do
    before do
      agent.remember("Memory 1")
      agent.remember("Memory 2")
      
      # Add another agent's memory
      other_memory = OpenAIAgents::Memory::Memory.new(
        content: "Other agent memory",
        agent_name: "OtherAgent"
      )
      memory_store.store("other", other_memory)
    end

    it "clears only agent's memories" do
      agent.clear_memories
      
      agent_keys = memory_store.list_keys(agent_name: "MemoryAgent")
      expect(agent_keys).to be_empty
      
      # Other agent's memory should remain
      other_keys = memory_store.list_keys(agent_name: "OtherAgent")
      expect(other_keys).not_to be_empty
    end
  end

  describe "#memory_context" do
    before do
      agent.remember("Context about Ruby programming")
      agent.remember("Context about Python")
      agent.remember("More Ruby details")
    end

    it "formats memories as context" do
      context = agent.memory_context
      
      expect(context).to include("## Previous Context")
      expect(context).to include("Ruby programming")
      expect(context).to include("Python")
    end

    it "filters by query" do
      context = agent.memory_context("Ruby", 2)
      
      expect(context).to include("Ruby programming")
      expect(context).to include("Ruby details")
      expect(context).not_to include("Python")
    end

    it "returns empty string without memories" do
      agent.clear_memories
      
      expect(agent.memory_context).to eq("")
    end
  end

  describe "#has_memories?" do
    it "returns false initially" do
      expect(agent.has_memories?).to be false
    end

    it "returns true after remembering" do
      agent.remember("Something")
      
      expect(agent.has_memories?).to be true
    end
  end

  describe "#memory_count" do
    it "returns memory count for agent" do
      expect(agent.memory_count).to eq(0)
      
      agent.remember("Memory 1")
      agent.remember("Memory 2")
      
      expect(agent.memory_count).to eq(2)
    end
  end
end