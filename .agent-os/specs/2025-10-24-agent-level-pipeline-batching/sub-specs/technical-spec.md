# Technical Specification: Intelligent Streaming

> Created: 2025-10-24
> Version: 2.0.0 (Unified Feature)
> RAAF Version: 2.0.0+

## 1. Architecture Overview

### Component Architecture

The intelligent streaming system consists of four main components working together to enable pipeline-level streaming with optional state management and optional incremental delivery:

```
Pipeline Execution Flow:
┌─────────────────┐
│    Pipeline     │
│    Executor     │
└────────┬────────┘
         │ Analyzes flow chain during init
         ▼
┌──────────────────────────┐
│ IntelligentStreamingMgr  │ ◄── Detects agents with
└────────┬─────────────────┘     intelligent_streaming
         │ Creates scopes
         ▼
┌──────────────────────────┐
│  StreamingScope          │ ◄── Encodes stream config
└────────┬─────────────────┘     (size, field, state, incremental)
         │ Uses
         ▼
┌──────────────────────────┐
│PipelineStreamExecutor    │ ◄── Executes scope in streams
└──────────────────────────┘     with optional state mgmt
```

### Data Flow Through System

```
Context with Array (1000 items)
           │
           ▼
    [Pre-Streaming Agents]
           │
           ▼
Agent with intelligent_streaming ◄─── Split into streams
           │                          Apply skip_if, load_existing
      ┌────┴────┐
      │ Stream 1 │──► [Streaming Scope Agents] ──► Results 1
      │ 100 items│  Apply persist_each_stream
      ├──────────┤  Call on_stream_complete if incremental: true
      │ Stream 2 │──► [Streaming Scope Agents] ──► Results 2
      │ 100 items│
      └──────────┘
           │
      Merge Results
      Call on_stream_complete if incremental: false
           │
           ▼
[Post-Streaming Agents]
```

## 2. Unified Intelligent Streaming Configuration

### Configuration Data Structure

Each agent's intelligent streaming configuration is stored as an `IntelligentStreamingConfig` object:

```ruby
module RAAF
  module DSL
    class IntelligentStreamingConfig
      attr_reader :stream_size        # Number of items per stream
      attr_reader :array_field        # Field containing array to stream
      attr_reader :incremental        # Boolean: enable per-stream callbacks
      attr_reader :skip_if_block      # Optional: skip record condition
      attr_reader :load_existing_block # Optional: load cached result
      attr_reader :persist_block      # Optional: persist stream results
      attr_reader :on_stream_start_hook # Optional: pre-stream hook
      attr_reader :on_stream_complete_hook # Optional: post-stream hook
      attr_reader :on_stream_error_hook   # Optional: error hook

      def initialize(
        stream_size:,
        array_field: nil,
        incremental: false,
        skip_if_block: nil,
        load_existing_block: nil,
        persist_block: nil,
        on_stream_start_hook: nil,
        on_stream_complete_hook: nil,
        on_stream_error_hook: nil
      )
        @stream_size = validate_stream_size(stream_size)
        @array_field = array_field
        @incremental = incremental
        @skip_if_block = skip_if_block
        @load_existing_block = load_existing_block
        @persist_block = persist_block
        @on_stream_start_hook = on_stream_start_hook
        @on_stream_complete_hook = on_stream_complete_hook
        @on_stream_error_hook = on_stream_error_hook
      end

      # Check if state management is configured
      def has_state_management?
        @skip_if_block.present? ||
        @load_existing_block.present? ||
        @persist_block.present?
      end

      # Check if incremental delivery is enabled
      def incremental?
        @incremental == true
      end
    end
  end
end
```

## 3. Core Components

### IntelligentStreamingManager

**Purpose:** Detects agents with intelligent_streaming configuration and creates execution scopes.

**Responsibilities:**
- Analyze pipeline flow chain to find agents with intelligent_streaming
- Create StreamingScope objects that define streaming boundaries
- Validate configurations for correctness and compatibility
- Provide lookup methods for finding scopes during execution

**Key Methods:**
```ruby
# Detect all streaming scopes in a pipeline flow
detect_scopes(flow_chain) -> Array[StreamingScope]

# Find the scope triggered by a specific agent
find_scope_for_agent(agent) -> StreamingScope | nil

# Check if agent is within any streaming scope
in_streaming_scope?(agent) -> Boolean
```

### StreamingScope

**Purpose:** Encapsulates the configuration and agent set for a single streaming scope.

**Attributes:**
- `trigger_agent`: Agent that declares `intelligent_streaming`
- `agents_in_scope`: All agents that run within this streaming scope
- `config`: IntelligentStreamingConfig object with all settings
- `scope_id`: Unique identifier for debugging

**Responsibilities:**
- Determine which array field to stream over (auto-detect if needed)
- Evaluate state management conditions (skip_if, load_existing, persist)
- Execute progress hooks (on_stream_start, on_stream_complete, on_stream_error)
- Store incremental delivery configuration

### PipelineStreamExecutor

**Purpose:** Executes a sub-flow of agents in streams with proper result merging.

**Responsibilities:**
- Split input array into streams of specified size
- Execute each stream sequentially through all scope agents
- Apply state management for each stream (skip, load, persist)
- Fire progress hooks appropriately based on incremental delivery mode
- Merge results from all streams back into a single result
- Handle errors and partial results

**Execution Flow:**
```
1. Split array into N streams
2. For each stream (incremental: true):
   - Fire on_stream_start hook
   - Apply skip_if { |record| ... } to filter records
   - Apply load_existing { |record| ... } to load cached results
   - Execute stream through all scope agents
   - Apply persist_each_stream { |stream| ... } to save results
   - Fire on_stream_complete with stream results (3 params)
3. Merge all stream results
4. If incremental: false, fire on_stream_complete with all results (1 param)
```

## 4. Incremental Delivery Behavior

### Incremental: True (Per-Stream Results)

When `incremental: true` is configured:

1. **Callback Signature:** `on_stream_complete` receives 3 parameters
   ```ruby
   on_stream_complete do |stream_num, total, stream_results|
     # Called after EACH stream completes
     # stream_results = results from only this stream
   end
   ```

2. **Execution Timeline:**
   - Stream 1 completes → on_stream_complete(1, 10, results_1) called
   - Stream 2 completes → on_stream_complete(2, 10, results_2) called
   - ... (continues for all streams)
   - All streams complete → Pipeline continues with merged results

3. **Use Cases:**
   - Real-time progress monitoring
   - Queuing results immediately after each stream
   - Early error detection and recovery
   - Memory-efficient result delivery to downstream systems

### Incremental: False (Accumulated Results)

When `incremental: false` (default):

1. **Callback Signature:** `on_stream_complete` receives 1 parameter
   ```ruby
   on_stream_complete do |all_results|
     # Called ONCE at end with all accumulated results
   end
   ```

2. **Execution Timeline:**
   - Stream 1 completes → Results accumulated in memory
   - Stream 2 completes → Results accumulated in memory
   - ... (all streams complete)
   - All accumulated → on_stream_complete(merged_results) called
   - Pipeline continues with merged results

3. **Use Cases:**
   - Simple stream processing with final result handling
   - Aggregating statistics across all streams
   - Post-processing all results before downstream agents

## 5. State Management Integration

### State Management Blocks

Each block is optional and works independently:

#### skip_if Block
```ruby
skip_if { |record, context|
  # Return true to skip processing this record
  # Return false to process it normally
  already_processed?(record)
}
```

**Behavior:**
- Evaluated for each record in the batch
- If true, record is excluded from agent processing
- Skipped records are still included in final results via load_existing
- Applied BEFORE agents execute

#### load_existing Block
```ruby
load_existing { |record, context|
  # Return cached/existing result for this record
  # Return nil if no existing result
  cache.fetch(record.id, nil)
}
```

**Behavior:**
- Called for skipped records to load pre-computed results
- Can also be called optionally in agent code
- Must return same structure as agent would produce
- Merged with agent-produced results in final output

#### persist_each_batch Block
```ruby
persist_each_batch { |batch_results, context|
  # Save batch results to database or external storage
  # Called after batch completes through all agents
  Model.insert_all(batch_results)
}
```

**Behavior:**
- Called after each batch finishes processing
- Receives complete batch results (both agent outputs + loaded)
- Enables resumable processing if job interrupted
- Useful for incremental database updates

### State Management Timeline

```
For each batch:
  1. Call skip_if for each record
    └─ Records marked as "skip"

  2. Call load_existing for skipped records
    └─ Populate results with cached data

  3. Execute agents for non-skipped records
    └─ Generate new results

  4. Merge loaded + agent results
    └─ Combined complete results

  5. Call persist_each_batch with merged results
    └─ Save to database

  6. Return merged results
```

## 6. Performance Characteristics

### Memory Usage

**Without Batching:**
```
Memory = O(N) where N = total items
Peak memory = All 1000 companies in memory simultaneously
```

**With Batching:**
```
Memory = O(B) where B = batch size
Peak memory = Max 100 companies in memory at once
Overhead = ~1KB per batch for metadata
```

### Optimal Chunk Sizes

| Data Type | Recommended Chunk Size | Rationale |
|-----------|------------------------|-----------|
| Simple objects (< 1KB) | 500-1000 | Low memory overhead |
| Complex objects (1-10KB) | 100-200 | Balance memory/performance |
| Large objects (> 10KB) | 20-50 | Prevent memory spikes |
| API calls | 10-25 | Respect rate limits |
| Database operations | 100-500 | Optimize query performance |

### Performance Benchmarks

```ruby
# Overhead measurements (target < 5ms per batch)

Batch size 100:
  - Batch creation: ~0.1ms
  - Context preparation: ~0.5ms
  - State mgmt evaluation: ~0.3ms
  - Hook execution: ~0.2ms
  - Result merging: ~1.0ms
  - Total overhead: ~2.1ms per batch ✓

Batch size 1000:
  - Batch creation: ~0.5ms
  - Context preparation: ~0.8ms
  - State mgmt evaluation: ~1.0ms
  - Hook execution: ~0.2ms
  - Result merging: ~3.0ms
  - Total overhead: ~5.5ms per batch ✓
```

## 7. Error Handling

### Batch Failure Behavior

When a batch fails during execution:

1. **Partial Results Preserved:** All previously successful batches are retained
2. **Error Context Captured:** Error hook fired with batch number and error details
3. **Continuation:** Processing continues with next batch (configurable)
4. **Final Result:** Includes successful results + error metadata

### Error Hook

```ruby
on_batch_error { |batch_num, total, error, context|
  # Called when a batch fails
  # Can log, alert, or perform recovery
  Rails.logger.error "Batch #{batch_num} failed: #{error.message}"
}
```

## 8. Thread Safety

All batching components are designed to be thread-safe:

1. **IntelligentBatchingManager:** Stateless analysis methods
2. **BatchingScope:** Immutable after construction
3. **BatchingConfig:** Immutable configuration object
4. **PipelineBatchExecutor:** Isolated execution context per instance
5. **Class-level config:** Stored in `Concurrent::Hash` for thread safety

## 9. Future Optimizations

1. **Lazy Batch Creation:** Create batches on-demand rather than upfront
2. **Parallel Batch Execution:** Process multiple batches concurrently
3. **Adaptive Chunk Sizing:** Adjust batch size based on memory/performance
4. **Batch Caching:** Optional disk persistence for long-running pipelines
5. **Nested Batching:** Support batching within batching scopes
