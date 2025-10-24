# Tests Specification: Intelligent Streaming

> Created: 2025-10-24
> Version: 2.0.0 (Unified Feature)
> RAAF Version: 2.0.0+

## Overview

Comprehensive test coverage for the unified intelligent streaming feature, including:
- **Unit Tests**: Core classes (IntelligentStreamingConfig, StreamingScope, IntelligentStreamingManager)
- **Integration Tests**: Pipeline integration, hook execution, state management
- **Incremental Delivery Tests**: Both `incremental: true` and `incremental: false` modes
- **State Management Tests**: skip_if, load_existing, persist_each_stream blocks
- **Edge Case Tests**: Empty arrays, single streams, nested scopes, errors
- **Performance Tests**: Overhead measurements, memory usage

## 1. Unit Tests

### IntelligentStreamingConfig Tests

**Purpose**: Verify configuration object behavior and validation

```ruby
RSpec.describe RAAF::DSL::IntelligentStreamingConfig do
  describe "#initialize" do
    context "with minimum required parameters" do
      it "creates config with batch_size and defaults" do
        config = described_class.new(batch_size: 100)

        expect(config.batch_size).to eq(100)
        expect(config.streaming?).to be false
        expect(config.has_state_management?).to be false
      end
    end

    context "with all parameters" do
      it "stores all provided configuration" do
        skip_block = proc { |r| r.id > 100 }
        load_block = proc { |r| { cached: true } }
        persist_block = proc { |b| puts b }

        config = described_class.new(
          batch_size: 100,
          array_field: :companies,
          streaming: true,
          skip_if_block: skip_block,
          load_existing_block: load_block,
          persist_block: persist_block
        )

        expect(config.batch_size).to eq(100)
        expect(config.array_field).to eq(:companies)
        expect(config.streaming?).to be true
        expect(config.has_state_management?).to be true
        expect(config.skip_if_block).to eq(skip_block)
      end
    end

    context "with invalid batch_size" do
      it "raises ConfigurationError for non-positive" do
        expect {
          described_class.new(batch_size: 0)
        }.to raise_error(RAAF::ConfigurationError)

        expect {
          described_class.new(batch_size: -50)
        }.to raise_error(RAAF::ConfigurationError)
      end

      it "raises ConfigurationError for non-integer" do
        expect {
          described_class.new(batch_size: "100")
        }.to raise_error(RAAF::ConfigurationError)
      end
    end
  end

  describe "#has_state_management?" do
    context "with no state management" do
      it "returns false" do
        config = described_class.new(batch_size: 100)
        expect(config.has_state_management?).to be false
      end
    end

    context "with skip_if only" do
      it "returns true" do
        config = described_class.new(
          batch_size: 100,
          skip_if_block: proc { true }
        )
        expect(config.has_state_management?).to be true
      end
    end

    context "with load_existing only" do
      it "returns true" do
        config = described_class.new(
          batch_size: 100,
          load_existing_block: proc { {} }
        )
        expect(config.has_state_management?).to be true
      end
    end

    context "with persist_each_batch only" do
      it "returns true" do
        config = described_class.new(
          batch_size: 100,
          persist_block: proc { |b| puts b }
        )
        expect(config.has_state_management?).to be true
      end
    end
  end

  describe "#streaming?" do
    it "returns true when streaming enabled" do
      config = described_class.new(batch_size: 100, streaming: true)
      expect(config.streaming?).to be true
    end

    it "returns false by default" do
      config = described_class.new(batch_size: 100)
      expect(config.streaming?).to be false
    end
  end
end
```

### StreamingScope Tests

**Purpose**: Verify scope configuration and state management evaluation

```ruby
RSpec.describe RAAF::DSL::StreamingScope do
  let(:trigger_agent) { instance_double("Agent", agent_name: "QuickFit") }
  let(:agent1) { instance_double("Agent", agent_name: "DeepIntel") }
  let(:agent2) { instance_double("Agent", agent_name: "Enrichment") }
  let(:config) { instance_double("Config", batch_size: 100, array_field: :companies) }

  describe "#initialize" do
    it "creates scope with configuration" do
      scope = described_class.new(
        trigger_agent: trigger_agent,
        agents_in_scope: [agent1, agent2],
        config: config
      )

      expect(scope.trigger_agent).to eq(trigger_agent)
      expect(scope.agents_in_scope).to eq([agent1, agent2])
      expect(scope.config).to eq(config)
    end

    it "generates unique scope_id" do
      scope1 = described_class.new(trigger_agent: trigger_agent, agents_in_scope: [], config: config)
      scope2 = described_class.new(trigger_agent: trigger_agent, agents_in_scope: [], config: config)

      expect(scope1.scope_id).not_to eq(scope2.scope_id)
    end
  end

  describe "#skip_record?" do
    context "with skip_if configured" do
      let(:skip_block) { proc { |r, _c| r[:id] > 50 } }
      let(:config) do
        instance_double("Config",
          batch_size: 100,
          array_field: :companies,
          skip_if_block: skip_block
        )
      end

      it "returns true when condition matches" do
        scope = described_class.new(trigger_agent: trigger_agent, agents_in_scope: [], config: config)

        expect(scope.skip_record?({ id: 100 }, {})).to be true
        expect(scope.skip_record?({ id: 25 }, {})).to be false
      end
    end

    context "without skip_if" do
      it "returns false for all records" do
        config_no_skip = instance_double("Config",
          batch_size: 100,
          array_field: :companies,
          skip_if_block: nil
        )
        scope = described_class.new(trigger_agent: trigger_agent, agents_in_scope: [], config: config_no_skip)

        expect(scope.skip_record?({ id: 100 }, {})).to be false
      end
    end
  end

  describe "#load_existing" do
    context "with load_existing configured" do
      let(:load_block) { proc { |r, _c| { cached_result: r[:id] * 10 } } }
      let(:config) do
        instance_double("Config",
          batch_size: 100,
          array_field: :companies,
          load_existing_block: load_block
        )
      end

      it "calls block and returns result" do
        scope = described_class.new(trigger_agent: trigger_agent, agents_in_scope: [], config: config)

        result = scope.load_existing({ id: 5 }, {})
        expect(result).to eq({ cached_result: 50 })
      end
    end

    context "without load_existing" do
      it "returns nil" do
        config_no_load = instance_double("Config",
          batch_size: 100,
          array_field: :companies,
          load_existing_block: nil
        )
        scope = described_class.new(trigger_agent: trigger_agent, agents_in_scope: [], config: config_no_load)

        expect(scope.load_existing({ id: 5 }, {})).to be nil
      end
    end
  end

  describe "#persist_batch" do
    context "with persist_each_batch configured" do
      let(:persist_block) { proc { |b, _c| puts b.size } }
      let(:config) do
        instance_double("Config",
          batch_size: 100,
          array_field: :companies,
          persist_block: persist_block
        )
      end

      it "calls persist block" do
        scope = described_class.new(trigger_agent: trigger_agent, agents_in_scope: [], config: config)

        expect_any_instance_of(Proc).to receive(:call)
        scope.persist_batch([{ id: 1 }], {})
      end
    end

    context "without persist_each_batch" do
      it "does nothing" do
        config_no_persist = instance_double("Config",
          batch_size: 100,
          array_field: :companies,
          persist_block: nil
        )
        scope = described_class.new(trigger_agent: trigger_agent, agents_in_scope: [], config: config_no_persist)

        expect {
          scope.persist_batch([{ id: 1 }], {})
        }.not_to raise_error
      end
    end
  end

  describe "#streaming?" do
    it "returns true when streaming enabled in config" do
      config_streaming = instance_double("Config",
        batch_size: 100,
        array_field: :companies,
        streaming?: true
      )
      scope = described_class.new(trigger_agent: trigger_agent, agents_in_scope: [], config: config_streaming)

      expect(scope.streaming?).to be true
    end

    it "returns false when streaming disabled" do
      config_no_stream = instance_double("Config",
        batch_size: 100,
        array_field: :companies,
        streaming?: false
      )
      scope = described_class.new(trigger_agent: trigger_agent, agents_in_scope: [], config: config_no_stream)

      expect(scope.streaming?).to be false
    end
  end
end
```

## 2. Integration Tests

### Pipeline Streaming Integration

**Purpose**: Verify streaming works correctly within pipeline execution

```ruby
RSpec.describe "Pipeline with intelligent_streaming" do
  let(:agent_with_streaming) do
    Class.new(RAAF::DSL::Agent) do
      agent_name "Analyzer"

      intelligent_streaming stream_size: 2, over: :items do
        on_stream_complete { |stream_num, total, results|
          @stream_results ||= {}
          @stream_results[stream_num] = results
        }
      end
    end
  end

  let(:simple_agent) do
    Class.new(RAAF::DSL::Agent) do
      agent_name "Processor"

      def execute(context, _results)
        { processed: true, count: context[:items].size }
      end
    end
  end

  let(:pipeline) do
    Class.new(RAAF::Pipeline) do
      flow SimpleAgent >> Agent WithStreaming
    end
  end

  context "with 5 items and stream size 2" do
    it "executes 3 streams (2, 2, 1)" do
      context = { items: [1, 2, 3, 4, 5] }

      result = pipeline.new(context).run

      # Verify streaming happened
      # Check results contain all items
    end
  end

  context "with incremental: true" do
    it "calls on_stream_complete after each stream" do
      # Verify callback called with stream_num, total, stream_results
    end
  end

  context "with incremental: false" do
    it "calls on_stream_complete once at end" do
      # Verify callback called with all_results parameter
    end
  end
end
```

### State Management Integration

**Purpose**: Verify skip_if, load_existing, persist_each_stream work together

```ruby
RSpec.describe "State management with streaming" do
  let(:agent_with_state) do
    Class.new(RAAF::DSL::Agent) do
      agent_name "StatefulAnalyzer"

      intelligent_streaming stream_size: 2, over: :items do
        skip_if { |record, _c| record[:skip] == true }
        load_existing { |record, _c| record[:cached] }
        persist_each_stream { |stream, _c| @persisted = stream }
      end
    end
  end

  context "skip_if filtering" do
    it "excludes matching records from processing" do
      items = [
        { id: 1, skip: false },
        { id: 2, skip: true },
        { id: 3, skip: false }
      ]

      # Verify agent processes [1, 3], skips [2]
    end
  end

  context "load_existing integration" do
    it "merges loaded results with agent results" do
      items = [
        { id: 1, cached: { value: 10 } },
        { id: 2, cached: nil },
        { id: 3, cached: { value: 30 } }
      ]

      # Verify final output includes cached and processed values
    end
  end

  context "persist_each_batch" do
    it "saves batch results after processing" do
      # Verify persist block called with batch results
      # Verify resumable processing possible
    end
  end
end
```

## 3. Incremental Delivery Mode Tests

**Purpose**: Verify incremental delivery behavior for both modes

```ruby
RSpec.describe "Incremental delivery modes" do
  context "incremental: true" do
    let(:incremental_agent) do
      Class.new(RAAF::DSL::Agent) do
        intelligent_streaming stream_size: 2, over: :items, incremental: true do
          on_stream_complete do |stream_num, total, results|
            @callbacks ||= []
            @callbacks << { stream: stream_num, total: total, count: results.size }
          end
        end
      end
    end

    it "calls on_stream_complete with 3 parameters" do
      # on_stream_complete { |stream_num, total, stream_results| }
    end

    it "calls callback per stream, not at end" do
      # 5 items, stream size 2 -> 3 streams -> 3 callbacks
    end

    it "provides immediate access to stream results" do
      # Can queue/process results as each stream completes
    end
  end

  context "incremental: false" do
    let(:non_incremental_agent) do
      Class.new(RAAF::DSL::Agent) do
        intelligent_streaming stream_size: 2, over: :items, incremental: false do
          on_stream_complete do |all_results|
            @final_results = all_results
          end
        end
      end
    end

    it "calls on_stream_complete with 1 parameter" do
      # on_stream_complete { |all_results| }
    end

    it "calls callback only after all streams" do
      # 5 items, stream size 2 -> 3 streams -> 1 callback at end
    end

    it "provides aggregated results" do
      # Can perform post-processing on all results
    end
  end
end
```

## 4. Edge Case Tests

**Purpose**: Verify correct behavior in edge cases

```ruby
RSpec.describe "Edge cases" do
  context "empty array" do
    it "creates no batches and completes normally" do
      context = { items: [] }
      # Verify no batching, returns empty results
    end
  end

  context "single item (less than batch_size)" do
    it "creates single batch" do
      context = { items: [1] }
      batch_size = 100
      # Verify creates 1 batch with 1 item
    end
  end

  context "exact batch size multiple" do
    it "creates exact number of full batches" do
      context = { items: Array(1..100) }
      batch_size = 25
      # Verify creates exactly 4 batches of 25 items
    end
  end

  context "multiple array fields without 'over' specified" do
    it "raises ConfigurationError" do
      context = { companies: [1, 2], products: [3, 4] }
      # Verify error requires explicit 'over: :field_name'
    end
  end

  context "batch failure in middle" do
    it "preserves results from successful batches" do
      # Batch 1 succeeds, Batch 2 fails, Batch 3 succeeds
      # Verify results from 1 and 3 are preserved
    end
  end

  context "nested batching (batching within batching)" do
    it "raises ConfigurationError" do
      # Agent1: intelligent_batching
      #   Agent2: intelligent_batching
      # Verify error on detection
    end
  end
end
```

## 5. Error Handling Tests

**Purpose**: Verify error handling and recovery

```ruby
RSpec.describe "Error handling" do
  context "on_batch_error hook" do
    let(:error_agent) do
      Class.new(RAAF::DSL::Agent) do
        intelligent_batching batch_size: 2, over: :items do
          on_batch_error do |batch_num, total, error, context|
            @error_info = { batch: batch_num, error: error.message }
          end
        end
      end
    end

    it "fires hook when batch fails" do
      # Verify on_batch_error called with correct parameters
    end

    it "includes batch number and error details" do
      # Verify batch_num, total, error, context passed
    end
  end

  context "partial results with errors" do
    it "returns successful batches even if one fails" do
      # 3 batches, batch 2 fails
      # Verify returns results from batches 1 and 3
    end
  end
end
```

## 6. Performance Tests

**Purpose**: Verify performance targets are met

```ruby
RSpec.describe "Performance" do
  context "batching overhead" do
    it "adds < 2ms per batch (size 100)" do
      # Measure batch creation, context prep, merging overhead
      # Target: < 2ms per batch
    end

    it "adds < 5ms per batch (size 1000)" do
      # Measure with larger batches
      # Target: < 5ms per batch
    end
  end

  context "memory efficiency" do
    it "limits peak memory to O(batch_size)" do
      # Process 10,000 items with batch size 100
      # Verify peak memory ~ 100 items, not 10,000
    end
  end
end
```

## Test Coverage Goals

- **Line Coverage**: ≥ 95% for all new classes
- **Branch Coverage**: ≥ 90% for conditional logic
- **Integration**: All pipeline combinations tested
- **Streaming**: Both `true` and `false` modes verified
- **State Management**: All optional blocks tested (individually and combined)
- **Edge Cases**: Empty, single, exact multiple, error scenarios
- **Performance**: Overhead and memory usage verified

## Running Tests

```bash
# Run all batching tests
bundle exec rspec spec/dsl/pipeline_dsl/intelligent_batching_spec.rb

# Run specific test
bundle exec rspec spec/dsl/pipeline_dsl/intelligent_batching_spec.rb:42

# Run with coverage
bundle exec rspec spec/dsl/pipeline_dsl/intelligent_batching_spec.rb --require simplecov

# Run performance tests
bundle exec rspec spec/dsl/pipeline_dsl/intelligent_batching_spec.rb -t performance
```
