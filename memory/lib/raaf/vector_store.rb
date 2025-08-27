# frozen_string_literal: true

require "json"
require "digest"
require_relative "../../../core/lib/raaf/utils"
begin
  # Suppress matrix deprecation warning
  original_verbose = $VERBOSE
  $VERBOSE = nil
  require "matrix"
  $VERBOSE = original_verbose
rescue LoadError
  # Matrix gem not available, this file won't be usable
  raise LoadError, "Matrix gem required for vector store functionality. Add 'gem \"matrix\"' to your Gemfile."
end

module RAAF
  ##
  # Vector store for semantic search and retrieval
  #
  # Provides high-performance vector storage and similarity search capabilities
  # for building RAG (Retrieval-Augmented Generation) systems and semantic
  # search applications. Supports multiple storage adapters including in-memory
  # and PostgreSQL with pgvector.
  #
  # @example Basic usage with documents
  #   store = VectorStore.new(
  #     name: "knowledge_base",
  #     dimensions: 1536  # OpenAI ada-002 dimensions
  #   )
  #   
  #   # Add documents
  #   documents = [
  #     "Ruby is a dynamic programming language",
  #     "Python is great for data science",
  #     "JavaScript runs in web browsers"
  #   ]
  #   
  #   store.add_documents(documents)
  #   
  #   # Search for similar content
  #   results = store.search("web development languages", k: 2)
  #   results.each { |result| puts result[:content] }
  #
  # @example With custom embeddings and metadata
  #   store = VectorStore.new(name: "products")
  #   
  #   products = [
  #     { 
  #       content: "MacBook Pro 16-inch laptop",
  #       category: "electronics",
  #       price: 2499.00
  #     },
  #     {
  #       content: "Ergonomic office chair",
  #       category: "furniture", 
  #       price: 299.99
  #     }
  #   ]
  #   
  #   # Custom embeddings (if you have them)
  #   embeddings = generate_custom_embeddings(products)
  #   store.add_documents(products, embeddings: embeddings)
  #   
  #   # Search with filters
  #   laptops = store.search(
  #     "portable computer",
  #     k: 5,
  #     filter: { category: "electronics" }
  #   )
  #
  # @example Using PostgreSQL adapter
  #   require 'pg'
  #   
  #   pg_adapter = VectorStore::Adapters::PgVectorAdapter.new(
  #     connection_string: "postgres://user:pass@localhost/db"
  #   )
  #   
  #   store = VectorStore.new(
  #     name: "enterprise_docs",
  #     adapter: pg_adapter,
  #     dimensions: 1536
  #   )
  #
  # @see Adapters::InMemoryAdapter In-memory storage for development
  # @see Adapters::PgVectorAdapter PostgreSQL with pgvector for production
  # @since 1.0.0
  #
  class VectorStore
    # @return [String] Name of the vector store
    attr_reader :name
    
    # @return [Integer] Dimensionality of the vectors (e.g., 1536 for OpenAI ada-002)
    attr_reader :dimensions
    
    # @return [Hash] Store-level metadata
    attr_reader :metadata

    ##
    # Initialize a new vector store
    #
    # @param name [String] Unique identifier for the vector store
    # @param dimensions [Integer] Vector dimensionality (default: 1536 for OpenAI embeddings)
    # @param adapter [Adapters::Base, nil] Storage adapter (default: InMemoryAdapter)
    # @param options [Hash] Additional options passed to the adapter
    # @option options [String] :distance_metric ("cosine") Distance calculation method
    # @option options [Boolean] :normalize_vectors (true) Whether to normalize vectors
    # @option options [Integer] :index_threshold (1000) When to build search index
    #
    def initialize(name:, dimensions: 1536, adapter: nil, **options)
      @name = name
      @dimensions = dimensions
      @adapter = adapter || Adapters::InMemoryAdapter.new
      @options = options
      @metadata = {}

      @adapter.initialize_store(name, dimensions, **options)
    end

    ##
    # Add documents to the vector store
    #
    # Stores documents with their vector embeddings for later similarity search.
    # If embeddings are not provided, they will be generated automatically
    # using the configured embedding model.
    #
    # @param documents [Array<String, Hash>] Documents to add
    # @param embeddings [Array<Array<Float>>, nil] Pre-computed embeddings (optional)
    # @param namespace [String, nil] Namespace to group documents (optional)
    # @return [Array<String>] IDs of the added documents
    #
    # @example With string documents
    #   ids = store.add_documents([
    #     "First document content",
    #     "Second document content"
    #   ])
    #
    # @example With structured documents
    #   ids = store.add_documents([
    #     {
    #       content: "Document text",
    #       title: "Document Title",
    #       author: "Author Name",
    #       category: "research"
    #     }
    #   ])
    #
    # @example With pre-computed embeddings
    #   embeddings = [[0.1, 0.2, ...], [0.3, 0.4, ...]]
    #   ids = store.add_documents(documents, embeddings: embeddings)
    #
    def add_documents(documents, embeddings: nil, namespace: nil)
      documents = Array(documents)

      # Generate embeddings if not provided
      embeddings ||= generate_embeddings(documents)

      # Prepare records
      records = documents.zip(embeddings).map.with_index do |(doc, embedding), idx|
        content = if doc.is_a?(Hash)
                    doc[:content] || doc["content"]
                  else
                    doc.to_s
                  end

        {
          id: generate_id(doc),
          content: content,
          embedding: embedding,
          metadata: extract_metadata(doc).merge(index: idx),
          namespace: namespace
        }
      end

      @adapter.add_records(records)
      records.map { |r| r[:id] }
    end

    # Search for similar documents
    def search(query, k: 5, namespace: nil, filter: nil, include_scores: false)
      # Generate query embedding
      query_embedding = generate_embedding(query)

      # Search in adapter
      results = @adapter.search(
        query_embedding,
        k: k,
        namespace: namespace,
        filter: filter
      )

      # Format results
      results.map do |result|
        output = {
          id: result[:id],
          content: result[:content],
          metadata: result[:metadata]
        }
        output[:score] = result[:score] if include_scores
        output
      end
    end

    # Update document
    def update_document(id, content: nil, metadata: nil, embedding: nil, namespace: nil)
      updates = {}
      updates[:content] = content if content
      updates[:metadata] = metadata if metadata
      updates[:embedding] = embedding || (content ? generate_embedding(content) : nil)

      @adapter.update_record(id, updates, namespace: namespace)
    end

    # Delete documents
    def delete_documents(ids: nil, filter: nil, namespace: nil)
      @adapter.delete_records(ids: ids, filter: filter, namespace: namespace)
    end

    # Get document by ID
    def get_document(id, namespace: nil)
      @adapter.get_record(id, namespace: namespace)
    end

    # List all namespaces
    def namespaces
      @adapter.list_namespaces
    end

    # Get store statistics
    def stats(namespace: nil)
      @adapter.stats(namespace: namespace)
    end

    # Clear all documents
    def clear(namespace: nil)
      @adapter.clear(namespace: namespace)
    end

    # Export store to file
    def export(path)
      data = {
        name: @name,
        dimensions: @dimensions,
        metadata: @metadata,
        records: @adapter.export_records
      }

      File.write(path, JSON.pretty_generate(data))
    end

    # Import store from file
    def import(path)
      data = RAAF::Utils.parse_json(File.read(path))

      @name = data[:name]
      @dimensions = data[:dimensions]
      @metadata = data[:metadata] || {}

      @adapter.import_records(data[:records])
    end

    private

    def generate_id(doc)
      content = if doc.is_a?(Hash)
                  doc[:content] || doc["content"]
                else
                  doc.to_s
                end
      Digest::SHA256.hexdigest(content)[0..15]
    end

    def extract_metadata(doc)
      return doc[:metadata] if doc.is_a?(Hash) && doc[:metadata]
      return doc["metadata"] if doc.is_a?(Hash) && doc["metadata"]

      {}
    end

    def generate_embeddings(documents)
      # This would normally call an embedding API
      # For now, return mock embeddings
      documents.map do |doc|
        content = if doc.is_a?(Hash)
                    doc[:content] || doc["content"]
                  else
                    doc.to_s
                  end
        generate_embedding(content)
      end
    end

    def generate_embedding(text)
      # Mock embedding generation - in production this would call OpenAI/other embedding API
      # Returns a vector of specified dimensions
      text_hash = Digest::SHA256.hexdigest(text.to_s).to_i(16)
      Array.new(@dimensions) { |i| Math.sin(text_hash * (i + 1)) * 0.1 }
    end
  end

  module Adapters
    # In-memory vector store adapter
    class InMemoryAdapter
      def initialize
        @store = {}
        @namespaces = {}
      end

      def initialize_store(name, dimensions, **options)
        @name = name
        @dimensions = dimensions
        @options = options
      end

      def add_records(records)
        records.each do |record|
          namespace = record[:namespace] || "default"
          @namespaces[namespace] ||= {}
          @namespaces[namespace][record[:id]] = record
        end
      end

      def search(query_embedding, k: 5, namespace: nil, filter: nil)
        namespace ||= "default"
        records = @namespaces[namespace] || {}

        # Filter records
        filtered = records.values
        filtered = filtered.select { |r| match_filter(r[:metadata], filter) } if filter

        # Calculate similarities
        results = filtered.map do |record|
          score = cosine_similarity(query_embedding, record[:embedding])
          record.merge(score: score)
        end

        # Sort by score and return top k
        results.sort_by { |r| -r[:score] }.first(k)
      end

      def update_record(id, updates, namespace: nil)
        namespace ||= "default"
        record = @namespaces[namespace]&.[](id)
        return false unless record

        record.merge!(updates)
        true
      end

      def delete_records(ids: nil, filter: nil, namespace: nil)
        namespaces = if namespace
                       [namespace]
                     else
                       @namespaces.keys
                     end

        count = 0
        namespaces.each do |ns|
          next unless @namespaces[ns]

          if ids
            ids.each do |id|
              count += 1 if @namespaces[ns].delete(id)
            end
          elsif filter
            @namespaces[ns].delete_if do |_, record|
              if match_filter(record[:metadata], filter)
                count += 1
                true
              else
                false
              end
            end
          end
        end

        count
      end

      def get_record(id, namespace: nil)
        namespace ||= "default"
        @namespaces[namespace]&.[](id)
      end

      def list_namespaces
        @namespaces.keys
      end

      def stats(namespace: nil)
        if namespace
          count = @namespaces[namespace]&.size || 0
          { namespace => count }
        else
          @namespaces.transform_values(&:size)
        end
      end

      def clear(namespace: nil)
        if namespace
          @namespaces.delete(namespace)
        else
          @namespaces.clear
        end
      end

      def export_records
        @namespaces
      end

      def import_records(records)
        @namespaces = records
      end

      private

      def cosine_similarity(vec1, vec2)
        return 0.0 if vec1.nil? || vec2.nil?

        dot_product = vec1.zip(vec2).map { |a, b| a * b }.sum
        norm1 = Math.sqrt(vec1.map { |x| x**2 }.sum)
        norm2 = Math.sqrt(vec2.map { |x| x**2 }.sum)

        return 0.0 if norm1 == 0 || norm2 == 0

        dot_product / (norm1 * norm2)
      end

      def match_filter(metadata, filter)
        filter.all? do |key, value|
          case value
          when Regexp
            metadata[key]&.match?(value)
          when Array
            value.include?(metadata[key])
          when Hash
            # Support nested filters
            match_filter(metadata[key] || {}, value)
          else
            metadata[key] == value
          end
        end
      end
    end

    # PostgreSQL + pgvector adapter
    class PgVectorAdapter
      def initialize(connection_string: nil, pool_size: 5)
        @connection_string = connection_string || ENV.fetch("DATABASE_URL", nil)
        @pool_size = pool_size

        begin
          require "pg"
          require "pgvector"
        rescue LoadError
          raise "pg and pgvector gems are required for PgVectorAdapter"
        end

        setup_connection_pool
      end

      def initialize_store(name, dimensions, **options)
        @table_name = "vector_store_#{name}".downcase.gsub(/[^a-z0-9_]/, "_")
        @dimensions = dimensions

        create_table_if_not_exists
        create_indexes
      end

      def add_records(records)
        with_connection do |conn|
          records.each do |record|
            conn.exec_params(
              "INSERT INTO #{@table_name} (id, content, embedding, metadata, namespace)
               VALUES ($1, $2, $3, $4, $5)
               ON CONFLICT (id, namespace) DO UPDATE
               SET content = $2, embedding = $3, metadata = $4",
              [
                record[:id],
                record[:content],
                Pgvector.encode(record[:embedding]),
                record[:metadata].to_json,
                record[:namespace] || "default"
              ]
            )
          end
        end
      end

      def search(query_embedding, k: 5, namespace: nil, filter: nil)
        query = build_search_query(namespace, filter)

        with_connection do |conn|
          results = conn.exec_params(
            "#{query} ORDER BY embedding <-> $1 LIMIT $2",
            [Pgvector.encode(query_embedding), k]
          )

          results.map do |row|
            {
              id: row["id"],
              content: row["content"],
              metadata: RAAF::Utils.parse_json(row["metadata"]),
              score: row["score"]&.to_f || calculate_similarity(query_embedding, Pgvector.decode(row["embedding"]))
            }
          end
        end
      end

      def update_record(id, updates, namespace: nil)
        namespace ||= "default"

        set_clauses = []
        values = []

        if updates[:content]
          set_clauses << "content = $#{values.length + 1}"
          values << updates[:content]
        end

        if updates[:embedding]
          set_clauses << "embedding = $#{values.length + 1}"
          values << Pgvector.encode(updates[:embedding])
        end

        if updates[:metadata]
          set_clauses << "metadata = $#{values.length + 1}"
          values << updates[:metadata].to_json
        end

        return false if set_clauses.empty?

        values.push(id, namespace)

        with_connection do |conn|
          result = conn.exec_params(
            "UPDATE #{@table_name} SET #{set_clauses.join(", ")}
             WHERE id = $#{values.length - 1} AND namespace = $#{values.length}",
            values
          )

          result.cmd_tuples > 0
        end
      end

      def delete_records(ids: nil, filter: nil, namespace: nil)
        conditions = []
        params = []

        if ids
          conditions << "id = ANY($#{params.length + 1})"
          params << ids
        end

        if namespace
          conditions << "namespace = $#{params.length + 1}"
          params << namespace
        end

        if filter
          filter_sql, filter_params = build_filter_sql(filter, params.length)
          conditions << filter_sql
          params.concat(filter_params)
        end

        return 0 if conditions.empty?

        with_connection do |conn|
          result = conn.exec_params(
            "DELETE FROM #{@table_name} WHERE #{conditions.join(" AND ")}",
            params
          )

          result.cmd_tuples
        end
      end

      def get_record(id, namespace: nil)
        namespace ||= "default"

        with_connection do |conn|
          result = conn.exec_params(
            "SELECT * FROM #{@table_name} WHERE id = $1 AND namespace = $2",
            [id, namespace]
          )

          return nil if result.ntuples == 0

          row = result[0]
          {
            id: row["id"],
            content: row["content"],
            embedding: Pgvector.decode(row["embedding"]),
            metadata: RAAF::Utils.parse_json(row["metadata"]),
            namespace: row["namespace"]
          }
        end
      end

      def list_namespaces
        with_connection do |conn|
          result = conn.exec("SELECT DISTINCT namespace FROM #{@table_name}")
          result.map { |row| row["namespace"] }
        end
      end

      def stats(namespace: nil)
        query = "SELECT namespace, COUNT(*) as count FROM #{@table_name}"
        query += " WHERE namespace = $1" if namespace
        query += " GROUP BY namespace"

        with_connection do |conn|
          result = if namespace
                     conn.exec_params(query, [namespace])
                   else
                     conn.exec(query)
                   end

          result.to_h { |row| [row["namespace"], row["count"].to_i] }
        end
      end

      def clear(namespace: nil)
        with_connection do |conn|
          if namespace
            conn.exec_params("DELETE FROM #{@table_name} WHERE namespace = $1", [namespace])
          else
            conn.exec("TRUNCATE #{@table_name}")
          end
        end
      end

      def export_records
        records = {}

        with_connection do |conn|
          result = conn.exec("SELECT * FROM #{@table_name}")

          result.each do |row|
            namespace = row["namespace"]
            records[namespace] ||= {}

            records[namespace][row["id"]] = {
              id: row["id"],
              content: row["content"],
              embedding: Pgvector.decode(row["embedding"]),
              metadata: RAAF::Utils.parse_json(row["metadata"]),
              namespace: namespace
            }
          end
        end

        records
      end

      def import_records(records)
        clear

        all_records = []
        records.each_value do |namespace_records|
          namespace_records.each_value do |record|
            all_records << record
          end
        end

        add_records(all_records)
      end

      private

      def setup_connection_pool
        # In production, use a proper connection pool
        @connections = []
      end

      def with_connection
        conn = PG.connect(@connection_string)
        yield conn
      ensure
        conn&.close
      end

      def create_table_if_not_exists
        with_connection do |conn|
          conn.exec("CREATE EXTENSION IF NOT EXISTS vector")

          conn.exec(<<~SQL)
            CREATE TABLE IF NOT EXISTS #{@table_name} (
              id TEXT NOT NULL,
              namespace TEXT NOT NULL DEFAULT 'default',
              content TEXT NOT NULL,
              embedding vector(#{@dimensions}),
              metadata JSONB DEFAULT '{}',
              created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
              updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
              PRIMARY KEY (id, namespace)
            )
          SQL
        end
      end

      def create_indexes
        with_connection do |conn|
          # Vector similarity index
          conn.exec(<<~SQL)
            CREATE INDEX IF NOT EXISTS #{@table_name}_embedding_idx#{" "}
            ON #{@table_name} USING ivfflat (embedding vector_cosine_ops)
            WITH (lists = 100)
          SQL

          # Metadata index for filtering
          conn.exec(<<~SQL)
            CREATE INDEX IF NOT EXISTS #{@table_name}_metadata_idx#{" "}
            ON #{@table_name} USING gin (metadata)
          SQL

          # Namespace index
          conn.exec(<<~SQL)
            CREATE INDEX IF NOT EXISTS #{@table_name}_namespace_idx#{" "}
            ON #{@table_name} (namespace)
          SQL
        end
      end

      def build_search_query(namespace, filter)
        conditions = []

        conditions << "namespace = '#{namespace}'" if namespace

        filter&.each do |key, value|
          conditions << "metadata->>'#{key}' = '#{value}'"
        end

        base_query = "SELECT *, 1 - (embedding <-> $1) as score FROM #{@table_name}"
        base_query += " WHERE #{conditions.join(" AND ")}" unless conditions.empty?

        base_query
      end

      def build_filter_sql(filter, param_offset)
        conditions = []
        params = []

        filter.each do |key, value|
          param_num = param_offset + params.length + 1

          case value
          when Array
            conditions << "metadata->>'#{key}' = ANY($#{param_num})"
            params << value
          when Regexp
            conditions << "metadata->>'#{key}' ~ $#{param_num}"
            params << value.source
          else
            conditions << "metadata->>'#{key}' = $#{param_num}"
            params << value.to_s
          end
        end

        [conditions.join(" AND "), params]
      end

      def calculate_similarity(vec1, vec2)
        # Cosine similarity
        dot_product = vec1.zip(vec2).map { |a, b| a * b }.sum
        norm1 = Math.sqrt(vec1.map { |x| x**2 }.sum)
        norm2 = Math.sqrt(vec2.map { |x| x**2 }.sum)

        return 0.0 if norm1 == 0 || norm2 == 0

        dot_product / (norm1 * norm2)
      end
    end

    # Additional adapters can be added here:
    # - PineconeAdapter
    # - WeaviateAdapter
    # - ChromaAdapter
    # - QdrantAdapter
  end
end
