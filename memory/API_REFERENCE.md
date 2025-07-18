# Memory API Reference

Complete Ruby API documentation for RAAF Memory components.

## Table of Contents

1. [ConversationManager](#conversationmanager)
2. [MemoryStore](#memorystore)
3. [Memory Providers](#memory-providers)
   - [InMemoryStore](#inmemorystore)
   - [RedisMemoryStore](#redismemorystore)
   - [ActiveRecordMemoryStore](#activerecordmemorystore)
4. [Conversation Context](#conversation-context)
5. [Memory Strategies](#memory-strategies)
6. [Integration Examples](#integration-examples)

## ConversationManager

Manages conversation history and context for agents.

### Constructor

```ruby
RAAF::Memory::ConversationManager.new(
  store: MemoryStore,              # Memory storage backend
  max_history: 50,                 # Maximum messages to retain
  summarization_threshold: 20,     # When to summarize old messages
  context_window: 10               # Active context size
)
```

### Core Methods

```ruby
# Add a message to conversation
manager.add_message(
  role: "user" | "assistant" | "system",
  content: String,
  metadata: Hash
)

# Get conversation history
manager.get_history(limit: 10)          # Get recent messages
manager.get_full_history                # Get all messages
manager.get_context                     # Get active context

# Conversation management
manager.clear_history                   # Clear all messages
manager.summarize_history               # Create summary of old messages
manager.export_conversation(format: :json) # Export conversation

# Search and retrieval
manager.search_history(query)           # Search messages
manager.get_messages_by_role(role)      # Filter by role
manager.get_messages_since(timestamp)   # Get recent messages
```

### Example Usage

```ruby
# Create conversation manager
store = RAAF::Memory::InMemoryStore.new
manager = RAAF::Memory::ConversationManager.new(
  store: store,
  max_history: 100,
  summarization_threshold: 50
)

# Add messages
manager.add_message(
  role: "user",
  content: "What's the weather like?",
  metadata: { user_id: "123", timestamp: Time.current }
)

manager.add_message(
  role: "assistant",
  content: "I'll help you check the weather. What's your location?",
  metadata: { agent: "WeatherBot" }
)

# Get context for next interaction
context = manager.get_context
# Returns last 10 messages for context window

# Search history
results = manager.search_history("weather")
# Returns messages containing "weather"
```

## MemoryStore

Base interface for memory storage backends.

### Required Methods

```ruby
class MemoryStore
  # Store a message
  def store(message_id, message_data)
    raise NotImplementedError
  end
  
  # Retrieve a message
  def retrieve(message_id)
    raise NotImplementedError
  end
  
  # List messages with optional filtering
  def list(filter: {}, limit: nil, offset: 0)
    raise NotImplementedError
  end
  
  # Delete a message
  def delete(message_id)
    raise NotImplementedError
  end
  
  # Clear all messages
  def clear
    raise NotImplementedError
  end
  
  # Count messages
  def count(filter: {})
    raise NotImplementedError
  end
end
```

## Memory Providers

### InMemoryStore

Simple in-memory storage for development/testing.

```ruby
# Constructor
store = RAAF::Memory::InMemoryStore.new(
  max_size: 1000,                  # Maximum messages to store
  ttl: nil                         # Optional TTL in seconds
)

# Additional methods
store.size                         # Current number of messages
store.memory_usage                 # Estimated memory usage
store.cleanup_expired              # Remove expired messages (if TTL set)
```

#### Example

```ruby
# Basic in-memory store
store = RAAF::Memory::InMemoryStore.new

# With size limit and TTL
store = RAAF::Memory::InMemoryStore.new(
  max_size: 500,
  ttl: 3600  # Messages expire after 1 hour
)

# Store and retrieve
store.store("msg_123", {
  role: "user",
  content: "Hello",
  timestamp: Time.current
})

message = store.retrieve("msg_123")
```

### RedisMemoryStore

Redis-backed storage for production use.

```ruby
# Constructor
store = RAAF::Memory::RedisMemoryStore.new(
  redis_client: Redis.new,         # Redis client instance
  namespace: "raaf:memory",        # Key namespace
  ttl: 86400,                     # Default TTL (24 hours)
  compression: true               # Enable compression
)

# Additional methods
store.flush_namespace             # Clear this namespace only
store.keys_count                  # Count keys in namespace
store.memory_info                 # Redis memory statistics
```

#### Example

```ruby
# Basic Redis store
redis = Redis.new(url: ENV['REDIS_URL'])
store = RAAF::Memory::RedisMemoryStore.new(
  redis_client: redis,
  namespace: "conversations",
  ttl: 7.days.to_i
)

# With compression for large conversations
store = RAAF::Memory::RedisMemoryStore.new(
  redis_client: redis,
  compression: true,
  compression_threshold: 1024  # Compress messages > 1KB
)

# Batch operations
messages = [
  { id: "msg_1", data: { role: "user", content: "Hi" } },
  { id: "msg_2", data: { role: "assistant", content: "Hello!" } }
]

store.batch_store(messages)
results = store.batch_retrieve(["msg_1", "msg_2"])
```

### ActiveRecordMemoryStore

Database-backed storage for Rails applications.

```ruby
# Constructor
store = RAAF::Memory::ActiveRecordMemoryStore.new(
  model_class: ConversationMessage,  # Your AR model
  batch_size: 100,                   # Batch operation size
  archive_after: 30.days             # Archive old messages
)

# Additional methods
store.archive_old_messages          # Move to archive table
store.vacuum                        # Database maintenance
store.statistics                    # Usage statistics
```

#### Model Setup

```ruby
# Migration
class CreateConversationMessages < ActiveRecord::Migration[7.0]
  def change
    create_table :conversation_messages do |t|
      t.string :message_id, null: false, index: { unique: true }
      t.string :conversation_id, index: true
      t.string :role, null: false
      t.text :content
      t.jsonb :metadata
      t.datetime :created_at, null: false
      
      t.index [:conversation_id, :created_at]
      t.index :metadata, using: :gin  # For PostgreSQL
    end
  end
end

# Model
class ConversationMessage < ApplicationRecord
  validates :message_id, presence: true, uniqueness: true
  validates :role, inclusion: { in: %w[user assistant system tool] }
  
  scope :by_conversation, ->(id) { where(conversation_id: id) }
  scope :recent, -> { order(created_at: :desc) }
  scope :by_role, ->(role) { where(role: role) }
end

# Usage
store = RAAF::Memory::ActiveRecordMemoryStore.new(
  model_class: ConversationMessage
)
```

## Conversation Context

### ContextWindow

Manages the active context window for agents.

```ruby
# Constructor
context = RAAF::Memory::ContextWindow.new(
  size: 10,                        # Window size
  token_limit: 4000,              # Max tokens
  include_system: true,           # Include system messages
  summarization_enabled: true     # Auto-summarize when full
)

# Methods
context.add_message(message)      # Add to context
context.get_messages             # Get current context
context.is_full?                 # Check if at capacity
context.token_count              # Current token usage
context.truncate                 # Remove oldest messages
context.summarize                # Create summary
```

### ContextBuilder

Builds optimized context for agents.

```ruby
builder = RAAF::Memory::ContextBuilder.new(
  strategy: :recency,              # :recency, :relevance, :hybrid
  max_tokens: 4000,
  include_metadata: false
)

# Build context from conversation
context = builder.build_context(
  messages: conversation_manager.get_history,
  current_query: "What did we discuss about pricing?",
  agent_instructions: agent.instructions
)
```

## Memory Strategies

### Summarization Strategy

```ruby
class SummarizationStrategy
  def initialize(
    summarizer_agent: nil,         # Agent to create summaries
    chunk_size: 20,               # Messages per chunk
    overlap: 2                    # Overlapping messages
  )
    @summarizer_agent = summarizer_agent || default_summarizer
    @chunk_size = chunk_size
    @overlap = overlap
  end
  
  def summarize(messages)
    chunks = create_chunks(messages)
    summaries = chunks.map { |chunk| summarize_chunk(chunk) }
    combine_summaries(summaries)
  end
  
  private
  
  def default_summarizer
    RAAF::Agent.new(
      name: "Summarizer",
      instructions: "Create concise summaries preserving key information.",
      model: "gpt-3.5-turbo"
    )
  end
end
```

### Relevance Strategy

```ruby
class RelevanceStrategy
  def initialize(
    embedding_model: "text-embedding-ada-002",
    similarity_threshold: 0.7
  )
    @embedding_model = embedding_model
    @similarity_threshold = similarity_threshold
  end
  
  def select_relevant_messages(messages, query, limit: 10)
    # Get embeddings
    query_embedding = get_embedding(query)
    message_embeddings = messages.map do |msg|
      { message: msg, embedding: get_embedding(msg[:content]) }
    end
    
    # Calculate similarities
    similarities = message_embeddings.map do |item|
      {
        message: item[:message],
        similarity: cosine_similarity(query_embedding, item[:embedding])
      }
    end
    
    # Select most relevant
    similarities
      .select { |item| item[:similarity] >= @similarity_threshold }
      .sort_by { |item| -item[:similarity] }
      .take(limit)
      .map { |item| item[:message] }
  end
end
```

### Hybrid Strategy

```ruby
class HybridMemoryStrategy
  def initialize(
    recency_weight: 0.5,
    relevance_weight: 0.5,
    max_messages: 20
  )
    @recency_weight = recency_weight
    @relevance_weight = relevance_weight
    @max_messages = max_messages
    @relevance_strategy = RelevanceStrategy.new
  end
  
  def select_messages(all_messages, current_query)
    # Get recent messages
    recent = all_messages.last(10)
    
    # Get relevant messages
    relevant = @relevance_strategy.select_relevant_messages(
      all_messages,
      current_query,
      limit: 10
    )
    
    # Combine with weights
    combined = score_and_combine(recent, relevant)
    
    # Return top messages
    combined
      .sort_by { |item| -item[:score] }
      .take(@max_messages)
      .map { |item| item[:message] }
  end
end
```

## Integration Examples

### With Agent

```ruby
# Create memory-enabled agent
memory_store = RAAF::Memory::RedisMemoryStore.new(
  redis_client: Redis.new,
  namespace: "agent:customer_support"
)

conversation_manager = RAAF::Memory::ConversationManager.new(
  store: memory_store,
  max_history: 100,
  context_window: 20
)

agent = RAAF::Agent.new(
  name: "CustomerSupport",
  instructions: "You are a helpful customer support agent with memory of past conversations.",
  model: "gpt-4"
)

# Custom runner with memory
class MemoryRunner < RAAF::Runner
  def initialize(agent:, conversation_manager:, **options)
    super(agent: agent, **options)
    @conversation_manager = conversation_manager
  end
  
  def run(messages, **options)
    # Add user message to memory
    if messages.is_a?(String)
      @conversation_manager.add_message(
        role: "user",
        content: messages
      )
      messages = [{ role: "user", content: messages }]
    elsif messages.is_a?(Array) && messages.last[:role] == "user"
      @conversation_manager.add_message(messages.last)
    end
    
    # Build context from memory
    context_messages = @conversation_manager.get_context
    full_messages = context_messages + messages
    
    # Run agent with context
    result = super(full_messages, **options)
    
    # Store assistant response
    if result.messages.last[:role] == "assistant"
      @conversation_manager.add_message(result.messages.last)
    end
    
    result
  end
end

# Usage
runner = MemoryRunner.new(
  agent: agent,
  conversation_manager: conversation_manager
)

# Conversation with memory
runner.run("Hi, I'm John and I need help with order #12345")
runner.run("What was my order number?")  # Agent remembers context
```

### Multi-User Conversations

```ruby
class MultiUserConversationManager
  def initialize(base_store)
    @base_store = base_store
    @managers = {}
  end
  
  def get_manager_for_user(user_id)
    @managers[user_id] ||= RAAF::Memory::ConversationManager.new(
      store: namespaced_store(user_id),
      max_history: 50,
      context_window: 10
    )
  end
  
  private
  
  def namespaced_store(user_id)
    RAAF::Memory::NamespacedStore.new(
      base_store: @base_store,
      namespace: "user:#{user_id}"
    )
  end
end

# Usage
multi_manager = MultiUserConversationManager.new(redis_store)

# Different users get isolated conversations
user1_manager = multi_manager.get_manager_for_user("user_123")
user2_manager = multi_manager.get_manager_for_user("user_456")
```

### Persistent Sessions

```ruby
class PersistentSession
  def initialize(session_id, memory_store)
    @session_id = session_id
    @memory_store = memory_store
    @conversation_manager = load_or_create_manager
  end
  
  def continue_conversation(message)
    # Restore context
    @conversation_manager.add_message(
      role: "user",
      content: message,
      metadata: { session_id: @session_id }
    )
    
    # Get appropriate context
    context = @conversation_manager.get_context
    
    # Process with agent
    result = runner.run(context + [{ role: "user", content: message }])
    
    # Save response
    @conversation_manager.add_message(
      role: "assistant",
      content: result.messages.last[:content],
      metadata: { session_id: @session_id }
    )
    
    # Persist state
    save_manager_state
    
    result
  end
  
  def export_transcript
    @conversation_manager.export_conversation(format: :text)
  end
  
  private
  
  def load_or_create_manager
    state = @memory_store.retrieve("session:#{@session_id}")
    
    if state
      RAAF::Memory::ConversationManager.from_state(state)
    else
      RAAF::Memory::ConversationManager.new(
        store: @memory_store,
        max_history: 100
      )
    end
  end
  
  def save_manager_state
    @memory_store.store(
      "session:#{@session_id}",
      @conversation_manager.to_state
    )
  end
end
```

### Memory Analytics

```ruby
class MemoryAnalytics
  def initialize(conversation_manager)
    @manager = conversation_manager
  end
  
  def generate_report
    messages = @manager.get_full_history
    
    {
      total_messages: messages.count,
      by_role: count_by_role(messages),
      average_length: average_message_length(messages),
      time_span: time_span(messages),
      most_discussed_topics: extract_topics(messages),
      sentiment_trend: analyze_sentiment_trend(messages)
    }
  end
  
  def conversation_summary
    summarizer = RAAF::Agent.new(
      name: "Summarizer",
      instructions: "Create a comprehensive summary of the conversation.",
      model: "gpt-4"
    )
    
    runner = RAAF::Runner.new(agent: summarizer)
    result = runner.run(
      "Summarize this conversation:\n\n" +
      @manager.export_conversation(format: :text)
    )
    
    result.messages.last[:content]
  end
  
  private
  
  def count_by_role(messages)
    messages.group_by { |m| m[:role] }
            .transform_values(&:count)
  end
  
  def average_message_length(messages)
    return 0 if messages.empty?
    
    total_length = messages.sum { |m| m[:content].length }
    (total_length / messages.count.to_f).round(2)
  end
  
  def time_span(messages)
    return nil if messages.empty?
    
    first = messages.first[:metadata][:timestamp]
    last = messages.last[:metadata][:timestamp]
    
    {
      start: first,
      end: last,
      duration_hours: ((last - first) / 3600.0).round(2)
    }
  end
end
```

For more information on integrating memory with agents, see the [Core API Reference](../core/API_REFERENCE.md).