# API Specification: Intelligent Streaming

> Created: 2025-10-24
> Version: 2.0.0 (Unified Feature)
> RAAF Version: 2.0.0+

## 1. Agent Class Method: `intelligent_streaming`

**Purpose:** Declares intelligent streaming with optional state management and optional incremental delivery.

```ruby
def self.intelligent_streaming(stream_size:, over: nil, incremental: false, &block)
```

### Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `stream_size` | Integer | Yes | - | Number of items per stream. Must be positive. |
| `over` | Symbol | No | nil | Field name containing array to stream. Auto-detected if not specified. |
| `incremental` | Boolean | No | false | Enable incremental delivery (results available per stream). |
| `&block` | Proc | No | nil | Configuration block for state management and hooks. |

### Return Value

Returns `nil`. Configuration is stored internally in the agent class.

### Behavior

- Sets up intelligent batching configuration on the agent class
- Can only be called once per agent class
- Configuration is inherited by subclasses but can be overridden
- Raises `ConfigurationError` if called multiple times without `override: true`
- Raises `ConfigurationError` if `batch_size` is not a positive integer

### Examples

#### Example 1: Simple Pipeline Streaming (No State Management)

```ruby
class QuickFitAnalyzer < ApplicationAgent
  agent_name "QuickFitAnalyzer"
  model "gpt-4o-mini"

  # Simple streaming: Process 100 items at a time through pipeline
  intelligent_streaming stream_size: 100, over: :companies
end

# Usage in pipeline:
class ProspectPipeline < RAAF::Pipeline
  flow CompanyDiscovery >> QuickFitAnalyzer >> DeepIntel >> Scoring

  # Execution:
  # - CompanyDiscovery returns 1000 companies
  # - QuickFitAnalyzer triggers streaming (100 per stream)
  # - Streams 1-10 flow through DeepIntel
  # - Scoring receives all 1000 merged results
end
```

#### Example 2: With Incremental Delivery

```ruby
class QuickFitAnalyzer < ApplicationAgent
  intelligent_streaming stream_size: 100, over: :companies, incremental: true do
    on_stream_complete do |stream_num, total, stream_results|
      # Called after EACH stream (not at end)
      Rails.logger.info "✅ Stream #{stream_num}/#{total}: #{stream_results.size} prospects"

      # Can process results immediately
      EnrichmentQueue.enqueue(stream_results)
    end
  end
end

# Timeline:
# Stream 1 complete (t=5s)  → on_stream_complete called → Enqueued to queue ✅
# Stream 2 complete (t=10s) → on_stream_complete called → Enqueued to queue ✅
# ...
# Stream 10 complete (t=50s) → on_stream_complete called → Enqueued to queue ✅
# Pipeline returns with summary
```

#### Example 3: With State Management (Skip, Load, Persist)

```ruby
class QuickFitAnalyzer < ApplicationAgent
  intelligent_streaming stream_size: 100, over: :companies do
    # Skip records already processed
    skip_if { |record, context|
      Prospect.exists?(company_id: record[:id])
    }

    # Load existing results instead of reprocessing
    load_existing { |record, context|
      Prospect.find_by(company_id: record[:id]).quick_analysis_data
    }

    # Persist stream results after processing
    persist_each_stream { |stream_results, context|
      Prospect.insert_all(batch_results)
    end
  end
end

# Execution:
# Input: [1000 companies], 700 already processed, 300 new
#
# For each batch (100 items):
#   - 70 items skipped → load_existing called → loaded from DB
#   - 30 items processed → passed to agent
#   - Results merged: 70 loaded + 30 new = 100 total
#   - persist_each_batch called → saved to DB
#   - Next batch
#
# After all 10 batches: 1000 total results (700 cached + 300 new)
```

#### Example 4: Combined - Streaming + State Management

```ruby
class QuickFitAnalyzer < ApplicationAgent
  intelligent_batching batch_size: 100, over: :companies, streaming: true do
    # Skip already-processed
    skip_if { |record| Prospect.exists?(company_id: record[:id]) }

    # Load existing
    load_existing { |record| Prospect.find_by(company_id: record[:id]).data }

    # Persist each batch
    persist_each_batch { |batch| Prospect.insert_all(batch) }

    # Progress tracking (called after each batch)
    on_batch_complete do |batch_num, total, results|
      progress_pct = (batch_num * 100 / total).round
      Rails.logger.info "#{progress_pct}% - Batch #{batch_num}/#{total} saved (#{results.size} items)"

      # Update real-time dashboard
      BroadcastProgress.call("batch_#{batch_num}_complete", progress_pct)
    end
  end
end

# Timeline with streaming + state management:
# Batch 1 (100 items):
#   - 70 skipped + 30 processed = 100 results
#   - Persisted to DB
#   - on_batch_complete called with 100 results ← Incremental result ✅
#   - Dashboard updated with 10% progress ✅
#
# Batch 2-9: Same pattern
#
# Batch 10: Same pattern
#   - on_batch_complete called with final 100 results ← Last incremental result ✅
#   - Dashboard updated with 100% progress ✅
```

#### Example 5: Auto-Detection of Array Field

```ruby
class DataProcessor < ApplicationAgent
  # Will auto-detect the array field from context
  # (defaults to first array field found)
  intelligent_batching batch_size: 50
end
```

#### Example 6: With Progress Hooks

```ruby
class AnalysisAgent < ApplicationAgent
  intelligent_batching batch_size: 100, over: :items, streaming: true do
    on_batch_start do |batch_num, total, context|
      Rails.logger.info "🔄 Starting batch #{batch_num}/#{total}"
    end

    on_batch_complete do |batch_num, total, results|
      Rails.logger.info "✅ Completed batch #{batch_num}/#{total} (#{results.size} items)"
    end

    on_batch_error do |batch_num, total, error, context|
      Rails.logger.error "❌ Batch #{batch_num} failed: #{error.message}"
      # Note: Error doesn't lose previous batch results
    end
  end
end
```

#### Example 7: Error Cases

```ruby
# ERROR: Cannot call twice
class BadAgent < ApplicationAgent
  intelligent_batching batch_size: 100
  intelligent_batching batch_size: 200  # Raises ConfigurationError
end

# ERROR: Invalid batch size
class BadAgent2 < ApplicationAgent
  intelligent_batching batch_size: 0     # Raises ConfigurationError
  intelligent_batching batch_size: -10   # Raises ConfigurationError
  intelligent_batching batch_size: "100" # Raises ConfigurationError
end

# ERROR: Invalid configuration
class BadAgent3 < ApplicationAgent
  intelligent_batching batch_size: 100 do
    skip_if { |record| }  # OK: optional
    load_existing { }     # OK: optional

    invalid_option true   # ERROR: Unknown option
  end
end
```

---

### ends_batching

**Purpose:** Declares that this agent ends the current batching scope, causing results from all batches to be merged before continuing.

```ruby
def self.ends_batching
```

#### Parameters

None.

#### Return Value

Returns `nil`. Configuration is stored internally in the agent class.

#### Behavior

- Marks the agent as a batching terminator
- Must be paired with a `triggers_batching` agent earlier in the pipeline
- Cannot be called on an agent that also has `triggers_batching`
- Configuration is inherited by subclasses

#### Examples

**Basic Usage:**
```ruby
class ScoringAgent < ApplicationAgent
  agent_name "ScoringAgent"
  model "gpt-4o"

  # This agent receives merged results from all batches
  ends_batching
end
```

**Complete Scope Definition:**
```ruby
# Start of batching scope
class QuickFitAnalyzer < ApplicationAgent
  triggers_batching chunk_size: 100, over: :companies
end

# Intermediate agents (implicitly in scope)
class DeepIntelligence < ApplicationAgent
  # Processes batches of companies
end

class Enrichment < ApplicationAgent
  # Also processes batches
end

# End of batching scope
class FinalScoring < ApplicationAgent
  ends_batching  # Receives all merged results
end

# Pipeline definition
class ProspectPipeline < RAAF::Pipeline
  flow CompanyDiscovery >>
       QuickFitAnalyzer >>   # Starts batching
       DeepIntelligence >>   # In batching scope
       Enrichment >>         # In batching scope
       FinalScoring >>       # Ends batching
       ReportGenerator       # After batching scope
end
```

**Error Cases:**
```ruby
# ERROR: Cannot have both triggers and ends
class ConflictingAgent < ApplicationAgent
  triggers_batching chunk_size: 100
  ends_batching  # Raises ConfigurationError
end
```

---

### batching_config (Reader)

**Purpose:** Returns the batching configuration for the agent class, if any.

```ruby
def self.batching_config
```

#### Return Value

Returns a hash with batching configuration, or `nil` if no batching is configured.

**Configuration Structure:**
```ruby
{
  triggers: {
    chunk_size: 100,
    field: :companies,
    hooks: {
      on_start: #<Proc>,
      on_complete: #<Proc>,
      on_error: #<Proc>
    }
  },
  ends: true  # Only if ends_batching was called
}
```

#### Examples

```ruby
class MyAgent < ApplicationAgent
  triggers_batching chunk_size: 100, over: :items

  on_batch_start do |n, t, c|
    puts "Batch #{n}/#{t}"
  end
end

# Inspect configuration
config = MyAgent.batching_config
puts config[:triggers][:chunk_size]  # => 100
puts config[:triggers][:field]       # => :items
puts config[:triggers][:hooks].keys  # => [:on_start]
```

---

### batching_trigger?

**Purpose:** Check if this agent triggers batching.

```ruby
def self.batching_trigger?
```

#### Return Value

Returns `true` if agent has `triggers_batching` configured, `false` otherwise.

#### Example

```ruby
class TriggerAgent < ApplicationAgent
  triggers_batching chunk_size: 100
end

class NormalAgent < ApplicationAgent
end

TriggerAgent.batching_trigger?  # => true
NormalAgent.batching_trigger?    # => false
```

---

### batching_terminator?

**Purpose:** Check if this agent ends batching.

```ruby
def self.batching_terminator?
```

#### Return Value

Returns `true` if agent has `ends_batching` configured, `false` otherwise.

#### Example

```ruby
class EndingAgent < ApplicationAgent
  ends_batching
end

EndingAgent.batching_terminator?  # => true
```

---

## 2. Hook Methods

### on_batch_start

**Purpose:** Register a callback to be executed before each batch begins processing.

```ruby
def self.on_batch_start(&block)
```

#### Block Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `batch_num` | Integer | Current batch number (1-indexed) |
| `total_batches` | Integer | Total number of batches |
| `context` | Hash | Current context with batch data |

#### Execution Context

- Called before the trigger agent processes each batch
- Has read-only access to context (modifications won't affect execution)
- Exceptions in hook are logged but don't halt execution

#### Examples

**Progress Tracking:**
```ruby
class AnalysisAgent < ApplicationAgent
  triggers_batching chunk_size: 100

  on_batch_start do |batch_num, total_batches, context|
    progress = (batch_num.to_f / total_batches * 100).round(1)
    Rails.logger.info "[BATCH] Starting #{batch_num}/#{total_batches} (#{progress}%)"

    # Update database or cache
    BatchProgress.create!(
      pipeline_run_id: context[:pipeline_run_id],
      batch_number: batch_num,
      total_batches: total_batches,
      status: 'started',
      started_at: Time.current
    )
  end
end
```

**Performance Monitoring:**
```ruby
on_batch_start do |batch_num, total, context|
  @batch_start_times ||= {}
  @batch_start_times[batch_num] = Time.now

  # Monitor memory usage
  memory = `ps -o rss= -p #{Process.pid}`.to_i / 1024
  Rails.logger.info "Batch #{batch_num} starting, Memory: #{memory}MB"
end
```

---

### on_batch_complete

**Purpose:** Register a callback to be executed after each batch completes processing.

```ruby
def self.on_batch_complete(&block)
```

#### Block Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `batch_num` | Integer | Current batch number (1-indexed) |
| `total_batches` | Integer | Total number of batches |
| `result` | Hash | Results from this batch |

#### Execution Context

- Called after the ending agent completes processing the batch
- Has access to batch results before merging
- Can be used for incremental result processing

#### Examples

**Result Streaming:**
```ruby
class ProcessingAgent < ApplicationAgent
  triggers_batching chunk_size: 50

  on_batch_complete do |batch_num, total_batches, result|
    # Stream results to client or queue
    ActionCable.server.broadcast(
      "pipeline_#{context[:pipeline_run_id]}",
      {
        event: 'batch_complete',
        batch: batch_num,
        total: total_batches,
        items_processed: result[:companies]&.size || 0,
        partial_results: result[:companies]
      }
    )
  end
end
```

**Duration Tracking:**
```ruby
on_batch_complete do |batch_num, total, result|
  if @batch_start_times && @batch_start_times[batch_num]
    duration = Time.now - @batch_start_times[batch_num]
    Rails.logger.info "Batch #{batch_num} completed in #{duration.round(2)}s"

    # Store metrics
    Metric.create!(
      name: 'batch_duration',
      value: duration,
      metadata: {
        batch_number: batch_num,
        items_processed: result[:companies]&.size
      }
    )
  end
end
```

---

### on_batch_error

**Purpose:** Register a callback to be executed when a batch encounters an error.

```ruby
def self.on_batch_error(&block)
```

#### Block Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `batch_num` | Integer | Batch that failed (1-indexed) |
| `total_batches` | Integer | Total number of batches |
| `error` | Exception | The error that occurred |

#### Execution Context

- Called when any agent in the batching scope raises an exception
- Pipeline may continue with remaining batches (configurable)
- Can be used for error tracking and alerting

#### Examples

**Error Notification:**
```ruby
class CriticalAgent < ApplicationAgent
  triggers_batching chunk_size: 100

  on_batch_error do |batch_num, total, error|
    Rails.logger.error "Batch #{batch_num}/#{total} failed: #{error.message}"
    Rails.logger.error error.backtrace.join("\n")

    # Send alert
    ErrorNotifier.notify(
      title: "Batch Processing Failed",
      message: "Batch #{batch_num}/#{total} failed in #{self.name}",
      error: error,
      metadata: {
        pipeline_id: context[:pipeline_run_id],
        batch_number: batch_num
      }
    )

    # Mark batch as failed
    BatchProgress.where(
      pipeline_run_id: context[:pipeline_run_id],
      batch_number: batch_num
    ).update!(
      status: 'failed',
      error_message: error.message,
      failed_at: Time.current
    )
  end
end
```

---

## 3. BatchingScope Public API

### Constructor

```ruby
def initialize(trigger_agent:, ending_agent:, chunk_size:, array_field: nil)
```

#### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `trigger_agent` | Agent | Yes | Agent that starts batching |
| `ending_agent` | Agent | Yes | Agent that ends batching |
| `chunk_size` | Integer | Yes | Items per batch |
| `array_field` | Symbol | No | Field to batch over |

---

### Public Methods

#### add_agent

```ruby
def add_agent(agent)
```

Adds an agent to the batching scope (between trigger and ending).

**Parameters:**
- `agent` - Agent instance to add to scope

**Returns:** nil

---

#### includes_agent?

```ruby
def includes_agent?(agent)
```

Checks if an agent is part of this batching scope.

**Parameters:**
- `agent` - Agent instance to check

**Returns:** Boolean

---

#### should_end?

```ruby
def should_end?(agent)
```

Checks if this agent ends the batching scope.

**Parameters:**
- `agent` - Agent instance to check

**Returns:** Boolean

---

#### detect_array_field

```ruby
def detect_array_field(context)
```

Auto-detects the array field from context if not specified.

**Parameters:**
- `context` - Context hash

**Returns:** Symbol (field name)

**Raises:** ConfigurationError if detection fails

---

#### get_array_from_context

```ruby
def get_array_from_context(context)
```

Extracts the array to batch from context.

**Parameters:**
- `context` - Context hash

**Returns:** Array

**Raises:** ExecutionError if field is not an array

---

#### valid?

```ruby
def valid?
```

Validates the batching scope configuration.

**Returns:** Boolean

---

### Usage Example

```ruby
# Create a batching scope
scope = BatchingScope.new(
  trigger_agent: quick_fit_agent,
  ending_agent: scoring_agent,
  chunk_size: 100,
  array_field: :companies
)

# Add intermediate agents
scope.add_agent(deep_intel_agent)
scope.add_agent(enrichment_agent)

# Check configuration
puts scope.valid?  # => true

# Use in execution
array = scope.get_array_from_context(context)
puts "Batching #{array.size} items in chunks of #{scope.chunk_size}"
```

---

## 4. BatchingScopeManager Public API

### Constructor

```ruby
def initialize
```

Creates a new scope manager instance.

---

### Public Methods

#### detect_scopes

```ruby
def detect_scopes(flow_chain)
```

Analyzes a pipeline flow chain and detects all batching scopes.

**Parameters:**
- `flow_chain` - Pipeline flow definition

**Returns:** Array of BatchingScope instances

**Raises:** ConfigurationError for invalid configurations

---

#### find_scope_for_agent

```ruby
def find_scope_for_agent(agent)
```

Finds the batching scope that starts with the given agent.

**Parameters:**
- `agent` - Agent instance

**Returns:** BatchingScope or nil

---

#### in_batching_scope?

```ruby
def in_batching_scope?(agent)
```

Checks if an agent is within any batching scope.

**Parameters:**
- `agent` - Agent instance

**Returns:** Boolean

---

#### agents_to_skip

```ruby
def agents_to_skip
```

Returns list of agents that should be skipped during normal execution (handled by batch executor).

**Returns:** Array of Agent instances

---

### Usage Example

```ruby
# In pipeline initialization
manager = BatchingScopeManager.new
scopes = manager.detect_scopes(pipeline.flow_chain)

puts "Found #{scopes.size} batching scope(s)"

# During execution
if scope = manager.find_scope_for_agent(current_agent)
  # Execute batching for this scope
  executor = PipelineBatchExecutor.new(scope)
  results = executor.execute_in_batches(context)
end

# Check if should skip
if manager.agents_to_skip.include?(agent)
  next  # Skip this agent
end
```

---

## 5. PipelineBatchExecutor Public API

### Constructor

```ruby
def initialize(scope)
```

Creates a new batch executor for the given scope.

**Parameters:**
- `scope` - BatchingScope instance

---

### Main Method

#### execute_in_batches

```ruby
def execute_in_batches(context, agent_results = nil)
```

Executes the batching scope by processing data in chunks.

**Parameters:**
- `context` - Current pipeline context
- `agent_results` - Previous agent results (optional)

**Returns:** Hash with merged results from all batches

**Raises:** BatchExecutionError if batches fail

---

### Public Attributes

#### accumulated_results

```ruby
attr_reader :accumulated_results
```

Array of results from each batch (for inspection/debugging).

---

#### execution_stats

```ruby
attr_reader :execution_stats
```

Statistics about the batch execution:

```ruby
{
  total_batches: 10,
  successful_batches: 9,
  failed_batches: 1,
  total_items: 1000,
  processed_items: 900,
  start_time: Time,
  end_time: Time
}
```

---

### Usage Example

```ruby
# Create executor
executor = PipelineBatchExecutor.new(batching_scope)

# Execute batches
begin
  results = executor.execute_in_batches(context, previous_results)

  # Check statistics
  stats = executor.execution_stats
  duration = stats[:end_time] - stats[:start_time]

  Rails.logger.info "Processed #{stats[:processed_items]}/#{stats[:total_items]} items"
  Rails.logger.info "Success rate: #{stats[:successful_batches]}/#{stats[:total_batches]}"
  Rails.logger.info "Duration: #{duration.round(2)}s"

rescue BatchExecutionError => e
  # Handle batch failure
  Rails.logger.error "Batch #{e.batch_number}/#{e.total_batches} failed"
  Rails.logger.error "Original error: #{e.original_error.message}"

  # Can still access partial results
  partial_results = e.partial_results
  Rails.logger.info "Got #{partial_results[:companies]&.size || 0} results before failure"
end
```

---

## 6. Context Changes During Batching

### Batch Metadata

During batch execution, the context includes special metadata:

```ruby
{
  # Original context fields
  search_terms: [...],
  product: ...,

  # Array field with current batch
  companies: [/* current batch items */],

  # Batch metadata (added automatically)
  _batch_metadata: {
    batch_number: 3,        # Current batch (1-indexed)
    total_batches: 10,      # Total number of batches
    batch_size: 100,        # Items in this batch
    scope_id: "a1b2c3d4",   # Unique scope identifier
    array_field: :companies # Field being batched
  }
}
```

### Accessing Batch Information

```ruby
class BatchAwareAgent < ApplicationAgent
  def call
    # Access batch metadata
    if batch_meta = context[:_batch_metadata]
      batch_num = batch_meta[:batch_number]
      total = batch_meta[:total_batches]

      Rails.logger.info "Processing batch #{batch_num}/#{total}"

      # Adjust behavior based on batch
      if batch_num == 1
        # First batch initialization
      elsif batch_num == total
        # Last batch cleanup
      end
    end

    # Normal processing
    super
  end
end
```

---

## 7. Complete Usage Examples

### Simple Batching (Single Trigger Agent)

```ruby
# Agent definitions
class CompanyAnalyzer < ApplicationAgent
  agent_name "CompanyAnalyzer"
  model "gpt-4o-mini"

  triggers_batching chunk_size: 100, over: :companies

  on_batch_start do |num, total, _|
    puts "Analyzing batch #{num}/#{total}"
  end
end

class ReportGenerator < ApplicationAgent
  agent_name "ReportGenerator"
  ends_batching
end

# Pipeline
class AnalysisPipeline < RAAF::Pipeline
  flow DataFetcher >> CompanyAnalyzer >> EnrichmentAgent >> ReportGenerator
end

# Execution
pipeline = AnalysisPipeline.new(search_query: "tech companies")
result = pipeline.run

# DataFetcher returns 500 companies
# CompanyAnalyzer processes in 5 batches of 100
# Each batch goes through EnrichmentAgent
# ReportGenerator receives all 500 processed companies
```

### With Progress Tracking

```ruby
class ProgressTrackingAgent < ApplicationAgent
  triggers_batching chunk_size: 50, over: :items

  on_batch_start do |num, total, context|
    # Store in Redis for real-time updates
    redis.set(
      "pipeline:#{context[:run_id]}:progress",
      { current: num, total: total, status: 'processing' }.to_json
    )
  end

  on_batch_complete do |num, total, result|
    # Update with results
    redis.set(
      "pipeline:#{context[:run_id]}:batch:#{num}",
      {
        completed_at: Time.now,
        items_processed: result[:items].size
      }.to_json
    )
  end

  on_batch_error do |num, total, error|
    # Track failures
    redis.set(
      "pipeline:#{context[:run_id]}:error",
      {
        batch: num,
        error: error.message,
        failed_at: Time.now
      }.to_json
    )
  end
end
```

### Nested Batching (Future - Currently Errors)

```ruby
# This configuration will raise an error in current implementation
class OuterBatchAgent < ApplicationAgent
  triggers_batching chunk_size: 1000, over: :records
end

class InnerBatchAgent < ApplicationAgent
  triggers_batching chunk_size: 10, over: :sub_records  # ERROR!
end

# Raises: "Nested batching scopes not yet supported"
```

### Combined with in_chunks_of

```ruby
# Agent-level batching (single agent)
class ChunkedProcessor < ApplicationAgent
  in_chunks_of 10  # Process input array in chunks of 10
end

# Pipeline-level batching (multiple agents)
class PipelineBatcher < ApplicationAgent
  triggers_batching chunk_size: 100  # Batch through multiple agents
end

# Can be used together
class CombinedPipeline < RAAF::Pipeline
  flow DataSource >>
       PipelineBatcher >>    # Start pipeline batching (100 items)
       ChunkedProcessor >>   # Each batch processed in chunks of 10
       Aggregator >>         # Still in pipeline batch
       FinalProcessor        # Ends pipeline batch
end
```

### Error Handling

```ruby
class ResilientBatchingAgent < ApplicationAgent
  triggers_batching chunk_size: 100

  on_batch_error do |num, total, error|
    # Log error
    Rails.logger.error "Batch #{num} failed: #{error}"

    # Attempt recovery
    if error.message.include?("rate limit")
      sleep(5)  # Wait before next batch
    end

    # Store for retry
    FailedBatch.create!(
      batch_number: num,
      total_batches: total,
      error_message: error.message,
      error_class: error.class.name,
      context: context.to_h,
      retry_count: 0
    )
  end
end

# Retry failed batches
class BatchRetryService
  def retry_failed_batches(pipeline_id)
    FailedBatch.where(pipeline_id: pipeline_id).each do |failed|
      # Recreate context for specific batch
      context = failed.context
      context[:_retry_batch] = failed.batch_number

      # Re-run pipeline for this batch
      pipeline = Pipeline.new(context)
      result = pipeline.run

      if result.success?
        failed.destroy
      else
        failed.increment!(:retry_count)
      end
    end
  end
end
```

---

## 8. Configuration Best Practices

### Choosing Chunk Size

```ruby
# Based on data size
class SmallDataAgent < ApplicationAgent
  triggers_batching chunk_size: 1000  # Small objects
end

class LargeDataAgent < ApplicationAgent
  triggers_batching chunk_size: 10    # Large objects or API calls
end

# Based on processing time
class FastAgent < ApplicationAgent
  triggers_batching chunk_size: 500   # Quick processing
end

class SlowAgent < ApplicationAgent
  triggers_batching chunk_size: 25    # Complex analysis
end

# Based on external constraints
class APIAgent < ApplicationAgent
  triggers_batching chunk_size: 100   # API rate limits
end
```

### Field Naming

```ruby
# Explicit is better than implicit
class ExplicitAgent < ApplicationAgent
  triggers_batching chunk_size: 100, over: :companies  # Clear
end

# But auto-detection works for simple cases
class SimpleAgent < ApplicationAgent
  triggers_batching chunk_size: 100  # Auto-detects single array field
end
```

### Hook Organization

```ruby
# Inline for simple hooks
class SimpleHooksAgent < ApplicationAgent
  triggers_batching chunk_size: 100 do
    on_batch_start { |n, t, _| puts "Batch #{n}/#{t}" }
  end
end

# Separate methods for complex logic
class ComplexHooksAgent < ApplicationAgent
  triggers_batching chunk_size: 100

  on_batch_start(&method(:handle_batch_start))
  on_batch_complete(&method(:handle_batch_complete))
  on_batch_error(&method(:handle_batch_error))

  private

  def self.handle_batch_start(num, total, context)
    # Complex logic here
  end

  def self.handle_batch_complete(num, total, result)
    # Complex logic here
  end

  def self.handle_batch_error(num, total, error)
    # Complex logic here
  end
end
```

---

## 9. Migration from Manual Batching

### Before (Manual Batching)

```ruby
class ManualBatchingService
  def process_companies(companies)
    results = []

    companies.each_slice(100) do |batch|
      Rails.logger.info "Processing batch of #{batch.size}"

      # Process batch through multiple steps
      analyzed = analyzer.analyze(batch)
      enriched = enricher.enrich(analyzed)
      scored = scorer.score(enriched)

      results.concat(scored)
    end

    results
  end
end
```

### After (Agent-Level Batching)

```ruby
class AnalyzerAgent < ApplicationAgent
  triggers_batching chunk_size: 100, over: :companies

  on_batch_start do |n, t, _|
    Rails.logger.info "Processing batch #{n}/#{t}"
  end
end

class ScorerAgent < ApplicationAgent
  ends_batching
end

class ProcessingPipeline < RAAF::Pipeline
  flow AnalyzerAgent >> EnricherAgent >> ScorerAgent
end

# Clean, declarative, automatic batching
pipeline = ProcessingPipeline.new(companies: companies)
results = pipeline.run
```