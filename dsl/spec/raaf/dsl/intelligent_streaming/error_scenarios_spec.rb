# frozen_string_literal: true

require "spec_helper"
require "raaf/dsl/intelligent_streaming/config"
require "raaf/dsl/intelligent_streaming/scope"
require "raaf/dsl/intelligent_streaming/executor"
require "raaf/dsl/core/context_variables"

RSpec.describe "IntelligentStreaming Error Scenarios" do
  let(:context_class) { RAAF::DSL::ContextVariables }
  let(:passing_agent) do
    Class.new do
      def self.name
        "PassingAgent"
      end

      def run(context: {})
        context.merge(processed: true)
      end
    end
  end
  let(:items) { (1..15).map { |i| { id: i } } }

  # Agent that fails for the records the caller nominates.
  def failing_agent(fail_on: [], message: "Stream processing failed")
    Class.new do
      define_singleton_method(:name) { "FailingAgent" }

      define_method(:run) do |context: {}|
        record = context[:current_record]
        raise StandardError, message if fail_on.include?(record[:id])

        context.merge(processed: true)
      end
    end
  end

  def executor_for(config, context, agent_class)
    scope = RAAF::DSL::IntelligentStreaming::Scope.new(
      trigger_agent: agent_class,
      scope_agents: [agent_class],
      stream_size: config.stream_size,
      array_field: config.array_field
    )

    RAAF::DSL::IntelligentStreaming::Executor.new(scope: scope, context: context, config: config)
  end

  def config_for(stream_size: 5, over: :items, incremental: false, &block)
    config = RAAF::DSL::IntelligentStreaming::Config.new(
      stream_size: stream_size,
      over: over,
      incremental: incremental
    )
    config.instance_eval(&block) if block
    config
  end

  describe "stream execution failures" do
    context "partial stream failures" do
      it "keeps the results of the streams that succeeded" do
        agent_class = failing_agent(fail_on: [7])
        executor = executor_for(config_for, context_class.new(items: items), agent_class)

        results = executor.execute([agent_class.new])

        # Streams 1 and 3 completed; stream 2 (items 6-10) failed as a whole.
        expect(executor.execution_stats[:successful_streams]).to eq(2)
        expect(executor.execution_stats[:failed_streams]).to eq(1)
        expect(results.map { |r| r[:current_record][:id] }).to eq([1, 2, 3, 4, 5, 11, 12, 13, 14, 15])
      end

      it "executes the on_stream_error hook on failure" do
        errors = []
        config = config_for do
          on_stream_error { |num, total, stream_items, error| errors << [num, total, stream_items.size, error.message] }
        end

        agent_class = failing_agent(fail_on: [7])
        executor_for(config, context_class.new(items: items), agent_class).execute([agent_class.new])

        expect(errors).to eq([[2, 3, 5, "Stream processing failed"]])
      end

      it "reports the failing stream's own message" do
        errors = []
        config = config_for do
          on_stream_error { |_num, _total, _items, error| errors << error }
        end

        agent_class = failing_agent(fail_on: [7], message: "downstream timeout")
        executor_for(config, context_class.new(items: items), agent_class).execute([agent_class.new])

        expect(errors.first).to be_a(StandardError)
        expect(errors.first.message).to eq("downstream timeout")
      end
    end

    context "multiple stream failures" do
      it "counts every failed stream and keeps going" do
        agent_class = failing_agent(fail_on: [2, 7, 12])
        executor = executor_for(config_for, context_class.new(items: items), agent_class)

        results = executor.execute([agent_class.new])

        expect(executor.execution_stats[:failed_streams]).to eq(3)
        expect(executor.execution_stats[:successful_streams]).to eq(0)
        expect(results).to eq([])
      end
    end

    context "when configured to stop on error" do
      it "re-raises instead of continuing" do
        config = config_for
        config.blocks[:stop_on_error] = true

        agent_class = failing_agent(fail_on: [7])
        executor = executor_for(config, context_class.new(items: items), agent_class)

        expect { executor.execute([agent_class.new]) }.to raise_error(StandardError, "Stream processing failed")
      end
    end
  end

  describe "hook failures" do
    it "lets an on_stream_start failure fail its own stream only" do
      config = config_for do
        on_stream_start { |num, _total, _items| raise "hook exploded" if num == 1 }
      end

      executor = executor_for(config, context_class.new(items: items), passing_agent)
      results = executor.execute([passing_agent.new])

      expect(executor.execution_stats[:failed_streams]).to eq(1)
      expect(results.map { |r| r[:current_record][:id] }).to eq((6..15).to_a)
    end

    it "surfaces an on_stream_complete failure in non-incremental mode" do
      config = config_for do
        on_stream_complete { |_all_results| raise "complete hook exploded" }
      end

      executor = executor_for(config, context_class.new(items: items), passing_agent)

      expect { executor.execute([passing_agent.new]) }.to raise_error("complete hook exploded")
    end

    it "routes an incremental on_stream_complete failure through the error hook" do
      errors = []
      config = config_for(incremental: true) do
        on_stream_complete { |_num, _total, _data, _results| raise "incremental hook exploded" }
        on_stream_error { |_num, _total, _items, error| errors << error.message }
      end

      executor = executor_for(config, context_class.new(items: items), passing_agent)
      executor.execute([passing_agent.new])

      expect(errors).to eq(["incremental hook exploded"] * 3)
      expect(executor.execution_stats[:failed_streams]).to eq(3)
    end
  end

  describe "state management failures" do
    it "fails the stream when skip_if raises" do
      config = config_for do
        skip_if { |record, _context| raise "skip_if exploded" if record[:id] == 1 }
      end

      executor = executor_for(config, context_class.new(items: items), passing_agent)
      results = executor.execute([passing_agent.new])

      expect(executor.execution_stats[:failed_streams]).to eq(1)
      expect(results.map { |r| r[:current_record][:id] }).to eq((6..15).to_a)
    end

    it "fails the stream when load_existing raises for a skipped record" do
      config = config_for do
        skip_if { |record, _context| record[:id] == 1 }
        load_existing { |_record, _context| raise "load_existing exploded" }
      end

      executor = executor_for(config, context_class.new(items: items), passing_agent)
      executor.execute([passing_agent.new])

      expect(executor.execution_stats[:failed_streams]).to eq(1)
    end

    it "fails the stream when the persist block raises" do
      config = config_for do
        persist { |_stream_results, _context| raise "persist exploded" }
      end

      executor = executor_for(config, context_class.new(items: items), passing_agent)
      executor.execute([passing_agent.new])

      expect(executor.execution_stats[:failed_streams]).to eq(3)
      expect(executor.execution_stats[:successful_streams]).to eq(0)
    end
  end

  describe "recovery" do
    it "returns whatever completed when only some streams fail" do
      agent_class = failing_agent(fail_on: [1])
      executor = executor_for(config_for, context_class.new(items: items), agent_class)

      results = executor.execute([agent_class.new])

      expect(results).not_to be_empty
      expect(executor.execution_stats[:successful_streams]).to eq(2)
    end

    it "records timing even when streams fail" do
      agent_class = failing_agent(fail_on: [1])
      executor = executor_for(config_for, context_class.new(items: items), agent_class)
      executor.execute([agent_class.new])

      expect(executor.execution_stats[:start_time]).to be_a(Time)
      expect(executor.execution_stats[:end_time]).to be_a(Time)
    end
  end
end
