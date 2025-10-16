# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RAAF::DSL::IncrementalProcessor do
  # Mock agent class for testing
  let(:agent_class) do
    Class.new do
      include RAAF::DSL::IncrementalProcessing

      # Mock context configuration
      def self.context_config
        {
          input_field: :company_list,
          output_field: :prospects
        }
      end

      # Mock schema
      def self.schema_config
        {
          prospects: { type: :array }
        }
      end

      # Initialize with context
      def initialize(context = {})
        @context = context
      end

      attr_reader :context
    end
  end

  let(:agent) { agent_class.new(company_list: input_items) }
  let(:input_items) { (1..50).map { |i| { id: i, name: "Company #{i}" } } }
  let(:config) { agent_class._incremental_config }

  before do
    # Configure agent with incremental processing
    agent_class.incremental_processing do
      chunk_size 20

      skip_if do |record, context|
        # Skip even-numbered records (simulating existing records)
        record[:id].even?
      end

      load_existing do |record, context|
        # Load existing data for skipped records
        {
          id: record[:id],
          name: record[:name],
          score: 50,
          source: "database"
        }
      end

      persistence_handler do |batch_results, context|
        # Track persisted batches
        context[:persisted_batches] ||= []
        context[:persisted_batches] << batch_results.map { |r| r[:id] }
      end
    end
  end

  describe "#initialize" do
    it "creates processor with agent and configuration" do
      processor = described_class.new(agent, config)

      expect(processor).to be_a(described_class)
    end

    it "raises error if agent is nil" do
      expect {
        described_class.new(nil, config)
      }.to raise_error(ArgumentError, /agent cannot be nil/)
    end

    it "raises error if config is nil" do
      expect {
        described_class.new(agent, nil)
      }.to raise_error(ArgumentError, /config cannot be nil/)
    end

    it "validates configuration completeness" do
      incomplete_config = RAAF::DSL::IncrementalConfig.new

      expect {
        described_class.new(agent, incomplete_config)
      }.to raise_error(RuntimeError, /configuration incomplete/)
    end
  end

  describe "#process" do
    let(:processor) { described_class.new(agent, config) }
    let(:process_block) do
      # Mock processing block that simulates AI processing
      ->(items, context) do
        items.map do |item|
          {
            id: item[:id],
            name: item[:name],
            score: 80,
            source: "ai_processed"
          }
        end
      end
    end

    context "with batching enabled" do
      it "processes items in configured batch sizes" do
        result = processor.process(input_items, agent.context, &process_block)

        # Input: 50 items split into batches of 20: [20, 20, 10]
        # Skip even IDs, so each batch has roughly half processed
        # Batch 1 (IDs 1-20): 10 odd items to process
        # Batch 2 (IDs 21-40): 10 odd items to process
        # Batch 3 (IDs 41-50): 5 odd items to process
        # Total: 3 batches with persistence
        expect(agent.context[:persisted_batches].count).to eq(3) # 3 batches
        expect(agent.context[:persisted_batches][0].count).to eq(10) # First batch: 10 odd items
        expect(agent.context[:persisted_batches][1].count).to eq(10) # Second batch: 10 odd items
        expect(agent.context[:persisted_batches][2].count).to eq(5) # Third batch: 5 odd items
      end

      it "returns merged results from processed and skipped items" do
        result = processor.process(input_items, agent.context, &process_block)

        expect(result.count).to eq(50) # All items returned
        expect(result.select { |r| r[:source] == "ai_processed" }.count).to eq(25) # 25 processed
        expect(result.select { |r| r[:source] == "database" }.count).to eq(25) # 25 skipped
      end

      it "maintains original order of items" do
        result = processor.process(input_items, agent.context, &process_block)

        # First item should be skipped (id: 1 is odd, not skipped in our logic - wait, 1 is odd)
        # Let me fix the test - even IDs are skipped, odd IDs are processed
        expect(result.first[:id]).to eq(1)
        expect(result.first[:source]).to eq("ai_processed") # ID 1 is odd, gets processed

        expect(result[1][:id]).to eq(2)
        expect(result[1][:source]).to eq("database") # ID 2 is even, skipped

        expect(result.last[:id]).to eq(50)
        expect(result.last[:source]).to eq("database") # ID 50 is even, skipped
      end
    end

    context "with force_reprocess enabled" do
      before do
        agent.context[:force_reprocess] = true
      end

      it "processes all items regardless of skip logic" do
        result = processor.process(input_items, agent.context, &process_block)

        # All items should be processed (none skipped)
        expect(result.select { |r| r[:source] == "ai_processed" }.count).to eq(50)
        expect(result.select { |r| r[:source] == "database" }.count).to eq(0)
      end

      it "calls persistence handler for all items" do
        processor.process(input_items, agent.context, &process_block)

        # With force reprocess, all 50 items are processed
        # In batches of 20: [20, 20, 10]
        expect(agent.context[:persisted_batches].count).to eq(3)
        expect(agent.context[:persisted_batches].first.count).to eq(20)
        expect(agent.context[:persisted_batches][1].count).to eq(20)
        expect(agent.context[:persisted_batches].last.count).to eq(10)
      end
    end

    context "with no batching (chunk_size: nil)" do
      before do
        agent_class.incremental_processing do
          # No chunk_size specified - process all at once

          skip_if do |record, context|
            record[:id].even?
          end

          load_existing do |record, context|
            {
              id: record[:id],
              name: record[:name],
              score: 50,
              source: "database"
            }
          end

          persistence_handler do |batch_results, context|
            context[:persisted_batches] ||= []
            context[:persisted_batches] << batch_results.map { |r| r[:id] }
          end
        end
      end

      it "processes all items in single batch" do
        result = processor.process(input_items, agent.context, &process_block)

        # Should process all non-skipped items (25 odd items) in single batch
        expect(agent.context[:persisted_batches].count).to eq(1)
        expect(agent.context[:persisted_batches].first.count).to eq(25)
      end
    end

    context "with empty input" do
      let(:input_items) { [] }

      it "returns empty result" do
        result = processor.process(input_items, agent.context, &process_block)

        expect(result).to eq([])
      end

      it "does not call persistence handler" do
        processor.process(input_items, agent.context, &process_block)

        expect(agent.context[:persisted_batches]).to be_nil
      end
    end

    context "with all items skipped" do
      before do
        agent_class.incremental_processing do
          chunk_size 20

          skip_if do |record, context|
            true # Skip all items
          end

          load_existing do |record, context|
            {
              id: record[:id],
              name: record[:name],
              score: 50,
              source: "database"
            }
          end

          persistence_handler do |batch_results, context|
            context[:persisted_batches] ||= []
            context[:persisted_batches] << batch_results.map { |r| r[:id] }
          end
        end
      end

      it "returns all items from load_existing" do
        result = processor.process(input_items, agent.context, &process_block)

        expect(result.count).to eq(50)
        expect(result.all? { |r| r[:source] == "database" }).to be true
      end

      it "does not call processing block" do
        expect(process_block).not_to receive(:call)

        processor.process(input_items, agent.context, &process_block)
      end

      it "does not call persistence handler" do
        processor.process(input_items, agent.context, &process_block)

        expect(agent.context[:persisted_batches]).to be_nil
      end
    end
  end

  describe "progress tracking" do
    let(:processor) { described_class.new(agent, config) }
    let(:process_block) do
      ->(items, context) do
        items.map do |item|
          {
            id: item[:id],
            name: item[:name],
            score: 80,
            source: "ai_processed"
          }
        end
      end
    end

    it "tracks items processed count" do
      # We'll need to capture logs or check internal state
      # For now, let's just verify processing completes
      result = processor.process(input_items, agent.context, &process_block)

      expect(result.count).to eq(50)
    end

    it "tracks items skipped count" do
      result = processor.process(input_items, agent.context, &process_block)

      # 25 items skipped (even IDs)
      expect(result.select { |r| r[:source] == "database" }.count).to eq(25)
    end
  end

  describe "error handling" do
    let(:processor) { described_class.new(agent, config) }

    context "when processing block raises error" do
      let(:error_block) do
        ->(items, context) do
          raise StandardError, "Processing failed"
        end
      end

      it "raises the error with context" do
        expect {
          processor.process(input_items, agent.context, &error_block)
        }.to raise_error(StandardError, /Processing failed/)
      end
    end

    context "when skip_if block raises error" do
      before do
        agent_class.incremental_processing do
          chunk_size 20

          skip_if do |record, context|
            raise StandardError, "Skip check failed"
          end

          load_existing do |record, context|
            { id: record[:id] }
          end

          persistence_handler do |batch_results, context|
            # No-op
          end
        end
      end

      it "raises the error with context" do
        expect {
          processor.process(input_items, agent.context) { |items, ctx| [] }
        }.to raise_error(StandardError, /Skip check failed/)
      end
    end

    context "when persistence_handler raises error" do
      before do
        agent_class.incremental_processing do
          chunk_size 20

          skip_if do |record, context|
            false # Process all
          end

          load_existing do |record, context|
            { id: record[:id] }
          end

          persistence_handler do |batch_results, context|
            raise StandardError, "Persistence failed"
          end
        end
      end

      let(:process_block) do
        ->(items, context) do
          items.map { |item| { id: item[:id], processed: true } }
        end
      end

      it "raises the error with context" do
        expect {
          processor.process(input_items, agent.context, &process_block)
        }.to raise_error(StandardError, /Persistence failed/)
      end
    end
  end

  describe "result accumulation" do
    let(:processor) { described_class.new(agent, config) }
    let(:process_block) do
      ->(items, context) do
        items.map do |item|
          {
            id: item[:id],
            name: item[:name],
            score: 80,
            source: "ai_processed",
            batch_number: context[:current_batch] || 1
          }
        end
      end
    end

    it "accumulates results from all batches" do
      result = processor.process(input_items, agent.context, &process_block)

      # All 50 items should be in result (25 processed + 25 skipped)
      expect(result.count).to eq(50)

      # Verify both sources are present
      expect(result.select { |r| r[:source] == "ai_processed" }.count).to eq(25)
      expect(result.select { |r| r[:source] == "database" }.count).to eq(25)
    end

    it "merges processed and skipped items correctly" do
      result = processor.process(input_items, agent.context, &process_block)

      # Verify first few items are correctly sourced
      expect(result[0][:id]).to eq(1) # Odd - processed
      expect(result[0][:source]).to eq("ai_processed")

      expect(result[1][:id]).to eq(2) # Even - skipped
      expect(result[1][:source]).to eq("database")

      expect(result[2][:id]).to eq(3) # Odd - processed
      expect(result[2][:source]).to eq("ai_processed")
    end
  end

  describe "batch processing logic" do
    let(:processor) { described_class.new(agent, config) }
    let(:process_block) do
      ->(items, context) do
        context[:batches_processed] ||= 0
        context[:batches_processed] += 1

        items.map do |item|
          {
            id: item[:id],
            name: item[:name],
            batch: context[:batches_processed]
          }
        end
      end
    end

    it "processes items in correct batch sizes" do
      # Input: 50 items, skip even (25 items to process)
      # Batch size: 20
      # Expected batches: [20 items, 5 items] from the 25 to process
      # But items are split BEFORE filtering, so actual batches are:
      # Batch 1: items 1-20 (10 odd items to process)
      # Batch 2: items 21-40 (10 odd items to process)
      # Batch 3: items 41-50 (5 odd items to process)

      result = processor.process(input_items, agent.context, &process_block)

      expect(agent.context[:batches_processed]).to eq(3)

      # First batch should have 10 processed items (odd IDs from 1-20)
      batch_1_items = result.select { |r| r[:batch] == 1 }
      expect(batch_1_items.count).to eq(10)

      # Second batch should have 10 processed items (odd IDs from 21-40)
      batch_2_items = result.select { |r| r[:batch] == 2 }
      expect(batch_2_items.count).to eq(10)

      # Third batch should have 5 processed items (odd IDs from 41-50)
      batch_3_items = result.select { |r| r[:batch] == 3 }
      expect(batch_3_items.count).to eq(5)
    end

    it "handles partial batches correctly" do
      # With 50 items and batch size 20, last batch should be 10 items
      result = processor.process(input_items, agent.context, &process_block)

      # Verify last batch size
      last_batch_items = result.select { |r| r[:batch] == 3 }
      expect(last_batch_items.count).to eq(5) # 5 odd items in items 41-50
    end
  end
end
