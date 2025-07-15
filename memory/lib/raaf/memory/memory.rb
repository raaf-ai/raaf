# frozen_string_literal: true

require "time"
require "securerandom"

module RubyAIAgentsFactory
  module Memory
    ##
    # Represents a single memory entry
    #
    # The Memory class encapsulates a single piece of information that an agent
    # wants to remember. It includes the content, metadata, timestamps, and
    # associations with specific agents and conversations. Memories can be
    # tagged, searched, and updated over time.
    #
    # @example Creating a memory
    #   memory = Memory.new(
    #     content: "User prefers dark theme",
    #     agent_name: "Assistant",
    #     conversation_id: "conv_123",
    #     metadata: { category: "preferences", user_id: "user_456" }
    #   )
    #
    # @example Adding tags
    #   memory.add_tags("ui", "preferences", "visual")
    #
    # @example Searching memories
    #   if memory.matches?("theme")
    #     puts memory.summary
    #   end
    #
    class Memory
      # @!attribute [rw] id
      #   @return [String] Unique identifier for the memory
      # @!attribute [rw] content
      #   @return [String, Hash] The actual memory content
      # @!attribute [rw] metadata
      #   @return [Hash] Additional metadata (tags, categories, etc.)
      # @!attribute [rw] created_at
      #   @return [Time] When the memory was created
      # @!attribute [rw] updated_at
      #   @return [Time] When the memory was last updated
      # @!attribute [rw] agent_name
      #   @return [String, nil] Name of the agent that created this memory
      # @!attribute [rw] conversation_id
      #   @return [String, nil] ID of the conversation this memory belongs to
      attr_accessor :id, :content, :metadata, :created_at, :updated_at, :agent_name, :conversation_id

      ##
      # Initialize a new memory
      #
      # @param content [String, Hash] The memory content to store
      # @param agent_name [String, nil] Name of the agent creating the memory
      # @param conversation_id [String, nil] ID of the associated conversation
      # @param metadata [Hash] Additional metadata for categorization
      # @param id [String, nil] Specific ID (auto-generated if not provided)
      #
      def initialize(content:, agent_name: nil, conversation_id: nil, metadata: {}, id: nil)
        @id = id || SecureRandom.uuid
        @content = content
        @agent_name = agent_name
        @conversation_id = conversation_id
        @metadata = metadata
        @created_at = Time.now
        @updated_at = Time.now
      end

      ##
      # Convert memory to hash for storage
      #
      # Serializes the memory object into a hash format suitable for
      # storage in various backends. Timestamps are converted to ISO8601
      # format for consistency.
      #
      # @return [Hash] Serialized memory data
      #
      # @example
      #   hash = memory.to_h
      #   # => { id: "uuid", content: "...", created_at: "2024-01-15T10:30:00Z", ... }
      #
      def to_h
        {
          id: @id,
          content: @content,
          agent_name: @agent_name,
          conversation_id: @conversation_id,
          metadata: @metadata,
          created_at: @created_at.iso8601,
          updated_at: @updated_at.iso8601
        }
      end

      ##
      # Create memory from hash
      #
      # Deserializes a hash (typically from storage) back into a Memory
      # object. Handles both symbol and string keys for flexibility.
      #
      # @param hash [Hash] Serialized memory data
      #
      # @return [Memory] Reconstructed memory object
      #
      # @example
      #   data = { content: "User preference", created_at: "2024-01-15T10:30:00Z" }
      #   memory = Memory.from_h(data)
      #
      def self.from_h(hash)
        memory = new(
          content: hash[:content] || hash["content"],
          agent_name: hash[:agent_name] || hash["agent_name"],
          conversation_id: hash[:conversation_id] || hash["conversation_id"],
          metadata: hash[:metadata] || hash["metadata"] || {},
          id: hash[:id] || hash["id"]
        )

        # Parse timestamps if present
        if hash[:created_at] || hash["created_at"]
          memory.created_at = Time.parse(hash[:created_at] || hash["created_at"])
        end

        if hash[:updated_at] || hash["updated_at"]
          memory.updated_at = Time.parse(hash[:updated_at] || hash["updated_at"])
        end

        memory
      end

      ##
      # Update the memory content
      #
      # Updates the memory's content and/or metadata, automatically
      # updating the timestamp.
      #
      # @param content [String, Hash, nil] New content (nil to keep existing)
      # @param metadata [Hash, nil] New metadata (nil to keep existing)
      #
      # @return [void]
      #
      # @example Update content
      #   memory.update(content: "User now prefers light theme")
      #
      # @example Update metadata
      #   memory.update(metadata: { priority: "high", verified: true })
      #
      def update(content: nil, metadata: nil)
        @content = content if content
        @metadata = metadata if metadata
        @updated_at = Time.now
      end

      ##
      # Add tags to metadata
      #
      # Adds one or more tags to the memory's metadata for categorization
      # and search purposes. Tags are stored uniquely (no duplicates).
      #
      # @param tags [Array<String>] Tags to add
      #
      # @return [void]
      #
      # @example
      #   memory.add_tags("important", "user-preference", "ui")
      #
      def add_tags(*tags)
        @metadata[:tags] ||= []
        @metadata[:tags].concat(tags).uniq!
        @updated_at = Time.now
      end

      ##
      # Check if memory has a specific tag
      #
      # @param tag [String] Tag to check for
      #
      # @return [Boolean] True if the tag exists, false otherwise
      #
      # @example
      #   if memory.has_tag?("important")
      #     process_important_memory(memory)
      #   end
      #
      def has_tag?(tag)
        @metadata[:tags]&.include?(tag) || false
      end

      ##
      # Get age of memory in seconds
      #
      # Calculates how long ago the memory was created. Useful for
      # implementing time-based memory decay or cleanup.
      #
      # @return [Float] Age in seconds
      #
      # @example Check if memory is old
      #   if memory.age > 86400  # 24 hours
      #     memory.add_tags("stale")
      #   end
      #
      def age
        Time.now - @created_at
      end

      ##
      # Get a summary of the memory
      #
      # Returns a truncated version of the content for display purposes.
      # Useful for showing memory lists or previews.
      #
      # @param max_length [Integer] Maximum length before truncation (default: 100)
      #
      # @return [String] Truncated content with ellipsis if needed
      #
      # @example
      #   puts memory.summary(50)  # "User prefers dark theme and wants notific..."
      #
      def summary(max_length = 100)
        return @content if @content.length <= max_length

        "#{@content[0...max_length]}..."
      end

      ##
      # Check if memory matches a query
      #
      # Performs a simple case-insensitive text search across the memory's
      # content, metadata values, and tags. This is a basic implementation
      # that can be extended for more sophisticated search.
      #
      # @param query [String] Search query
      #
      # @return [Boolean] True if query matches anywhere in the memory
      #
      # @example
      #   memories = store.list_keys.map { |key| Memory.from_h(store.retrieve(key)) }
      #   matching = memories.select { |m| m.matches?("preferences") }
      #
      def matches?(query)
        query_lower = query.downcase

        # Search in content
        return true if @content.downcase.include?(query_lower)

        # Search in metadata
        @metadata.each_value do |value|
          return true if value.to_s.downcase.include?(query_lower)
        end

        # Search in tags
        @metadata[:tags]&.each do |tag|
          return true if tag.downcase.include?(query_lower)
        end

        false
      end
    end
  end
end
