# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/raaf/dsl/intelligent_streaming"
require_relative "../../../../lib/raaf/dsl/intelligent_streaming/executor"
require_relative "../../../../lib/raaf/dsl/core/context_variables"

RSpec.describe RAAF::DSL::IntelligentStreaming::Executor do
  let(:stream_size) { 10 }
  let(:array_field) { :items }

  let(:config) do
    RAAF::DSL::IntelligentStreaming::Config.new(
      stream_size: stream_size,
      over: array_field,
      incremental: false
    )
  end

  let(:scope) do
    RAAF::DSL::IntelligentStreaming::Scope.new(
      trigger_agent: MockAgent,
      scope_agents: [ProcessingAgent],
      stream_size: stream_size,
      array_field: array_field
    )
  end

  let(:context) do
    RAAF::DSL::ContextVariables.new(
      items: test_items,
      other_data: "test"
    )
  end

  let(:test_items) { (1..25).to_a }

  let(:agent_chain) { [MockAgent.new, ProcessingAgent.new] }

  let(:executor) { described_class.new(scope: scope, context: context, config: config) }

  # Mock agent classes for testing
  class MockAgent
    def self.name
      "MockAgent"
    end

    def run(context: {})
      # Simple pass-through agent
      context[:processed] = true if context[:current_record]
      context
    end
  end

  class ProcessingAgent
    def self.name
      "ProcessingAgent"
    end

    def run(context: {})
      # Add processing flag
      context[:processing_complete] = true if context[:current_record]
      context
    end
  end

  describe "#initialize" do
    it "initializes with scope, context, and config" do
      expect(executor).to be_a(described_class)
      expect(executor.instance_variable_get(:@scope)).to eq(scope)
      expect(executor.instance_variable_get(:@context)).to eq(context)
      expect(executor.instance_variable_get(:@config)).to eq(config)
    end
  end

  describe "#execute" do
    context "with valid array field" do
      it "splits items into streams of configured size" do
        results = []

        # Patch to track stream execution
        allow(executor).to receive(:execute_stream) do |args|
          results << args[:stream_items].size
          []
        end

        executor.execute(agent_chain)

        # Should have 3 streams: 10, 10, 5 items
        expect(results).to eq([10, 10, 5])
      end

      it "executes each stream through all agents in chain" do
        execution_log = []

        # Track execution
        allow_any_instance_of(MockAgent).to receive(:run) do |_, context:|
          execution_log << { agent: "MockAgent", record: context[:current_record] }
          context.merge(processed: true)
        end

        allow_any_instance_of(ProcessingAgent).to receive(:run) do |_, context:|
          execution_log << { agent: "ProcessingAgent", record: context[:current_record] }
          context.merge(processing_complete: true)
        end

        executor.execute(agent_chain)

        # Each item should be processed by both agents
        test_items.each do |item|
          expect(execution_log).to include(
            hash_including(agent: "MockAgent", record: item)
          )
          expect(execution_log).to include(
            hash_including(agent: "ProcessingAgent", record: item)
          )
        end
      end

      it "merges results from all streams" do
        allow_any_instance_of(MockAgent).to receive(:run) do |_, context:|
          record = context[:current_record]
          context.merge(processed_id: record)
        end

        allow_any_instance_of(ProcessingAgent).to receive(:run) do |_, context:|
          context.merge(final: true)
        end

        result = executor.execute(agent_chain)

        expect(result).to be_a(Array)
        expect(result.size).to eq(25)
        expect(result.all? { |r| r[:final] == true }).to be true
      end
    end

    context "with empty array" do
      let(:test_items) { [] }

      it "returns empty result without error" do
        result = executor.execute(agent_chain)
        expect(result).to eq([])
      end

      it "does not execute any streams" do
        expect(executor).not_to receive(:execute_stream)
        executor.execute(agent_chain)
      end
    end

    context "with single item" do
      let(:test_items) { [42] }

      it "processes single item in one stream" do
        result = executor.execute(agent_chain)
        expect(result).to be_a(Array)
        expect(result.size).to eq(1)
      end
    end

    context "with exact stream size" do
      let(:test_items) { (1..10).to_a }
      let(:stream_size) { 10 }

      it "processes in exactly one stream" do
        stream_count = 0

        allow(executor).to receive(:execute_stream).and_wrap_original do |method, **args|
          stream_count += 1
          method.call(**args)
        end

        executor.execute(agent_chain)
        expect(stream_count).to eq(1)
      end
    end

    context "when array field is missing" do
      let(:context) do
        RAAF::DSL::ContextVariables.new(
          other_data: "test"
        )
      end

      it "raises error with helpful message" do
        expect {
          executor.execute(agent_chain)
        }.to raise_error(RAAF::DSL::IntelligentStreaming::ExecutorError, /No array field 'items' found in context/)
      end
    end

    context "when array field contains non-array" do
      let(:context) do
        RAAF::DSL::ContextVariables.new(
          items: "not an array"
        )
      end

      it "raises error with helpful message" do
        expect {
          executor.execute(agent_chain)
        }.to raise_error(RAAF::DSL::IntelligentStreaming::ExecutorError, /Field 'items' does not contain an array/)
      end
    end
  end

  describe "#execute_stream with state management" do
    let(:skipped_ids) { [1, 3, 5, 7, 9] }
    let(:cached_results) { { 1 => { cached: true, id: 1 }, 3 => { cached: true, id: 3 } } }

    let(:config_with_state) do
      RAAF::DSL::IntelligentStreaming::Config.new(
        stream_size: stream_size,
        over: array_field,
        incremental: false
      ).tap do |cfg|
        cfg.skip_if { |record| skipped_ids.include?(record) }
        cfg.load_existing { |record| cached_results[record] }
        cfg.persist_each_stream { |results| @persisted_results = results }
      end
    end

    let(:executor_with_state) { described_class.new(scope: scope, context: context, config: config_with_state) }

    it "evaluates skip_if for each record" do
      skip_evaluations = []

      config_with_state.instance_eval do
        skip_if { |record|
          skip_evaluations << record
          skipped_ids.include?(record)
        }
      end

      executor_with_state.execute(agent_chain)

      # Should evaluate skip_if for all records
      expect(skip_evaluations.sort).to eq(test_items)
    end

    it "loads existing results for skipped records" do
      loaded_records = []

      config_with_state.instance_eval do
        load_existing { |record|
          loaded_records << record
          cached_results[record]
        }
      end

      result = executor_with_state.execute(agent_chain)

      # Should only load for skipped records
      expect(loaded_records.sort).to eq(skipped_ids)
    end

    it "processes non-skipped records through agents" do
      processed_records = []

      allow_any_instance_of(MockAgent).to receive(:run) do |_, context:|
        record = context[:current_record]
        processed_records << record if record
        context
      end

      executor_with_state.execute(agent_chain)

      # Should only process non-skipped records
      non_skipped = test_items - skipped_ids
      expect(processed_records.sort).to eq(non_skipped.sort)
    end

    it "merges loaded and processed results correctly" do
      allow_any_instance_of(MockAgent).to receive(:run) do |_, context:|
        context.merge(agent_processed: true)
      end

      result = executor_with_state.execute(agent_chain)

      # Check that we have results for all items
      expect(result.size).to eq(test_items.size)

      # Verify cached results are included
      cached_items = result.select { |r| r[:cached] == true }
      expect(cached_items.size).to eq(cached_results.size)

      # Verify processed results are included
      processed_items = result.select { |r| r[:agent_processed] == true }
      non_skipped_count = test_items.size - skipped_ids.size
      expect(processed_items.size).to eq(non_skipped_count)
    end

    it "calls persist_each_stream after each stream completes" do
      persisted_streams = []

      config_with_state.instance_eval do
        persist_each_stream { |results|
          persisted_streams << results.size
        }
      end

      executor_with_state.execute(agent_chain)

      # Should persist 3 streams (10, 10, 5 items)
      expect(persisted_streams).to eq([10, 10, 5])
    end
  end

  describe "#execute_stream with hooks" do
    let(:hook_calls) { [] }

    context "on_stream_start hook" do
      let(:config_with_hooks) do
        RAAF::DSL::IntelligentStreaming::Config.new(
          stream_size: stream_size,
          over: array_field,
          incremental: false
        ).tap do |cfg|
          cfg.on_stream_start { |stream_num, total, data|
            hook_calls << {
              hook: :start,
              stream_num: stream_num,
              total: total,
              data_size: data.size
            }
          }
        end
      end

      let(:executor_with_hooks) { described_class.new(scope: scope, context: context, config: config_with_hooks) }

      it "fires before each stream execution" do
        executor_with_hooks.execute(agent_chain)

        expect(hook_calls.size).to eq(3)
        expect(hook_calls[0]).to include(hook: :start, stream_num: 1, total: 3, data_size: 10)
        expect(hook_calls[1]).to include(hook: :start, stream_num: 2, total: 3, data_size: 10)
        expect(hook_calls[2]).to include(hook: :start, stream_num: 3, total: 3, data_size: 5)
      end
    end

    context "on_stream_complete hook with incremental: false" do
      let(:config_non_incremental) do
        RAAF::DSL::IntelligentStreaming::Config.new(
          stream_size: stream_size,
          over: array_field,
          incremental: false
        ).tap do |cfg|
          cfg.on_stream_complete { |all_results|
            hook_calls << {
              hook: :complete,
              param_count: 1,
              results_size: all_results.size
            }
          }
        end
      end

      let(:executor_non_incremental) { described_class.new(scope: scope, context: context, config: config_non_incremental) }

      it "fires once at end with all results" do
        executor_non_incremental.execute(agent_chain)

        expect(hook_calls.size).to eq(1)
        expect(hook_calls[0]).to include(
          hook: :complete,
          param_count: 1,
          results_size: 25
        )
      end
    end

    context "on_stream_complete hook with incremental: true" do
      let(:config_incremental) do
        RAAF::DSL::IntelligentStreaming::Config.new(
          stream_size: stream_size,
          over: array_field,
          incremental: true
        ).tap do |cfg|
          cfg.on_stream_complete { |stream_num, total, stream_data, stream_results|
            hook_calls << {
              hook: :complete,
              param_count: 4,
              stream_num: stream_num,
              total: total,
              data_size: stream_data.size,
              results_size: stream_results.size
            }
          }
        end
      end

      let(:executor_incremental) { described_class.new(scope: scope, context: context, config: config_incremental) }

      it "fires after each stream with stream results" do
        executor_incremental.execute(agent_chain)

        expect(hook_calls.size).to eq(3)

        expect(hook_calls[0]).to include(
          hook: :complete,
          param_count: 4,
          stream_num: 1,
          total: 3,
          data_size: 10,
          results_size: 10
        )

        expect(hook_calls[1]).to include(
          hook: :complete,
          param_count: 4,
          stream_num: 2,
          total: 3,
          data_size: 10,
          results_size: 10
        )

        expect(hook_calls[2]).to include(
          hook: :complete,
          param_count: 4,
          stream_num: 3,
          total: 3,
          data_size: 5,
          results_size: 5
        )
      end
    end

    context "on_stream_error hook" do
      let(:config_with_error_hook) do
        RAAF::DSL::IntelligentStreaming::Config.new(
          stream_size: stream_size,
          over: array_field,
          incremental: false
        ).tap do |cfg|
          cfg.on_stream_error { |stream_num, total, data, error|
            hook_calls << {
              hook: :error,
              stream_num: stream_num,
              total: total,
              data_size: data.size,
              error_message: error.message
            }
          }
        end
      end

      let(:executor_with_error_hook) { described_class.new(scope: scope, context: context, config: config_with_error_hook) }

      it "fires when stream encounters error" do
        # Make second stream fail
        call_count = 0
        allow_any_instance_of(MockAgent).to receive(:run) do |_, context:|
          call_count += 1
          raise StandardError, "Stream processing failed" if call_count == 15 # Second stream
          context
        end

        # Execute and expect partial results
        result = executor_with_error_hook.execute(agent_chain)

        # Error hook should have been called for failed stream
        error_hooks = hook_calls.select { |h| h[:hook] == :error }
        expect(error_hooks.size).to eq(1)
        expect(error_hooks[0]).to include(
          hook: :error,
          stream_num: 2,
          total: 3,
          data_size: 10,
          error_message: "Stream processing failed"
        )

        # Should still return partial results from successful streams
        expect(result).to be_a(Array)
        expect(result.size).to be >= 10 # At least first stream
      end
    end
  end

  describe "#merge_results" do
    it "concatenates array results" do
      all_results = [
        [1, 2, 3],
        [4, 5, 6],
        [7, 8]
      ]

      merged = executor.send(:merge_results, all_results)
      expect(merged).to eq([1, 2, 3, 4, 5, 6, 7, 8])
    end

    it "deep merges hash results" do
      all_results = [
        [{ count: 10, data: { a: 1 } }],
        [{ count: 20, data: { b: 2 } }],
        [{ count: 15, data: { c: 3 } }]
      ]

      merged = executor.send(:merge_results, all_results)
      expect(merged).to eq({
        count: 15, # Last wins
        data: { a: 1, b: 2, c: 3 } # Deep merge
      })
    end

    it "returns flattened array for non-hash results" do
      all_results = [[1], [2], [3]]

      merged = executor.send(:merge_results, all_results)
      expect(merged).to eq([1, 2, 3])
    end

    it "handles mixed result types gracefully" do
      all_results = [
        [1, 2],
        [{ data: "test" }],
        ["string"]
      ]

      merged = executor.send(:merge_results, all_results)
      expect(merged).to eq([1, 2, { data: "test" }, "string"])
    end
  end

  describe "edge cases" do
    context "with very large stream size" do
      let(:stream_size) { 1000 }
      let(:test_items) { (1..100).to_a }

      it "processes all items in single stream" do
        stream_count = 0

        allow(executor).to receive(:execute_stream).and_wrap_original do |method, **args|
          stream_count += 1
          expect(args[:stream_items].size).to eq(100)
          method.call(**args)
        end

        executor.execute(agent_chain)
        expect(stream_count).to eq(1)
      end
    end

    context "with stream size of 1" do
      let(:stream_size) { 1 }
      let(:test_items) { [1, 2, 3] }

      it "processes each item in separate stream" do
        stream_count = 0

        allow(executor).to receive(:execute_stream).and_wrap_original do |method, **args|
          stream_count += 1
          expect(args[:stream_items].size).to eq(1)
          method.call(**args)
        end

        executor.execute(agent_chain)
        expect(stream_count).to eq(3)
      end
    end
  end

  describe "thread safety" do
    it "handles concurrent stream execution safely" do
      # This tests that the executor doesn't have race conditions
      # when used in multi-threaded contexts

      threads = []
      results = []
      mutex = Mutex.new

      3.times do |i|
        threads << Thread.new do
          local_context = RAAF::DSL::ContextVariables.new(
            items: (1..10).map { |n| n + (i * 100) }
          )

          local_executor = described_class.new(
            scope: scope,
            context: local_context,
            config: config
          )

          result = local_executor.execute(agent_chain)

          mutex.synchronize do
            results << result
          end
        end
      end

      threads.each(&:join)

      # Each thread should have processed its items independently
      expect(results.size).to eq(3)
      expect(results[0].size).to eq(10)
      expect(results[1].size).to eq(10)
      expect(results[2].size).to eq(10)
    end
  end

  describe "performance characteristics" do
    let(:large_items) { (1..1000).to_a }
    let(:stream_size) { 100 }

    let(:context) do
      RAAF::DSL::ContextVariables.new(
        items: large_items
      )
    end

    it "maintains memory efficiency with large datasets" do
      # Track memory usage pattern
      memory_snapshots = []

      allow(executor).to receive(:execute_stream).and_wrap_original do |method, **args|
        # Simulate memory snapshot
        memory_snapshots << args[:stream_items].size
        method.call(**args)
      end

      executor.execute(agent_chain)

      # Memory should be bounded by stream size, not total size
      expect(memory_snapshots.max).to eq(100)
      expect(memory_snapshots.size).to eq(10) # 1000 / 100
    end

    it "has acceptable overhead per stream" do
      start_time = Time.now
      executor.execute(agent_chain)
      duration = Time.now - start_time

      # Should complete reasonably quickly
      expect(duration).to be < 1.0 # Less than 1 second for 1000 items
    end
  end
end