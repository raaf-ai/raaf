# frozen_string_literal: true

require_relative "base_store"
require_relative "memory"

module OpenAIAgents
  module Memory
    # In-memory implementation of memory storage
    # Useful for development, testing, and short-lived processes
    class InMemoryStore < BaseStore
      def initialize
        @memories = {}
        @mutex = Mutex.new
      end

      def store(key, value, metadata = {})
        @mutex.synchronize do
          memory = case value
                   when Memory
                     value
                   when Hash
                     Memory.from_h(value)
                   else
                     Memory.new(content: value.to_s, metadata: metadata)
                   end

          memory.updated_at = Time.now
          @memories[key] = memory
        end
      end

      def retrieve(key)
        @mutex.synchronize do
          memory = @memories[key]
          memory&.to_h
        end
      end

      def search(query, options = {})
        limit = options[:limit] || 100
        agent_name = options[:agent_name]
        conversation_id = options[:conversation_id]
        tags = options[:tags] || []

        @mutex.synchronize do
          results = @memories.values.select do |memory|
            # Filter by agent name if provided
            next false if agent_name && memory.agent_name != agent_name

            # Filter by conversation ID if provided
            next false if conversation_id && memory.conversation_id != conversation_id

            # Filter by tags if provided
            next false if tags.any? && !tags.all? { |tag| memory.has_tag?(tag) }

            # Match query
            memory.matches?(query)
          end

          # Sort by relevance (most recent first for now)
          results.sort_by! { |m| -m.updated_at.to_i }

          # Apply limit
          results = results.take(limit)

          # Convert to hashes
          results.map(&:to_h)
        end
      end

      def delete(key)
        @mutex.synchronize do
          @memories.delete(key) ? true : false
        end
      end

      def list_keys(options = {})
        agent_name = options[:agent_name]
        conversation_id = options[:conversation_id]

        @mutex.synchronize do
          if agent_name || conversation_id
            @memories.select do |_key, memory|
              (agent_name.nil? || memory.agent_name == agent_name) &&
                (conversation_id.nil? || memory.conversation_id == conversation_id)
            end.keys
          else
            @memories.keys
          end
        end
      end

      def clear
        @mutex.synchronize do
          @memories.clear
        end
      end

      def count
        @mutex.synchronize do
          @memories.size
        end
      end

      def get_by_time_range(start_time, end_time)
        @mutex.synchronize do
          results = @memories.values.select do |memory|
            memory.created_at.between?(start_time, end_time)
          end

          results.sort_by!(&:created_at)
          results.map(&:to_h)
        end
      end

      def get_recent(limit = 10)
        @mutex.synchronize do
          @memories.values
                   .sort_by { |m| -m.updated_at.to_i }
                   .take(limit)
                   .map(&:to_h)
        end
      end

      # Additional utility methods for in-memory store

      # Get all memories for a specific agent
      def get_by_agent(agent_name, limit = nil)
        @mutex.synchronize do
          results = @memories.values.select { |m| m.agent_name == agent_name }
          results = results.sort_by { |m| -m.updated_at.to_i }
          results = results.take(limit) if limit
          results.map(&:to_h)
        end
      end

      # Get all memories for a specific conversation
      def get_by_conversation(conversation_id, limit = nil)
        @mutex.synchronize do
          results = @memories.values.select { |m| m.conversation_id == conversation_id }
          results = results.sort_by(&:created_at)
          results = results.take(limit) if limit
          results.map(&:to_h)
        end
      end

      # Export all memories (useful for persistence)
      def export
        @mutex.synchronize do
          @memories.transform_values(&:to_h)
        end
      end

      # Import memories (useful for loading from persistence)
      def import(data)
        @mutex.synchronize do
          data.each do |key, value|
            @memories[key] = Memory.from_h(value)
          end
        end
      end
    end
  end
end
