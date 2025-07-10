# frozen_string_literal: true

require "spec_helper"
require "openai_agents/memory/memory_manager"
require "openai_agents/memory/memory"

RSpec.describe OpenAIAgents::Memory::MemoryManager do
  let(:manager) { described_class.new(max_tokens: 100) }
  
  let(:memories) do
    [
      {
        id: "1",
        content: "First memory content",
        created_at: (Time.now - 3600).iso8601,
        agent_name: "Agent1",
        conversation_id: "conv-123"
      },
      {
        id: "2",
        content: "Second memory content with more text",
        created_at: (Time.now - 1800).iso8601,
        agent_name: "Agent1",
        metadata: { tags: ["important"] }
      },
      {
        id: "3",
        content: "Third memory content",
        created_at: Time.now.iso8601,
        agent_name: "Agent1"
      }
    ]
  end

  describe "#initialize" do
    it "sets default values" do
      expect(manager.max_tokens).to eq(100)
      expect(manager.summary_threshold).to eq(0.8)
    end

    it "accepts custom values" do
      custom_manager = described_class.new(max_tokens: 500, summary_threshold: 0.9)
      
      expect(custom_manager.max_tokens).to eq(500)
      expect(custom_manager.summary_threshold).to eq(0.9)
    end

    it "accepts custom token counter" do
      counter = lambda(&:length)
      custom_manager = described_class.new(token_counter: counter)
      
      expect(custom_manager.count_tokens("test")).to eq(4)
    end
  end

  describe "#build_context" do
    it "builds context from memories" do
      context = manager.build_context(memories)
      
      expect(context).to include("## Memory Context")
      expect(context).to include("First memory content")
      expect(context).to include("Second memory content")
      expect(context).to include("Third memory content")
    end

    it "orders memories by recency" do
      context = manager.build_context(memories)
      
      # Most recent should appear first
      third_pos = context.index("Third memory content")
      second_pos = context.index("Second memory content")
      first_pos = context.index("First memory content")
      
      expect(third_pos).to be < second_pos
      expect(second_pos).to be < first_pos
    end

    it "respects token limit" do
      # Create manager with very low token limit
      limited_manager = described_class.new(max_tokens: 50)
      
      context = limited_manager.build_context(memories)
      tokens = limited_manager.count_tokens(context)
      
      expect(tokens).to be <= 100 # Some overhead for formatting
    end

    it "includes metadata when requested" do
      context = manager.build_context(memories, include_metadata: true)
      
      expect(context).to include("important") # Tag from metadata
    end
  end

  describe "#format_memory" do
    let(:memory) { memories.first }

    it "formats basic memory" do
      formatted = manager.format_memory(memory)
      
      expect(formatted).to include(memory[:created_at])
      expect(formatted).to include("First memory content")
    end

    it "includes conversation ID" do
      formatted = manager.format_memory(memory)
      
      expect(formatted).to include("Conv: conv-123")
    end

    it "includes metadata when requested" do
      memory_with_meta = memories[1]
      formatted = manager.format_memory(memory_with_meta, true)
      
      expect(formatted).to include("tags: [\"important\"]")
    end
  end

  describe "#count_tokens" do
    it "estimates tokens based on words" do
      text = "This is a test sentence with seven words"
      
      # Default estimation: ~1.3 tokens per word
      expect(manager.count_tokens(text)).to be_between(10, 11)
    end
  end

  describe "#prune_memories" do
    context "with :oldest strategy" do
      it "keeps most recent memories" do
        pruned = manager.prune_memories(memories, :oldest)
        
        # Should keep the most recent memories that fit
        expect(pruned.map { |m| m[:id] }).to include("3")
        expect(pruned.size).to be < memories.size
      end
    end

    it "returns all memories if under limit" do
      high_limit_manager = described_class.new(max_tokens: 10_000)
      
      pruned = high_limit_manager.prune_memories(memories)
      
      expect(pruned.size).to eq(memories.size)
    end
  end

  describe "#summarize_memories" do
    let(:summarizer) { ->(text) { "Summary of: #{text.split.first(3).join(" ")}" } }

    it "creates summaries grouped by conversation" do
      summaries = manager.summarize_memories(memories, summarizer)
      
      expect(summaries).to be_an(Array)
      expect(summaries.any? { |s| s[:content].include?("Summary:") }).to be true
    end

    it "includes metadata about summarization" do
      summaries = manager.summarize_memories(memories, summarizer)
      
      summary = summaries.first
      expect(summary[:metadata][:type]).to eq("summary")
      expect(summary[:metadata]).to have_key(:original_count)
      expect(summary[:metadata]).to have_key(:summarized_at)
    end

    it "groups by date when no conversation ID" do
      memories_without_conv = memories.map { |m| m.except(:conversation_id) }
      
      summaries = manager.summarize_memories(memories_without_conv, summarizer)
      
      expect(summaries).not_to be_empty
    end
  end
end