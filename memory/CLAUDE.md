# RAAF Memory - Claude Code Guide

This gem provides memory management and context persistence for RAAF agents with vector storage capabilities.

## Quick Start

```ruby
require 'raaf-memory'

# Create memory store
memory = RAAF::Memory::FileStore.new("agent_memory.json")

# Add to agent
agent = RAAF::Agent.new(
  name: "MemoryAgent",
  instructions: "Remember our conversation",
  model: "gpt-4o"
)

# Create memory manager
memory_manager = RAAF::Memory::MemoryManager.new(
  store: memory,
  max_tokens: 4000
)

runner = RAAF::Runner.new(agent: agent, memory_manager: memory_manager)
```

## Core Components

- **MemoryManager** - Orchestrates memory operations
- **FileStore** - File-based memory persistence
- **InMemoryStore** - RAM-based temporary storage
- **VectorStore** - Semantic search with embeddings
- **SemanticSearch** - Context-aware memory retrieval

## Memory Stores

### File Store
```ruby
# Persistent file-based storage
memory = RAAF::Memory::FileStore.new("conversations/agent_#{agent_id}.json")

# With custom format
memory = RAAF::Memory::FileStore.new("memory.json") do |config|
  config.auto_save = true
  config.compression = true
  config.encryption_key = ENV['MEMORY_KEY']
end
```

### In-Memory Store
```ruby
# Temporary session storage
memory = RAAF::Memory::InMemoryStore.new

# With size limits
memory = RAAF::Memory::InMemoryStore.new(max_entries: 1000)
```

### Vector Store
```ruby
# Semantic memory with embeddings
vector_store = RAAF::Memory::VectorStore.new do |config|
  config.embedding_model = "text-embedding-3-small"
  config.dimension = 1536
  config.similarity_threshold = 0.7
end

# Store with semantic context
vector_store.store(
  content: "User prefers Ruby over Python",
  metadata: { category: "preference", user_id: 123 },
  embedding: generate_embedding("User prefers Ruby over Python")
)

# Semantic search
similar_memories = vector_store.search("programming language preference")
```

## Memory Manager

```ruby
memory_manager = RAAF::Memory::MemoryManager.new(
  store: memory_store,
  max_tokens: 4000,
  summarization_threshold: 0.8
) do |config|
  # Automatic summarization when near token limit
  config.auto_summarize = true
  
  # Keep important memories
  config.preserve_keywords = ["important", "remember", "don't forget"]
  
  # Memory categories
  config.categories = {
    facts: { weight: 1.0, retention: :permanent },
    preferences: { weight: 0.8, retention: :long_term },
    context: { weight: 0.6, retention: :session }
  }
end
```

## Usage Patterns

### Conversational Memory
```ruby
# Agent remembers conversation context
runner = RAAF::Runner.new(agent: agent, memory_manager: memory_manager)

# First conversation
result1 = runner.run("My name is John and I love Ruby programming")

# Later conversation - agent remembers
result2 = runner.run("What programming language do I prefer?")
# Agent: "You prefer Ruby programming, John!"
```

### Semantic Context
```ruby
# Store contextual information
memory_manager.store_context(
  "User is working on a Rails project",
  category: :project_context,
  importance: :high
)

# Retrieve relevant context
context = memory_manager.get_relevant_context("How do I add authentication?")
# Returns Rails-specific authentication guidance
```

### Multi-Session Memory
```ruby
# Persistent across sessions
agent_memory = RAAF::Memory::FileStore.new("user_#{user_id}_memory.json")
memory_manager = RAAF::Memory::MemoryManager.new(store: agent_memory)

# Session 1
runner.run("I'm building an e-commerce site")

# Session 2 (different day)
runner.run("How should I handle payments?")
# Agent remembers the e-commerce context
```

## Advanced Features

### Memory Summarization
```ruby
# Automatic summarization when approaching token limits
memory_manager.configure do |config|
  config.summarization_strategy = :adaptive
  config.summary_compression_ratio = 0.3
  config.preserve_recent_messages = 10
end
```

### Memory Search
```ruby
# Search stored memories
search_results = memory_manager.search(
  query: "user preferences",
  category: :preferences,
  limit: 5,
  similarity_threshold: 0.8
)
```

### Memory Analytics
```ruby
# Analyze memory usage
stats = memory_manager.analyze do
  show_token_usage true
  show_category_distribution true
  show_retrieval_patterns true
end

puts "Memory efficiency: #{stats[:efficiency_score]}"
puts "Most accessed memories: #{stats[:top_memories]}"
```

## Environment Variables

```bash
export OPENAI_API_KEY="your-key"
export RAAF_MEMORY_ENCRYPTION_KEY="your-encryption-key"
export RAAF_MEMORY_STORAGE_PATH="/path/to/memory/storage"
export RAAF_MEMORY_MAX_TOKENS="4000"
```