# frozen_string_literal: true

require 'active_support/core_ext/hash/deep_merge'
require_relative 'edge_cases'

module RAAF
  module DSL
    # Automatic merge strategy detection and execution for RAAF agents
    #
    # This module provides intelligent merging of AI agent results with existing pipeline context
    # by detecting appropriate merge strategies based on data patterns and structure. It eliminates
    # the need for manual `process_*_from_data` methods in agents.
    #
    # @example Basic usage
    #   existing = [{ id: 1, name: 'Market A' }]
    #   new_data = [{ id: 1, score: 85 }, { id: 2, name: 'Market B' }]
    #   result = RAAF::DSL::MergeStrategy.merge(:markets, existing, new_data)
    #   # => [{ id: 1, name: 'Market A', score: 85 }, { id: 2, name: 'Market B' }]
    #
    # @example Strategy detection
    #   strategy = RAAF::DSL::MergeStrategy.detect_strategy(:markets, existing, new_data)
    #   # => :by_id
    #
    module MergeStrategy
      # Available merge strategies with their implementations
      STRATEGIES = {
        by_id: ->(existing, new_data) { merge_by_id(existing, new_data) },
        append: ->(existing, new_data) { merge_by_append(existing, new_data) },
        deep_merge: ->(existing, new_data) { existing.deep_merge(new_data) },
        replace: ->(existing, new_data) { new_data }
      }.freeze

      # Detects the appropriate merge strategy based on data patterns
      #
      # @param field_name [Symbol] The field name being merged (for context)
      # @param existing_data [Object] The existing data in the pipeline context
      # @param new_data [Object] The new data from the AI agent
      # @return [Symbol] The detected strategy (:by_id, :append, :deep_merge, :replace)
      def self.detect_strategy(field_name, existing_data, new_data)
        # Handle nil data - always replace
        return :replace if existing_data.nil? || new_data.nil?

        # Arrays with ID-bearing objects -> by_id merge
        return :by_id if array_with_ids?(existing_data, new_data)

        # Arrays without consistent IDs -> append
        return :append if both_arrays?(existing_data, new_data)

        # Hash objects -> deep merge
        return :deep_merge if both_hashes?(existing_data, new_data)

        # Mixed types or edge cases -> check for special handling
        return :edge_case if requires_edge_case_handling?(existing_data, new_data)

        # Default fallback -> replace
        :replace
      end

      # Applies the specified merge strategy to the data
      #
      # @param strategy [Symbol] The merge strategy to apply
      # @param existing_data [Object] The existing data
      # @param new_data [Object] The new data to merge
      # @return [Object] The merged result
      def self.apply_strategy(strategy, existing_data, new_data)
        case strategy
        when :by_id
          merge_by_id(existing_data, new_data)
        when :append
          merge_by_append(existing_data, new_data)
        when :deep_merge
          existing_data.deep_merge(new_data)
        when :replace
          new_data
        when :edge_case
          EdgeCases.handle_single_record_merge(existing_data, new_data)
        else
          raise ArgumentError, "Unknown merge strategy: #{strategy}"
        end
      end

      # One-step merge: detects strategy and applies it
      #
      # @param field_name [Symbol] The field name being merged
      # @param existing_data [Object] The existing data
      # @param new_data [Object] The new data to merge
      # @return [Object] The merged result
      def self.merge(field_name, existing_data, new_data)
        strategy = detect_strategy(field_name, existing_data, new_data)
        apply_strategy(strategy, existing_data, new_data)
      end

      private

      # Checks if both data sets are arrays with consistent ID fields
      def self.array_with_ids?(existing, new_data)
        both_arrays?(existing, new_data) &&
          has_consistent_ids?(existing) &&
          has_consistent_ids?(new_data)
      end

      # Checks if both data sets are arrays
      def self.both_arrays?(existing, new_data)
        existing.is_a?(Array) && new_data.is_a?(Array)
      end

      # Checks if both data sets are hashes
      def self.both_hashes?(existing, new_data)
        existing.is_a?(Hash) && new_data.is_a?(Hash)
      end

      # Checks if an array has consistent ID fields across all elements
      def self.has_consistent_ids?(array)
        return false if array.empty?
        return false unless array.all? { |item| item.is_a?(Hash) }

        id_presence = array.map { |item| item.key?(:id) || item.key?('id') }
        id_presence.all? || id_presence.none?
      end

      # Checks if data requires special edge case handling
      def self.requires_edge_case_handling?(existing, new_data)
        # Mixed array/single record scenarios
        (existing.is_a?(Array) && new_data.is_a?(Hash)) ||
          (existing.is_a?(Hash) && new_data.is_a?(Array)) ||
          # Arrays with inconsistent ID presence
          (both_arrays?(existing, new_data) && !has_consistent_ids?(existing + new_data))
      end

      # Merges arrays by ID, handling overlapping and new records efficiently
      def self.merge_by_id(existing_array, new_array)
        # Convert to hash for O(1) lookup performance
        existing_by_id = index_by_id(existing_array)
        result_by_id = existing_by_id.dup

        # Process new data
        new_array.each do |new_item|
          id = extract_id(new_item)

          if existing_by_id.key?(id)
            # Merge with existing record
            result_by_id[id] = existing_by_id[id].merge(new_item)
          else
            # Add new record
            result_by_id[id] = new_item
          end
        end

        # Return as array, preserving original order where possible
        result_by_id.values
      end

      # Appends arrays together, handling single items gracefully
      def self.merge_by_append(existing_array, new_data)
        return existing_array if new_data.nil?

        existing_array + Array(new_data)
      end

      # Creates an index hash for efficient ID-based lookups
      def self.index_by_id(array)
        array.each_with_object({}) do |item, hash|
          id = extract_id(item)
          hash[id] = item
        end
      end

      # Extracts ID from a hash item, handling both symbol and string keys
      def self.extract_id(item)
        return nil unless item.is_a?(Hash)

        item[:id] || item['id']
      end
    end
  end
end