# frozen_string_literal: true

require_relative "base_store"
require_relative "memory"
require "json"
require "fileutils"

module OpenAIAgents
  module Memory
    # File-based implementation of memory storage
    # Persists memories to JSON files on disk
    class FileStore < BaseStore
      def initialize(base_dir = nil)
        @base_dir = base_dir || File.join(Dir.home, ".openai_agents", "memories")
        @index_file = File.join(@base_dir, "index.json")
        @mutex = Mutex.new
        
        # Ensure directory exists
        FileUtils.mkdir_p(@base_dir)
        
        # Load or create index
        load_index
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
          
          # Save memory to individual file
          memory_file = memory_path(key)
          File.write(memory_file, JSON.pretty_generate(memory.to_h))
          
          # Update index
          @index[key] = {
            file: memory_file,
            created_at: memory.created_at.iso8601,
            updated_at: memory.updated_at.iso8601,
            agent_name: memory.agent_name,
            conversation_id: memory.conversation_id,
            tags: memory.metadata[:tags] || []
          }
          
          save_index
        end
      end

      def retrieve(key)
        @mutex.synchronize do
          return nil unless @index.key?(key)
          
          memory_file = @index[key][:file] || memory_path(key)
          return nil unless File.exist?(memory_file)
          
          JSON.parse(File.read(memory_file), symbolize_names: true)
        rescue JSON::ParserError, Errno::ENOENT
          nil
        end
      end

      def search(query, options = {})
        limit = options[:limit] || 100
        agent_name = options[:agent_name]
        conversation_id = options[:conversation_id]
        tags = options[:tags] || []

        @mutex.synchronize do
          results = []
          
          @index.each do |key, index_entry|
            # Apply filters from index first (faster)
            next if agent_name && index_entry[:agent_name] != agent_name
            next if conversation_id && index_entry[:conversation_id] != conversation_id
            
            if tags.any?
              entry_tags = index_entry[:tags] || []
              next unless tags.all? { |tag| entry_tags.include?(tag) }
            end
            
            # Load and check memory content
            memory_data = retrieve(key)
            next unless memory_data
            
            memory = Memory.from_h(memory_data)
            results << memory_data if memory.matches?(query)
            
            break if results.size >= limit
          end
          
          results
        end
      end

      def delete(key)
        @mutex.synchronize do
          return false unless @index.key?(key)
          
          # Delete file
          memory_file = @index[key][:file] || memory_path(key)
          File.delete(memory_file) if File.exist?(memory_file)
          
          # Remove from index
          @index.delete(key)
          save_index
          
          true
        end
      end

      def list_keys(options = {})
        agent_name = options[:agent_name]
        conversation_id = options[:conversation_id]

        @mutex.synchronize do
          if agent_name || conversation_id
            @index.select do |_key, entry|
              (agent_name.nil? || entry[:agent_name] == agent_name) &&
                (conversation_id.nil? || entry[:conversation_id] == conversation_id)
            end.keys
          else
            @index.keys
          end
        end
      end

      def clear
        @mutex.synchronize do
          # Delete all memory files
          @index.each do |_key, entry|
            memory_file = entry[:file]
            File.delete(memory_file) if memory_file && File.exist?(memory_file)
          end
          
          # Clear index
          @index.clear
          save_index
        end
      end

      def count
        @mutex.synchronize do
          @index.size
        end
      end

      def get_by_time_range(start_time, end_time)
        @mutex.synchronize do
          results = []
          
          @index.each do |key, entry|
            created_at = Time.parse(entry[:created_at])
            next unless created_at >= start_time && created_at <= end_time
            
            memory_data = retrieve(key)
            results << memory_data if memory_data
          end
          
          results.sort_by { |m| m[:created_at] }
        end
      end

      def get_recent(limit = 10)
        @mutex.synchronize do
          # Sort index entries by updated_at
          sorted_keys = @index.sort_by { |_k, v| -Time.parse(v[:updated_at]).to_i }
                              .take(limit)
                              .map(&:first)
          
          # Retrieve memories
          sorted_keys.map { |key| retrieve(key) }.compact
        end
      end

      # Compact the storage (remove orphaned files)
      def compact!
        @mutex.synchronize do
          # Find all memory files
          memory_files = Dir.glob(File.join(@base_dir, "*.memory.json"))
          
          # Find files not in index
          indexed_files = @index.values.map { |v| v[:file] }.compact
          orphaned_files = memory_files - indexed_files
          
          # Delete orphaned files
          orphaned_files.each { |file| File.delete(file) }
          
          orphaned_files.size
        end
      end

      private

      def memory_path(key)
        # Sanitize key for filesystem
        safe_key = key.gsub(/[^a-zA-Z0-9_-]/, "_")
        File.join(@base_dir, "#{safe_key}.memory.json")
      end

      def load_index
        if File.exist?(@index_file)
          @index = JSON.parse(File.read(@index_file), symbolize_names: true)
        else
          @index = {}
          save_index
        end
      rescue JSON::ParserError
        @index = {}
        save_index
      end

      def save_index
        File.write(@index_file, JSON.pretty_generate(@index))
      end
    end
  end
end