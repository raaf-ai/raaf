# frozen_string_literal: true

require "spec_helper"
require "openai_agents/memory/in_memory_store"
require "openai_agents/memory/memory"

RSpec.describe RAAF::Memory::InMemoryStore do
  let(:store) { described_class.new }
  let(:memory) { RAAF::Memory::Memory.new(content: "Test memory", agent_name: "TestAgent") }

  describe "#store" do
    it "stores a memory object" do
      store.store("key1", memory)
      
      retrieved = store.retrieve("key1")
      expect(retrieved).not_to be_nil
      expect(retrieved[:content]).to eq("Test memory")
    end

    it "stores a hash as memory" do
      store.store("key2", { content: "Hash memory" })
      
      retrieved = store.retrieve("key2")
      expect(retrieved[:content]).to eq("Hash memory")
    end

    it "stores a string as memory" do
      store.store("key3", "String memory")
      
      retrieved = store.retrieve("key3")
      expect(retrieved[:content]).to eq("String memory")
    end

    it "updates existing memory" do
      store.store("key1", "Original")
      store.store("key1", "Updated")
      
      retrieved = store.retrieve("key1")
      expect(retrieved[:content]).to eq("Updated")
    end
  end

  describe "#retrieve" do
    it "returns nil for non-existent key" do
      expect(store.retrieve("non-existent")).to be_nil
    end

    it "returns memory as hash" do
      store.store("key1", memory)
      
      retrieved = store.retrieve("key1")
      expect(retrieved).to be_a(Hash)
      expect(retrieved).to include(:id, :content, :created_at, :updated_at)
    end
  end

  describe "#search" do
    before do
      store.store("mem1", RAAF::Memory::Memory.new(
                            content: "Ruby programming guide",
                            agent_name: "Agent1",
                            metadata: { tags: %w[ruby programming] }
                          ))
      
      store.store("mem2", RAAF::Memory::Memory.new(
                            content: "Python tutorial",
                            agent_name: "Agent2",
                            metadata: { tags: %w[python programming] }
                          ))
      
      store.store("mem3", RAAF::Memory::Memory.new(
                            content: "Ruby on Rails framework",
                            agent_name: "Agent1",
                            conversation_id: "conv-123"
                          ))
    end

    it "searches by content" do
      results = store.search("ruby")
      
      expect(results.size).to eq(2)
      expect(results.map { |r| r[:content] }).to include(
        "Ruby programming guide",
        "Ruby on Rails framework"
      )
    end

    it "filters by agent name" do
      results = store.search("programming", agent_name: "Agent1")
      
      expect(results.size).to eq(1)
      expect(results.first[:content]).to eq("Ruby programming guide")
    end

    it "filters by conversation ID" do
      results = store.search("ruby", conversation_id: "conv-123")
      
      expect(results.size).to eq(1)
      expect(results.first[:content]).to eq("Ruby on Rails framework")
    end

    it "filters by tags" do
      results = store.search("programming", tags: ["ruby"])
      
      expect(results.size).to eq(1)
      expect(results.first[:content]).to eq("Ruby programming guide")
    end

    it "respects limit" do
      results = store.search("programming", limit: 1)
      
      expect(results.size).to eq(1)
    end
  end

  describe "#delete" do
    it "deletes existing memory" do
      store.store("key1", "Memory to delete")
      
      expect(store.delete("key1")).to be true
      expect(store.retrieve("key1")).to be_nil
    end

    it "returns false for non-existent key" do
      expect(store.delete("non-existent")).to be false
    end
  end

  describe "#list_keys" do
    before do
      store.store("key1", RAAF::Memory::Memory.new(content: "1", agent_name: "Agent1"))
      store.store("key2", RAAF::Memory::Memory.new(content: "2", agent_name: "Agent2"))
      store.store("key3", RAAF::Memory::Memory.new(content: "3", agent_name: "Agent1", conversation_id: "conv-123"))
    end

    it "lists all keys" do
      expect(store.list_keys).to contain_exactly("key1", "key2", "key3")
    end

    it "filters by agent name" do
      expect(store.list_keys(agent_name: "Agent1")).to contain_exactly("key1", "key3")
    end

    it "filters by conversation ID" do
      expect(store.list_keys(conversation_id: "conv-123")).to contain_exactly("key3")
    end
  end

  describe "#clear" do
    it "removes all memories" do
      store.store("key1", "Memory 1")
      store.store("key2", "Memory 2")
      
      store.clear
      
      expect(store.count).to eq(0)
      expect(store.list_keys).to be_empty
    end
  end

  describe "#count" do
    it "returns number of stored memories" do
      expect(store.count).to eq(0)
      
      store.store("key1", "Memory 1")
      expect(store.count).to eq(1)
      
      store.store("key2", "Memory 2")
      expect(store.count).to eq(2)
    end
  end

  describe "#get_by_time_range" do
    it "returns memories within time range" do
      Time.now
      
      store.store("old", RAAF::Memory::Memory.new(content: "Old memory"))
      
      sleep 0.1
      start_time = Time.now
      
      store.store("new1", RAAF::Memory::Memory.new(content: "New memory 1"))
      store.store("new2", RAAF::Memory::Memory.new(content: "New memory 2"))
      
      end_time = Time.now + 1
      
      results = store.get_by_time_range(start_time, end_time)
      
      expect(results.size).to eq(2)
      expect(results.map { |r| r[:content] }).to contain_exactly("New memory 1", "New memory 2")
    end
  end

  describe "#get_recent" do
    it "returns most recent memories" do
      store.store("old", RAAF::Memory::Memory.new(content: "Old"))
      sleep 0.01
      store.store("middle", RAAF::Memory::Memory.new(content: "Middle"))
      sleep 0.01
      store.store("new", RAAF::Memory::Memory.new(content: "New"))
      
      results = store.get_recent(2)
      
      expect(results.size).to eq(2)
      expect(results.first[:content]).to eq("New")
      expect(results.last[:content]).to eq("Middle")
    end
  end

  describe "#exists?" do
    it "checks memory existence" do
      store.store("key1", "Memory")
      
      expect(store.exists?("key1")).to be true
      expect(store.exists?("non-existent")).to be false
    end
  end

  describe "#get_by_agent" do
    before do
      store.store("a1", RAAF::Memory::Memory.new(content: "A1", agent_name: "Agent1"))
      store.store("a2", RAAF::Memory::Memory.new(content: "A2", agent_name: "Agent1"))
      store.store("b1", RAAF::Memory::Memory.new(content: "B1", agent_name: "Agent2"))
    end

    it "returns memories for specific agent" do
      results = store.get_by_agent("Agent1")
      
      expect(results.size).to eq(2)
      expect(results.map { |r| r[:content] }).to contain_exactly("A1", "A2")
    end

    it "respects limit" do
      results = store.get_by_agent("Agent1", 1)
      
      expect(results.size).to eq(1)
    end
  end

  describe "#get_by_conversation" do
    before do
      store.store("c1", RAAF::Memory::Memory.new(content: "C1", conversation_id: "conv-123"))
      store.store("c2", RAAF::Memory::Memory.new(content: "C2", conversation_id: "conv-123"))
      store.store("d1", RAAF::Memory::Memory.new(content: "D1", conversation_id: "conv-456"))
    end

    it "returns memories for specific conversation" do
      results = store.get_by_conversation("conv-123")
      
      expect(results.size).to eq(2)
      expect(results.map { |r| r[:content] }).to contain_exactly("C1", "C2")
    end
  end

  describe "#export and #import" do
    it "exports and imports all memories" do
      store.store("key1", RAAF::Memory::Memory.new(content: "Memory 1"))
      store.store("key2", RAAF::Memory::Memory.new(content: "Memory 2"))
      
      exported = store.export
      
      new_store = described_class.new
      new_store.import(exported)
      
      expect(new_store.count).to eq(2)
      expect(new_store.retrieve("key1")[:content]).to eq("Memory 1")
      expect(new_store.retrieve("key2")[:content]).to eq("Memory 2")
    end
  end

  describe "thread safety" do
    it "handles concurrent operations safely" do
      threads = []
      
      10.times do |i|
        threads << Thread.new do
          store.store("key#{i}", "Memory #{i}")
          store.retrieve("key#{i}")
          store.search("Memory")
        end
      end
      
      threads.each(&:join)
      
      expect(store.count).to eq(10)
    end
  end
end