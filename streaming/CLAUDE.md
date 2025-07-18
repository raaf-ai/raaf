# RAAF Streaming - Claude Code Guide

This gem provides real-time streaming and asynchronous capabilities for RAAF agents.

## Quick Start

```ruby
require 'raaf-streaming'

# Streaming agent responses
agent = RAAF::Agent.new(
  name: "StreamingAgent",
  instructions: "Respond in real-time",
  model: "gpt-4o"
)

runner = RAAF::Streaming::Runner.new(agent: agent)

# Stream response chunks
runner.run("Tell me a story") do |chunk|
  print chunk[:content]
end
```

## Core Components

- **StreamingRunner** - Real-time response streaming
- **AsyncRunner** - Background agent processing
- **WebSocketServer** - Real-time WebSocket connections
- **WebSocketClient** - Client-side WebSocket handling
- **EventEmitter** - Event-driven response handling

## Streaming Responses

```ruby
# Basic streaming
streaming_runner = RAAF::Streaming::Runner.new(agent: agent)

streaming_runner.run("Write a long story") do |chunk|
  case chunk[:type]
  when :content
    print chunk[:content]
  when :tool_call
    puts "\n[Using tool: #{chunk[:tool_name]}]"
  when :complete
    puts "\n[Response complete]"
  end
end
```

## Async Processing

```ruby
# Background processing
async_runner = RAAF::Streaming::AsyncRunner.new(agent: agent)

# Start async task
task = async_runner.run_async("Analyze this large dataset")

# Check status
puts "Status: #{task.status}"  # :pending, :running, :completed, :failed

# Get result when ready
result = task.wait_for_completion(timeout: 60)
puts result.messages.last[:content]
```

## WebSocket Integration

### Server Setup
```ruby
# Start WebSocket server
server = RAAF::Streaming::WebSocketServer.new(port: 8080)

server.on_connection do |client|
  puts "Client connected: #{client.id}"
  
  client.on_message do |message|
    agent = RAAF::Agent.new(
      name: "ChatAgent", 
      instructions: "Be helpful"
    )
    
    runner = RAAF::Streaming::Runner.new(agent: agent)
    
    runner.run(message) do |chunk|
      client.send_message(chunk)
    end
  end
end

server.start
```

### Client Usage
```ruby
# WebSocket client
client = RAAF::Streaming::WebSocketClient.new("ws://localhost:8080")

client.connect do
  client.send_message("Hello, how are you?")
  
  client.on_message do |chunk|
    print chunk[:content] if chunk[:type] == :content
  end
end
```

## Event-Driven Architecture

```ruby
# Event emitter for custom handling
emitter = RAAF::Streaming::EventEmitter.new

emitter.on(:start) { puts "Agent started" }
emitter.on(:chunk) { |chunk| print chunk[:content] }
emitter.on(:tool_call) { |tool| puts "\nUsing: #{tool[:name]}" }
emitter.on(:complete) { puts "\nDone!" }

runner = RAAF::Streaming::Runner.new(agent: agent, emitter: emitter)
runner.run("Tell me about Ruby")
```

## Batch Processing

```ruby
# Process multiple requests concurrently
batch_processor = RAAF::Streaming::BatchProcessor.new(
  agent: agent,
  max_concurrent: 5
)

requests = [
  "Summarize this article",
  "Translate to Spanish", 
  "Find related topics"
]

# Process all requests in parallel
results = batch_processor.process_batch(requests) do |request, response|
  puts "Completed: #{request}"
end
```

## Real-Time Chat

```ruby
# Real-time chat interface
chat = RAAF::Streaming::RealTimeChat.new do |config|
  config.agent = agent
  config.enable_typing_indicators = true
  config.response_delay = 0.1  # seconds between chunks
  config.max_message_length = 4000
end

# Simulate typing and stream response
chat.send_message("What's the weather like?") do |event|
  case event[:type]
  when :typing_start
    puts "[Agent is typing...]"
  when :content
    print event[:content]
  when :typing_stop
    puts "\n[Agent finished]"
  end
end
```

## Message Queue Integration

```ruby
# Background message processing
queue = RAAF::Streaming::MessageQueue.new do |config|
  config.backend = :redis  # or :memory, :sidekiq
  config.redis_url = ENV['REDIS_URL']
  config.queue_name = "agent_messages"
end

# Enqueue message for processing
queue.enqueue(
  message: "Process this in background",
  agent_config: { name: "BackgroundAgent" },
  callback_url: "https://myapp.com/webhook"
)

# Process queue
queue.process do |job|
  agent = RAAF::Agent.new(job[:agent_config])
  runner = RAAF::Runner.new(agent: agent)
  result = runner.run(job[:message])
  
  # Send result to callback
  HTTP.post(job[:callback_url], json: result.to_h)
end
```

## Performance Options

```ruby
# Configure streaming performance
RAAF::Streaming.configure do |config|
  config.chunk_size = 50          # characters per chunk
  config.chunk_delay = 0.05       # seconds between chunks
  config.buffer_size = 1024       # bytes
  config.max_connections = 100    # WebSocket connections
  config.heartbeat_interval = 30  # seconds
end
```

## Error Handling

```ruby
runner = RAAF::Streaming::Runner.new(agent: agent)

runner.run("Hello") do |chunk|
  print chunk[:content]
rescue RAAF::Streaming::ConnectionError => e
  puts "Connection lost: #{e.message}"
  # Attempt reconnection
rescue RAAF::Streaming::TimeoutError => e
  puts "Response timeout: #{e.message}"
  # Handle timeout
end
```