# RAAF Memory

[![Gem Version](https://badge.fury.io/rb/raaf-memory.svg)](https://badge.fury.io/rb/raaf-memory)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

The **RAAF Memory** gem provides comprehensive memory management and vector search capabilities for the Ruby AI Agents Factory (RAAF) ecosystem. It offers persistent conversation history, semantic search, knowledge base integration, and advanced memory patterns for AI agents.

## Overview

RAAF (Ruby AI Agents Factory) Memory extends the core memory capabilities from `raaf-core` to provide memory management and vector search for Ruby AI Agents Factory (RAAF). This gem provides persistent and ephemeral memory storage for AI agents, including vector stores, semantic search, and memory management across conversations and sessions.

## Features

- **Persistent Memory** - Store and retrieve agent memories across sessions
- **Vector Storage** - High-performance vector databases for semantic search
- **Semantic Search** - Advanced semantic search with multiple indexing algorithms
- **Multiple Adapters** - Support for in-memory, file-based, and database storage
- **Memory Management** - Automatic cleanup and memory optimization
- **RAG Support** - Full support for Retrieval-Augmented Generation workflows
- **PostgreSQL Integration** - Production-ready PostgreSQL + pgvector support

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'raaf-memory'
```

And then execute:

```bash
bundle install
```

## Quick Start

### Basic Memory Usage

```ruby
require 'raaf-memory'

# Create memory store
store = RubyAIAgentsFactory::Memory.create_store(:file, base_dir: "./memory")

# Use with agent
agent = RubyAIAgentsFactory::Agent.new(
  name: "Assistant",
  memory_store: store
)

# Agent will remember across sessions
runner = RubyAIAgentsFactory::Runner.new(agent: agent)
result = runner.run("Remember my name is Alice")
```

### Vector Store for Semantic Search

```ruby
require 'raaf-memory'

# Create vector store
vector_store = RubyAIAgentsFactory::VectorStore.new(
  name: "knowledge_base",
  dimensions: 1536
)

# Add documents
documents = [
  "Ruby is a dynamic programming language",
  "Python is great for data science", 
  "JavaScript runs in web browsers"
]

vector_store.add_documents(documents)

# Search for similar content
results = vector_store.search("web development languages", k: 2)
results.each { |result| puts result[:content] }
```

### Advanced Semantic Search

```ruby
require 'raaf-memory'

# Create semantic search database
db = RubyAIAgentsFactory::SemanticSearch::VectorDatabase.new(
  dimension: 1536,
  index_type: :hnsw
)

# Index documents with metadata
indexer = RubyAIAgentsFactory::SemanticSearch::DocumentIndexer.new(
  vector_db: db
)

documents = [
  { 
    content: "Article about Ruby programming", 
    title: "Ruby Guide", 
    metadata: { category: "programming", difficulty: "beginner" }
  },
  { 
    content: "Advanced Python techniques", 
    title: "Python Advanced", 
    metadata: { category: "programming", difficulty: "advanced" }
  }
]

indexer.index_documents(documents)

# Search with filtering
results = indexer.search(
  "programming languages",
  k: 5,
  filter: { category: "programming" }
)
```

## Memory Stores

### In-Memory Store (Default)

```ruby
# Ephemeral storage - data lost when process ends
store = RubyAIAgentsFactory::Memory.create_store(:in_memory)
```

### File Store

```ruby
# Persistent file-based storage
store = RubyAIAgentsFactory::Memory.create_store(
  :file, 
  base_dir: "./agent_memory"
)
```

### Custom Store

```ruby
# Implement your own store
class RedisStore < RubyAIAgentsFactory::Memory::BaseStore
  def initialize(redis_client)
    @redis = redis_client
  end
  
  def get(key)
    @redis.get(key)
  end
  
  def set(key, value)
    @redis.set(key, value)
  end
end

store = RubyAIAgentsFactory::Memory.create_store(
  :custom,
  store_class: RedisStore,
  redis_client: Redis.new
)
```

## Vector Stores

### In-Memory Vector Store

```ruby
# Good for development and small datasets
vector_store = RubyAIAgentsFactory::VectorStore.new(
  name: "dev_knowledge",
  dimensions: 1536
)
```

### PostgreSQL Vector Store

```ruby
require 'pg'

# Production-ready PostgreSQL + pgvector
adapter = RubyAIAgentsFactory::Adapters::PgVectorAdapter.new(
  connection_string: "postgres://user:pass@localhost/db"
)

vector_store = RubyAIAgentsFactory::VectorStore.new(
  name: "production_knowledge",
  adapter: adapter,
  dimensions: 1536
)
```

### Adding Documents with Metadata

```ruby
documents = [
  {
    content: "MacBook Pro 16-inch laptop",
    title: "MacBook Pro",
    category: "electronics",
    price: 2499.00,
    tags: ["apple", "laptop", "professional"]
  },
  {
    content: "Ergonomic office chair",
    title: "Office Chair",
    category: "furniture",
    price: 299.99,
    tags: ["office", "ergonomic", "comfort"]
  }
]

vector_store.add_documents(documents)

# Search with filters
results = vector_store.search(
  "portable computer",
  k: 5,
  filter: { category: "electronics" }
)
```

## Semantic Search

### Vector Database

```ruby
# Create high-performance vector database
db = RubyAIAgentsFactory::SemanticSearch::VectorDatabase.new(
  dimension: 1536,
  index_type: :hnsw  # or :flat for smaller datasets
)

# Add vectors with metadata
embeddings = [
  [0.1, 0.2, 0.3, ...],  # 1536-dimensional vectors
  [0.4, 0.5, 0.6, ...],
  [0.7, 0.8, 0.9, ...]
]

metadata = [
  { title: "Document 1", category: "tech" },
  { title: "Document 2", category: "science" },
  { title: "Document 3", category: "tech" }
]

db.add(embeddings, metadata)

# Search with filtering
results = db.search(
  query_embedding,
  k: 5,
  filter: { category: "tech" }
)
```

### Document Indexer

```ruby
# Index documents with chunking
indexer = RubyAIAgentsFactory::SemanticSearch::DocumentIndexer.new

documents = [
  { content: "Long article content...", title: "Article 1" },
  { content: "Another long document...", title: "Article 2" }
]

indexer.index_documents(documents, chunk_size: 500, overlap: 50)

# Search documents
results = indexer.search("machine learning", k: 10)
```

### Hybrid Search

```ruby
# Combine semantic and keyword search
semantic_indexer = RubyAIAgentsFactory::SemanticSearch::DocumentIndexer.new
keyword_indexer = RubyAIAgentsFactory::SemanticSearch::KeywordIndexer.new

hybrid = RubyAIAgentsFactory::SemanticSearch::HybridSearch.new(
  semantic_indexer,
  keyword_indexer
)

# Index documents in both systems
hybrid.index_documents(documents)

# Search with combined scoring
results = hybrid.search(
  "machine learning algorithms",
  k: 10
)
```

## Configuration

### Global Configuration

```ruby
RubyAIAgentsFactory::Memory.configure do |config|
  config.default_store_type = :file
  config.default_base_dir = "/var/lib/agent_memory"
  config.default_dimensions = 1536
  config.enable_cache = true
  config.cache_ttl = 3600
end
```

### Environment Variables

```bash
# OpenAI API key for embeddings
export OPENAI_API_KEY="your-api-key-here"

# PostgreSQL connection
export DATABASE_URL="postgres://user:pass@localhost/db"

# Memory configuration
export RAAF_MEMORY_DEFAULT_STORE=file
export RAAF_MEMORY_BASE_DIR="/var/lib/agent_memory"
```

## Agent Integration

### Basic Agent with Memory

```ruby
require 'raaf-core'
require 'raaf-memory'

# Create memory store
memory_store = RubyAIAgentsFactory::Memory.create_store(
  :file,
  base_dir: "./agent_memory"
)

# Create agent with memory
agent = RubyAIAgentsFactory::Agent.new(
  name: "Assistant",
  instructions: "You are a helpful assistant with memory",
  memory_store: memory_store
)

# Agent will remember across conversations
runner = RubyAIAgentsFactory::Runner.new(agent: agent)
result = runner.run("My favorite color is blue")
```

### Agent with Semantic Search Tool

```ruby
require 'raaf-core'
require 'raaf-memory'

# Create knowledge base
knowledge_base = RubyAIAgentsFactory::SemanticSearch::DocumentIndexer.new

# Add documents
documents = [
  { content: "Ruby documentation...", title: "Ruby Guide" },
  { content: "Python tutorial...", title: "Python Basics" }
]
knowledge_base.index_documents(documents)

# Create search tool
search_tool = RubyAIAgentsFactory::SemanticSearch::SemanticSearchTool.new(
  knowledge_base,
  name: "search_knowledge",
  description: "Search the knowledge base"
)

# Add to agent
agent = RubyAIAgentsFactory::Agent.new(
  name: "KnowledgeAssistant",
  instructions: "Answer questions using the knowledge base"
)
agent.add_tool(search_tool)

# Agent can now search the knowledge base
runner = RubyAIAgentsFactory::Runner.new(agent: agent)
result = runner.run("What is Ruby?")
```

## Performance Tips

### Vector Search Optimization

```ruby
# Use HNSW for large datasets (faster search)
db = RubyAIAgentsFactory::SemanticSearch::VectorDatabase.new(
  dimension: 1536,
  index_type: :hnsw
)

# Use Flat for small datasets (exact search)
db = RubyAIAgentsFactory::SemanticSearch::VectorDatabase.new(
  dimension: 1536,
  index_type: :flat
)
```

### Embedding Caching

```ruby
# Enable caching for embedding generation
generator = RubyAIAgentsFactory::SemanticSearch::EmbeddingGenerator.new
embeddings = generator.generate(texts, cache: true)

# Clear cache when needed
generator.clear_cache
```

### PostgreSQL Optimization

```ruby
# Use connection pooling
adapter = RubyAIAgentsFactory::Adapters::PgVectorAdapter.new(
  connection_string: "postgres://user:pass@localhost/db",
  pool_size: 10
)

# Use appropriate vector index
# - IVFFlat for balanced performance
# - HNSW for fast search (PostgreSQL 16+)
```

## Development

After checking out the repo, run:

```bash
bundle install
bundle exec rspec
```

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Add tests for your changes
5. Ensure all tests pass (`bundle exec rspec`)
6. Commit your changes (`git commit -am 'Add amazing feature'`)
7. Push to the branch (`git push origin feature/amazing-feature`)
8. Open a Pull Request

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).