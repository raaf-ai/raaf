# frozen_string_literal: true

require 'securerandom'
require 'active_support/core_ext/hash/deep_merge'

module RAAF
  module DSL
    # Edge case handling for complex merge scenarios
    #
    # This module handles special cases that don't fit the standard merge strategies,
    # such as single records merging with arrays, missing IDs, and malformed data.
    # It provides robust fallbacks to ensure data integrity is maintained.
    #
    # @example Single record merging with array
    #   existing = [{ id: 1, name: 'A' }]
    #   new_data = { id: 2, name: 'B' }
    #   result = EdgeCases.handle_single_record_merge(existing, new_data)
    #   # => [{ id: 1, name: 'A' }, { id: 2, name: 'B' }]
    #
    module EdgeCases
      # Handles complex merge scenarios that require special logic
      #
      # @param existing [Object] The existing data
      # @param new_data [Object] The new data to merge
      # @return [Object] The merged result
      def self.handle_single_record_merge(existing, new_data)
        return new_data if existing.nil?
        return existing if new_data.nil?

        case
        when both_single_hashes?(existing, new_data)
          # Single records -> deep merge
          existing.deep_merge(new_data)
        when existing_array_new_single?(existing, new_data)
          # Existing array + single new record
          handle_array_single_merge(existing, new_data)
        when single_existing_new_array?(existing, new_data)
          # Single existing + new array -> convert to array and merge
          [existing] + new_data
        else
          # Fallback to replace for incompatible types
          new_data
        end
      rescue StandardError => e
        # Graceful fallback for any unexpected errors
        RAAF.logger&.warn("EdgeCases merge error: #{e.message}, falling back to replace")
        new_data
      end

      # Generates a unique temporary ID for records without IDs
      #
      # @return [String] A temporary ID in format "temp_<16-hex-chars>"
      def self.generate_temp_id
        "temp_#{SecureRandom.hex(8)}"
      end

      # Merges a single record into an existing array
      #
      # @param existing_array [Array] The existing array of records
      # @param new_record [Hash] The new record to merge
      # @return [Array] The updated array
      def self.merge_single_with_array(existing_array, new_record)
        return existing_array unless new_record.is_a?(Hash)

        new_id = new_record[:id] || new_record['id']

        if !new_id.nil? && new_id != ""
          # Try to merge by ID
          updated = false
          result = existing_array.map do |item|
            item_id = item.is_a?(Hash) ? (item[:id] || item['id']) : nil

            if item_id == new_id && !updated
              updated = true
              item.is_a?(Hash) ? item.merge(new_record) : new_record
            else
              item
            end
          end

          # If no existing record was found, append the new one
          result << new_record unless updated
          result
        else
          # No ID available, append the new record
          existing_array + [new_record]
        end
      end

      private

      # Checks if both data items are single hash objects
      def self.both_single_hashes?(existing, new_data)
        existing.is_a?(Hash) && new_data.is_a?(Hash)
      end

      # Checks if existing is array and new is single hash
      def self.existing_array_new_single?(existing, new_data)
        existing.is_a?(Array) && new_data.is_a?(Hash)
      end

      # Checks if existing is single hash and new is array
      def self.single_existing_new_array?(existing, new_data)
        existing.is_a?(Hash) && new_data.is_a?(Array)
      end

      # Handles merging a single record into an array
      def self.handle_array_single_merge(existing_array, new_record)
        if new_record.key?(:id) || new_record.key?('id')
          # Has ID -> try to merge by ID, append if not found
          merge_single_with_array(existing_array, new_record)
        else
          # No ID -> generate temporary ID and append
          new_record_with_id = new_record.merge(id: generate_temp_id)
          existing_array + [new_record_with_id]
        end
      end
    end
  end
end