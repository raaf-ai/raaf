# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RAAF::DSL::IncrementalProcessing do
  # Mock agent class that includes IncrementalProcessing
  let(:agent_class) do
    Class.new do
      include RAAF::DSL::IncrementalProcessing

      # Mock context configuration support
      def self.context_config
        @context_config ||= {}
      end

      def self.context(&block)
        # Simple mock - just store that it was called
        @context_config[:block] = block if block_given?
      end
    end
  end

  let(:agent) { agent_class.new }

  describe 'module inclusion' do
    it 'includes the module successfully' do
      expect(agent_class.ancestors).to include(RAAF::DSL::IncrementalProcessing)
    end

    it 'makes incremental_processing DSL method available' do
      expect(agent_class).to respond_to(:incremental_processing)
    end

    it 'makes incremental_config reader available' do
      expect(agent).to respond_to(:incremental_config)
    end

    it 'makes incremental_processing? helper available' do
      expect(agent).to respond_to(:incremental_processing?)
    end
  end

  describe '.incremental_processing DSL method' do
    context 'when called with a block' do
      it 'creates an IncrementalConfig instance' do
        agent_class.incremental_processing do
          chunk_size 20
        end

        expect(agent_class._incremental_config).to be_a(RAAF::DSL::IncrementalConfig)
      end

      it 'evaluates the block in the context of IncrementalConfig' do
        agent_class.incremental_processing do
          chunk_size 15
        end

        config = agent_class._incremental_config
        expect(config.chunk_size).to eq(15)
      end

      it 'stores skip_if closure' do
        skip_block = proc { |record, context| record[:id] > 100 }

        agent_class.incremental_processing do
          skip_if(&skip_block)
        end

        config = agent_class._incremental_config
        expect(config.skip_if_block).to be_a(Proc)
      end

      it 'stores load_existing closure' do
        load_block = proc { |record, context| { id: record[:id] } }

        agent_class.incremental_processing do
          load_existing(&load_block)
        end

        config = agent_class._incremental_config
        expect(config.load_existing_block).to be_a(Proc)
      end

      it 'stores persistence_handler closure' do
        persist_block = proc { |batch, context| batch.each { |r| puts r } }

        agent_class.incremental_processing do
          persistence_handler(&persist_block)
        end

        config = agent_class._incremental_config
        expect(config.persistence_handler_block).to be_a(Proc)
      end
    end

    context 'when called without a block' do
      it 'raises an ArgumentError' do
        expect {
          agent_class.incremental_processing
        }.to raise_error(ArgumentError, /block required/)
      end
    end
  end

  describe '#incremental_processing?' do
    context 'when incremental processing is configured' do
      before do
        agent_class.incremental_processing do
          chunk_size 10
          skip_if { |record, context| false }
          load_existing { |record, context| record }
          persistence_handler { |batch, context| nil }
        end
      end

      it 'returns true' do
        expect(agent.incremental_processing?).to be true
      end
    end

    context 'when incremental processing is not configured' do
      it 'returns false' do
        expect(agent.incremental_processing?).to be false
      end
    end
  end

  describe 'configuration inheritance' do
    it 'makes config available to instances' do
      agent_class.incremental_processing do
        chunk_size 25
      end

      expect(agent.incremental_config).to be_a(RAAF::DSL::IncrementalConfig)
      expect(agent.incremental_config.chunk_size).to eq(25)
    end
  end

  describe 'complete configuration example' do
    it 'supports all configuration options' do
      agent_class.incremental_processing do
        # Optional batching
        chunk_size 50

        # Required: Check if already processed
        skip_if do |record, context|
          record[:already_processed] == true
        end

        # Required: Load existing data
        load_existing do |record, context|
          {
            id: record[:id],
            name: record[:name],
            existing_data: "loaded from database"
          }
        end

        # Required: Persist batch
        persistence_handler do |batch_results, context|
          batch_results.each do |result|
            # Persist to database
            result[:persisted] = true
          end
        end
      end

      config = agent.incremental_config

      # Verify chunk size
      expect(config.chunk_size).to eq(50)

      # Verify skip_if works
      expect(config.skip_if_block.call({ already_processed: true }, {})).to be true
      expect(config.skip_if_block.call({ already_processed: false }, {})).to be false

      # Verify load_existing works
      loaded = config.load_existing_block.call({ id: 1, name: "Test" }, {})
      expect(loaded[:existing_data]).to eq("loaded from database")

      # Verify persistence_handler works
      batch = [{ id: 1 }, { id: 2 }]
      config.persistence_handler_block.call(batch, {})
      expect(batch.all? { |r| r[:persisted] == true }).to be true
    end
  end

  describe 'error handling' do
    context 'when skip_if is missing' do
      it 'allows configuration without skip_if (validation happens later)' do
        expect {
          agent_class.incremental_processing do
            chunk_size 10
            load_existing { |r, c| r }
            persistence_handler { |b, c| nil }
          end
        }.not_to raise_error
      end
    end

    context 'when load_existing is missing' do
      it 'allows configuration without load_existing (validation happens later)' do
        expect {
          agent_class.incremental_processing do
            chunk_size 10
            skip_if { |r, c| false }
            persistence_handler { |b, c| nil }
          end
        }.not_to raise_error
      end
    end

    context 'when persistence_handler is missing' do
      it 'allows configuration without persistence_handler (validation happens later)' do
        expect {
          agent_class.incremental_processing do
            chunk_size 10
            skip_if { |r, c| false }
            load_existing { |r, c| r }
          end
        }.not_to raise_error
      end
    end
  end

  describe 'force_reprocess support' do
    it 'can access force_reprocess from context' do
      agent_class.incremental_processing do
        skip_if do |record, context|
          # Skip unless force_reprocess is true
          !context[:force_reprocess] && record[:processed]
        end

        load_existing { |record, context| record }
        persistence_handler { |batch, context| nil }
      end

      config = agent.incremental_config

      # Normal operation - skips processed records
      expect(config.skip_if_block.call({ processed: true }, { force_reprocess: false })).to be true

      # Force reprocess - doesn't skip
      expect(config.skip_if_block.call({ processed: true }, { force_reprocess: true })).to be false
    end
  end

  describe 'multiple agents with different configurations' do
    let(:agent_class_1) do
      Class.new do
        include RAAF::DSL::IncrementalProcessing
      end
    end

    let(:agent_class_2) do
      Class.new do
        include RAAF::DSL::IncrementalProcessing
      end
    end

    it 'maintains separate configurations for each agent class' do
      agent_class_1.incremental_processing do
        chunk_size 10
        skip_if { |r, c| false }
        load_existing { |r, c| r }
        persistence_handler { |b, c| nil }
      end

      agent_class_2.incremental_processing do
        chunk_size 20
        skip_if { |r, c| true }
        load_existing { |r, c| r }
        persistence_handler { |b, c| nil }
      end

      expect(agent_class_1._incremental_config.chunk_size).to eq(10)
      expect(agent_class_2._incremental_config.chunk_size).to eq(20)

      expect(agent_class_1._incremental_config.skip_if_block.call({}, {})).to be false
      expect(agent_class_2._incremental_config.skip_if_block.call({}, {})).to be true
    end
  end
end
