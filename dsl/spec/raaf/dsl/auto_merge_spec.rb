# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RAAF::DSL::AutoMerge do
  # Mock agent class that includes AutoMerge
  let(:agent_class) do
    Class.new do
      include RAAF::DSL::AutoMerge

      # Mock the super run method
      def run(context: nil, input_context_variables: nil, stop_checker: nil, skip_retries: false, previous_result: nil)
        # Return a mocked AI result
        {
          success: true,
          results: @mock_results || {},
          context_variables: context || input_context_variables,
          summary: "Agent execution completed"
        }
      end

      # Allow setting mock results for testing
      attr_writer :mock_results
    end
  end

  let(:agent) { agent_class.new }

  # Mock context variables class
  let(:context_class) do
    Class.new do
      def initialize(data = {})
        @variables = data
      end

      def get(key)
        @variables[key] || @variables[key.to_s]
      end

      def set(key, value)
        @variables[key] = value
      end

      def to_h
        @variables
      end

      attr_reader :variables
    end
  end

  describe '#run with automatic merging' do
    context 'when there is no existing context data' do
      let(:context) { context_class.new }

      it 'returns new data without merging' do
        agent.mock_results = { markets: [{ id: 1, name: 'Market A' }] }

        result = agent.run(context: context)

        expect(result[:success]).to be true
        expect(result[:results][:markets]).to eq([{ id: 1, name: 'Market A' }])
      end
    end

    context 'when merging arrays with IDs' do
      let(:existing_markets) do
        [
          { id: 1, name: 'Market A', score: 80 },
          { id: 2, name: 'Market B', score: 75 }
        ]
      end

      let(:context) { context_class.new(markets: existing_markets) }

      it 'merges new data with existing data by ID' do
        agent.mock_results = {
          markets: [
            { id: 1, overall_score: 85, scoring: { complexity: 'medium' } },
            { id: 3, name: 'Market C', score: 90 }
          ]
        }

        result = agent.run(context: context)

        expect(result[:success]).to be true
        expect(result[:results][:markets]).to contain_exactly(
          { id: 1, name: 'Market A', score: 80, overall_score: 85, scoring: { complexity: 'medium' } },
          { id: 2, name: 'Market B', score: 75 },
          { id: 3, name: 'Market C', score: 90 }
        )

        # Verify context was updated
        expect(context.get(:markets)).to eq(result[:results][:markets])
      end
    end

    context 'when merging arrays without IDs' do
      let(:existing_tags) { ['tag1', 'tag2'] }
      let(:context) { context_class.new(tags: existing_tags) }

      it 'appends new data to existing data' do
        agent.mock_results = { tags: ['tag3', 'tag4'] }

        result = agent.run(context: context)

        expect(result[:success]).to be true
        expect(result[:results][:tags]).to eq(['tag1', 'tag2', 'tag3', 'tag4'])

        # Verify context was updated
        expect(context.get(:tags)).to eq(['tag1', 'tag2', 'tag3', 'tag4'])
      end
    end

    context 'when merging hash data' do
      let(:existing_metadata) do
        {
          source: 'analysis',
          stats: { total_count: 10, processed: 8 },
          created_at: '2025-09-15'
        }
      end

      let(:context) { context_class.new(metadata: existing_metadata) }

      it 'deep merges hash structures' do
        agent.mock_results = {
          metadata: {
            timestamp: '2025-09-16',
            stats: { total_count: 12, success_rate: 0.95 },
            additional_info: { version: '1.0' }
          }
        }

        result = agent.run(context: context)

        expect(result[:success]).to be true
        expected_metadata = {
          source: 'analysis',
          created_at: '2025-09-15',
          timestamp: '2025-09-16',
          stats: { total_count: 12, processed: 8, success_rate: 0.95 },
          additional_info: { version: '1.0' }
        }
        expect(result[:results][:metadata]).to eq(expected_metadata)
      end
    end

    context 'when handling edge cases' do
      let(:existing_markets) { [{ id: 1, name: 'Market A' }] }
      let(:context) { context_class.new(markets: existing_markets) }

      it 'handles single record merging with arrays' do
        agent.mock_results = { markets: { id: 2, name: 'Market B' } }

        result = agent.run(context: context)

        expect(result[:success]).to be true
        expect(result[:results][:markets]).to contain_exactly(
          { id: 1, name: 'Market A' },
          { id: 2, name: 'Market B' }
        )
      end
    end

    context 'when multiple fields need merging' do
      let(:context) do
        context_class.new(
          markets: [{ id: 1, name: 'Market A' }],
          tags: ['existing_tag'],
          metadata: { source: 'analysis' }
        )
      end

      it 'merges all fields with appropriate strategies' do
        agent.mock_results = {
          markets: [{ id: 1, score: 85 }, { id: 2, name: 'Market B' }],
          tags: ['new_tag'],
          metadata: { timestamp: '2025-09-16' },
          new_field: 'new_value'
        }

        result = agent.run(context: context)

        expect(result[:success]).to be true

        # Markets merged by ID
        expect(result[:results][:markets]).to contain_exactly(
          { id: 1, name: 'Market A', score: 85 },
          { id: 2, name: 'Market B' }
        )

        # Tags appended
        expect(result[:results][:tags]).to eq(['existing_tag', 'new_tag'])

        # Metadata deep merged
        expect(result[:results][:metadata]).to eq({
          source: 'analysis',
          timestamp: '2025-09-16'
        })

        # New field added as-is
        expect(result[:results][:new_field]).to eq('new_value')
      end
    end

    context 'when AI execution fails' do
      let(:failing_agent_class) do
        Class.new do
          include RAAF::DSL::AutoMerge

          def run(context: nil, input_context_variables: nil, stop_checker: nil, skip_retries: false, previous_result: nil)
            {
              success: false,
              error: "AI execution failed",
              results: nil
            }
          end
        end
      end

      let(:failing_agent) { failing_agent_class.new }

      it 'returns the original failed result without merging' do
        context = context_class.new(existing_data: 'should not be affected')

        result = failing_agent.run(context: context)

        expect(result[:success]).to be false
        expect(result[:error]).to eq("AI execution failed")
        expect(result[:results]).to be_nil

        # Context should not be modified
        expect(context.get(:existing_data)).to eq('should not be affected')
      end
    end

    context 'when using Hash context instead of ContextVariables' do
      let(:hash_context) { { markets: [{ id: 1, name: 'Market A' }] } }

      it 'works with hash contexts' do
        agent.mock_results = { markets: [{ id: 1, score: 85 }] }

        result = agent.run(context: hash_context)

        expect(result[:success]).to be true
        expect(result[:results][:markets]).to contain_exactly(
          { id: 1, name: 'Market A', score: 85 }
        )

        # Hash context should be updated
        expect(hash_context[:markets]).to eq(result[:results][:markets])
      end
    end
  end

  describe 'private helper methods' do
    describe '#extract_context_data' do
      it 'extracts data from ContextVariables objects' do
        context = context_class.new(key1: 'value1', key2: 'value2')
        data = agent.send(:extract_context_data, context)

        expect(data).to include(key1: 'value1', key2: 'value2')
      end

      it 'handles Hash objects' do
        context = { key1: 'value1', key2: 'value2' }
        data = agent.send(:extract_context_data, context)

        expect(data).to eq(context)
      end

      it 'handles nil context' do
        data = agent.send(:extract_context_data, nil)
        expect(data).to eq({})
      end

      it 'handles objects with to_h method' do
        context = double(to_h: { key1: 'value1' })
        data = agent.send(:extract_context_data, context)

        expect(data).to eq({ key1: 'value1' })
      end
    end

    describe '#present?' do
      it 'returns true for non-empty values' do
        expect(agent.send(:present?, 'value')).to be true
        expect(agent.send(:present?, [1, 2, 3])).to be true
        expect(agent.send(:present?, { key: 'value' })).to be true
        expect(agent.send(:present?, 42)).to be true
      end

      it 'returns false for empty values' do
        expect(agent.send(:present?, nil)).to be false
        expect(agent.send(:present?, '')).to be false
        expect(agent.send(:present?, [])).to be false
        expect(agent.send(:present?, {})).to be false
      end
    end
  end

  describe 'performance with auto-merge' do
    let(:large_existing_data) do
      (1..1000).map { |i| { id: i, name: "Item #{i}", value: i * 10 } }
    end

    let(:large_new_data) do
      (500..1500).map { |i| { id: i, score: i * 2, updated: true } }
    end

    let(:context) { context_class.new(items: large_existing_data) }

    it 'merges large datasets efficiently' do
      agent.mock_results = { items: large_new_data }

      start_time = Time.now
      result = agent.run(context: context)
      execution_time = Time.now - start_time

      expect(execution_time).to be < 0.01  # Should complete in under 10ms
      expect(result[:success]).to be true
      expect(result[:results][:items].length).to eq(1500)

      # Verify merge accuracy
      merged_item = result[:results][:items].find { |item| item[:id] == 500 }
      expect(merged_item).to include(
        id: 500,
        name: "Item 500",
        value: 5000,
        score: 1000,
        updated: true
      )
    end
  end
end