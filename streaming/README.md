# RAAF Streaming

[![Gem Version](https://badge.fury.io/rb/raaf-streaming.svg)](https://badge.fury.io/rb/raaf-streaming)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

The **RAAF Streaming** gem provides comprehensive real-time streaming capabilities for the Ruby AI Agents Factory (RAAF) ecosystem. This gem enables real-time AI agent responses, WebSocket communication, async processing, and interactive chat interfaces.

## Overview

RAAF (Ruby AI Agents Factory) Streaming delivers enterprise-grade real-time communication capabilities for AI agents. It provides:

- **🚀 Real-time Response Streaming** - Stream AI responses as they're generated for immediate user feedback
- **🔌 WebSocket Support** - Full-duplex communication with connection management and channels
- **⚡ Async Processing** - Non-blocking agent operations with thread pool management
- **📡 Event-Driven Architecture** - Publish-subscribe system for decoupled communication
- **💬 Real-time Chat Interface** - Complete chat system with rooms, handoffs, and message queues
- **📊 Performance Monitoring** - Built-in metrics, statistics, and connection tracking
- **🛡️ Production-Ready** - Connection pooling, error handling, and graceful degradation

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'raaf-streaming'
```

And then execute:

```bash
bundle install
```

Or install it yourself as:

```bash
gem install raaf-streaming
```

## Dependencies

- **raaf-core** - Core RAAF functionality and base classes
- **async** - Async I/O framework for Ruby
- **async-websocket** - WebSocket support for async
- **concurrent-ruby** - Thread-safe concurrency utilities
- **redis** - Redis client for background processing and queues
- **eventmachine** - High-performance event-driven I/O

## Quick Start

### Basic Streaming

```ruby
require 'raaf-streaming'

# Create an agent
agent = RubyAIAgentsFactory::Agent.new(
  name: "StreamingAgent",
  instructions: "You are a helpful assistant that provides streaming responses",
  model: "gpt-4o"
)

# Create streaming runner
runner = RubyAIAgentsFactory::Runner.new(agent: agent)

# Stream responses in real-time
runner.run("Tell me about AI streaming", stream: true) do |chunk|
  print chunk.content if chunk.respond_to?(:content)
  $stdout.flush
end
```

### WebSocket Server

```ruby
require 'raaf-streaming'

# Create WebSocket server
server = RubyAIAgentsFactory::Streaming::WebSocketServer.new(
  port: 8080,
  max_connections: 1000
)

# Handle client connections
server.on_connection do |client|
  puts "Client connected: #{client.id}"
  
  client.on_message do |message|
    # Process message with agent
    runner.run(message["content"], stream: true) do |chunk|
      client.send_message({
        type: "response_chunk",
        content: chunk.content
      })
    end
  end
end

# Start server
server.start
```

### Async Processing

```ruby
require 'raaf-streaming'

# Create async runner
async_runner = RubyAIAgentsFactory::Streaming::AsyncRunner.new(
  pool_size: 10,
  queue_size: 100
)

# Process messages asynchronously
task_id = async_runner.process_async(agent, "Hello") do |result|
  puts "Async result: #{result.messages.last[:content]}"
end

# Process multiple agents concurrently
agents = [agent1, agent2, agent3]
async_runner.process_concurrent(agents, "Same message") do |agent, result|
  puts "#{agent.name}: #{result.messages.last[:content]}"
end
```

## Core Components

### 1. Streaming Responses

Real-time response streaming with immediate feedback:

```ruby
# Basic streaming with chunk processing
runner.run("Explain quantum computing", stream: true) do |chunk|
  case chunk
  when String
    print chunk
  else
    print chunk.content if chunk.respond_to?(:content)
  end
  $stdout.flush
end

# Advanced streaming with event handling
response_buffer = ""
tool_calls = []

runner.run("What's the weather?", stream: true) do |chunk|
  if chunk.respond_to?(:tool_calls) && chunk.tool_calls
    tool_calls.concat(chunk.tool_calls)
    puts "\n🔧 [Tool executing...]"
  elsif chunk.respond_to?(:content) && chunk.content
    print chunk.content
    response_buffer += chunk.content
    $stdout.flush
  end
end
```

### 2. WebSocket Server

Full-featured WebSocket server with connection management:

```ruby
server = RubyAIAgentsFactory::Streaming::WebSocketServer.new(
  port: 8080,
  host: "localhost",
  max_connections: 5000,
  heartbeat_interval: 30
)

# Connection lifecycle events
server.on_connection do |client|
  puts "New client: #{client.id}"
  client.set_metadata("user_id", "user123")
  client.set_metadata("session_id", SecureRandom.uuid)
end

server.on_disconnection do |client|
  puts "Client disconnected: #{client.id}"
  cleanup_client_resources(client)
end

server.on_error do |client, error|
  puts "Error from #{client.id}: #{error}"
  handle_client_error(client, error)
end

# Message handling
server.on_message do |client, message|
  case message["type"]
  when "chat_message"
    handle_chat_message(client, message)
  when "agent_stream"
    handle_agent_stream(client, message)
  when "subscribe"
    server.subscribe_to_channel(client.id, message["channel"])
  end
end

# Channel support for room-based communication
server.subscribe_to_channel("client123", "general")
server.broadcast({
  type: "announcement",
  message: "Welcome to the chat!"
}, channel: "general")

# Start server
server.start
puts "WebSocket server running on ws://localhost:8080"
```

### 3. Async Runner

Non-blocking agent processing with thread pool management:

```ruby
async_runner = RubyAIAgentsFactory::Streaming::AsyncRunner.new(
  pool_size: 20,
  queue_size: 500,
  timeout: 60
)

# Single async processing
task_id = async_runner.process_async(agent, "Process this message") do |result|
  puts "Async result: #{result.messages.last[:content]}"
end

# Concurrent processing of multiple agents
agents = [support_agent, sales_agent, tech_agent]
task_ids = async_runner.process_concurrent(agents, "Handle customer query") do |agent, result|
  puts "#{agent.name}: #{result.messages.last[:content]}"
end

# Wait for completion
results = async_runner.wait_for_tasks(task_ids, timeout: 30)

# Processing with retry logic
task_id = async_runner.process_with_retry(
  agent,
  "Complex query",
  retry_count: 3,
  retry_delay: 2.0
) do |result|
  puts "Result after retries: #{result.messages.last[:content]}"
end

# Create streaming session
session = async_runner.create_streaming_session(agent)
session.start

session.send_message("Hello") do |chunk|
  puts chunk[:content]
end
```

### 4. Background Processor

Redis-based background job processing for heavy workloads:

```ruby
processor = RubyAIAgentsFactory::Streaming::BackgroundProcessor.new(
  redis_url: "redis://localhost:6379",
  workers: 5,
  retry_count: 3,
  queue_name: "agent_jobs"
)

# Register job handlers
processor.handle_job("process_message") do |data|
  agent = find_agent(data["agent_id"])
  result = agent.run(data["message"])
  
  # Process result and notify
  notify_user(data["user_id"], result.messages.last[:content])
end

processor.handle_job("batch_analysis") do |data|
  results = data["messages"].map do |msg|
    agent.run(msg)
  end
  
  # Store batch results
  store_batch_results(data["batch_id"], results)
end

# Start background processor
processor.start

# Enqueue jobs with priorities
job_id = processor.enqueue_job("process_message", {
  agent_id: "agent123",
  user_id: "user456",
  message: "Process this in background"
}, priority: :high)

# Schedule delayed jobs
processor.schedule_job("send_reminder", {
  user_id: "user123",
  message: "Don't forget about your meeting"
}, at: 1.hour.from_now)

# Monitor job queues
puts processor.stats
# => {
#      running: true,
#      workers: 5,
#      high_priority_queue: 2,
#      normal_priority_queue: 15,
#      low_priority_queue: 3,
#      scheduled_jobs: 8,
#      failed_jobs: 1
#    }
```

### 5. Event Emitter

Publish-subscribe event system for decoupled communication:

```ruby
emitter = RubyAIAgentsFactory::Streaming::EventEmitter.new(
  max_listeners: 50,
  enable_wildcards: true,
  enable_history: true
)

# Add event listeners
listener_id = emitter.on("agent.response") do |event|
  puts "Agent responded: #{event[:data][:content]}"
  log_agent_response(event[:data])
end

# Wildcard listeners for pattern matching
emitter.on("user.*") do |event|
  puts "User event: #{event[:event]}"
  track_user_activity(event)
end

# One-time listeners
emitter.once("system.startup") do |event|
  puts "System started at #{event[:data][:timestamp]}"
  initialize_system_monitoring
end

# Emit events
emitter.emit("user.login", {
  user_id: "user123",
  timestamp: Time.current,
  ip_address: "192.168.1.100"
})

# Async event emission
future = emitter.emit_async("heavy.processing", {
  data: large_dataset,
  process_id: "proc123"
})

# Wait for specific events
event_data = emitter.wait_for_event("user.login", timeout: 10)

# Event filtering and mapping
filtered_emitter = emitter.filter do |event|
  event[:data][:priority] == :high
end

mapped_emitter = emitter.map do |event|
  {
    event: event[:event],
    data: event[:data].transform_keys(&:upcase)
  }
end
```

### 6. Real-time Chat

Complete chat interface with rooms, handoffs, and message history:

```ruby
# Create chat system with multiple agents
chat = RubyAIAgentsFactory::Streaming::RealTimeChat.new(
  agent: primary_agent,
  websocket_port: 8080,
  redis_url: "redis://localhost:6379"
)

# Add specialist agents for handoffs
chat.add_agent(support_agent)
chat.add_agent(technical_agent)
chat.add_agent(sales_agent)

# Create chat rooms
general_room = chat.create_room("General Support", {
  max_participants: 50,
  message_history: 100
})

tech_room = chat.create_room("Technical Discussion", {
  max_participants: 20,
  message_history: 200,
  restricted: true
})

# Configure chat features
chat.configure do |config|
  config.enable_handoffs = true
  config.enable_message_history = true
  config.max_message_length = 2000
  config.rate_limit = 60 # messages per minute
  config.enable_typing_indicators = true
end

# Start chat server
chat.start
puts "Chat server running on ws://localhost:8080"

# Monitor chat statistics
puts chat.stats
# => {
#      connected_clients: 25,
#      active_sessions: 18,
#      active_streams: 5,
#      available_agents: 4,
#      total_messages: 1247,
#      rooms: {
#        "General Support" => { participants: 20, messages: 450 },
#        "Technical Discussion" => { participants: 8, messages: 120 }
#      }
#    }
```

## Configuration

### Global Configuration

```ruby
RubyAIAgentsFactory::Streaming.configure do |config|
  # WebSocket server settings
  config.websocket.port = 8080
  config.websocket.host = "0.0.0.0"
  config.websocket.max_connections = 5000
  config.websocket.heartbeat_interval = 30
  config.websocket.enable_compression = true
  
  # Streaming settings
  config.streaming.chunk_size = 1024
  config.streaming.buffer_size = 8192
  config.streaming.timeout = 60
  config.streaming.enable_sse = true
  
  # Async processing settings
  config.async.pool_size = 20
  config.async.queue_size = 1000
  config.async.thread_timeout = 30
  
  # Background processing settings
  config.background.redis_url = "redis://localhost:6379"
  config.background.workers = 10
  config.background.retry_count = 3
  config.background.retry_delay = 5
  
  # Event system settings
  config.events.max_listeners = 100
  config.events.enable_wildcards = true
  config.events.history_size = 1000
  
  # Chat system settings
  config.chat.max_rooms = 100
  config.chat.max_participants_per_room = 50
  config.chat.message_history_size = 500
  config.chat.enable_typing_indicators = true
end
```

### Environment Variables

```bash
# Redis configuration
export REDIS_URL="redis://localhost:6379"
export REDIS_POOL_SIZE=20

# WebSocket configuration
export WEBSOCKET_PORT=8080
export WEBSOCKET_HOST="0.0.0.0"
export WEBSOCKET_MAX_CONNECTIONS=5000

# Async processing
export ASYNC_POOL_SIZE=20
export ASYNC_QUEUE_SIZE=1000

# Background processing
export BACKGROUND_WORKERS=10
export BACKGROUND_RETRY_COUNT=3

# Streaming configuration
export STREAMING_CHUNK_SIZE=1024
export STREAMING_BUFFER_SIZE=8192
export STREAMING_TIMEOUT=60
```

## Advanced Usage

### Custom Stream Processor

```ruby
class CustomStreamProcessor < RubyAIAgentsFactory::Streaming::StreamProcessor
  def initialize(options = {})
    super(options)
    @custom_filters = options[:filters] || []
  end

  def process_chunk(chunk, stream_id)
    # Apply custom processing
    processed = super(chunk, stream_id)
    
    # Apply custom filters
    @custom_filters.each do |filter|
      processed = filter.call(processed)
    end
    
    # Add metadata
    processed[:processed_at] = Time.current.iso8601
    processed[:stream_id] = stream_id
    processed[:processor] = self.class.name
    
    processed
  end
  
  def handle_error(error, stream_id)
    # Custom error handling
    log_error("Stream processing error", error: error, stream_id: stream_id)
    super(error, stream_id)
  end
end

# Use custom processor
processor = CustomStreamProcessor.new(
  chunk_size: 512,
  filters: [
    ->(chunk) { chunk.merge(filtered: true) },
    ->(chunk) { chunk.merge(timestamp: Time.current.to_i) }
  ]
)
```

### WebSocket Client

```ruby
client = RubyAIAgentsFactory::Streaming::WebSocketClient.new(
  "ws://localhost:8080",
  auto_reconnect: true,
  max_reconnect_attempts: 5,
  reconnect_delay: 2.0
)

# Connection management
client.on_connect do
  puts "Connected to server"
  client.authenticate(token: "user_token")
end

client.on_disconnect do
  puts "Disconnected from server"
end

client.on_reconnect do |attempt|
  puts "Reconnecting (attempt #{attempt})"
end

# Message handling
client.on_message do |message|
  case message["type"]
  when "response_chunk"
    handle_streaming_chunk(message)
  when "agent_handoff"
    handle_agent_handoff(message)
  when "error"
    handle_error(message)
  end
end

# Connect and subscribe
client.connect
client.subscribe("general")
client.subscribe("notifications")

# Send messages
client.send_message({
  type: "chat_message",
  content: "Hello server!",
  channel: "general"
})

# Start agent streaming
client.start_agent_stream(agent, "Tell me about streaming") do |chunk|
  puts chunk[:content]
end
```

## Performance Optimization

### Connection Pooling

```ruby
# Configure Redis connection pooling
RubyAIAgentsFactory::Streaming.configure do |config|
  config.background.redis_url = "redis://localhost:6379"
  config.background.pool_size = 20
  config.background.pool_timeout = 5
  config.background.pool_checkout_timeout = 5
end

# WebSocket connection limits
RubyAIAgentsFactory::Streaming.configure do |config|
  config.websocket.max_connections = 10000
  config.websocket.connection_timeout = 30
  config.websocket.keepalive_interval = 30
end
```

### Batch Processing

```ruby
# Process messages in batches for better performance
queue = RubyAIAgentsFactory::Streaming::MessageQueue.new(
  redis_url: "redis://localhost:6379",
  batch_size: 100
)

queue.process_messages(batch_size: 50) do |messages|
  # Process batch of messages
  results = messages.map do |message|
    agent.run(message["content"])
  end
  
  # Batch store results
  store_batch_results(results)
end
```

### Async Processing Best Practices

```ruby
# Use appropriate pool sizes
async_runner = RubyAIAgentsFactory::Streaming::AsyncRunner.new(
  pool_size: [20, Concurrent.processor_count * 2].min,
  queue_size: 1000,
  timeout: 30
)

# Process in batches when possible
requests.each_slice(10) do |batch|
  batch.each do |request|
    async_runner.process_async(agent, request) do |result|
      handle_result(result)
    end
  end
end
```

## Monitoring and Debugging

### Statistics Collection

```ruby
# Collect comprehensive statistics
stats = {
  websocket_server: websocket_server.stats,
  async_runner: async_runner.stats,
  background_processor: background_processor.stats,
  message_queue: message_queue.stats,
  event_emitter: event_emitter.stats,
  chat_system: chat.stats
}

# Combined system statistics
all_stats = RubyAIAgentsFactory::Streaming.stats
puts JSON.pretty_generate(all_stats)
```

### Debug Logging

```ruby
# Enable comprehensive debug logging
RubyAIAgentsFactory::Logging.configure do |config|
  config.log_level = :debug
  config.debug_categories = [:streaming, :websocket, :async, :background]
  config.log_format = :json
end

# Log streaming events
class DebugStreamProcessor < RubyAIAgentsFactory::Streaming::StreamProcessor
  include RubyAIAgentsFactory::Logger
  
  def process_chunk(chunk, stream_id)
    log_debug_streaming("Processing chunk", {
      stream_id: stream_id,
      chunk_size: chunk.to_s.length,
      chunk_type: chunk.class.name
    })
    
    super(chunk, stream_id)
  end
end
```

### Health Checks

```ruby
# Comprehensive health check system
class HealthChecker
  def self.check_all
    {
      websocket_server: check_websocket_server,
      background_processor: check_background_processor,
      redis_connection: check_redis_connection,
      async_runner: check_async_runner,
      message_queue: check_message_queue
    }
  end
  
  def self.check_websocket_server
    {
      running: websocket_server.running?,
      connections: websocket_server.connection_count,
      memory_usage: websocket_server.memory_usage,
      uptime: websocket_server.uptime
    }
  end
  
  def self.check_redis_connection
    {
      connected: redis.ping == "PONG",
      memory_usage: redis.info["used_memory"],
      connections: redis.info["connected_clients"]
    }
  end
  
  # ... other health checks
end
```

## Testing

### Mock Streaming Provider

```ruby
# Mock provider for testing
mock_provider = RubyAIAgentsFactory::Testing::MockProvider.new
streaming_provider = RubyAIAgentsFactory::Streaming::StreamingProvider.new(
  provider: mock_provider,
  enable_simulation: true,
  simulation_delay: 0.01
)

# Test streaming functionality
agent = RubyAIAgentsFactory::Agent.new(
  name: "TestAgent",
  provider: streaming_provider
)

chunks = []
agent.stream("Test message") do |chunk|
  chunks << chunk
end

expect(chunks).not_to be_empty
expect(chunks.first).to respond_to(:content)
```

### WebSocket Testing

```ruby
# Test WebSocket server
server = RubyAIAgentsFactory::Streaming::WebSocketServer.new(port: 8081)
server.start

client = RubyAIAgentsFactory::Streaming::WebSocketClient.new("ws://localhost:8081")
client.connect

received_messages = []
client.on_message do |message|
  received_messages << message
end

client.send_message({ type: "test", content: "hello" })
sleep(0.1)

expect(received_messages).not_to be_empty
```

### Async Testing

```ruby
# Test async processing
async_runner = RubyAIAgentsFactory::Streaming::AsyncRunner.new(
  pool_size: 2,
  queue_size: 10
)

results = []
completed = Concurrent::CountDownLatch.new(3)

3.times do |i|
  async_runner.process_async(agent, "Message #{i}") do |result|
    results << result
    completed.count_down
  end
end

completed.wait(5) # Wait up to 5 seconds
expect(results.size).to eq(3)
```

## Error Handling

### Streaming Error Handling

```ruby
begin
  runner.run("Message", stream: true) do |chunk|
    process_chunk(chunk)
  end
rescue RubyAIAgentsFactory::Streaming::StreamingError => e
  puts "Streaming error: #{e.message}"
  fallback_to_non_streaming(message)
rescue RubyAIAgentsFactory::Streaming::ConnectionError => e
  puts "Connection error: #{e.message}"
  retry_with_backoff
rescue StandardError => e
  puts "General error: #{e.message}"
  handle_general_error(e)
end
```

### WebSocket Error Handling

```ruby
websocket_server.on_error do |client, error|
  case error
  when RubyAIAgentsFactory::Streaming::ProtocolError
    puts "Protocol error from #{client.id}: #{error.message}"
    client.close(1002, "Protocol error")
  when RubyAIAgentsFactory::Streaming::ConnectionError
    puts "Connection error from #{client.id}: #{error.message}"
    attempt_reconnection(client)
  when RubyAIAgentsFactory::Streaming::TimeoutError
    puts "Timeout error from #{client.id}: #{error.message}"
    client.ping
  else
    puts "Unknown error from #{client.id}: #{error.message}"
    log_error("Unknown WebSocket error", error: error, client_id: client.id)
  end
end
```

### Background Job Error Handling

```ruby
background_processor.handle_job("risky_job") do |data|
  begin
    risky_operation(data)
  rescue SpecificError => e
    # Handle specific error types
    log_error("Specific error in job", error: e, job_data: data)
    raise # Re-raise to trigger retry
  rescue StandardError => e
    # Handle general errors
    log_error("Job failed", error: e, job_data: data)
    send_error_notification(e, data)
    # Don't re-raise to prevent retry
  end
end
```

## Best Practices

### Resource Management

```ruby
# Proper resource cleanup
begin
  websocket_server.start
  background_processor.start
  async_runner.start
  
  # Run application
  run_application
ensure
  # Always cleanup resources
  websocket_server.stop
  background_processor.stop
  async_runner.stop
  
  # Close connections
  redis.close if redis
end
```

### Message Validation

```ruby
# Validate all incoming messages
websocket_server.on_message do |client, message|
  # Basic format validation
  unless message.is_a?(Hash) && message["type"]
    client.send_error("Invalid message format")
    return
  end
  
  # Content validation
  case message["type"]
  when "chat_message"
    unless message["content"].is_a?(String) && message["content"].length <= 2000
      client.send_error("Invalid content")
      return
    end
  when "agent_stream"
    unless message["query"].is_a?(String) && message["agent_id"]
      client.send_error("Invalid streaming request")
      return
    end
  end
  
  # Process valid message
  process_message(client, message)
end
```

### Rate Limiting

```ruby
# Implement rate limiting
class RateLimitedServer < RubyAIAgentsFactory::Streaming::WebSocketServer
  def initialize(*args)
    super
    @rate_limits = {}
  end
  
  private
  
  def handle_message(client, message)
    # Check rate limit
    if rate_limit_exceeded?(client)
      client.send_error("Rate limit exceeded")
      return
    end
    
    # Update rate limit counter
    update_rate_limit(client)
    
    super(client, message)
  end
  
  def rate_limit_exceeded?(client)
    now = Time.current.to_i
    client_rates = @rate_limits[client.id] ||= []
    client_rates.select! { |time| time > now - 60 } # Last minute
    client_rates.size >= 60 # Max 60 messages per minute
  end
  
  def update_rate_limit(client)
    @rate_limits[client.id] << Time.current.to_i
  end
end
```

## Relationship with Other RAAF Gems

### Core Dependencies

RAAF Streaming builds on and extends several core gems:

- **raaf-core** - Uses base Agent and Runner classes for streaming
- **raaf-logging** - Integrates with unified logging system
- **raaf-tracing** - Provides streaming span tracking and monitoring

### Enhanced by Extensions

- **raaf-rails** - Mounts streaming endpoints in Rails applications
- **raaf-memory** - Provides persistent chat history and session storage
- **raaf-guardrails** - Validates streaming content in real-time
- **raaf-providers** - Streams responses from multiple AI providers

### Integration Points

- **raaf-tools-advanced** - Streams tool execution progress
- **raaf-compliance** - Audits streaming sessions for compliance
- **raaf-analytics** - Analyzes streaming performance and usage

## Architecture

### Component Architecture

```
RubyAIAgentsFactory::Streaming::
├── StreamingProvider           # Core streaming functionality
├── WebSocketServer            # WebSocket server implementation
├── WebSocketClient            # WebSocket client implementation
├── AsyncRunner                # Async processing engine
├── BackgroundProcessor        # Background job processing
├── EventEmitter              # Event system
├── MessageQueue              # Message queuing
├── RealTimeChat              # Complete chat system
├── StreamProcessor           # Stream processing pipeline
└── Utils                     # Utilities and helpers
```

### Data Flow

```
User Input → WebSocket → Agent → Streaming Response → Client
     ↓
Background Jobs → Redis Queue → Worker → Database
     ↓
Events → Event Emitter → Subscribers → Actions
```

## Development

### Setup

```bash
git clone https://github.com/raaf-ai/ruby-ai-agents-factory
cd ruby-ai-agents-factory/streaming
bundle install
```

### Running Tests

```bash
bundle exec rspec
```

### Starting Development Services

```bash
# Start Redis for background processing
docker run -d -p 6379:6379 redis:alpine

# Start development server
ruby examples/streaming_example.rb
```

### Development Tools

```bash
# Start interactive console
irb -r ./lib/raaf-streaming

# Run performance benchmarks
ruby benchmarks/streaming_performance.rb

# Test WebSocket connections
ruby examples/websocket_client_test.rb
```

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Write tests for your changes
4. Ensure all tests pass (`bundle exec rspec`)
5. Follow the coding standards (`bundle exec rubocop`)
6. Commit your changes (`git commit -am 'Add amazing feature'`)
7. Push to the branch (`git push origin feature/amazing-feature`)
8. Open a Pull Request

### Development Guidelines

- Write comprehensive tests for all new features
- Follow Ruby and Rails conventions
- Document all public APIs
- Include examples for complex functionality
- Ensure thread safety for concurrent operations
- Handle errors gracefully with proper fallbacks

## License

This gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Support

- **Documentation**: [https://docs.raaf.ai/streaming](https://docs.raaf.ai/streaming)
- **GitHub Issues**: [https://github.com/raaf-ai/ruby-ai-agents-factory/issues](https://github.com/raaf-ai/ruby-ai-agents-factory/issues)
- **Community Discord**: [https://discord.gg/raaf-ai](https://discord.gg/raaf-ai)
- **Stack Overflow**: Tag questions with `raaf-streaming`

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for detailed version history and updates.