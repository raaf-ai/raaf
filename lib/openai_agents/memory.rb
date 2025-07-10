# frozen_string_literal: true

require_relative "memory/base_store"
require_relative "memory/memory"
require_relative "memory/in_memory_store"
require_relative "memory/file_store"
require_relative "memory/memory_manager"

module OpenAIAgents
  # Memory system for OpenAI Agents
  # Provides persistent memory storage and retrieval for agents
  module Memory
    # Create a memory store based on type
    # @param type [Symbol] Store type (:in_memory, :file, :custom)
    # @param options [Hash] Options for the store
    # @return [BaseStore] Memory store instance
    def self.create_store(type = :in_memory, **options)
      case type
      when :in_memory
        InMemoryStore.new
      when :file
        FileStore.new(options[:base_dir])
      when :custom
        store_class = options[:store_class]
        raise ArgumentError, "store_class required for custom store" unless store_class

        store_class.new(**options.except(:store_class))
      else
        raise ArgumentError, "Unknown store type: #{type}"
      end
    end

    # Configure default memory store for all agents
    # @param store [BaseStore] Default store instance
    def self.default_store=(store)
      @default_store = store
    end

    # Get default memory store
    # @return [BaseStore, nil] Default store instance
    def self.default_store
      @default_store
    end
  end
end
