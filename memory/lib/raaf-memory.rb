# frozen_string_literal: true

require_relative "raaf/memory/version"
require_relative "raaf/memory"
require_relative "raaf/vector_store"
require_relative "raaf/semantic_search"

module RubyAIAgentsFactory
  ##
  # Memory and vector storage for Ruby AI Agents Factory
  #
  # The Memory gem provides comprehensive memory management and vector search
  # capabilities for AI agents. It includes persistent storage, semantic search,
  # vector databases, and memory management across conversations and sessions.
  #
  # Key features:
  # - **Persistent Memory** - Store and retrieve agent memories across sessions
  # - **Vector Storage** - High-performance vector databases for semantic search
  # - **Semantic Search** - Advanced semantic search with multiple indexing algorithms
  # - **Multiple Adapters** - Support for in-memory, file-based, and database storage
  # - **Memory Management** - Automatic cleanup and memory optimization
  # - **RAG Support** - Full support for Retrieval-Augmented Generation workflows
  #
  # @example Basic memory usage
  #   require 'raaf-memory'
  #   
  #   # Create memory store
  #   store = RubyAIAgentsFactory::Memory.create_store(:file, base_dir: "./memory")
  #   
  #   # Use with agent
  #   agent = RubyAIAgentsFactory::Agent.new(
  #     name: "Assistant",
  #     memory_store: store
  #   )
  #
  # @example Vector store for semantic search
  #   require 'raaf-memory'
  #   
  #   # Create vector store
  #   vector_store = RubyAIAgentsFactory::VectorStore.new(
  #     name: "knowledge_base",
  #     dimensions: 1536
  #   )
  #   
  #   # Add documents
  #   documents = [
  #     "Ruby is a dynamic programming language",
  #     "Python is great for data science",
  #     "JavaScript runs in web browsers"
  #   ]
  #   
  #   vector_store.add_documents(documents)
  #   
  #   # Search for similar content
  #   results = vector_store.search("web development languages", k: 2)
  #   
  # @example Advanced semantic search
  #   require 'raaf-memory'
  #   
  #   # Create semantic search database
  #   db = RubyAIAgentsFactory::SemanticSearch::VectorDatabase.new(
  #     dimension: 1536,
  #     index_type: :hnsw
  #   )
  #   
  #   # Index documents
  #   indexer = RubyAIAgentsFactory::SemanticSearch::DocumentIndexer.new(
  #     vector_db: db
  #   )
  #   
  #   documents = [
  #     { content: "Article about Ruby", title: "Ruby Guide", metadata: { category: "programming" } },
  #     { content: "Python tutorial", title: "Python Basics", metadata: { category: "programming" } }
  #   ]
  #   
  #   indexer.index_documents(documents)
  #   
  #   # Search with filtering
  #   results = indexer.search(
  #     "programming languages",
  #     k: 5,
  #     filter: { category: "programming" }
  #   )
  #
  # @example PostgreSQL vector store
  #   require 'raaf-memory'
  #   require 'pg'
  #   
  #   # Create PostgreSQL adapter
  #   adapter = RubyAIAgentsFactory::Adapters::PgVectorAdapter.new(
  #     connection_string: "postgres://user:pass@localhost/db"
  #   )
  #   
  #   # Create vector store with PostgreSQL backend
  #   vector_store = RubyAIAgentsFactory::VectorStore.new(
  #     name: "production_knowledge",
  #     adapter: adapter,
  #     dimensions: 1536
  #   )
  #
  # @since 1.0.0
  module Memory
    # Re-export main classes for convenience
    VectorStore = RubyAIAgentsFactory::VectorStore
    SemanticSearch = RubyAIAgentsFactory::SemanticSearch

    ##
    # Configure memory settings
    #
    # @param options [Hash] Configuration options
    # @option options [String] :default_store_type (:in_memory) Default store type
    # @option options [String] :default_base_dir ("./memory") Default directory for file stores
    # @option options [Integer] :default_dimensions (1536) Default vector dimensions
    # @option options [Boolean] :enable_cache (true) Enable memory caching
    # @option options [Integer] :cache_ttl (3600) Cache TTL in seconds
    #
    # @example Configure memory defaults
    #   RubyAIAgentsFactory::Memory.configure do |config|
    #     config.default_store_type = :file
    #     config.default_base_dir = "/var/lib/agent_memory"
    #     config.default_dimensions = 1536
    #     config.enable_cache = true
    #   end
    #
    def self.configure
      @config ||= {
        default_store_type: :in_memory,
        default_base_dir: "./memory",
        default_dimensions: 1536,
        enable_cache: true,
        cache_ttl: 3600
      }
      yield @config if block_given?
      @config
    end

    ##
    # Get current configuration
    #
    # @return [Hash] Current configuration
    def self.config
      @config ||= configure
    end

    ##
    # Create a vector store with default configuration
    #
    # @param name [String] Vector store name
    # @param options [Hash] Additional options
    # @return [VectorStore] New vector store instance
    #
    def self.create_vector_store(name, **options)
      options[:dimensions] ||= config[:default_dimensions]
      VectorStore.new(name: name, **options)
    end

    ##
    # Create a semantic search database with default configuration
    #
    # @param options [Hash] Configuration options
    # @return [SemanticSearch::VectorDatabase] New semantic search database
    #
    def self.create_semantic_search(**options)
      options[:dimension] ||= config[:default_dimensions]
      SemanticSearch::VectorDatabase.new(**options)
    end

    ##
    # Get memory statistics
    #
    # @return [Hash] Memory usage statistics
    #
    def self.stats
      {
        default_store: default_store&.class&.name,
        config: config,
        ruby_version: RUBY_VERSION,
        gem_version: VERSION
      }
    end

    ##
    # Clear all memory stores and caches
    #
    def self.clear_all
      @default_store = nil
      @config = nil
      # Clear any global caches
      SemanticSearch::EmbeddingGenerator.new.clear_cache if defined?(SemanticSearch::EmbeddingGenerator)
    end
  end
end