**DO NOT READ THIS FILE ON GITHUB, GUIDES ARE PUBLISHED ON <https://guides.raaf.dev>.**

RAAF Memory Guide
=================

This guide covers advanced memory management and context persistence in Ruby AI Agents Factory (RAAF). Memory management is crucial for maintaining conversation context, handling long-running interactions, and optimizing performance.

After reading this guide, you will know:

* How to configure different memory storage backends
* Memory pruning strategies and optimization techniques
* Context preservation across agent handoffs
* Semantic search and vector storage capabilities
* Performance tuning for large-scale memory systems

--------------------------------------------------------------------------------

Introduction
------------

### Memory as Context Intelligence

RAAF's memory system represents a sophisticated approach to context management that goes beyond simple conversation storage. It implements intelligent context curation, relevance-based retrieval, and adaptive context preservation strategies.

### Core Memory Capabilities

**Storage Abstraction**: Multiple storage backends enable different persistence models, from ephemeral in-memory storage to persistent database and vector storage systems. This abstraction allows memory strategies to be selected based on use case requirements.

**Context Curation**: Intelligent pruning mechanisms automatically manage context based on token limits, relevance scoring, and temporal factors. This curation ensures that the most important information is retained while respecting model constraints.

**Semantic Retrieval**: Vector-based search capabilities enable context retrieval based on semantic similarity rather than keyword matching. This approach finds relevant information even when expressed differently.

**Persistence Management**: Cross-session persistence enables conversation continuity across application restarts and extended time periods. This capability supports long-term interactions and user relationship building.

**Multi-Agent Coordination**: Shared context mechanisms enable multiple agents to coordinate around common conversation history and shared knowledge. This coordination supports complex multi-agent workflows.

### The Context Window Challenge

Memory management addresses a fundamental architectural constraint in AI systems: the fixed context window limits of language models. This constraint creates a tension between conversation continuity and model operational requirements.

### Context Loss Patterns

**Abrupt Context Loss**: When conversations exceed token limits, systems often truncate context abruptly, losing critical information mid-conversation. This pattern creates jarring user experiences and reduces system effectiveness.

**Reference Degradation**: Users expect to reference earlier conversation points, but token limits prevent maintaining complete conversation history. This degradation breaks the conversational flow and reduces user satisfaction.

**Repetitive Interactions**: Without context preservation, users must repeatedly provide the same information, creating frustration and inefficiency. This pattern reduces system perceived intelligence and utility.

**Inconsistent Responses**: Missing context leads to responses that contradict earlier statements or ignore established user preferences. This inconsistency undermines user trust and system reliability.

### Strategic Memory Management

Effective memory management transforms these challenges into manageable system behavior through intelligent context curation, relevance-based retention, and graceful degradation strategies.

### Memory Model Comparison

AI memory systems occupy a unique position between human and computer memory models, requiring characteristics from both:

**Human Memory Characteristics**:
- Selective attention and relevance filtering
- Associative recall and context connection
- Graceful degradation and forgetting
- Meaning preservation over detail retention

**Computer Memory Characteristics**:
- Precise storage and retrieval
- Structured organization and indexing
- Deterministic access patterns
- Exact reproduction of stored information

**AI Memory Requirements**:
- Intelligent context selection within token constraints
- Semantic understanding of information relevance
- Adaptive retention strategies based on usage patterns
- Seamless integration with natural language processing

### The Selective Attention Problem

AI systems must implement selective attention mechanisms that determine which information to retain, summarize, or discard. This decision-making process requires understanding context relevance, temporal importance, and user preferences while operating within strict token limitations.

### What Makes Memory Hard?

1. **Context Window Limits**: AI models have fixed context windows that create hard cutoffs
2. **Message Relevance**: Not all conversation messages have equal importance for future context
3. **Information Loss**: Summarization techniques can lose important details
4. **Context Retrieval**: Finding relevant historical context in large conversation datasets

### How RAAF Solves Memory

RAAF implements a sophisticated memory architecture that addresses these challenges through intelligent context curation rather than simple storage:

**Intelligent Pruning**: Context retention strategies that preserve high-value information while removing redundant or less relevant content. This approach maintains conversation continuity while respecting token constraints.

**Semantic Context Retrieval**: Vector-based search mechanisms that identify relevant context based on semantic similarity rather than keyword matching. This capability enables finding related information across long conversation histories.

**Gradual Context Degradation**: Smooth transitions between different levels of context detail, ensuring that important information is never lost abruptly. This approach maintains user experience quality during context transitions.

**Tiered Storage Strategy**: Multiple storage tiers optimize for different access patterns and persistence requirements. Hot storage for immediate context, warm storage for recent history, and cold storage for long-term persistence.

### Memory Architecture

```ruby
# Basic memory setup
memory_manager = RAAF::Memory::MemoryManager.new(
  store: RAAF::Memory::InMemoryStore.new,
  max_tokens: 4000,
  pruning_strategy: :sliding_window
)

runner = RAAF::Runner.new(
  agent: agent,
  memory_manager: memory_manager
)
```

Memory Storage Backends
-----------------------

### Storage Backend Selection

Storage backend choice depends on your persistence requirements, performance needs, and system architecture. Each backend offers different trade-offs:

**Key considerations:**

- Data persistence requirements
- Performance and latency needs
- Scalability and concurrent access
- Integration with existing infrastructure

Here's what each backend is designed for:

### In-Memory Store: Fast but Forgetful

**The Reality**: Your server will restart. Deployments happen. Memory gets cleared.

**Perfect for**:

- Development and testing
- Stateless chatbots
- Demo environments
- High-performance caching layer

**Not suitable for**:

- Production customer support systems
- Multi-day workflows requiring persistence
- Systems requiring audit trails or compliance

```ruby
# Simple in-memory storage
memory_store = RAAF::Memory::InMemoryStore.new

# With size limits
memory_store = RAAF::Memory::InMemoryStore.new(
  max_size: 100.megabytes,
  max_entries: 10000
)

memory_manager = RAAF::Memory::MemoryManager.new(
  store: memory_store,
  max_tokens: 4000
)
```

### File Store

Best for: Persistent sessions, development with persistence

```ruby
# Basic file storage
file_store = RAAF::Memory::FileStore.new(
  directory: './conversations',
  session_id: 'user_123'
)

# With compression and encryption
file_store = RAAF::Memory::FileStore.new(
  directory: './conversations',
  session_id: 'user_123',
  compression: :gzip,
  encryption: {
    key: ENV['MEMORY_ENCRYPTION_KEY'],
    algorithm: 'AES-256-GCM'
  }
)

memory_manager = RAAF::Memory::MemoryManager.new(
  store: file_store,
  max_tokens: 8000,
  pruning_strategy: :summarization
)
```

### Database Store: When You Need Real Persistence

**Production benefits**: Database storage provides data persistence across restarts, audit trails for compliance, and reliable conversation history management.

**Perfect for**:

- Production systems (you need audit trails)
- Compliance requirements (GDPR, HIPAA)
- Analytics and reporting
- Multi-agent workflows

**Watch out for**:

- Slower than in-memory (obviously)
- Database migrations when schema changes
- Connection pool exhaustion at scale

```ruby
# ActiveRecord integration
class ConversationMemory < ActiveRecord::Base
  serialize :messages, JSON
  serialize :metadata, JSON
  
  validates :session_id, presence: true
  scope :for_user, ->(user_id) { where(user_id: user_id) }
end

db_store = RAAF::Memory::DatabaseStore.new(
  model: ConversationMemory,
  session_id: 'user_123',
  user_id: current_user.id
)

# With custom schema
db_store = RAAF::Memory::DatabaseStore.new(
  connection: ActiveRecord::Base.connection,
  table_name: 'agent_conversations',
  session_column: 'conversation_id',
  content_column: 'message_data',
  metadata_column: 'context_data'
)
```

This ActiveRecord model provides the foundation for database-backed conversation memory. The `serialize` directives handle JSON encoding/decoding for complex data structures, while the validation ensures data integrity. The scope provides convenient querying for user-specific conversations.

The database store can work with existing ActiveRecord models or custom database schemas. The first configuration uses a standard model setup, while the second demonstrates how to integrate with custom table structures by specifying column mappings. This flexibility allows RAAF to work with your existing database schema.

### Vector Store: Semantic Search Capabilities

Vector stores enable semantic search across conversation history, finding contextually relevant information regardless of exact keyword matches.

**Key capabilities**:

- Semantic similarity search beyond exact text matching
- Efficient querying of large conversation datasets
- Cross-conversation context retrieval
- Support for recommendation and personalization features

**Implementation considerations**:

- Embedding generation costs (approximately $0.0001 per 1K tokens)
- Vector database infrastructure requirements
- Embedding generation latency
- Storage and indexing overhead

```ruby
# Basic vector store with OpenAI embeddings
vector_store = RAAF::Memory::VectorStore.new(
  embedding_model: 'text-embedding-3-small',
  dimension: 1536,
  similarity_threshold: 0.7
)

# With custom vector database
vector_store = RAAF::Memory::VectorStore.new(
  backend: :pinecone,
  api_key: ENV['PINECONE_API_KEY'],
  index_name: 'raaf-conversations',
  embedding_model: 'text-embedding-3-small'
)

# With local vector database
vector_store = RAAF::Memory::VectorStore.new(
  backend: :chroma,
  persist_directory: './vector_store',
  collection_name: 'conversations'
)

memory_manager = RAAF::Memory::MemoryManager.new(
  store: vector_store,
  max_tokens: 16000,
  pruning_strategy: :semantic_similarity
)
```

Vector stores enable semantic search capabilities that go beyond simple chronological memory management. Instead of just keeping the most recent messages, the vector store can retrieve contextually relevant information from anywhere in the conversation history. This is particularly powerful for long conversations where important context might be buried in earlier exchanges.

The configuration options support different vector database backends. Pinecone provides hosted vector search with excellent performance, while Chroma offers local vector storage that keeps your data on-premises. The embedding model choice affects both cost and search quality, with text-embedding-3-small providing a good balance of performance and cost.

Memory Pruning Strategies
-------------------------

### Memory Pruning Strategies

Effective memory management requires selective retention of conversation context. Not all messages have equal importance for future interactions.

Example of context priority challenges:
```
User: Hi
AI: Hello! How can I help?
User: Weather?
AI: It's sunny today.
[... 50 more small talk exchanges ...]
User: About that $50,000 invoice we discussed...
AI: I don't see any previous discussion about an invoice.
```

This demonstrates why simple chronological retention isn't sufficient. Important business context can be displaced by less relevant exchanges.

### Sliding Window Strategy

The sliding window approach maintains the most recent messages within the token limit, providing a simple and predictable pruning mechanism.

**Optimal use cases**: 

- Customer service (recent context typically most relevant)
- Technical support (current problem focus)
- Short-term conversational interactions

**Limitations**:

- Legal discussions (early context may be critical)
- Complex troubleshooting (initial problem statement importance)
- Multi-topic conversations requiring historical context

Keeps the most recent messages within token limit:

```ruby
memory_manager = RAAF::Memory::MemoryManager.new(
  store: store,
  max_tokens: 4000,
  pruning_strategy: :sliding_window,
  window_config: {
    preserve_system_messages: true,
    preserve_last_user_message: true,
    minimum_messages: 2
  }
)
```

The sliding window strategy maintains conversation recency while preserving important structural elements. System messages contain the agent's instructions and should never be removed, while the last user message provides essential context for the current response. The minimum messages setting ensures that conversations don't become too truncated to maintain coherence.

This approach works well for most conversational applications where recent context is more important than distant history. The configuration options allow you to fine-tune the behavior based on your specific use case and conversation patterns.

### Summarization

Summarizes older messages to preserve context while reducing tokens:

```ruby
memory_manager = RAAF::Memory::MemoryManager.new(
  store: store,
  max_tokens: 6000,
  pruning_strategy: :summarization,
  summary_config: {
    summary_model: 'gpt-4o-mini',  # Use cheaper model for summaries
    summary_trigger: 0.8,          # Summarize when 80% of tokens used
    summary_ratio: 0.3,            # Reduce to 30% of original size
    preserve_recent_count: 5       # Keep last 5 messages unsummarized
  }
)
```

### Semantic Similarity

Keeps most relevant messages based on current context:

```ruby
memory_manager = RAAF::Memory::MemoryManager.new(
  store: RAAF::Memory::VectorStore.new,
  max_tokens: 8000,
  pruning_strategy: :semantic_similarity,
  similarity_config: {
    similarity_threshold: 0.75,
    max_relevant_messages: 20,
    context_window: 3,              # Messages around relevant ones
    recency_weight: 0.3             # Weight recent messages higher
  }
)
```

### Importance-Based

Keeps messages based on importance scoring:

```ruby
memory_manager = RAAF::Memory::MemoryManager.new(
  store: store,
  max_tokens: 6000,
  pruning_strategy: :importance_based,
  importance_config: {
    importance_model: 'gpt-4o-mini',
    scoring_prompt: """
      Rate the importance of this message for future conversation context.
      Consider: relevance, emotional significance, actionable information.
      Score from 1-10.
    """,
    minimum_importance: 6,
    preserve_high_importance: true
  }
)
```

### Hybrid Strategies

Combine multiple pruning approaches:

```ruby
memory_manager = RAAF::Memory::MemoryManager.new(
  store: RAAF::Memory::VectorStore.new,
  max_tokens: 10000,
  pruning_strategy: :hybrid,
  hybrid_config: {
    strategies: [
      { type: :sliding_window, weight: 0.3, preserve_count: 3 },
      { type: :semantic_similarity, weight: 0.4, threshold: 0.8 },
      { type: :importance_based, weight: 0.3, min_score: 7 }
    ],
    fallback_strategy: :sliding_window
  }
)
```

Advanced Memory Features
------------------------

### Context Variables

Persistent context that survives pruning:

```ruby
memory_manager = RAAF::Memory::MemoryManager.new(
  store: store,
  max_tokens: 4000,
  context_variables: {
    user_preferences: { theme: 'dark', language: 'en' },
    conversation_goal: 'technical_support',
    user_expertise_level: 'intermediate'
  }
)

# Update context variables during conversation
runner.memory_manager.update_context(
  user_expertise_level: 'advanced',
  last_successful_solution: 'database_optimization'
)

# Access in tools
def provide_help(topic:)
  user_level = runner.memory_manager.context[:user_expertise_level]
  
  case user_level
  when 'beginner'
    provide_basic_help(topic)
  when 'intermediate'
    provide_detailed_help(topic)
  when 'advanced'
    provide_expert_help(topic)
  end
end
```

### Memory Compression

Reduce storage space while preserving essential information:

```ruby
compressed_store = RAAF::Memory::CompressedStore.new(
  backend_store: RAAF::Memory::FileStore.new(directory: './conversations'),
  compression_algorithm: :lz4,      # :gzip, :lz4, :zstd
  compression_level: 6,
  compress_threshold: 1000          # Compress when >1000 characters
)

memory_manager = RAAF::Memory::MemoryManager.new(
  store: compressed_store,
  max_tokens: 8000
)
```

### Memory Analytics

Track and analyze memory usage patterns:

```ruby
analytics_store = RAAF::Memory::AnalyticsStore.new(
  backend_store: store,
  analytics_config: {
    track_access_patterns: true,
    track_pruning_events: true,
    track_token_usage: true,
    generate_insights: true
  }
)

# Get memory analytics
analytics = analytics_store.get_analytics
puts "Average conversation length: #{analytics[:avg_conversation_length]}"
puts "Most accessed topics: #{analytics[:top_topics]}"
puts "Pruning efficiency: #{analytics[:pruning_efficiency]}"
```

Multi-Agent Memory Sharing
--------------------------

### Multi-Agent Memory Coordination

Multi-agent workflows require careful memory coordination to maintain context across agent handoffs.

**Context sharing challenges**:

- Each agent may need different subsets of conversation history
- Agent-specific context requirements vary by role
- Information transfer between agents must preserve relevance

**Agent-specific context needs**:

- Research agents: search history, source credibility, methodology
- Writer agents: key facts, narrative structure, style requirements
- Editor agents: style guides, fact-check references, revision history

**Solution approach**: Selective memory sharing where each agent receives contextually relevant information while maintaining workflow continuity.

### Shared Context: Making Agents Work as a Team

Share context across agents in workflows:

```ruby
# Shared memory for multi-agent workflow
shared_memory = RAAF::Memory::SharedMemoryManager.new(
  store: RAAF::Memory::VectorStore.new,
  session_id: 'workflow_123',
  sharing_strategy: :selective
)

# Research agent
research_agent = RAAF::Agent.new(
  name: "Researcher",
  instructions: "Research topics thoroughly"
)

# Writer agent  
writer_agent = RAAF::Agent.new(
  name: "Writer",
  instructions: "Write based on research findings"
)

# Both agents share the same memory
research_runner = RAAF::Runner.new(
  agent: research_agent,
  memory_manager: shared_memory
)

writer_runner = RAAF::Runner.new(
  agent: writer_agent, 
  memory_manager: shared_memory
)

# Research phase
research_result = research_runner.run("Research sustainable energy")

# Writing phase - has access to research context
writing_result = writer_runner.run("Write an article based on the research")
```

### Context Handoffs

Transfer specific context between agents:

```ruby
class ContextHandoffManager
  def initialize
    @agent_memories = {}
  end
  
  def create_agent_memory(agent_name, base_memory)
    @agent_memories[agent_name] = RAAF::Memory::ScopedMemoryManager.new(
      base_memory: base_memory,
      scope: agent_name,
      inheritance_rules: {
        inherit_context_variables: true,
        inherit_important_messages: true,
        inherit_recent_messages: 3
      }
    )
  end
  
  def handoff_context(from_agent, to_agent, context_filter = nil)
    source_memory = @agent_memories[from_agent]
    target_memory = @agent_memories[to_agent]
    
    # Extract relevant context
    handoff_context = source_memory.extract_context(
      filter: context_filter,
      importance_threshold: 7,
      recent_count: 5
    )
    
    # Transfer to target agent
    target_memory.receive_handoff_context(
      from_agent: from_agent,
      context: handoff_context,
      timestamp: Time.now
    )
  end
end
```

Performance Optimization
------------------------

### Memory Performance Optimization

Memory system performance directly impacts user experience. Slow memory operations create noticeable delays in conversation initiation and response generation.

**Common performance bottlenecks**:

1. Database connection overhead for each request
2. Inefficient data loading (retrieving full history for partial needs)
3. Synchronous operations blocking response generation
4. Lack of caching for frequently accessed context

**Optimization strategies**:

### Connection Pooling

Database connection establishment introduces significant latency (100-300ms per connection). Connection pooling amortizes this cost across multiple operations.

**Implementation**: Maintain a pool of persistent database connections that can be reused across memory operations.

For database-backed memory stores:

```ruby
# Connection pooled database store
pooled_store = RAAF::Memory::PooledDatabaseStore.new(
  connection_pool: ConnectionPool.new(size: 10, timeout: 5) do
    ActiveRecord::Base.connection
  end,
  table_name: 'conversations'
)
```

### Async Operations

Non-blocking memory operations:

```ruby
async_memory = RAAF::Memory::AsyncMemoryManager.new(
  store: store,
  async_operations: [:save, :prune, :search],
  thread_pool_size: 3,
  queue_size: 100
)

# Non-blocking save
async_memory.save_async(session_id, messages) do |result|
  if result.success?
    logger.info "Memory saved successfully"
  else
    logger.error "Memory save failed: #{result.error}"
  end
end
```

### Performance Optimization

For memory caching and optimization strategies, see the **[Performance Guide](performance_guide.html)**.

### Batch Operations

Optimize bulk memory operations:

```ruby
batch_memory = RAAF::Memory::BatchMemoryManager.new(
  store: store,
  batch_size: 100,
  flush_interval: 30.seconds,
  auto_flush: true
)

# Operations are batched automatically
batch_memory.save(session_id, message1)
batch_memory.save(session_id, message2)
batch_memory.save(session_id, message3)
# Automatically flushes when batch_size reached or flush_interval elapsed
```

Semantic Search and RAG
-----------------------

### Conversation Search

Find relevant conversations or messages:

```ruby
search_memory = RAAF::Memory::SearchableMemoryManager.new(
  store: RAAF::Memory::VectorStore.new,
  search_config: {
    embedding_model: 'text-embedding-3-small',
    index_strategy: :real_time,
    search_fields: [:content, :summary, :context_variables]
  }
)

# Semantic search across conversations
search_results = search_memory.search(
  query: "How to optimize database performance",
  limit: 10,
  similarity_threshold: 0.7,
  filters: {
    user_id: current_user.id,
    date_range: 1.month.ago..Time.now,
    conversation_type: 'technical_support'
  }
)

search_results.each do |result|
  puts "Similarity: #{result[:similarity]}"
  puts "Message: #{result[:content]}"
  puts "Context: #{result[:context]}"
end
```

### RAG Integration

Use memory as knowledge base for retrieval-augmented generation:

```ruby
rag_memory = RAAF::Memory::RAGMemoryManager.new(
  store: RAAF::Memory::VectorStore.new,
  rag_config: {
    chunk_size: 500,
    chunk_overlap: 50,
    retrieval_count: 5,
    rerank_model: 'cross-encoder/ms-marco-MiniLM-L-6-v2'
  }
)

# Add knowledge documents
rag_memory.index_document(
  content: File.read('technical_docs.md'),
  metadata: { type: 'documentation', topic: 'database' }
)

# Agent with RAG capabilities
rag_agent = RAAF::Agent.new(
  name: "RAGAgent",
  instructions: """
    You are a technical assistant with access to relevant documentation.
    Use the provided context to answer questions accurately.
  """
)

# Tool for RAG retrieval
rag_agent.add_tool(lambda do |query:|
  relevant_docs = rag_memory.retrieve(
    query: query,
    count: 3,
    rerank: true
  )
  
  {
    context: relevant_docs.map { |doc| doc[:content] },
    sources: relevant_docs.map { |doc| doc[:metadata] }
  }
end)
```

Testing Memory Systems
----------------------

### Unit Testing

```ruby
RSpec.describe 'Memory Management' do
  let(:memory_store) { RAAF::Memory::InMemoryStore.new }
  let(:memory_manager) do
    RAAF::Memory::MemoryManager.new(
      store: memory_store,
      max_tokens: 1000,
      pruning_strategy: :sliding_window
    )
  end
  
  it 'stores and retrieves messages' do
    memory_manager.add_message(
      session_id: 'test_session',
      role: 'user',
      content: 'Hello'
    )
    
    messages = memory_manager.get_messages('test_session')
    expect(messages).to have(1).message
    expect(messages.first[:content]).to eq('Hello')
  end
  
  it 'prunes messages when token limit exceeded' do
    # Add messages that exceed token limit
    10.times do |i|
      memory_manager.add_message(
        session_id: 'test_session',
        role: 'user',
        content: 'A' * 200  # Large message
      )
    end
    
    messages = memory_manager.get_messages('test_session')
    total_tokens = memory_manager.count_tokens(messages)
    
    expect(total_tokens).to be <= 1000
    expect(messages.count).to be < 10
  end
end
```

### Integration Testing

```ruby
RSpec.describe 'Memory in Agent Workflows' do
  let(:memory_manager) do
    RAAF::Memory::MemoryManager.new(
      store: RAAF::Memory::InMemoryStore.new,
      max_tokens: 2000
    )
  end
  
  let(:agent) do
    RAAF::Agent.new(
      name: "MemoryAgent",
      instructions: "Remember what users tell you"
    )
  end
  
  let(:runner) do
    RAAF::Runner.new(
      agent: agent,
      memory_manager: memory_manager
    )
  end
  
  it 'maintains context across turns' do
    # First turn
    result1 = runner.run("My name is Alice and I'm a developer")
    expect(result1.success?).to be true
    
    # Second turn - agent should remember
    result2 = runner.run("What's my profession?")
    expect(result2.messages.last[:content]).to include('developer')
  end
  
  it 'handles memory pruning gracefully' do
    # Fill memory to capacity
    20.times do |i|
      runner.run("This is message number #{i} with lots of content to fill up memory space")
    end
    
    # New message should still work
    result = runner.run("What's the weather like?")
    expect(result.success?).to be true
  end
end
```

Best Practices
--------------

### Production Memory System Guidelines

Production memory systems require careful consideration of cost, performance, and reliability trade-offs.

#### Memory Cost Considerations

Memory storage impacts multiple cost dimensions:

- API token costs when including context ($5-30 per million tokens)
- Storage infrastructure costs (database, vector stores)
- Processing overhead (larger context increases response time)
- Cognitive complexity (excessive context can reduce AI performance)

#### Memory Strategy Selection

**Conversation length considerations:**

- Short conversations (< 10 turns): Sliding window approach
- Medium conversations (10-50 turns): Summarization strategies
- Long conversations (50+ turns): Semantic similarity or hybrid approaches
- Variable length: Hybrid approach with adaptive strategies

**Reliability requirements:**

- Zero data loss tolerance: Database storage with backup strategies
- Moderate reliability needs: File-based storage
- Best effort scenarios: In-memory storage

**Scale considerations:**

- Low volume (< 100 conversations/day): Any backend approach
- Medium volume (100-10K/day): Database or vector store
- High volume (10K+/day): Distributed vector store with caching layers

### Memory Strategy Selection

Choose the right strategy for your use case:

```ruby
# Short conversations, development
memory_manager = RAAF::Memory::MemoryManager.new(
  store: RAAF::Memory::InMemoryStore.new,
  max_tokens: 4000,
  pruning_strategy: :sliding_window
)

# Long conversations, detailed context needed
memory_manager = RAAF::Memory::MemoryManager.new(
  store: RAAF::Memory::VectorStore.new,
  max_tokens: 8000,
  pruning_strategy: :semantic_similarity
)

# Production, high volume
memory_manager = RAAF::Memory::MemoryManager.new(
  store: RAAF::Memory::DatabaseStore.new,
  max_tokens: 6000,
  pruning_strategy: :hybrid,
  async_operations: true
)
```

### Configuration Guidelines

```ruby
# Development configuration
development_memory = RAAF::Memory::MemoryManager.new(
  store: RAAF::Memory::FileStore.new(directory: './tmp/conversations'),
  max_tokens: 4000,
  pruning_strategy: :sliding_window,
  debug_mode: true
)

# Production configuration
production_memory = RAAF::Memory::MemoryManager.new(
  store: RAAF::Memory::DatabaseStore.new(
    model: ConversationMemory,
    connection_pool: true
  ),
  max_tokens: 8000,
  pruning_strategy: :hybrid,
  encryption: true,
  compression: true,
  monitoring: true
)
```

### Monitoring and Debugging

```ruby
monitored_memory = RAAF::Memory::MonitoredMemoryManager.new(
  store: store,
  monitoring_config: {
    track_token_usage: true,
    track_pruning_events: true,
    track_performance_metrics: true,
    alert_on_errors: true
  }
)

# Memory health check
health_status = monitored_memory.health_check
puts "Memory health: #{health_status[:status]}"
puts "Token usage: #{health_status[:token_usage_percent]}%"
puts "Average response time: #{health_status[:avg_response_time]}ms"
```

Next Steps
----------

Now that you understand RAAF memory management:

* **[RAAF Tracing Guide](tracing_guide.html)** - Monitor memory performance
* **[Performance Guide](performance_guide.html)** - Optimize memory operations
* **[Multi-Agent Guide](multi_agent_guide.html)** - Memory in multi-agent systems
* **[RAAF Testing Guide](testing_guide.html)** - Test memory configurations
* **[Configuration Reference](configuration_reference.html)** - Production memory configuration