# frozen_string_literal: true

require "spec_helper"
require "openai_agents/memory/memory"

RSpec.describe OpenAIAgents::Memory::Memory do
  describe "#initialize" do
    it "creates a memory with required content" do
      memory = described_class.new(content: "Test content")
      
      expect(memory.content).to eq("Test content")
      expect(memory.id).not_to be_nil
      expect(memory.created_at).to be_a(Time)
      expect(memory.updated_at).to be_a(Time)
    end

    it "accepts optional parameters" do
      memory = described_class.new(
        content: "Test",
        agent_name: "TestAgent",
        conversation_id: "conv-123",
        metadata: { tags: ["important"] },
        id: "custom-id"
      )
      
      expect(memory.agent_name).to eq("TestAgent")
      expect(memory.conversation_id).to eq("conv-123")
      expect(memory.metadata).to eq({ tags: ["important"] })
      expect(memory.id).to eq("custom-id")
    end
  end

  describe "#to_h" do
    it "converts memory to hash" do
      memory = described_class.new(
        content: "Test content",
        agent_name: "Agent1",
        conversation_id: "conv-123"
      )
      
      hash = memory.to_h
      
      expect(hash).to include(
        id: memory.id,
        content: "Test content",
        agent_name: "Agent1",
        conversation_id: "conv-123",
        metadata: {},
        created_at: memory.created_at.iso8601,
        updated_at: memory.updated_at.iso8601
      )
    end
  end

  describe ".from_h" do
    it "creates memory from hash" do
      original = described_class.new(
        content: "Test",
        agent_name: "Agent1",
        metadata: { priority: "high" }
      )
      
      hash = original.to_h
      restored = described_class.from_h(hash)
      
      expect(restored.id).to eq(original.id)
      expect(restored.content).to eq(original.content)
      expect(restored.agent_name).to eq(original.agent_name)
      expect(restored.metadata).to eq(original.metadata)
      expect(restored.created_at.to_i).to eq(original.created_at.to_i)
    end

    it "handles string keys" do
      hash = {
        "id" => "test-id",
        "content" => "Test content",
        "agent_name" => "Agent1",
        "metadata" => { "key" => "value" },
        "created_at" => Time.now.iso8601
      }
      
      memory = described_class.from_h(hash)
      
      expect(memory.id).to eq("test-id")
      expect(memory.content).to eq("Test content")
      expect(memory.agent_name).to eq("Agent1")
    end
  end

  describe "#update" do
    it "updates content and metadata" do
      memory = described_class.new(content: "Original")
      original_created = memory.created_at
      
      sleep 0.01 # Ensure time difference
      memory.update(content: "Updated", metadata: { edited: true })
      
      expect(memory.content).to eq("Updated")
      expect(memory.metadata).to eq({ edited: true })
      expect(memory.created_at).to eq(original_created)
      expect(memory.updated_at).to be > original_created
    end
  end

  describe "#add_tags" do
    it "adds tags to metadata" do
      memory = described_class.new(content: "Test")
      
      memory.add_tags("important", "urgent")
      expect(memory.metadata[:tags]).to eq(%w[important urgent])
      
      memory.add_tags("urgent", "todo")
      expect(memory.metadata[:tags]).to eq(%w[important urgent todo])
    end
  end

  describe "#has_tag?" do
    it "checks for tag presence" do
      memory = described_class.new(content: "Test")
      memory.add_tags("important")
      
      expect(memory.has_tag?("important")).to be true
      expect(memory.has_tag?("urgent")).to be false
    end
  end

  describe "#age" do
    it "returns age in seconds" do
      memory = described_class.new(content: "Test")
      
      sleep 0.1
      expect(memory.age).to be_between(0.1, 0.2)
    end
  end

  describe "#summary" do
    it "returns full content if under limit" do
      memory = described_class.new(content: "Short content")
      
      expect(memory.summary(100)).to eq("Short content")
    end

    it "truncates long content" do
      long_content = "a" * 150
      memory = described_class.new(content: long_content)
      
      summary = memory.summary(100)
      expect(summary).to eq(("a" * 100) + "...")
      expect(summary.length).to eq(103)
    end
  end

  describe "#matches?" do
    let(:memory) do
      described_class.new(
        content: "Ruby programming is fun",
        metadata: { 
          category: "programming",
          tags: %w[ruby coding]
        }
      )
    end

    it "matches content" do
      expect(memory.matches?("ruby")).to be true
      expect(memory.matches?("RUBY")).to be true
      expect(memory.matches?("python")).to be false
    end

    it "matches metadata values" do
      expect(memory.matches?("programming")).to be true
    end

    it "matches tags" do
      expect(memory.matches?("coding")).to be true
    end
  end
end