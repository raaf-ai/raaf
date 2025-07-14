# frozen_string_literal: true

module OpenAIAgents
  module Memory
    ##
    # Abstract base class for memory storage implementations
    #
    # This class defines the interface that all memory stores must implement.
    # Memory stores provide persistent or ephemeral storage for agent memories,
    # enabling agents to maintain context across conversations and sessions.
    #
    # Subclasses must implement all abstract methods to provide a complete
    # storage backend. The interface is designed to be flexible enough to
    # support various storage systems including databases, files, and
    # cloud storage services.
    #
    # @abstract Subclass and implement all abstract methods
    #
    # @example Implementing a custom memory store
    #   class RedisMemoryStore < BaseStore
    #     def initialize(redis_client)
    #       @redis = redis_client
    #       @prefix = "agent_memory:"
    #     end
    #     
    #     def store(key, value, metadata = {})
    #       data = { value: value, metadata: metadata, timestamp: Time.now }
    #       @redis.set("#{@prefix}#{key}", data.to_json)
    #     end
    #     
    #     def retrieve(key)
    #       data = @redis.get("#{@prefix}#{key}")
    #       return nil unless data
    #       JSON.parse(data, symbolize_names: true)[:value]
    #     end
    #     
    #     def search(query, options = {})
    #       # Implement search logic
    #       []
    #     end
    #     
    #     def delete(key)
    #       @redis.del("#{@prefix}#{key}") > 0
    #     end
    #   end
    #
    class BaseStore
      ##
      # Store a memory entry
      #
      # Saves a memory with the given key and value. Metadata can be used
      # to store additional information like timestamps, tags, or context.
      #
      # @param key [String] Unique identifier for the memory
      # @param value [Hash] Memory data to store (typically conversation context)
      # @param metadata [Hash] Optional metadata (tags, timestamps, user_id, etc.)
      #
      # @return [void]
      #
      # @raise [NotImplementedError] Must be implemented by subclasses
      #
      # @example Storing a user preference
      #   store.store(
      #     "user_123_preferences",
      #     { theme: "dark", language: "en" },
      #     { timestamp: Time.now, category: "preferences" }
      #   )
      #
      def store(key, value, metadata = {})
        raise NotImplementedError, "Subclasses must implement store"
      end

      ##
      # Retrieve a memory entry
      #
      # Fetches a previously stored memory by its key. Returns nil if
      # the memory doesn't exist.
      #
      # @param key [String] Unique identifier for the memory
      #
      # @return [Hash, nil] The stored memory data or nil if not found
      #
      # @raise [NotImplementedError] Must be implemented by subclasses
      #
      # @example Retrieving user preferences
      #   preferences = store.retrieve("user_123_preferences")
      #   if preferences
      #     puts "Theme: #{preferences[:theme]}"
      #   end
      #
      def retrieve(key)
        raise NotImplementedError, "Subclasses must implement retrieve"
      end

      ##
      # Search memories based on query
      #
      # Searches stored memories using the provided query. The search
      # implementation is store-specific and may support different
      # query formats (keywords, semantic search, filters, etc.).
      #
      # @param query [String] Search query
      # @param options [Hash] Search options
      # @option options [Integer] :limit Maximum results to return
      # @option options [Hash] :filters Additional filters (tags, date range, etc.)
      # @option options [Symbol] :sort_by Field to sort by
      # @option options [Symbol] :order Sort order (:asc or :desc)
      #
      # @return [Array<Hash>] Array of matching memories with keys and values
      #
      # @raise [NotImplementedError] Must be implemented by subclasses
      #
      # @example Basic search
      #   results = store.search("user preferences")
      #
      # @example Search with options
      #   results = store.search("billing", 
      #     limit: 10,
      #     filters: { category: "support" },
      #     sort_by: :timestamp,
      #     order: :desc
      #   )
      #
      def search(query, options = {})
        raise NotImplementedError, "Subclasses must implement search"
      end

      ##
      # Delete a memory entry
      #
      # Removes a memory from storage. Returns true if the memory
      # existed and was deleted, false if it didn't exist.
      #
      # @param key [String] Unique identifier for the memory
      #
      # @return [Boolean] True if deleted, false if not found
      #
      # @raise [NotImplementedError] Must be implemented by subclasses
      #
      # @example Deleting old preferences
      #   if store.delete("user_123_old_preferences")
      #     puts "Old preferences removed"
      #   end
      #
      def delete(key)
        raise NotImplementedError, "Subclasses must implement delete"
      end

      ##
      # List all memory keys
      #
      # Returns an array of all stored memory keys, optionally filtered
      # by the provided options.
      #
      # @param options [Hash] Filter options
      # @option options [String] :prefix Only keys starting with this prefix
      # @option options [Regexp] :pattern Only keys matching this pattern
      # @option options [Integer] :limit Maximum number of keys to return
      #
      # @return [Array<String>] Array of memory keys
      #
      # @raise [NotImplementedError] Must be implemented by subclasses
      #
      # @example List all keys
      #   all_keys = store.list_keys
      #
      # @example List user preference keys
      #   pref_keys = store.list_keys(prefix: "user_", pattern: /_preferences$/)
      #
      def list_keys(options = {})
        raise NotImplementedError, "Subclasses must implement list_keys"
      end

      ##
      # Clear all memories
      #
      # Removes all stored memories. Use with caution as this operation
      # is typically irreversible.
      #
      # @return [void]
      #
      # @raise [NotImplementedError] Must be implemented by subclasses
      #
      # @example Clear all memories
      #   store.clear
      #   puts "All memories cleared"
      #
      def clear
        raise NotImplementedError, "Subclasses must implement clear"
      end

      ##
      # Get count of stored memories
      #
      # Returns the total number of memories currently stored.
      #
      # @return [Integer] Number of stored memories
      #
      # @raise [NotImplementedError] Must be implemented by subclasses
      #
      # @example Check memory usage
      #   puts "Currently storing #{store.count} memories"
      #
      def count
        raise NotImplementedError, "Subclasses must implement count"
      end

      ##
      # Check if a memory exists
      #
      # Checks whether a memory with the given key exists in storage.
      # Default implementation uses retrieve, but subclasses may override
      # for efficiency.
      #
      # @param key [String] Unique identifier for the memory
      #
      # @return [Boolean] True if exists, false otherwise
      #
      # @example Check before storing
      #   unless store.exists?("user_123_preferences")
      #     store.store("user_123_preferences", default_preferences)
      #   end
      #
      def exists?(key)
        !retrieve(key).nil?
      end

      ##
      # Get memories within a time range
      #
      # Retrieves all memories created or modified within the specified
      # time range. Requires the store implementation to track timestamps.
      #
      # @param start_time [Time] Start of the time range (inclusive)
      # @param end_time [Time] End of the time range (inclusive)
      #
      # @return [Array<Hash>] Array of memories within the range
      #
      # @raise [NotImplementedError] Must be implemented by subclasses
      #
      # @example Get memories from the last hour
      #   recent = store.get_by_time_range(1.hour.ago, Time.now)
      #
      # @example Get memories from a specific day
      #   day_start = Date.parse("2024-01-15").to_time
      #   day_end = day_start + 86400  # 24 hours
      #   memories = store.get_by_time_range(day_start, day_end)
      #
      def get_by_time_range(start_time, end_time)
        raise NotImplementedError, "Subclasses must implement get_by_time_range"
      end

      ##
      # Get recent memories
      #
      # Retrieves the most recently created or modified memories.
      # Useful for maintaining conversation context or showing
      # recent activity.
      #
      # @param limit [Integer] Number of recent memories to retrieve (default: 10)
      #
      # @return [Array<Hash>] Array of recent memories, newest first
      #
      # @raise [NotImplementedError] Must be implemented by subclasses
      #
      # @example Get last 5 memories
      #   recent = store.get_recent(5)
      #   recent.each do |memory|
      #     puts "#{memory[:key]}: #{memory[:value]}"
      #   end
      #
      def get_recent(limit = 10)
        raise NotImplementedError, "Subclasses must implement get_recent"
      end
    end
  end
end
