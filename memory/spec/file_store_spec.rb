# frozen_string_literal: true

require "spec_helper"
require "openai_agents/memory/file_store"
require "openai_agents/memory/memory"
require "tmpdir"
require "fileutils"

RSpec.describe RAAF::Memory::FileStore do
  let(:temp_dir) { Dir.mktmpdir }
  let(:store) { described_class.new(temp_dir) }
  let(:memory) { RAAF::Memory::Memory.new(content: "Test memory", agent_name: "TestAgent") }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "#initialize" do
    it "creates directory if it doesn't exist" do
      new_dir = File.join(temp_dir, "new_memories")
      expect(Dir.exist?(new_dir)).to be false
      
      described_class.new(new_dir)
      
      expect(Dir.exist?(new_dir)).to be true
    end

    it "creates index file" do
      index_file = File.join(temp_dir, "index.json")
      
      expect(File.exist?(index_file)).to be true
      expect(JSON.parse(File.read(index_file))).to eq({})
    end
  end

  describe "#store" do
    it "stores memory to file" do
      store.store("key1", memory)
      
      memory_file = File.join(temp_dir, "key1.memory.json")
      expect(File.exist?(memory_file)).to be true
      
      stored_data = JSON.parse(File.read(memory_file), symbolize_names: true)
      expect(stored_data[:content]).to eq("Test memory")
    end

    it "updates index" do
      store.store("key1", memory)
      
      index = JSON.parse(File.read(File.join(temp_dir, "index.json")), symbolize_names: true)
      expect(index).to have_key(:key1)
      expect(index[:key1][:agent_name]).to eq("TestAgent")
    end

    it "handles special characters in keys" do
      store.store("key/with\\special:chars", "Memory")
      
      files = Dir.glob(File.join(temp_dir, "*.memory.json"))
      expect(files.size).to eq(1)
      expect(files.first).to include("key_with_special_chars")
    end
  end

  describe "#retrieve" do
    it "retrieves stored memory" do
      store.store("key1", memory)
      
      retrieved = store.retrieve("key1")
      expect(retrieved).not_to be_nil
      expect(retrieved[:content]).to eq("Test memory")
      expect(retrieved[:agent_name]).to eq("TestAgent")
    end

    it "returns nil for non-existent key" do
      expect(store.retrieve("non-existent")).to be_nil
    end

    it "handles corrupted files gracefully" do
      store.store("key1", memory)
      
      # Corrupt the file
      memory_file = File.join(temp_dir, "key1.memory.json")
      File.write(memory_file, "invalid json")
      
      expect(store.retrieve("key1")).to be_nil
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
                            content: "Ruby on Rails",
                            agent_name: "Agent1",
                            conversation_id: "conv-123"
                          ))
    end

    it "searches by content" do
      results = store.search("ruby")
      
      expect(results.size).to eq(2)
      contents = results.map { |r| r[:content] }
      expect(contents).to include("Ruby programming guide", "Ruby on Rails")
    end

    it "uses index for filtering" do
      results = store.search("programming", agent_name: "Agent1")
      
      expect(results.size).to eq(1)
      expect(results.first[:content]).to eq("Ruby programming guide")
    end
  end

  describe "#delete" do
    it "deletes memory file and index entry" do
      store.store("key1", "Memory to delete")
      
      expect(store.delete("key1")).to be true
      
      memory_file = File.join(temp_dir, "key1.memory.json")
      expect(File.exist?(memory_file)).to be false
      
      index = JSON.parse(File.read(File.join(temp_dir, "index.json")))
      expect(index).not_to have_key("key1")
    end
  end

  describe "#clear" do
    it "removes all memory files and clears index" do
      store.store("key1", "Memory 1")
      store.store("key2", "Memory 2")
      
      store.clear
      
      memory_files = Dir.glob(File.join(temp_dir, "*.memory.json"))
      expect(memory_files).to be_empty
      
      index = JSON.parse(File.read(File.join(temp_dir, "index.json")))
      expect(index).to eq({})
    end
  end

  describe "#compact!" do
    it "removes orphaned files" do
      store.store("key1", "Memory 1")
      
      # Create orphaned file
      orphaned_file = File.join(temp_dir, "orphaned.memory.json")
      File.write(orphaned_file, JSON.generate({ content: "Orphaned" }))
      
      expect(File.exist?(orphaned_file)).to be true
      
      removed = store.compact!
      
      expect(removed).to eq(1)
      expect(File.exist?(orphaned_file)).to be false
    end
  end

  describe "persistence" do
    it "persists data between instances" do
      store.store("key1", "Persistent memory")
      
      # Create new instance with same directory
      new_store = described_class.new(temp_dir)
      
      retrieved = new_store.retrieve("key1")
      expect(retrieved[:content]).to eq("Persistent memory")
    end
  end

  describe "concurrent access" do
    it "handles concurrent operations" do
      threads = []
      
      5.times do |i|
        threads << Thread.new do
          store.store("key#{i}", "Memory #{i}")
          store.retrieve("key#{i}")
        end
      end
      
      threads.each(&:join)
      
      expect(store.count).to eq(5)
    end
  end
end