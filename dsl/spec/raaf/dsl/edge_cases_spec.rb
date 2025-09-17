# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RAAF::DSL::EdgeCases do
  describe '.handle_single_record_merge' do
    context 'when both existing and new data are single hashes' do
      let(:existing_data) do
        { name: 'Market A', score: 80, metadata: { source: 'analysis' } }
      end

      let(:new_data) do
        { score: 85, overall_score: 90, metadata: { timestamp: '2025-09-16' } }
      end

      it 'deep merges the hashes' do
        result = described_class.handle_single_record_merge(existing_data, new_data)

        expect(result).to eq({
          name: 'Market A',
          score: 85,  # Overwritten
          overall_score: 90,  # Added
          metadata: {
            source: 'analysis',  # Preserved
            timestamp: '2025-09-16'  # Added
          }
        })
      end
    end

    context 'when existing is array and new is single record with ID' do
      let(:existing_data) do
        [
          { id: 1, name: 'Market A', score: 80 },
          { id: 2, name: 'Market B', score: 75 }
        ]
      end

      context 'when new record has matching ID' do
        let(:new_data) { { id: 1, overall_score: 85, new_field: 'value' } }

        it 'merges with existing record by ID' do
          result = described_class.handle_single_record_merge(existing_data, new_data)

          expect(result).to contain_exactly(
            { id: 1, name: 'Market A', score: 80, overall_score: 85, new_field: 'value' },
            { id: 2, name: 'Market B', score: 75 }
          )
        end
      end

      context 'when new record has non-matching ID' do
        let(:new_data) { { id: 3, name: 'Market C', score: 90 } }

        it 'appends new record to array' do
          result = described_class.handle_single_record_merge(existing_data, new_data)

          expect(result).to contain_exactly(
            { id: 1, name: 'Market A', score: 80 },
            { id: 2, name: 'Market B', score: 75 },
            { id: 3, name: 'Market C', score: 90 }
          )
        end
      end

      context 'when new record has no ID' do
        let(:new_data) { { name: 'Market C', score: 90 } }

        it 'generates temporary ID and appends' do
          result = described_class.handle_single_record_merge(existing_data, new_data)

          expect(result.length).to eq(3)
          expect(result[0..1]).to contain_exactly(
            { id: 1, name: 'Market A', score: 80 },
            { id: 2, name: 'Market B', score: 75 }
          )

          new_record = result[2]
          expect(new_record).to include(name: 'Market C', score: 90)
          expect(new_record[:id]).to match(/temp_[a-f0-9]{16}/)
        end
      end
    end

    context 'when existing is single record and new is array' do
      let(:existing_data) { { id: 1, name: 'Market A', score: 80 } }
      let(:new_data) do
        [
          { id: 2, name: 'Market B', score: 75 },
          { id: 3, name: 'Market C', score: 90 }
        ]
      end

      it 'converts existing to array and merges' do
        result = described_class.handle_single_record_merge(existing_data, new_data)

        expect(result).to contain_exactly(
          { id: 1, name: 'Market A', score: 80 },
          { id: 2, name: 'Market B', score: 75 },
          { id: 3, name: 'Market C', score: 90 }
        )
      end
    end

    context 'when data types are incompatible' do
      let(:existing_data) { 'string_value' }
      let(:new_data) { { hash: 'value' } }

      it 'falls back to replace strategy' do
        result = described_class.handle_single_record_merge(existing_data, new_data)
        expect(result).to eq({ hash: 'value' })
      end
    end

    context 'when either data is nil' do
      it 'handles nil existing data' do
        result = described_class.handle_single_record_merge(nil, { name: 'New' })
        expect(result).to eq({ name: 'New' })
      end

      it 'handles nil new data' do
        result = described_class.handle_single_record_merge({ name: 'Existing' }, nil)
        expect(result).to be_nil
      end

      it 'handles both nil' do
        result = described_class.handle_single_record_merge(nil, nil)
        expect(result).to be_nil
      end
    end
  end

  describe '.generate_temp_id' do
    it 'generates unique temporary IDs' do
      id1 = described_class.generate_temp_id
      id2 = described_class.generate_temp_id

      expect(id1).to match(/temp_[a-f0-9]{16}/)
      expect(id2).to match(/temp_[a-f0-9]{16}/)
      expect(id1).not_to eq(id2)
    end

    it 'generates IDs with consistent format' do
      100.times do
        id = described_class.generate_temp_id
        expect(id).to match(/\Atemp_[a-f0-9]{16}\z/)
      end
    end
  end

  describe '.merge_single_with_array' do
    let(:existing_array) do
      [
        { id: 1, name: 'Item A', score: 80 },
        { id: 2, name: 'Item B', score: 75 }
      ]
    end

    context 'when new record matches existing ID' do
      let(:new_record) { { id: 1, updated_field: 'value', score: 95 } }

      it 'merges with existing record' do
        result = described_class.merge_single_with_array(existing_array, new_record)

        expect(result).to contain_exactly(
          { id: 1, name: 'Item A', score: 95, updated_field: 'value' },
          { id: 2, name: 'Item B', score: 75 }
        )
      end
    end

    context 'when new record has new ID' do
      let(:new_record) { { id: 3, name: 'Item C', score: 90 } }

      it 'appends new record' do
        result = described_class.merge_single_with_array(existing_array, new_record)

        expect(result).to contain_exactly(
          { id: 1, name: 'Item A', score: 80 },
          { id: 2, name: 'Item B', score: 75 },
          { id: 3, name: 'Item C', score: 90 }
        )
      end
    end

    context 'when array has duplicate IDs' do
      let(:existing_array) do
        [
          { id: 1, name: 'Item A', version: 1 },
          { id: 1, name: 'Item A', version: 2 },
          { id: 2, name: 'Item B', score: 75 }
        ]
      end

      let(:new_record) { { id: 1, updated: true } }

      it 'merges with first matching record only' do
        result = described_class.merge_single_with_array(existing_array, new_record)

        expect(result[0]).to eq({ id: 1, name: 'Item A', version: 1, updated: true })
        expect(result[1]).to eq({ id: 1, name: 'Item A', version: 2 })
        expect(result[2]).to eq({ id: 2, name: 'Item B', score: 75 })
      end
    end
  end

  describe 'malformed data handling' do
    context 'when arrays contain non-hash elements' do
      let(:existing_data) { [{ id: 1, name: 'A' }, 'string_element', { id: 2, name: 'B' }] }
      let(:new_data) { [{ id: 1, score: 85 }] }

      it 'handles mixed array elements gracefully' do
        # Should not crash when encountering non-hash elements
        expect {
          described_class.handle_single_record_merge(existing_data, new_data)
        }.not_to raise_error
      end
    end

    context 'when hash keys are mixed types' do
      let(:existing_data) { { id: 1, 'name' => 'A', :score => 80 } }
      let(:new_data) { { :id => 1, 'updated' => true, score: 95 } }

      it 'handles mixed key types' do
        result = described_class.handle_single_record_merge(existing_data, new_data)

        # Should merge based on key equivalence
        expect(result[:id]).to eq(1)
        expect(result[:score]).to eq(95)
        expect(result['updated']).to be true
      end
    end

    context 'when data contains circular references' do
      let(:circular_hash) { { name: 'A' } }

      before do
        circular_hash[:self] = circular_hash
      end

      it 'handles circular references without infinite loops' do
        expect {
          described_class.handle_single_record_merge(circular_hash, { updated: true })
        }.not_to raise_error
      end
    end
  end

  describe 'private helper methods' do
    describe '.both_single_hashes?' do
      it 'returns true when both are hashes' do
        result = described_class.send(:both_single_hashes?, { a: 1 }, { b: 2 })
        expect(result).to be true
      end

      it 'returns false when either is not a hash' do
        expect(described_class.send(:both_single_hashes?, { a: 1 }, [1, 2])).to be false
        expect(described_class.send(:both_single_hashes?, 'string', { b: 2 })).to be false
        expect(described_class.send(:both_single_hashes?, nil, { b: 2 })).to be false
      end
    end

    describe '.existing_array_new_single?' do
      it 'returns true when existing is array and new is hash' do
        result = described_class.send(:existing_array_new_single?, [1, 2], { a: 1 })
        expect(result).to be true
      end

      it 'returns false in other cases' do
        expect(described_class.send(:existing_array_new_single?, { a: 1 }, { b: 2 })).to be false
        expect(described_class.send(:existing_array_new_single?, [1, 2], [3, 4])).to be false
      end
    end

    describe '.single_existing_new_array?' do
      it 'returns true when existing is hash and new is array' do
        result = described_class.send(:single_existing_new_array?, { a: 1 }, [1, 2])
        expect(result).to be true
      end

      it 'returns false in other cases' do
        expect(described_class.send(:single_existing_new_array?, { a: 1 }, { b: 2 })).to be false
        expect(described_class.send(:single_existing_new_array?, [1, 2], [3, 4])).to be false
      end
    end
  end

  describe 'integration with MergeStrategy' do
    it 'is used by MergeStrategy for complex edge cases' do
      # Test that EdgeCases module integrates properly with the main merge system
      existing = [{ id: 1, name: 'A' }]
      new_data = { id: 2, name: 'B' }

      # This should trigger edge case handling for single record merge
      result = RAAF::DSL::MergeStrategy.merge(:items, existing, new_data)

      expect(result).to contain_exactly(
        { id: 1, name: 'A' },
        { id: 2, name: 'B' }
      )
    end
  end
end