# RAAF Thread Safety Guide

This document outlines the thread safety characteristics of the Ruby AI Agents Factory (RAAF) framework.

## ✅ Thread-Safe Components

### Core Architecture
- **RunExecutor**: Stateless design, safe for concurrent use
- **ModelConfig**: Instance-based configuration, safe when not shared
- **ResponsesProvider**: Creates new instances per request, no shared state
- **Agent**: Read-only operations are thread-safe, instances should not be shared for write operations

### Streaming Components
- **BackgroundProcessor**: Uses `Mutex` for thread-safe shared state management
- **MessageQueue**: Thread-safe with `Mutex` for ID generation and operations
- **BatchTraceProcessor**: Uses `concurrent-ruby` gem for thread-safe data structures

### Tracing System
- **SpanTracer**: Thread-safe span processing with atomic operations
- **Processors**: Individual processors are thread-safe for span processing

## ⚠️ Thread Safety Considerations

### Provider Instances
- Provider instances (OpenAI, Anthropic, etc.) should **NOT** be shared between threads
- Each thread should create its own provider instance
- Instance variables like `@api_key`, `@redis` are not synchronized

### Runner Usage
- **Runner** instances should be used per-thread
- Safe pattern: Create one runner per thread
- Unsafe pattern: Sharing a single runner across threads

### Agent Configuration
- Agent instances are thread-safe for **read operations**
- **Write operations** (adding tools, modifying configuration) should be done before concurrent access
- DSL configuration is now thread-local (see DSL section below)

## 🔧 Implementation Details

### MockProvider (Testing)
**Status**: ✅ **Fixed** - Now thread-safe

The MockProvider class variables are now protected with synchronization:

```ruby
class MockProvider
  # Thread-safe class variables
  @@instances = []
  @@global_responses = {}
  @@class_mutex = Mutex.new

  def self.add_global_response(input, response)
    @@class_mutex.synchronize do
      @@global_responses[input] = response
    end
  end

  def self.instances
    @@class_mutex.synchronize do
      @@instances.dup
    end
  end
end
```

### DSL Configuration
**Status**: ✅ **Fixed** - Now thread-local

DSL configuration is now stored in thread-local storage to prevent race conditions:

```ruby
module AgentDsl
  included do
    # Thread-local storage for DSL configuration
    def self._agent_config
      Thread.current[:raaf_dsl_agent_config] ||= {}
    end

    def self._tools_config
      Thread.current[:raaf_dsl_tools_config] ||= []
    end
    
    # ... similar for other config types
  end
end
```

### Concurrent Data Structures
The framework uses `concurrent-ruby` gem for thread-safe operations:

```ruby
# BatchTraceProcessor uses concurrent data structures
@queue = Concurrent::Array.new
@shutdown = Concurrent::AtomicBoolean.new(false)
@force_flush = Concurrent::Event.new
@last_flush_time = Concurrent::AtomicReference.new(Time.now)
```

## 📋 Best Practices

### 1. Per-Thread Instances
```ruby
# ✅ Good: Each thread gets its own instances
Thread.new do
  agent = RAAF::Agent.new(name: "Worker", instructions: "...")
  provider = RAAF::Models::ResponsesProvider.new
  runner = RAAF::Runner.new(agent: agent, provider: provider)
  
  result = runner.run("Hello")
end
```

### 2. Shared Configuration
```ruby
# ✅ Good: Configure before threading
agent = RAAF::Agent.new(name: "Worker", instructions: "...")
agent.add_tool(my_tool)  # Configure before threading

# Then use read-only in threads
threads = 3.times.map do |i|
  Thread.new do
    runner = RAAF::Runner.new(agent: agent)
    runner.run("Message #{i}")
  end
end
```

### 3. Testing Thread Safety
```ruby
# ✅ Good: Thread-local test setup
RSpec.describe "Thread safety" do
  it "handles concurrent requests" do
    threads = 10.times.map do |i|
      Thread.new do
        provider = RAAF::Testing::MockProvider.new
        provider.add_response("Thread #{i} response")
        
        agent = RAAF::Agent.new(name: "TestAgent")
        runner = RAAF::Runner.new(agent: agent, provider: provider)
        
        runner.run("Test message")
      end
    end
    
    results = threads.map(&:join).map(&:value)
    expect(results).to all(be_a(RAAF::RunResult))
  end
end
```

## 🚨 Anti-Patterns to Avoid

### 1. Sharing Provider Instances
```ruby
# ❌ Bad: Sharing provider between threads
provider = RAAF::Models::ResponsesProvider.new

threads = 5.times.map do
  Thread.new do
    runner = RAAF::Runner.new(agent: agent, provider: provider)  # Unsafe!
    runner.run("Hello")
  end
end
```

### 2. Modifying Agent Configuration Concurrently
```ruby
# ❌ Bad: Modifying agent during concurrent access
agent = RAAF::Agent.new(name: "Shared")

threads = 3.times.map do |i|
  Thread.new do
    agent.add_tool(tool)  # Unsafe concurrent modification!
    runner = RAAF::Runner.new(agent: agent)
    runner.run("Message #{i}")
  end
end
```

### 3. Global State Mutation
```ruby
# ❌ Bad: Mutating global state without synchronization
class MyTool
  @@cache = {}  # Unsafe global state
  
  def execute(params)
    @@cache[params[:key]] = params[:value]  # Race condition!
  end
end
```

## 🔍 Debugging Thread Issues

### 1. Enable Debug Logging
```ruby
# Enable thread-aware logging
RAAF::Logging.configure do |config|
  config.debug_enabled = true
  config.debug_categories = [:threading, :api, :tracing]
end
```

### 2. Thread-Safe Logging
```ruby
# ✅ Good: Thread-safe logging with context
RAAF::Logging.info("Processing request", 
  thread_id: Thread.current.object_id,
  agent_name: agent.name,
  timestamp: Time.current
)
```

### 3. Monitoring Concurrent Operations
```ruby
# Monitor concurrent operations
mutex = Mutex.new
counter = 0

threads = 10.times.map do
  Thread.new do
    mutex.synchronize { counter += 1 }
    # ... agent operations
    mutex.synchronize { counter -= 1 }
  end
end
```

## 🧪 Testing Thread Safety

### Unit Tests
```ruby
RSpec.describe "Thread safety" do
  it "handles concurrent MockProvider operations" do
    threads = 100.times.map do |i|
      Thread.new do
        RAAF::Testing::MockProvider.add_global_response("test_#{i}", "response_#{i}")
      end
    end
    
    threads.each(&:join)
    
    # Should have all responses without data corruption
    expect(RAAF::Testing::MockProvider.instances.size).to eq(100)
  end
end
```

### Integration Tests
```ruby
RSpec.describe "Concurrent agent execution" do
  it "processes multiple requests simultaneously" do
    results = []
    mutex = Mutex.new
    
    threads = 10.times.map do |i|
      Thread.new do
        agent = RAAF::Agent.new(name: "ConcurrentAgent#{i}")
        runner = RAAF::Runner.new(agent: agent)
        result = runner.run("Process #{i}")
        
        mutex.synchronize { results << result }
      end
    end
    
    threads.each(&:join)
    
    expect(results.size).to eq(10)
    expect(results).to all(be_a(RAAF::RunResult))
  end
end
```

## 📈 Performance Considerations

### 1. Thread Pool Usage
```ruby
# Use thread pools for better resource management
require 'concurrent-ruby'

pool = Concurrent::ThreadPoolExecutor.new(
  min_threads: 2,
  max_threads: 10,
  max_queue: 100
)

futures = 100.times.map do |i|
  Concurrent::Future.execute(executor: pool) do
    agent = RAAF::Agent.new(name: "PoolWorker#{i}")
    runner = RAAF::Runner.new(agent: agent)
    runner.run("Task #{i}")
  end
end

results = futures.map(&:value)
```

### 2. Connection Pooling
```ruby
# Use connection pooling for providers
class ThreadSafeProvider
  def initialize
    @connection_pool = Concurrent::Map.new
  end
  
  def get_connection
    thread_id = Thread.current.object_id
    @connection_pool.fetch_or_store(thread_id) do
      RAAF::Models::ResponsesProvider.new
    end
  end
end
```

## 📚 References

- [concurrent-ruby gem](https://github.com/ruby-concurrency/concurrent-ruby) - Thread-safe data structures
- [Ruby Thread Safety](https://ruby-doc.org/core-3.0.0/Thread.html) - Official Ruby documentation
- [RAAF Architecture](./guides/source/architecture_patterns.md) - Framework architecture patterns

## 🔄 Version History

- **v1.0.0**: Initial thread safety implementation
- **v1.1.0**: Added MockProvider synchronization
- **v1.2.0**: Implemented thread-local DSL configuration
- **v1.3.0**: Enhanced tracing thread safety

---

**Note**: This document is updated with each release. Always refer to the latest version for current thread safety guarantees.