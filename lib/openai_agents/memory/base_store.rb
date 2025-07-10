# frozen_string_literal: true

module OpenAIAgents
  module Memory
    # Base interface for memory storage implementations
    class BaseStore
      # Store a memory entry
      # @param key [String] Unique identifier for the memory
      # @param value [Hash] Memory data to store
      # @param metadata [Hash] Optional metadata (tags, timestamps, etc.)
      # @return [void]
      def store(key, value, metadata = {})
        raise NotImplementedError, "Subclasses must implement store"
      end

      # Retrieve a memory entry
      # @param key [String] Unique identifier for the memory
      # @return [Hash, nil] The stored memory data or nil if not found
      def retrieve(key)
        raise NotImplementedError, "Subclasses must implement retrieve"
      end

      # Search memories based on query
      # @param query [String] Search query
      # @param options [Hash] Search options (limit, filters, etc.)
      # @return [Array<Hash>] Array of matching memories
      def search(query, options = {})
        raise NotImplementedError, "Subclasses must implement search"
      end

      # Delete a memory entry
      # @param key [String] Unique identifier for the memory
      # @return [Boolean] True if deleted, false if not found
      def delete(key)
        raise NotImplementedError, "Subclasses must implement delete"
      end

      # List all memory keys
      # @param options [Hash] Filter options
      # @return [Array<String>] Array of memory keys
      def list_keys(options = {})
        raise NotImplementedError, "Subclasses must implement list_keys"
      end

      # Clear all memories
      # @return [void]
      def clear
        raise NotImplementedError, "Subclasses must implement clear"
      end

      # Get count of stored memories
      # @return [Integer] Number of stored memories
      def count
        raise NotImplementedError, "Subclasses must implement count"
      end

      # Check if a memory exists
      # @param key [String] Unique identifier for the memory
      # @return [Boolean] True if exists, false otherwise
      def exists?(key)
        !retrieve(key).nil?
      end

      # Get memories within a time range
      # @param start_time [Time] Start of the time range
      # @param end_time [Time] End of the time range
      # @return [Array<Hash>] Array of memories within the range
      def get_by_time_range(start_time, end_time)
        raise NotImplementedError, "Subclasses must implement get_by_time_range"
      end

      # Get recent memories
      # @param limit [Integer] Number of recent memories to retrieve
      # @return [Array<Hash>] Array of recent memories
      def get_recent(limit = 10)
        raise NotImplementedError, "Subclasses must implement get_recent"
      end
    end
  end
end
