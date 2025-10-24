# Specification: Intelligent Streaming

> Created: 2025-10-24
> Updated: 2025-10-24 (Unified Streaming Feature)
> Status: Planning
> RAAF Version: 2.0.0+

## Overview

Implement a unified **`intelligent_streaming`** feature that enables agents to declare smart streaming behavior with optional state management and optional incremental result delivery. This single feature combines what could have been multiple separate concerns:

1. **Pipeline-Level Streaming** (core) - Process large arrays through multiple agents in streams
2. **State Management** (optional) - Skip reprocessing, load existing results, persist stream progress
3. **Incremental Delivery** (optional) - Receive results after each stream completes

**Streaming Architecture:**
- **Agent-level streaming** (`in_chunks_of`): Single agent processes input chunks for memory/API efficiency
- **Intelligent streaming** (this spec): Core pipeline streaming with optional state management and optional incremental delivery
  - **Basic:** Pipeline streaming only (no state management, no incremental delivery)
  - **With State Management:** Skip, load existing, persist stream results
  - **With Incremental Delivery:** Results available after each stream (vs waiting for all streams)

**Goal:** Provide a unified, flexible API where developers declare what batching strategy they need (via optional parameters), while keeping pipeline `flow` definitions focused purely on data flow dependencies.

## User Stories

### Story 1: Cost-Optimized Prospect Discovery with Incremental Delivery

**As a** product developer building a cost-optimized AI pipeline
**I want to** process 1000 companies in streams of 100 through multiple analysis stages **and receive results as each stream completes**
**So that** I get early results faster, can monitor progress, and can start downstream processing before entire pipeline finishes

**Workflow:**
1. Developer declares `intelligent_streaming` with `stream_size: 100`, `incremental: true`
2. Pipeline automatically streams after `CompanyDiscovery` returns 1000 companies
3. **Stream 1:** 100 companies flow through `QuickFitAnalyzer` → `DeepIntel` → `Enrichment`
   - Results available immediately via `on_stream_complete` callback ✅
4. **Stream 2:** 100 companies flow through same agents
   - Results available immediately ✅
5. Continue for streams 3-10
6. `Scoring` receives all 1000 merged results after all streams complete

**Problem Solved:** Without this feature, either all 1000 companies must complete the entire pipeline before any results are available, or complex manual streaming logic must be implemented. With incremental delivery, results are available after each stream (90% faster for first results).

### Story 2: Resumable Processing (Skip Reprocessing, Persist Progress)

**As a** developer building large-scale stream processing with resumable capabilities
**I want to** skip companies already analyzed, load cached results, and persist new results
**So that** I can resume interrupted jobs without reprocessing and avoid redundant API calls

**Workflow:**
1. Developer declares `intelligent_streaming` with state management:
   - `skip_if { |record| already_analyzed?(record) }`
   - `load_existing { |record| load_cached_result(record) }`
   - `persist_each_stream { |stream| save_stream(stream) }`
2. Input: 1000 companies, 700 already analyzed, 300 new
3. Agent processes:
   - 700 skipped: Load from cache
   - 300 new: Process through agent
   - Results merged: 700 cached + 300 new = 1000 total
   - Persisted to DB after each stream
4. If job interrupted, restart: Already-analyzed items skipped, progress saved

**Problem Solved:** Without state management, restarting an interrupted job reprocesses everything or requires manual tracking of what's already done.

## Core Requirements

### Functional Requirements

1. **Unified `intelligent_streaming` Declaration**
   - Agents declare `intelligent_streaming` block with configuration options
   - Required: `stream_size` and `over` (field name)
   - Optional: State management (`skip_if`, `load_existing`, `persist_each_stream`)
   - Optional: Incremental delivery mode (`incremental: true` or `incremental: false`)
   - Configuration must be part of agent class definition (not runtime)

2. **Pipeline-Level Streaming (Core Feature)**
   - Automatic array field detection (default to first array field)
   - Explicit field specification via `over: :field_name`
   - Streams flow through multiple agents before next stream starts
   - Automatic scope detection: Streaming continues until next agent without `intelligent_streaming`

3. **State Management (Optional)**
   - `skip_if { |record, context| ... }` - Skip processing for records matching condition
   - `load_existing { |record, context| ... }` - Load existing result instead of reprocessing
   - `persist_each_stream { |stream_results, context| ... }` - Save stream to DB or external storage
   - All three features are optional and work independently or together

4. **Incremental Delivery (Optional)**
   - `incremental: true` - Results available after EACH stream via callback (incremental)
   - `incremental: false` (default) - Results accumulated and available only at end
   - Callback signature determines delivery behavior:
     - 3 params `|stream_num, total, results|` → incremental: true (per-stream results)
     - 1 param `|all_results|` → incremental: false (all results at end)

5. **Progress Hooks**
   - `on_stream_start { |stream_num, total, context| ... }` - Fires before stream execution
   - `on_stream_complete { |stream_num, total, results| ... }` - Fires after stream completes
     - With `incremental: true` - Called after EACH stream with stream results only
     - With `incremental: false` - Called ONCE at end with all accumulated results
   - `on_stream_error { |stream_num, total, error, context| ... }` - Fires on stream failure

6. **Error Handling**
   - Failed batches do not lose successful batch results
   - Clear error messages indicating which batch failed and why
   - Results from completed batches accumulated and returned
   - Failed batch can be retried independently

### Non-Functional Requirements

1. **Performance**
   - Batching overhead must be < 5ms per batch
   - Memory usage must scale with batch size, not total data size
   - No performance degradation for non-batching pipelines

2. **Backward Compatibility**
   - Existing `in_chunks_of` agent batching must continue to work unchanged
   - Existing pipelines without batching must work identically
   - All existing pipeline operators (`>>`, `|`) must work with batching

3. **Developer Experience**
   - Clear, concise API (3-line agent declaration)
   - Helpful error messages for misconfigurations
   - Consistent with existing RAAF DSL patterns
   - Easy to debug with built-in logging

4. **Tracing Integration**
   - Batching operations must integrate with RAAF tracing system
   - Each batch must create appropriate trace spans
   - Trace hierarchy must clearly show batch relationships

## Visual Design

N/A - This is a backend DSL feature with no UI components.

## Reusable Components

### Existing Code to Leverage

**Components:**
- `BatchedAgent` - Current agent-level batching wrapper (`in_chunks_of`)
- `ChainedAgent` - Sequential agent execution wrapper
- `PipelineDSL::WrapperDSL` - Base wrapper interface
- `ContextVariables` - Context management with indifferent access
- `Pipelineable` - Base module for pipeline-compatible components
- `Hooks::AgentHooks` - Lifecycle hooks system

**Patterns:**
- Wrapper pattern from `BatchedAgent` for batching logic
- Class method DSL pattern from `Agent` class (`agent_name`, `model`, etc.)
- Hook registration pattern from `AgentHooks` (`before_execute`, `after_execute`)
- Execute wrapper pattern from `BatchedAgent.execute` method
- Scope detection pattern from `BatchedAgent.detect_array_field`

### New Components Required

1. **`PipelineBatchingAgent`** - New wrapper for pipeline-level batching
   - Why new: Different execution model than `BatchedAgent` (multi-agent scope vs single agent)
   - Wraps multiple agents (entire sub-pipeline) not just one agent
   - Must track batching scope boundaries
   - Must handle batch-level hooks
   - Must merge results across batches

2. **`BatchingConfiguration`** - DSL for agent batching declarations
   - Why new: No existing class-level batching configuration
   - Stores `chunk_size`, `over` field, validation rules
   - Validates configuration at class definition time
   - Provides introspection methods for pipeline

3. **`BatchingScopeDetector`** - Logic to detect batching boundaries in flow
   - Why new: Complex flow introspection logic specific to batching
   - Analyzes flow chain to find `triggers_batching` and `ends_batching` agents
   - Validates scope nesting and configuration
   - Provides scope metadata to pipeline executor

4. **`BatchProgressContext`** - Context object for batch hooks
   - Why new: Specialized context for batch-level operations
   - Provides batch number, total batches, batch data
   - Immutable to prevent hook interference
   - Structured for consistent hook signatures

## Technical Approach

### 1. Agent Class-Level API

Agents declare batching using class methods (similar to `agent_name`, `model`, etc.):

```ruby
class QuickFitAnalyzer < ApplicationAgent
  agent_name "QuickFitAnalyzer"
  model "gpt-4o-mini"

  # Trigger pipeline batching from this agent onwards
  triggers_batching chunk_size: 100, over: :companies

  # Optional: batch progress hooks
  on_batch_start do |batch_num, total_batches, context|
    Rails.logger.info "Starting batch #{batch_num}/#{total_batches}"
  end

  on_batch_complete do |batch_num, total_batches, batch_result|
    Rails.logger.info "Batch #{batch_num} complete: #{batch_result[:companies].size} companies"
  end
end

class Scoring < ApplicationAgent
  agent_name "Scoring"

  # End batching scope here
  ends_batching
end
```

### 2. Pipeline Flow (Unchanged)

Pipeline flow remains a pure description of data dependencies:

```ruby
class ProspectPipeline < RAAF::Pipeline
  # Flow describes data flow only, not execution strategy
  flow CompanyDiscovery >> QuickFitAnalyzer >> DeepIntel >> Enrichment >> Scoring

  context do
    required :search_terms, :product, :company
  end
end
```

### 3. Execution Behavior

Pipeline executor detects batching configuration and automatically:

1. **Scope Detection Phase** (at pipeline initialization):
   - Analyze flow chain for `triggers_batching` and `ends_batching`
   - Validate batching scope boundaries
   - Build batching execution plan

2. **Execution Phase**:
   - Execute agents before batching scope normally
   - At `triggers_batching` agent:
     - Extract array field from context
     - Split into batches
     - For each batch:
       - Execute entire batching scope (all agents until `ends_batching`)
       - Call batch hooks
       - Accumulate results
     - Merge batch results
     - Continue pipeline with merged results

3. **Merging Phase**:
   - Intelligent merge based on data types
   - Arrays: concatenate
   - Objects: deep merge with conflict resolution
   - Primitives: last wins (with warning)

### 4. Implementation Classes

**`BatchingConfiguration`** (in `agent.rb`):
```ruby
module RAAF
  module DSL
    class Agent
      class << self
        def triggers_batching(chunk_size:, over: nil)
          _batching_config[:triggers] = {
            chunk_size: chunk_size,
            field: over,
            hooks: {}
          }
        end

        def ends_batching
          _batching_config[:ends] = true
        end

        def on_batch_start(&block)
          _batching_config.dig(:triggers, :hooks, :on_start) = block
        end

        def on_batch_complete(&block)
          _batching_config.dig(:triggers, :hooks, :on_complete) = block
        end

        def _batching_config
          @_batching_config ||= Concurrent::Hash.new
        end

        def batching_trigger?
          _batching_config[:triggers].present?
        end

        def batching_terminator?
          _batching_config[:ends] == true
        end
      end
    end
  end
end
```

**`PipelineBatchingAgent`** (new file `pipeline_dsl/pipeline_batching_agent.rb`):
```ruby
module RAAF
  module DSL
    module PipelineDSL
      class PipelineBatchingAgent
        include RAAF::Logger
        include WrapperDSL

        attr_reader :trigger_agent, :scope_agents, :terminator_agent, :chunk_size, :field

        def initialize(trigger_agent, scope_agents, terminator_agent, chunk_size:, field:)
          @trigger_agent = trigger_agent
          @scope_agents = scope_agents
          @terminator_agent = terminator_agent
          @chunk_size = chunk_size
          @field = field
        end

        def execute(context, agent_results = nil)
          # Implementation in technical spec
        end
      end
    end
  end
end
```

**`BatchingScopeDetector`** (new file `pipeline_dsl/batching_scope_detector.rb`):
```ruby
module RAAF
  module DSL
    module PipelineDSL
      class BatchingScopeDetector
        def self.detect(flow_chain)
          # Analyze flow chain for batching configuration
          # Returns array of batching scopes
        end

        def self.validate_scopes(scopes)
          # Validate scope nesting and configuration
        end
      end
    end
  end
end
```

### 5. Scope Detection Algorithm

```ruby
def detect_batching_scopes(flow_chain)
  scopes = []
  current_scope = nil
  agents = flatten_flow_chain(flow_chain)

  agents.each_with_index do |agent, index|
    if agent.batching_trigger?
      raise Error, "Nested batching not yet supported" if current_scope
      current_scope = {
        trigger: agent,
        trigger_index: index,
        agents: [],
        config: agent._batching_config[:triggers]
      }
    elsif current_scope
      current_scope[:agents] << agent

      if agent.batching_terminator?
        current_scope[:terminator] = agent
        current_scope[:terminator_index] = index
        scopes << current_scope
        current_scope = nil
      end
    end
  end

  raise Error, "Batching scope not terminated" if current_scope
  scopes
end
```

## Out of Scope

The following features are explicitly **not** included in this initial implementation:

1. **Nested Batching Scopes**
   - Multiple batching scopes within a single pipeline
   - Batching within batching (e.g., batch by company, then by product)
   - *Rationale:* Adds significant complexity, unclear use cases
   - *Future:* Can be added in v2 if needed

2. **Parallel Batch Execution**
   - Processing multiple batches simultaneously
   - Thread pool management for batch concurrency
   - *Rationale:* Sequential batching satisfies current use cases, parallel adds complexity
   - *Future:* Can add `parallel: true` option later

3. **Dynamic Batch Sizing**
   - Adjusting batch size based on performance metrics
   - Auto-scaling batch size based on memory/CPU usage
   - *Rationale:* Static batch sizes work for current needs
   - *Future:* Can add adaptive batching algorithm

4. **Batch-Level Caching**
   - Caching batch results to disk
   - Resume from cached batch checkpoint
   - *Rationale:* Adds persistence complexity, unclear ROI
   - *Future:* Can add if long-running pipeline failures become issue

5. **Batch Ordering Strategies**
   - Priority-based batch ordering
   - Custom batch sorting algorithms
   - *Rationale:* Simple sequential ordering sufficient
   - *Future:* Can add if specific ordering needs emerge

6. **Cross-Batch Context**
   - Sharing state between batches
   - Accumulator pattern across batches
   - *Rationale:* Batches should be independent for safety
   - *Future:* Can add carefully if needed

## Expected Deliverable

### Testable Outcomes

1. **Basic Batching Execution**
   - ✅ Pipeline with `triggers_batching` agent processes data in batches
   - ✅ Each batch flows through entire scope before next batch starts
   - ✅ Results from all batches are merged correctly
   - ✅ Final result matches non-batching pipeline output

2. **Scope Management**
   - ✅ Batching scope starts at `triggers_batching` agent
   - ✅ Batching scope ends at `ends_batching` agent
   - ✅ Agents between trigger and terminator participate in batching
   - ✅ Agents after terminator receive merged results

3. **Progress Hooks**
   - ✅ `on_batch_start` hook fires before each batch
   - ✅ `on_batch_complete` hook fires after each batch
   - ✅ Hooks receive correct batch number and total batches
   - ✅ Hook modifications to context persist

4. **Error Handling**
   - ✅ Failed batch returns partial results from successful batches
   - ✅ Error message clearly indicates which batch failed
   - ✅ Pipeline state remains consistent after batch failure
   - ✅ Retry logic works for failed batches

5. **Backward Compatibility**
   - ✅ Existing `in_chunks_of` agent batching works unchanged
   - ✅ Pipelines without batching work identically
   - ✅ All pipeline operators (`>>`, `|`) work with batching
   - ✅ No performance degradation for non-batching pipelines

6. **Field Auto-Detection**
   - ✅ Batching auto-detects array field when `over` not specified
   - ✅ Clear error when multiple array fields and no `over` specified
   - ✅ Clear error when specified field is not an array
   - ✅ Field auto-detection works with complex context

### Acceptance Criteria

**Given** a pipeline with batching configuration:
```ruby
class QuickFitAnalyzer < ApplicationAgent
  triggers_batching chunk_size: 100, over: :companies
end

class Scoring < ApplicationAgent
  ends_batching
end

class ProspectPipeline < RAAF::Pipeline
  flow CompanyDiscovery >> QuickFitAnalyzer >> DeepIntel >> Enrichment >> Scoring
end
```

**When** the pipeline is executed with 1000 companies:
```ruby
pipeline = ProspectPipeline.new(
  search_terms: ["CTO", "DevOps"],
  product: product,
  company: company
)
result = pipeline.run
```

**Then:**
1. `CompanyDiscovery` runs once, returns 1000 companies
2. Pipeline splits 1000 companies into 10 batches of 100
3. For each batch:
   - `QuickFitAnalyzer` receives 100 companies
   - `DeepIntel` receives filtered results from `QuickFitAnalyzer`
   - `Enrichment` receives results from `DeepIntel`
   - Batch results accumulated
4. All batch results merged: 300 total prospects (70% rejected)
5. `Scoring` receives all 300 merged prospects at once
6. Final result matches non-batching pipeline output

**And** batch progress is tracked:
- 10 `on_batch_start` hooks fired
- 10 `on_batch_complete` hooks fired
- Each hook receives correct batch number (1-10)
- Each hook receives correct total (10)

**And** error handling works:
- If batch 5 fails, batches 1-4 results are returned
- Error message indicates "Batch 5/10 failed at QuickFitAnalyzer"
- Pipeline state remains consistent

## Success Criteria

1. **Functional Correctness**
   - All 6 testable outcomes pass
   - Acceptance criteria fully met
   - 100% test coverage for batching logic

2. **Performance**
   - Batching overhead < 5ms per batch
   - Memory usage scales with batch size (O(batch_size), not O(total_size))
   - No regression in non-batching pipeline performance

3. **Code Quality**
   - Clear separation of concerns (scope detection, execution, merging)
   - Consistent with existing RAAF DSL patterns
   - Comprehensive error messages
   - Inline documentation for complex logic

4. **Developer Experience**
   - 3-line agent declaration (trigger + hooks)
   - Pipeline flow unchanged
   - Clear error messages for misconfigurations
   - Easy to debug with built-in logging

5. **Production Readiness**
   - Thread-safe implementation
   - Tracing integration complete
   - Error handling robust
   - Memory-efficient for large batches

## Migration Path

### For Existing Pipelines

No migration required - existing pipelines work unchanged.

### For New Batching Pipelines

**Step 1: Identify Batching Trigger Agent**
```ruby
# Before: No batching
class QuickFitAnalyzer < ApplicationAgent
  agent_name "QuickFitAnalyzer"
  model "gpt-4o-mini"
end

# After: Add batching trigger
class QuickFitAnalyzer < ApplicationAgent
  agent_name "QuickFitAnalyzer"
  model "gpt-4o-mini"
  triggers_batching chunk_size: 100, over: :companies
end
```

**Step 2: Identify Batching Terminator Agent**
```ruby
# Before: No batching
class Scoring < ApplicationAgent
  agent_name "Scoring"
end

# After: Add batching terminator
class Scoring < ApplicationAgent
  agent_name "Scoring"
  ends_batching
end
```

**Step 3: Optional Progress Hooks**
```ruby
class QuickFitAnalyzer < ApplicationAgent
  triggers_batching chunk_size: 100, over: :companies

  on_batch_start do |batch_num, total, context|
    Rails.logger.info "Batch #{batch_num}/#{total} starting"
  end

  on_batch_complete do |batch_num, total, result|
    Rails.logger.info "Batch #{batch_num}/#{total} complete"
  end
end
```

**Step 4: Test and Deploy**
- Verify batching behavior with test data
- Monitor batch progress in logs
- Adjust batch size based on performance

## Documentation Requirements

1. **RAAF Pipeline DSL Guide Update**
   - Add "Pipeline Batching" section
   - Include complete examples
   - Explain difference from agent batching (`in_chunks_of`)
   - Document best practices

2. **API Documentation**
   - `triggers_batching` method signature and options
   - `ends_batching` method usage
   - `on_batch_start` and `on_batch_complete` hook signatures
   - `PipelineBatchingAgent` class documentation

3. **Migration Guide**
   - When to use pipeline batching vs agent batching
   - How to choose batch size
   - Performance tuning tips
   - Common pitfalls and solutions

4. **Examples**
   - Basic batching example
   - Progress tracking example
   - Error handling example
   - Complex pipeline with batching

## Testing Strategy

### Unit Tests

1. **`BatchingConfiguration`**
   - Test `triggers_batching` class method registration
   - Test `ends_batching` class method registration
   - Test batch hook registration
   - Test configuration validation

2. **`BatchingScopeDetector`**
   - Test scope detection with simple chain
   - Test scope detection with parallel agents
   - Test validation of scope boundaries
   - Test error cases (missing terminator, nested scopes)

3. **`PipelineBatchingAgent`**
   - Test batch splitting logic
   - Test batch execution order
   - Test result merging
   - Test hook execution
   - Test error handling

### Integration Tests

1. **End-to-End Pipeline Execution**
   - Test complete batching pipeline
   - Verify batch count and sizes
   - Verify final result correctness
   - Verify batch hooks fire

2. **Progress Tracking**
   - Test batch progress reporting
   - Verify hook parameters
   - Test progress with different batch sizes

3. **Error Handling**
   - Test batch failure scenarios
   - Verify partial results returned
   - Test retry logic

4. **Backward Compatibility**
   - Test existing pipelines work unchanged
   - Test `in_chunks_of` still works
   - Test performance of non-batching pipelines

### Performance Tests

1. **Batching Overhead**
   - Measure overhead per batch (< 5ms target)
   - Compare batched vs non-batched execution time
   - Verify memory usage scales with batch size

2. **Large Dataset Tests**
   - Test with 10,000+ items
   - Verify memory usage stays constant per batch
   - Test different batch sizes (10, 100, 1000)

### Edge Case Tests

1. **Boundary Conditions**
   - Empty array (0 items)
   - Single item (1 item)
   - Exact batch size (100 items, batch size 100)
   - One less than batch size (99 items, batch size 100)
   - One more than batch size (101 items, batch size 100)

2. **Configuration Edge Cases**
   - Missing `ends_batching` (should error)
   - Multiple `triggers_batching` (should error for nested)
   - Invalid chunk size (0, negative, non-integer)
   - Invalid field name (non-existent, non-array)

3. **Context Edge Cases**
   - Multiple array fields (should error without `over`)
   - No array fields (should error)
   - Complex nested context structures
   - Context modifications during batching

---

**Spec Cross-References:**
- **Technical Details:** See `sub-specs/technical-spec.md`
- **API Design:** See `sub-specs/api-spec.md`
- **Database Schema:** N/A (no database changes)
- **Tests Specification:** See `sub-specs/tests.md`

**Version History:**
- 2025-10-24: Initial specification created
