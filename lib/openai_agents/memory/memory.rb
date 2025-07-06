# frozen_string_literal: true

require "time"
require "securerandom"

module OpenAIAgents
  module Memory
    # Represents a single memory entry
    class Memory
      attr_accessor :id, :content, :metadata, :created_at, :updated_at, :agent_name, :conversation_id

      def initialize(content:, agent_name: nil, conversation_id: nil, metadata: {}, id: nil)
        @id = id || SecureRandom.uuid
        @content = content
        @agent_name = agent_name
        @conversation_id = conversation_id
        @metadata = metadata
        @created_at = Time.now
        @updated_at = Time.now
      end

      # Convert memory to hash for storage
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

      # Create memory from hash
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

      # Update the memory content
      def update(content: nil, metadata: nil)
        @content = content if content
        @metadata = metadata if metadata
        @updated_at = Time.now
      end

      # Add tags to metadata
      def add_tags(*tags)
        @metadata[:tags] ||= []
        @metadata[:tags].concat(tags).uniq!
        @updated_at = Time.now
      end

      # Check if memory has a specific tag
      def has_tag?(tag)
        @metadata[:tags]&.include?(tag) || false
      end

      # Get age of memory in seconds
      def age
        Time.now - @created_at
      end

      # Get a summary of the memory (useful for display)
      def summary(max_length = 100)
        return @content if @content.length <= max_length
        
        "#{@content[0...max_length]}..."
      end

      # Check if memory matches a query (simple text search)
      def matches?(query)
        query_lower = query.downcase
        
        # Search in content
        return true if @content.downcase.include?(query_lower)
        
        # Search in metadata
        @metadata.each do |_key, value|
          return true if value.to_s.downcase.include?(query_lower)
        end
        
        # Search in tags
        if @metadata[:tags]
          @metadata[:tags].each do |tag|
            return true if tag.downcase.include?(query_lower)
          end
        end
        
        false
      end
    end
  end
end