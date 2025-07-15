# frozen_string_literal: true

require_relative "memory/base_store"
require_relative "memory/memory"
require_relative "memory/in_memory_store"
require_relative "memory/file_store"
require_relative "memory/memory_manager"

module RubyAIAgentsFactory
  ##
  # Memory system for OpenAI Agents
  #
  # The Memory module provides persistent and ephemeral memory storage for agents,
  # enabling them to maintain context across conversations and sessions. It supports
  # multiple storage backends including in-memory, file-based, and custom stores.
  #
  # Memory allows agents to:
  # - Remember user preferences and past interactions
  # - Maintain conversation history beyond single sessions
  # - Share knowledge between different agent instances
  # - Implement personalization and context awareness
  #
  # @example Using in-memory storage (ephemeral)
  #   store = RubyAIAgentsFactory::Memory.create_store(:in_memory)
  #   agent = RubyAIAgentsFactory::Agent.new(
  #     name: "Assistant",
  #     memory_store: store
  #   )
  #
  # @example Using file-based storage (persistent)
  #   store = RubyAIAgentsFactory::Memory.create_store(
  #     :file,
  #     base_dir: "./agent_memory"
  #   )
  #   agent.memory_store = store
  #
  # @example Setting a default store for all agents
  #   RubyAIAgentsFactory::Memory.default_store = RubyAIAgentsFactory::Memory.create_store(
  #     :file,
  #     base_dir: "./shared_memory"
  #   )
  #
  # @example Creating a custom store
  #   class RedisStore < RubyAIAgentsFactory::Memory::BaseStore
  #     def initialize(redis_client)
  #       @redis = redis_client
  #     end
  #     
  #     def get(key)
  #       @redis.get(key)
  #     end
  #     
  #     def set(key, value)
  #       @redis.set(key, value)
  #     end
  #   end
  #   
  #   store = RubyAIAgentsFactory::Memory.create_store(
  #     :custom,
  #     store_class: RedisStore,
  #     redis_client: Redis.new
  #   )
  #
  module Memory
    ##
    # Create a memory store based on type
    #
    # Factory method for creating different types of memory stores.
    # Supports built-in stores and custom implementations.
    #
    # @param type [Symbol] Store type (:in_memory, :file, :custom)
    # @param options [Hash] Options specific to the store type
    # @option options [String] :base_dir (for :file type) Directory for file storage
    # @option options [Class] :store_class (for :custom type) Custom store class
    # @option options [Hash] Additional options passed to custom store constructor
    #
    # @return [BaseStore] Memory store instance
    #
    # @raise [ArgumentError] If type is unknown or required options are missing
    #
    # @example In-memory store
    #   store = Memory.create_store(:in_memory)
    #
    # @example File store with custom directory
    #   store = Memory.create_store(:file, base_dir: "/var/lib/agent_memory")
    #
    # @example Custom store with options
    #   store = Memory.create_store(
    #     :custom,
    #     store_class: MyCustomStore,
    #     connection_string: "mongodb://localhost:27017"
    #   )
    #
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

    ##
    # Configure default memory store for all agents
    #
    # Sets a global default memory store that will be used by all agents
    # unless they specify their own store. This is useful for sharing
    # memory across multiple agents or ensuring all agents use the same
    # storage backend.
    #
    # @param store [BaseStore] Default store instance
    #
    # @example Set file-based default store
    #   Memory.default_store = Memory.create_store(
    #     :file,
    #     base_dir: "./shared_agent_memory"
    #   )
    #
    # @example Use custom store as default
    #   Memory.default_store = MyCustomStore.new(
    #     connection: database_connection
    #   )
    #
    def self.default_store=(store)
      @default_store = store
    end

    ##
    # Get default memory store
    #
    # Returns the globally configured default memory store, if any.
    # Agents will use this store unless they have their own configured.
    #
    # @return [BaseStore, nil] Default store instance or nil if not set
    #
    # @example Check if default store is configured
    #   if Memory.default_store
    #     puts "Using default store: #{Memory.default_store.class}"
    #   else
    #     puts "No default store configured"
    #   end
    #
    def self.default_store
      @default_store
    end
  end
end
