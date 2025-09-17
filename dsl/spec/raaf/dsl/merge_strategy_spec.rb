# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RAAF::DSL::MergeStrategy do
  describe '.detect_strategy' do
    context 'when data has arrays with ID fields' do
      let(:existing_data) do
        [
          { id: 1, name: 'Market A', score: 80 },
          { id: 2, name: 'Market B', score: 75 }
        ]
      end

      let(:new_data) do
        [
          { id: 1, overall_score: 85, scoring: { complexity: 'medium' } },
          { id: 3, name: 'Market C', score: 90 }
        ]
      end

      it 'detects by_id strategy' do
        strategy = described_class.detect_strategy(:markets, existing_data, new_data)
        expect(strategy).to eq(:by_id)
      end
    end

    context 'when data has arrays without ID fields' do
      let(:existing_data) { ['tag1', 'tag2'] }
      let(:new_data) { ['tag3', 'tag4'] }

      it 'detects append strategy' do
        strategy = described_class.detect_strategy(:tags, existing_data, new_data)
        expect(strategy).to eq(:append)
      end
    end

    context 'when data has hash structures' do
      let(:existing_data) do
        {
          metadata: { source: 'analysis' },
          stats: { total_count: 10 }
        }
      end

      let(:new_data) do
        {
          metadata: { timestamp: '2025-09-16' },
          additional_info: { version: '1.0' }
        }
      end

      it 'detects deep_merge strategy' do
        strategy = described_class.detect_strategy(:data, existing_data, new_data)
        expect(strategy).to eq(:deep_merge)
      end
    end

    context 'when data has scalar values' do
      let(:existing_data) { 'old_value' }
      let(:new_data) { 'new_value' }

      it 'detects replace strategy' do
        strategy = described_class.detect_strategy(:field, existing_data, new_data)
        expect(strategy).to eq(:replace)
      end
    end

    context 'when existing data is nil' do
      let(:existing_data) { nil }
      let(:new_data) { [{ id: 1, name: 'New Item' }] }

      it 'detects replace strategy' do
        strategy = described_class.detect_strategy(:field, existing_data, new_data)
        expect(strategy).to eq(:replace)
      end
    end

    context 'when new data is nil' do
      let(:existing_data) { [{ id: 1, name: 'Existing' }] }
      let(:new_data) { nil }

      it 'detects replace strategy' do
        strategy = described_class.detect_strategy(:field, existing_data, new_data)
        expect(strategy).to eq(:replace)
      end
    end

    context 'when arrays have mixed ID presence' do
      let(:existing_data) { [{ id: 1, name: 'A' }, { name: 'B' }] }
      let(:new_data) { [{ id: 2, name: 'C' }] }

      it 'falls back to append strategy' do
        strategy = described_class.detect_strategy(:items, existing_data, new_data)
        expect(strategy).to eq(:append)
      end
    end
  end

  describe '.apply_strategy' do
    describe 'by_id strategy' do
      let(:existing_data) do
        [
          { id: 1, name: 'Market A', score: 80 },
          { id: 2, name: 'Market B', score: 75 }
        ]
      end

      context 'when merging with overlapping IDs' do
        let(:new_data) do
          [
            { id: 1, overall_score: 85, scoring: { complexity: 'medium' } },
            { id: 3, name: 'Market C', score: 90 }
          ]
        end

        it 'merges existing records and appends new ones' do
          result = described_class.apply_strategy(:by_id, existing_data, new_data)

          expect(result).to contain_exactly(
            { id: 1, name: 'Market A', score: 80, overall_score: 85, scoring: { complexity: 'medium' } },
            { id: 2, name: 'Market B', score: 75 },
            { id: 3, name: 'Market C', score: 90 }
          )
        end
      end

      context 'when all IDs are new' do
        let(:new_data) do
          [
            { id: 3, name: 'Market C', score: 90 },
            { id: 4, name: 'Market D', score: 85 }
          ]
        end

        it 'appends all new records' do
          result = described_class.apply_strategy(:by_id, existing_data, new_data)

          expect(result).to contain_exactly(
            { id: 1, name: 'Market A', score: 80 },
            { id: 2, name: 'Market B', score: 75 },
            { id: 3, name: 'Market C', score: 90 },
            { id: 4, name: 'Market D', score: 85 }
          )
        end
      end

      context 'when new data overwrites existing fields' do
        let(:new_data) do
          [
            { id: 1, name: 'Updated Market A', score: 95 }
          ]
        end

        it 'overwrites existing field values' do
          result = described_class.apply_strategy(:by_id, existing_data, new_data)

          expect(result).to contain_exactly(
            { id: 1, name: 'Updated Market A', score: 95 },
            { id: 2, name: 'Market B', score: 75 }
          )
        end
      end

      context 'when IDs have different types (string vs integer)' do
        let(:new_data) do
          [
            { id: '1', updated_field: 'new_value' }
          ]
        end

        it 'treats different ID types as separate records' do
          result = described_class.apply_strategy(:by_id, existing_data, new_data)

          expect(result).to contain_exactly(
            { id: 1, name: 'Market A', score: 80 },
            { id: 2, name: 'Market B', score: 75 },
            { id: '1', updated_field: 'new_value' }
          )
        end
      end
    end

    describe 'append strategy' do
      let(:existing_data) { ['tag1', 'tag2'] }

      context 'when appending array data' do
        let(:new_data) { ['tag3', 'tag4'] }

        it 'concatenates arrays' do
          result = described_class.apply_strategy(:append, existing_data, new_data)
          expect(result).to eq(['tag1', 'tag2', 'tag3', 'tag4'])
        end
      end

      context 'when appending single item' do
        let(:new_data) { 'tag3' }

        it 'wraps single item in array and appends' do
          result = described_class.apply_strategy(:append, existing_data, new_data)
          expect(result).to eq(['tag1', 'tag2', 'tag3'])
        end
      end

      context 'when new data is nil' do
        let(:new_data) { nil }

        it 'returns existing data unchanged' do
          result = described_class.apply_strategy(:append, existing_data, new_data)
          expect(result).to eq(['tag1', 'tag2'])
        end
      end

      context 'when existing data is empty array' do
        let(:existing_data) { [] }
        let(:new_data) { ['tag1', 'tag2'] }

        it 'returns new data' do
          result = described_class.apply_strategy(:append, existing_data, new_data)
          expect(result).to eq(['tag1', 'tag2'])
        end
      end
    end

    describe 'deep_merge strategy' do
      let(:existing_data) do
        {
          metadata: { source: 'analysis', created_at: '2025-09-15' },
          stats: { total_count: 10, processed: 8 },
          tags: ['old_tag']
        }
      end

      context 'when merging nested hashes' do
        let(:new_data) do
          {
            metadata: { timestamp: '2025-09-16', version: '1.0' },
            stats: { total_count: 12, success_rate: 0.95 },
            additional_info: { notes: 'Updated analysis' }
          }
        end

        it 'deep merges nested structures' do
          result = described_class.apply_strategy(:deep_merge, existing_data, new_data)

          expect(result).to eq({
            metadata: {
              source: 'analysis',
              created_at: '2025-09-15',
              timestamp: '2025-09-16',
              version: '1.0'
            },
            stats: {
              total_count: 12,  # Overwritten
              processed: 8,     # Preserved
              success_rate: 0.95 # Added
            },
            tags: ['old_tag'],  # Preserved
            additional_info: { notes: 'Updated analysis' } # Added
          })
        end
      end

      context 'when new data overwrites arrays' do
        let(:new_data) do
          {
            tags: ['new_tag1', 'new_tag2']
          }
        end

        it 'replaces arrays instead of merging them' do
          result = described_class.apply_strategy(:deep_merge, existing_data, new_data)
          expect(result[:tags]).to eq(['new_tag1', 'new_tag2'])
        end
      end

      context 'when merging with nil values' do
        let(:new_data) do
          {
            metadata: { source: nil, new_field: 'value' },
            stats: nil
          }
        end

        it 'handles nil values appropriately' do
          result = described_class.apply_strategy(:deep_merge, existing_data, new_data)

          expect(result[:metadata][:source]).to be_nil
          expect(result[:metadata][:new_field]).to eq('value')
          expect(result[:stats]).to be_nil
        end
      end
    end

    describe 'replace strategy' do
      let(:existing_data) { 'old_value' }
      let(:new_data) { 'new_value' }

      it 'replaces existing data entirely' do
        result = described_class.apply_strategy(:replace, existing_data, new_data)
        expect(result).to eq('new_value')
      end

      context 'when new data is nil' do
        let(:new_data) { nil }

        it 'replaces with nil' do
          result = described_class.apply_strategy(:replace, existing_data, new_data)
          expect(result).to be_nil
        end
      end

      context 'when replacing complex structures' do
        let(:existing_data) { { complex: 'structure' } }
        let(:new_data) { ['array', 'data'] }

        it 'completely replaces data type' do
          result = described_class.apply_strategy(:replace, existing_data, new_data)
          expect(result).to eq(['array', 'data'])
        end
      end
    end
  end

  describe '.merge' do
    it 'detects strategy and applies it automatically' do
      existing = [{ id: 1, name: 'A' }]
      new_data = [{ id: 1, score: 85 }, { id: 2, name: 'B' }]

      result = described_class.merge(:markets, existing, new_data)

      expect(result).to contain_exactly(
        { id: 1, name: 'A', score: 85 },
        { id: 2, name: 'B' }
      )
    end

    it 'handles edge cases gracefully' do
      result = described_class.merge(:field, nil, 'new_value')
      expect(result).to eq('new_value')
    end
  end

  describe 'performance with large datasets' do
    let(:large_existing_data) do
      (1..1000).map { |i| { id: i, name: "Item #{i}", value: i * 10 } }
    end

    let(:large_new_data) do
      (500..1500).map { |i| { id: i, score: i * 2, updated: true } }
    end

    it 'merges large datasets efficiently' do
      start_time = Time.now

      result = described_class.apply_strategy(:by_id, large_existing_data, large_new_data)

      execution_time = Time.now - start_time

      # Should complete well under the 50ms target for large arrays
      expect(execution_time).to be < 0.05

      # Verify correctness
      expect(result.length).to eq(1500)

      # Check merge accuracy for overlapping IDs
      merged_item = result.find { |item| item[:id] == 500 }
      expect(merged_item).to include(
        id: 500,
        name: "Item 500",
        value: 5000,
        score: 1000,
        updated: true
      )
    end
  end

  describe 'memory efficiency' do
    let(:existing_data) do
      (1..100).map { |i| { id: i, data: "x" * 1000 } }  # ~100KB of data
    end

    let(:new_data) do
      (50..150).map { |i| { id: i, additional: "y" * 500 } }  # ~50KB of new data
    end

    it 'maintains reasonable memory overhead' do
      # Force garbage collection to get baseline
      GC.start
      memory_before = GC.stat[:total_allocated_bytes]

      result = described_class.apply_strategy(:by_id, existing_data, new_data)

      memory_after = GC.stat[:total_allocated_bytes]
      memory_used = memory_after - memory_before

      # Memory overhead should be reasonable (less than 2x the original data size)
      original_size = existing_data.to_s.bytesize + new_data.to_s.bytesize
      expect(memory_used).to be < (original_size * 2)

      # Verify result correctness
      expect(result.length).to eq(150)
    end
  end
end