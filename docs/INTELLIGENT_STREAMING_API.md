# Intelligent Streaming API Reference

## Overview

The Intelligent Streaming feature provides pipeline-level streaming with optional state management and incremental delivery for processing large arrays efficiently through multiple agents.

## Table of Contents

1. [Core Classes](#core-classes)
2. [DSL Methods](#dsl-methods)
3. [Configuration Options](#configuration-options)
4. [State Management Methods](#state-management-methods)
5. [Hook Methods](#hook-methods)
6. [Introspection Methods](#introspection-methods)
7. [Error Handling](#error-handling)
8. [Complete API Example](#complete-api-example)

---

## Core Classes

### `RAAF::DSL::IntelligentStreaming::Config`

Immutable configuration object that stores streaming behavior settings.

**Location:** `dsl/lib/raaf/dsl/intelligent_streaming/config.rb`

#### Constructor

```ruby
Config.new(stream_size:, over: nil, incremental: false)
```

**Parameters:**
- `stream_size` (Integer, required) - Number of items to process per stream
- `over` (Symbol, optional) - Field name containing the array to stream. If not specified, auto-detects first array field
- `incremental` (Boolean, optional) - Enable per-stream callbacks (default: `false`)

**Raises:**
- `ArgumentError` - If stream_size is not a positive integer

**Example:**
```ruby
config = RAAF::DSL::IntelligentStreaming::Config.new(
  stream_size: 100,
  over: :companies,
  incremental: true
)
```

#### Instance Methods

| Method | Return Type | Description |
|--------|-------------|-------------|
| `stream_size` | Integer | Number of items per stream |
| `array_field` | Symbol/nil | Field containing array to stream |
| `incremental` | Boolean | Whether incremental mode is enabled |
| `incremental?` | Boolean | Alias for `incremental` |
| `has_state_management?` | Boolean | Returns true if any state management blocks are defined |
| `blocks` | Hash | Hash of all configured blocks (skip_if, load_existing, etc.) |

---

### `RAAF::DSL::IntelligentStreaming::Scope`

Represents a streaming scope within a pipeline - the range of agents that will be executed for each stream.

**Location:** `dsl/lib/raaf/dsl/intelligent_streaming/scope.rb`

#### Constructor

```ruby
Scope.new(trigger_agent:, start_index:, end_index:, agents:)
```

#### Instance Methods

| Method | Return Type | Description |
|--------|-------------|-------------|
| `trigger_agent` | Class | Agent that triggered streaming |
| `start_index` | Integer | Starting position in pipeline |
| `end_index` | Integer | Ending position in pipeline |
| `agents` | Array | Agents in this scope |
| `size` | Integer | Number of agents in scope |

---

### `RAAF::DSL::IntelligentStreaming::Manager`

Manages streaming execution for pipelines.

**Location:** `dsl/lib/raaf/dsl/intelligent_streaming/manager.rb`

#### Instance Methods

| Method | Parameters | Return | Description |
|--------|-----------|--------|-------------|
| `detect_scopes` | `agents` | Array[Scope] | Detects streaming scopes in pipeline |
| `should_stream?` | `scopes` | Boolean | Determines if streaming should occur |
| `execute_with_streaming` | `context, scopes` | ContextVariables | Executes pipeline with streaming |

---

### `RAAF::DSL::IntelligentStreaming::ProgressContext`

Immutable context object passed to progress hooks.

**Location:** `dsl/lib/raaf/dsl/intelligent_streaming/progress_context.rb`

#### Attributes

| Attribute | Type | Description |
|-----------|------|-------------|
| `stream_number` | Integer | Current stream number (1-based) |
| `total_streams` | Integer | Total number of streams |
| `stream_data` | Array | Data for current stream |
| `stream_results` | ContextVariables/nil | Results from stream (only in on_complete) |
| `error` | Exception/nil | Error if stream failed (only in on_error) |

---

## DSL Methods

### `Agent.intelligent_streaming`

Configures intelligent streaming behavior for an agent.

```ruby
intelligent_streaming(stream_size:, over: nil, incremental: false) do
  # Configuration blocks
end
```

**Parameters:**
- `stream_size` (Integer, required) - Number of items per stream
- `over` (Symbol, optional) - Field containing array to stream
- `incremental` (Boolean, optional) - Enable per-stream callbacks

**Configuration Blocks:**
- `skip_if { |record| }` - Skip record condition
- `load_existing { |record| }` - Load cached result
- `persist_each_stream { |results| }` - Save results after each stream
- `on_stream_start { |stream_num, total, data| }` - Stream start hook
- `on_stream_complete { |stream_num, total, data, results| }` - Stream complete hook
- `on_stream_error { |stream_num, total, data, error| }` - Error hook

**Example:**
```ruby
class MyAgent < RAAF::DSL::Agent
  intelligent_streaming stream_size: 100, incremental: true do
    skip_if { |record| record[:processed] }

    load_existing { |record|
      Cache.get(record[:id])
    }

    persist_each_stream { |results|
      Database.insert_all(results)
    }

    on_stream_start { |stream_num, total, data|
      Rails.logger.info "Starting stream #{stream_num}/#{total}"
    }

    on_stream_complete { |stream_num, total, data, results|
      Rails.logger.info "Completed stream #{stream_num}/#{total}"
      BackgroundJob.enqueue(results)
    }

    on_stream_error { |stream_num, total, data, error|
      Rails.logger.error "Stream #{stream_num} failed: #{error}"
    }
  end
end
```

---

## Configuration Options

### Stream Size Selection Guide

| Use Case | Recommended Size | Example |
|----------|-----------------|---------|
| Simple objects in memory | 500-1000 | `stream_size: 1000` |
| API calls with rate limits | 10-25 | `stream_size: 20` |
| Database batch operations | 100-500 | `stream_size: 200` |
| Large JSON objects | 20-50 | `stream_size: 30` |
| Memory-constrained environment | 50-100 | `stream_size: 50` |

### Incremental Mode

When `incremental: true`:
- Callbacks fire after each stream completes
- Results available immediately for downstream processing
- Useful for progress monitoring and partial result handling

When `incremental: false` (default):
- Only final result available
- Lower overhead
- Simpler execution model

---

## State Management Methods

### `skip_if`

Determines whether a record should be skipped.

```ruby
skip_if do |record|
  # Return true to skip this record
  ProcessedRecords.exists?(id: record[:id])
end
```

**Parameters:**
- `record` - Individual record from the array

**Returns:**
- Boolean - true to skip, false to process

### `load_existing`

Loads cached/existing results instead of reprocessing.

```ruby
load_existing do |record|
  # Return existing result or nil to process
  cached = RedisCache.get("result:#{record[:id]}")
  cached ? JSON.parse(cached) : nil
end
```

**Parameters:**
- `record` - Individual record from the array

**Returns:**
- Object/nil - Existing result or nil to process normally

### `persist_each_stream`

Saves results after each stream completes.

```ruby
persist_each_stream do |results|
  # Save results to database or cache
  BulkInsert.insert_all(results)
  Rails.logger.info "Saved #{results.count} records"
end
```

**Parameters:**
- `results` - Array of results from the completed stream

**Returns:**
- Any (return value ignored)

---

## Hook Methods

### `on_stream_start`

Called before each stream begins processing.

```ruby
on_stream_start do |stream_num, total_streams, stream_data|
  Rails.logger.info "Starting stream #{stream_num} of #{total_streams}"
  Rails.logger.info "Processing #{stream_data.count} items"
end
```

**Parameters:**
- `stream_num` (Integer) - Current stream number (1-based)
- `total_streams` (Integer) - Total number of streams
- `stream_data` (Array) - Data for this stream

### `on_stream_complete`

Called after each stream completes successfully.

```ruby
on_stream_complete do |stream_num, total_streams, stream_data, stream_results|
  Rails.logger.info "Completed stream #{stream_num} of #{total_streams}"

  # Access results
  processed_count = stream_results[:processed_items].count

  # Trigger side effects
  NotificationService.send_progress(stream_num, total_streams)
  EnrichmentQueue.enqueue(stream_results[:companies])
end
```

**Parameters:**
- `stream_num` (Integer) - Current stream number (1-based)
- `total_streams` (Integer) - Total number of streams
- `stream_data` (Array) - Original data for this stream
- `stream_results` (ContextVariables) - Results from stream processing

### `on_stream_error`

Called when a stream encounters an error.

```ruby
on_stream_error do |stream_num, total_streams, stream_data, error|
  Rails.logger.error "Stream #{stream_num} failed: #{error.message}"
  Rails.logger.error error.backtrace.join("\n")

  # Report to error tracking
  Sentry.capture_exception(error, extra: {
    stream_num: stream_num,
    total_streams: total_streams,
    data_count: stream_data.count
  })

  # Could implement retry logic here
  RetryQueue.add(stream_data) if error.is_a?(NetworkError)
end
```

**Parameters:**
- `stream_num` (Integer) - Current stream number (1-based)
- `total_streams` (Integer) - Total number of streams
- `stream_data` (Array) - Data that failed to process
- `error` (Exception) - The error that occurred

---

## Introspection Methods

### Class-level Methods

```ruby
# Check if agent has streaming configured
MyAgent.streaming_config?  # => true/false

# Get streaming configuration
config = MyAgent.streaming_config
config.stream_size  # => 100
config.array_field  # => :companies
config.incremental?  # => true

# Check if agent will trigger streaming
MyAgent.streaming_trigger?  # => true/false
```

### Instance-level Methods

```ruby
agent = MyAgent.new

# Access configuration
agent.class.streaming_config

# Check state
agent.class.streaming_config.has_state_management?  # => true/false
```

---

## Error Handling

### Error Recovery Patterns

```ruby
class ResilientAgent < RAAF::DSL::Agent
  intelligent_streaming stream_size: 50 do
    on_stream_error do |stream_num, total, data, error|
      case error
      when NetworkError
        # Retry with exponential backoff
        retry_with_backoff(data, attempt: stream_num)
      when ValidationError
        # Log and continue
        Rails.logger.warn "Validation failed for stream #{stream_num}"
        # Partial results still processed
      else
        # Re-raise for critical errors
        raise error
      end
    end
  end

  private

  def retry_with_backoff(data, attempt:)
    delay = 2 ** attempt
    Rails.logger.info "Retrying stream in #{delay} seconds..."
    sleep(delay)
    # Re-process data
  end
end
```

### Partial Failure Handling

```ruby
intelligent_streaming stream_size: 100 do
  on_stream_complete do |stream_num, total, data, results|
    successful = results[:items].select { |i| i[:success] }
    failed = results[:items].reject { |i| i[:success] }

    if failed.any?
      FailureQueue.add(failed)
      Rails.logger.warn "Stream #{stream_num}: #{failed.count} items failed"
    end

    # Process successful items
    persist_successful(successful) if successful.any?
  end
end
```

---

## Complete API Example

Here's a comprehensive example using all API features:

```ruby
module AI
  module Agents
    class ComprehensiveStreamingAgent < RAAF::DSL::Agent
      agent_name "ComprehensiveStreamingAgent"
      model "gpt-4o-mini"

      # Configure streaming with all options
      intelligent_streaming stream_size: 25, over: :items, incremental: true do
        # State Management
        skip_if do |record|
          # Skip if already processed in last 24 hours
          last_processed = ProcessingLog.find_by(item_id: record[:id])
          last_processed && last_processed.created_at > 24.hours.ago
        end

        load_existing do |record|
          # Try to load from cache first
          cached = Rails.cache.read("processed_item_#{record[:id]}")
          if cached
            Rails.logger.info "✅ Loaded cached result for item #{record[:id]}"
            cached
          else
            nil  # Process normally
          end
        end

        persist_each_stream do |results|
          # Bulk insert to database
          ProcessedItem.insert_all(
            results.map do |result|
              {
                item_id: result[:id],
                data: result.to_json,
                processed_at: Time.current,
                created_at: Time.current,
                updated_at: Time.current
              }
            end
          )

          # Update cache
          results.each do |result|
            Rails.cache.write(
              "processed_item_#{result[:id]}",
              result,
              expires_in: 24.hours
            )
          end
        end

        # Progress Hooks
        on_stream_start do |stream_num, total_streams, stream_data|
          Rails.logger.info "🚀 Starting stream #{stream_num}/#{total_streams}"
          Rails.logger.info "📊 Processing #{stream_data.count} items"

          # Track metrics
          StatsD.increment("streaming.stream_started")
          StatsD.gauge("streaming.stream_size", stream_data.count)
        end

        on_stream_complete do |stream_num, total_streams, stream_data, stream_results|
          Rails.logger.info "✅ Completed stream #{stream_num}/#{total_streams}"

          # Extract metrics
          processed_count = stream_results[:processed_items]&.count || 0
          success_rate = stream_results[:success_rate] || 0.0

          # Log performance
          Rails.logger.info "📈 Processed: #{processed_count}, Success rate: #{success_rate}%"

          # Update progress in UI
          ActionCable.server.broadcast(
            "processing_channel",
            {
              type: "progress_update",
              stream: stream_num,
              total: total_streams,
              processed: processed_count,
              success_rate: success_rate
            }
          )

          # Trigger downstream processing
          if success_rate > 80
            EnrichmentJob.perform_async(stream_results[:successful_items])
          end

          # Record metrics
          StatsD.increment("streaming.stream_completed")
          StatsD.timing("streaming.success_rate", success_rate)
        end

        on_stream_error do |stream_num, total_streams, stream_data, error|
          Rails.logger.error "❌ Stream #{stream_num}/#{total_streams} failed"
          Rails.logger.error "Error: #{error.class.name} - #{error.message}"
          Rails.logger.error error.backtrace.first(10).join("\n")

          # Track error metrics
          StatsD.increment("streaming.stream_failed")
          StatsD.increment("streaming.errors.#{error.class.name}")

          # Report to error tracking
          Bugsnag.notify(error) do |report|
            report.add_metadata(:streaming, {
              stream_number: stream_num,
              total_streams: total_streams,
              items_count: stream_data.count,
              sample_item: stream_data.first
            })
          end

          # Implement retry logic
          if stream_num <= 3  # Retry first 3 streams
            RetryJob.perform_in(5.minutes, stream_data)
          else
            # Add to dead letter queue
            DeadLetterQueue.add(
              type: "streaming_failure",
              stream: stream_num,
              data: stream_data,
              error: error.message
            )
          end
        end
      end

      # Agent schema
      schema do
        field :processed_items, type: :array, required: true do
          field :id, type: :integer, required: true
          field :status, type: :string, required: true
          field :result, type: :object, required: true
        end
        field :success_rate, type: :number, required: true
        field :successful_items, type: :array, required: true
      end

      # Standard agent logic
      def call
        # This will be called for each stream
        # Context automatically includes the streamed data
        super
      end
    end
  end
end

# Usage in a pipeline
class DataProcessingPipeline < RAAF::Pipeline
  flow DataLoader >> ComprehensiveStreamingAgent >> ResultAggregator

  context do
    required :data_source
    optional batch_id: SecureRandom.uuid
  end
end

# Execute pipeline
pipeline = DataProcessingPipeline.new(
  data_source: "production_db"
)

# Will automatically stream if DataLoader returns large array
result = pipeline.run
```

---

## Performance Considerations

### Memory Usage

Memory usage is bounded by `O(stream_size * object_size)`:

```ruby
# Memory-efficient configuration
intelligent_streaming stream_size: 50 do  # Small streams
  persist_each_stream { |results|
    # Write to disk/database immediately
    File.write("stream_#{stream_num}.json", results.to_json)
    results = nil  # Allow garbage collection
  }
end
```

### Throughput Optimization

```ruby
# Optimize for throughput
intelligent_streaming stream_size: 500 do  # Larger streams
  # Minimal state management for speed
  on_stream_complete do |num, total, data, results|
    # Async processing
    ProcessingJob.perform_async(results)
  end
end
```

### Cost Optimization

```ruby
# Use cheap model for filtering
class FilterAgent < RAAF::DSL::Agent
  model "gpt-4o-mini"  # $0.001 per call

  intelligent_streaming stream_size: 200 do
    on_stream_complete do |num, total, data, results|
      # Only pass good candidates to expensive model
      good_candidates = results.select { |r| r[:score] > 70 }
      ExpensiveAnalysis.process(good_candidates)
    end
  end
end
```

---

## Testing Intelligent Streaming

### RSpec Examples

```ruby
RSpec.describe MyStreamingAgent do
  let(:agent) { described_class.new }

  describe "streaming configuration" do
    it "has correct stream size" do
      expect(described_class.streaming_config.stream_size).to eq(100)
    end

    it "has state management configured" do
      expect(described_class.streaming_config.has_state_management?).to be true
    end

    it "triggers streaming" do
      expect(described_class.streaming_trigger?).to be true
    end
  end

  describe "state management" do
    it "skips processed records" do
      create(:processed_record, item_id: 123)

      config = described_class.streaming_config
      skip_block = config.blocks[:skip_if]

      expect(skip_block.call({ id: 123 })).to be true
      expect(skip_block.call({ id: 456 })).to be false
    end

    it "loads existing results from cache" do
      Rails.cache.write("result_123", { data: "cached" })

      config = described_class.streaming_config
      load_block = config.blocks[:load_existing]

      expect(load_block.call({ id: 123 })).to eq({ data: "cached" })
      expect(load_block.call({ id: 456 })).to be_nil
    end
  end

  describe "progress hooks" do
    it "calls on_stream_complete with results" do
      config = described_class.streaming_config
      complete_block = config.blocks[:on_stream_complete]

      expect(BackgroundJob).to receive(:enqueue).with(["result1", "result2"])

      complete_block.call(1, 5, ["item1", "item2"], {
        results: ["result1", "result2"]
      })
    end
  end
end
```

---

## Migration Checklist

When migrating to intelligent streaming:

- [ ] Identify large array processing in your pipelines
- [ ] Choose appropriate `stream_size` based on data characteristics
- [ ] Decide if you need state management (skip/load/persist)
- [ ] Determine if incremental delivery would benefit your use case
- [ ] Add progress hooks for monitoring
- [ ] Implement error handling for partial failures
- [ ] Test with small datasets first
- [ ] Monitor memory usage and performance
- [ ] Document streaming configuration for team

---

## Related Documentation

- [Pipeline DSL Guide](PIPELINE_DSL_GUIDE.md) - Complete pipeline documentation
- [Migration Guide](INTELLIGENT_STREAMING_MIGRATION.md) - When and how to migrate
- [Examples](examples/intelligent_streaming/) - Working code examples
- [Performance Guide](PERFORMANCE_GUIDE.md) - Optimization strategies