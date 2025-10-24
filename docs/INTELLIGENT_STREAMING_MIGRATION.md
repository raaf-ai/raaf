# Intelligent Streaming Migration Guide

## When to Use Intelligent Streaming

This guide helps you decide when to use intelligent streaming versus other batching approaches, and provides step-by-step migration instructions.

## Table of Contents

1. [Decision Matrix](#decision-matrix)
2. [Feature Comparison](#feature-comparison)
3. [Migration Patterns](#migration-patterns)
4. [Code Migration Examples](#code-migration-examples)
5. [Performance Considerations](#performance-considerations)
6. [Common Pitfalls](#common-pitfalls)
7. [Testing Your Migration](#testing-your-migration)

---

## Decision Matrix

Use this matrix to determine the best approach for your use case:

| Scenario | Use Agent Batching | Use Pipeline Streaming | Rationale |
|----------|-------------------|------------------------|-----------|
| **Single agent processing** | ✅ `in_chunks_of` | ❌ Not needed | No pipeline complexity |
| **Multiple agents, need memory efficiency** | ❌ Less effective | ✅ `intelligent_streaming` | Streams flow through entire pipeline |
| **Need state management (skip/load/persist)** | ❌ Not available | ✅ Built-in | State management is streaming-only |
| **Need incremental result delivery** | ❌ Not built-in | ✅ Supported | Get results per stream |
| **100+ items to process** | ✅ Works | ✅ Preferred | Better control with streaming |
| **1000+ items to process** | ⚠️ Memory risk | ✅ Recommended | Memory-efficient streaming |
| **API rate limiting concerns** | ✅ Works | ✅ Better | More control with streaming |
| **Need to resume interrupted jobs** | ❌ Manual only | ✅ Built-in | State management handles resumption |
| **Complex data transformations** | ✅ Simple | ✅ More flexible | Streaming provides hooks |
| **Real-time progress updates** | ❌ Manual | ✅ Built-in | Progress hooks included |

### Quick Decision Tree

```
Is it a single agent?
├─ Yes → Use in_chunks_of (agent batching)
└─ No → Multiple agents in pipeline
        │
        Need state management or incremental delivery?
        ├─ Yes → Use intelligent_streaming ✅
        └─ No → How many items?
                ├─ < 100 → Either approach works
                ├─ 100-1000 → Prefer intelligent_streaming
                └─ > 1000 → Must use intelligent_streaming ✅
```

---

## Feature Comparison

### Agent Batching (`in_chunks_of`)

```ruby
class SingleAgent < RAAF::DSL::Agent
  def call
    items = context[:items]  # All items at once
    process_in_batches(items)
  end
end
```

**Pros:**
- Simple to implement
- Good for single agent scenarios
- Low overhead

**Cons:**
- No built-in state management
- All items must fit in memory
- No incremental delivery
- Manual progress tracking

### Pipeline Streaming (`intelligent_streaming`)

```ruby
class StreamingAgent < RAAF::DSL::Agent
  intelligent_streaming stream_size: 100 do
    skip_if { |record| already_processed?(record) }
    persist_each_stream { |results| save(results) }
    on_stream_complete { |num, total, results| notify_progress(num, total) }
  end
end
```

**Pros:**
- Built-in state management
- Memory efficient (O(stream_size))
- Incremental delivery
- Progress hooks
- Resume capability
- Works across entire pipeline scope

**Cons:**
- More complex setup
- Small overhead per stream (~5ms)

---

## Migration Patterns

### Pattern 1: From Manual Batching

**Before (manual batching):**
```ruby
class ProcessingService
  def process_all(items)
    results = []

    items.each_slice(100) do |batch|
      Rails.logger.info "Processing batch..."

      batch_results = batch.map do |item|
        next if ProcessedItems.exists?(item_id: item[:id])

        result = process_item(item)
        ProcessedItems.create!(item_id: item[:id], data: result)
        result
      end.compact

      results.concat(batch_results)
      NotificationService.notify_progress(results.count, items.count)
    end

    results
  end

  private

  def process_item(item)
    # Processing logic
  end
end
```

**After (intelligent streaming):**
```ruby
class ProcessingAgent < RAAF::DSL::Agent
  intelligent_streaming stream_size: 100, incremental: true do
    skip_if { |item| ProcessedItems.exists?(item_id: item[:id]) }

    persist_each_stream do |results|
      ProcessedItems.insert_all(
        results.map { |r| { item_id: r[:id], data: r } }
      )
    end

    on_stream_complete do |num, total, data, results|
      processed_count = results.count
      total_count = total * 100  # stream_size * total_streams
      NotificationService.notify_progress(processed_count, total_count)
    end
  end

  # Processing logic moves to agent's call method or schema
  schema do
    field :processed_items, type: :array, required: true
  end
end
```

### Pattern 2: From Single Large Processing

**Before (all at once):**
```ruby
class CompanyAnalyzer < RAAF::DSL::Agent
  def call
    companies = context[:companies]  # Could be 1000+ items

    analyzed = companies.map do |company|
      # Memory spike - all companies in memory
      analyze_company(company)
    end

    { analyzed_companies: analyzed }
  end

  private

  def analyze_company(company)
    # API calls, expensive processing
  end
end
```

**After (streaming):**
```ruby
class CompanyAnalyzer < RAAF::DSL::Agent
  intelligent_streaming stream_size: 50 do  # Process 50 at a time
    on_stream_complete do |num, total, data, results|
      Rails.logger.info "Analyzed stream #{num}/#{total}"
      # Memory freed after each stream
    end
  end

  # Same logic, but automatically batched
  schema do
    field :analyzed_companies, type: :array, required: true
  end
end
```

### Pattern 3: From Async Job Processing

**Before (background jobs):**
```ruby
class ProcessItemsJob < ApplicationJob
  def perform(item_ids)
    items = Item.where(id: item_ids)

    items.find_each do |item|
      ProcessSingleItemJob.perform_later(item.id)
    end
  end
end

class ProcessSingleItemJob < ApplicationJob
  def perform(item_id)
    item = Item.find(item_id)
    # Process item
  end
end
```

**After (streaming pipeline):**
```ruby
class ItemProcessor < RAAF::DSL::Agent
  intelligent_streaming stream_size: 100 do
    persist_each_stream do |results|
      # Batch processing instead of individual jobs
      Item.where(id: results.map { |r| r[:id] })
          .update_all(processed: true)
    end
  end
end

class ProcessingPipeline < RAAF::Pipeline
  flow ItemLoader >> ItemProcessor >> ResultNotifier
end

# Single job processes everything efficiently
class ProcessItemsJob < ApplicationJob
  def perform
    pipeline = ProcessingPipeline.new
    pipeline.run
  end
end
```

---

## Code Migration Examples

### Example 1: E-commerce Order Processing

**Before:**
```ruby
class OrderProcessor
  def process_daily_orders
    orders = Order.pending.includes(:items, :customer)

    orders.each do |order|
      # Memory issue with large order volumes
      validate_inventory(order)
      calculate_shipping(order)
      apply_discounts(order)
      charge_payment(order)
      send_confirmation(order)
    end
  end
end
```

**After:**
```ruby
class OrderProcessingPipeline < RAAF::Pipeline
  flow OrderValidator >> PaymentProcessor >> NotificationSender
end

class OrderValidator < RAAF::DSL::Agent
  intelligent_streaming stream_size: 25 do  # Small batches for payment processing
    skip_if { |order| order[:status] == "processed" }

    on_stream_error do |num, total, data, error|
      # Handle payment failures gracefully
      FailedOrders.create!(
        order_ids: data.map { |o| o[:id] },
        error: error.message
      )
    end
  end
end
```

### Example 2: Data Import Pipeline

**Before:**
```ruby
class CsvImporter
  def import(file_path)
    csv_data = CSV.read(file_path, headers: true)  # Loads entire file

    csv_data.each do |row|
      record = transform_row(row)
      validate_record(record)
      save_record(record)
    end
  end
end
```

**After:**
```ruby
class CsvImportPipeline < RAAF::Pipeline
  flow CsvLoader >> DataValidator >> DataPersistor
end

class DataValidator < RAAF::DSL::Agent
  intelligent_streaming stream_size: 500 do
    skip_if { |row| row[:id].blank? }

    load_existing do |row|
      # Check for duplicates
      existing = ImportedRecord.find_by(external_id: row[:id])
      existing&.attributes
    end

    persist_each_stream do |validated_rows|
      ImportedRecord.insert_all(validated_rows)
    end

    on_stream_complete do |num, total, data, results|
      ImportLog.create!(
        batch_number: num,
        total_batches: total,
        records_processed: results.count,
        status: "completed"
      )
    end
  end
end
```

### Example 3: ML Feature Engineering

**Before:**
```ruby
class FeatureEngineering
  def generate_features(dataset)
    features = []

    dataset.each do |record|
      # CPU and memory intensive
      extracted = extract_features(record)
      normalized = normalize_features(extracted)
      encoded = encode_features(normalized)
      features << encoded
    end

    features
  end
end
```

**After:**
```ruby
class FeatureEngineeringPipeline < RAAF::Pipeline
  flow FeatureExtractor >> FeatureNormalizer >> FeatureEncoder
end

class FeatureExtractor < RAAF::DSL::Agent
  intelligent_streaming stream_size: 100 do
    # Process in parallel-friendly batches
    on_stream_complete do |num, total, data, results|
      # Save intermediate results for checkpointing
      FeatureCache.set("batch_#{num}", results)
    end
  end
end
```

---

## Performance Considerations

### Memory Usage Comparison

```ruby
# Without streaming: O(n) memory
def process_all(items)  # 10,000 items = ~100MB memory
  items.map { |item| process(item) }
end

# With streaming: O(stream_size) memory
intelligent_streaming stream_size: 100 do  # Max 100 items = ~1MB memory
  # Memory released after each stream
end
```

### Throughput Analysis

| Items | No Streaming | With Streaming | Difference |
|-------|-------------|----------------|------------|
| 100 | 5 sec | 5.05 sec | +1% (overhead) |
| 1,000 | 50 sec | 51 sec | +2% (minimal) |
| 10,000 | 500 sec | 510 sec | +2% (with benefits) |
| 100,000 | Out of Memory | 5,100 sec | ✅ Completes |

### Cost Optimization Example

```ruby
# Before: All items use expensive model
class Analyzer < RAAF::DSL::Agent
  model "gpt-4o"  # $0.01 per call

  def call
    items = context[:items]  # 1000 items = $10
    analyze_all(items)
  end
end

# After: Stream with filtering
class FilterAgent < RAAF::DSL::Agent
  model "gpt-4o-mini"  # $0.001 per call

  intelligent_streaming stream_size: 100 do
    on_stream_complete do |num, total, data, results|
      # Only good candidates go to expensive model
      good_items = results.select { |r| r[:score] > 70 }
      ExpensiveAnalyzer.process(good_items)  # 30% of items = $3
    end
  end
end
# Total savings: 70% cost reduction
```

---

## Common Pitfalls

### Pitfall 1: Stream Size Too Large

**Problem:**
```ruby
intelligent_streaming stream_size: 10000 do  # Too large!
  # Defeats the purpose of streaming
end
```

**Solution:**
```ruby
intelligent_streaming stream_size: 100 do  # Reasonable size
  # Good balance of efficiency and memory
end
```

### Pitfall 2: Forgetting Array Field

**Problem:**
```ruby
class MyAgent < RAAF::DSL::Agent
  intelligent_streaming stream_size: 50 do
    # Error: Cannot detect array field
  end
end
```

**Solution:**
```ruby
class MyAgent < RAAF::DSL::Agent
  intelligent_streaming stream_size: 50, over: :items do  # Specify field
    # Now it knows what to stream
  end
end
```

### Pitfall 3: Side Effects in skip_if

**Problem:**
```ruby
skip_if do |record|
  # DON'T: Side effects in condition
  ProcessedCount.increment!
  record[:processed]
end
```

**Solution:**
```ruby
skip_if do |record|
  # DO: Pure condition check
  record[:processed]
end

on_stream_complete do |num, total, data, results|
  # DO: Side effects in hooks
  ProcessedCount.increment_by(results.count)
end
```

### Pitfall 4: Not Handling Partial Failures

**Problem:**
```ruby
intelligent_streaming stream_size: 100 do
  # What if stream 5 of 10 fails?
end
```

**Solution:**
```ruby
intelligent_streaming stream_size: 100 do
  on_stream_error do |num, total, data, error|
    # Log failure
    Rails.logger.error "Stream #{num} failed: #{error}"

    # Save failed items for retry
    FailedItems.create!(
      stream_number: num,
      items: data,
      error: error.message
    )

    # Don't let one stream failure stop everything
    # The pipeline will continue with next stream
  end

  persist_each_stream do |results|
    # Each successful stream is saved
    # Even if later streams fail
  end
end
```

---

## Testing Your Migration

### Unit Tests

```ruby
RSpec.describe "Streaming Migration" do
  let(:agent) { MyStreamingAgent.new }

  describe "configuration" do
    it "has appropriate stream size" do
      config = MyStreamingAgent.streaming_config
      expect(config.stream_size).to eq(100)
    end

    it "has state management" do
      config = MyStreamingAgent.streaming_config
      expect(config.has_state_management?).to be true
    end
  end

  describe "behavior" do
    it "processes in streams" do
      items = create_list(:item, 250)  # 2.5 streams

      result = agent.call(items: items)

      expect(result[:processed_items].count).to eq(250)
    end

    it "skips already processed items" do
      processed = create(:item, processed: true)
      unprocessed = create(:item, processed: false)

      result = agent.call(items: [processed, unprocessed])

      expect(result[:processed_items]).to include(
        hash_including(id: unprocessed.id)
      )
      expect(result[:processed_items]).not_to include(
        hash_including(id: processed.id)
      )
    end
  end
end
```

### Integration Tests

```ruby
RSpec.describe "Pipeline Streaming" do
  let(:pipeline) { MyPipeline.new }

  it "handles large datasets" do
    # Create large dataset
    items = create_list(:item, 1000)

    # Should complete without memory errors
    result = pipeline.run(items: items)

    expect(result[:success]).to be true
    expect(result[:processed_count]).to eq(1000)
  end

  it "provides incremental updates" do
    items = create_list(:item, 200)
    updates = []

    # Mock notification service to capture updates
    allow(NotificationService).to receive(:notify) do |update|
      updates << update
    end

    pipeline.run(items: items)

    # Should have received 2 updates (200 items / 100 stream_size)
    expect(updates.count).to eq(2)
  end
end
```

### Performance Tests

```ruby
RSpec.describe "Streaming Performance" do
  it "maintains memory bounds" do
    items = create_list(:item, 10000)

    # Monitor memory usage
    memory_before = GetProcessMem.new.mb

    pipeline.run(items: items)

    memory_after = GetProcessMem.new.mb
    memory_increase = memory_after - memory_before

    # Memory increase should be bounded
    expect(memory_increase).to be < 50  # MB
  end

  it "completes in reasonable time" do
    items = create_list(:item, 1000)

    time = Benchmark.realtime do
      pipeline.run(items: items)
    end

    # Should complete efficiently
    expect(time).to be < 60  # seconds
  end
end
```

---

## Migration Checklist

Before migrating to intelligent streaming, complete this checklist:

### Planning
- [ ] Identify large array processing in your codebase
- [ ] Measure current memory usage and performance
- [ ] Determine optimal stream_size for your data
- [ ] Identify if you need state management features
- [ ] Plan for incremental delivery if beneficial

### Implementation
- [ ] Add intelligent_streaming configuration to agent
- [ ] Implement skip_if for deduplication (if needed)
- [ ] Implement load_existing for caching (if needed)
- [ ] Add persist_each_stream for saving progress
- [ ] Implement progress hooks for monitoring
- [ ] Add error handling with on_stream_error

### Testing
- [ ] Unit test streaming configuration
- [ ] Test state management blocks
- [ ] Integration test with real pipeline
- [ ] Performance test with large datasets
- [ ] Test error recovery scenarios
- [ ] Verify memory bounds are maintained

### Deployment
- [ ] Deploy to staging environment
- [ ] Monitor memory usage in staging
- [ ] Test with production-like data volumes
- [ ] Set up monitoring/alerting
- [ ] Plan rollback strategy
- [ ] Deploy to production with monitoring

### Post-Deployment
- [ ] Monitor performance metrics
- [ ] Check error rates
- [ ] Verify cost savings (if applicable)
- [ ] Gather team feedback
- [ ] Document lessons learned
- [ ] Optimize stream_size if needed

---

## Getting Help

If you encounter issues during migration:

1. Check the [API Documentation](INTELLIGENT_STREAMING_API.md)
2. Review [working examples](examples/intelligent_streaming/)
3. Run the diagnostic script: `bundle exec rake streaming:diagnose`
4. Check logs for streaming-related messages (look for 🚀, ✅, ❌ emojis)
5. Contact the RAAF team with:
   - Your agent configuration
   - Error messages
   - Data characteristics (count, size, complexity)

---

## Summary

Intelligent streaming is the recommended approach for:
- Processing 100+ items through multiple agents
- Scenarios requiring state management
- Jobs that need resumability
- Pipelines requiring incremental delivery
- Memory-constrained environments

Start with a simple configuration and add features as needed. The streaming system is designed to be progressive - you can begin with just `stream_size` and add state management and hooks later.

Remember: **When in doubt, use intelligent streaming** - the small overhead is worth the benefits of memory efficiency, state management, and progress tracking.