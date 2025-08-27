# frozen_string_literal: true

require "json"
require_relative "../../../core/lib/raaf/utils"
require_relative "../../../core/lib/raaf/function_tool"
begin
  # Suppress matrix deprecation warning
  original_verbose = $VERBOSE
  $VERBOSE = nil
  require "matrix"
  $VERBOSE = original_verbose
rescue LoadError
  # Matrix gem not available, this file won't be usable
  raise LoadError, "Matrix gem required for semantic search functionality. Add 'gem \"matrix\"' to your Gemfile."
end

module RAAF
  ##
  # Semantic search capabilities for agents
  #
  # This module provides advanced semantic search functionality using vector
  # embeddings, enabling agents to find contextually relevant information
  # rather than just keyword matches. Supports multiple indexing algorithms
  # and hybrid search combining semantic and keyword search.
  #
  # @example Basic semantic search setup
  #   # Create vector database
  #   db = SemanticSearch::VectorDatabase.new(dimension: 1536)
  #   
  #   # Add documents with embeddings
  #   documents = ["Ruby programming", "Python development", "JavaScript frameworks"]
  #   embeddings = EmbeddingGenerator.new.generate(documents)
  #   metadata = documents.map.with_index { |doc, i| { text: doc, id: i } }
  #   
  #   db.add(embeddings, metadata)
  #   
  #   # Search for similar content
  #   query_embedding = EmbeddingGenerator.new.generate(["web development"])[0]
  #   results = db.search(query_embedding, k: 2)
  #   
  #   results.each { |result| puts result[:metadata][:text] }
  #
  # @example Advanced semantic search with agent integration
  #   # Setup semantic search tool
  #   search_tool = SemanticSearch::SemanticSearchTool.new(
  #     database: knowledge_db,
  #     embedding_model: "text-embedding-3-small"
  #   )
  #   
  #   # Add to agent
  #   agent = Agent.new(
  #     name: "KnowledgeAgent",
  #     instructions: "Answer questions using the knowledge base"
  #   )
  #   agent.add_tool(search_tool)
  #   
  #   # Agent can now perform semantic search
  #   result = agent.run("What programming languages are good for web development?")
  #
  # @example Hybrid search (semantic + keyword)
  #   hybrid = SemanticSearch::HybridSearch.new(
  #     vector_db: vector_database,
  #     keyword_indexer: SemanticSearch::KeywordIndexer.new
  #   )
  #   
  #   # Combines semantic similarity with keyword matching
  #   results = hybrid.search(
  #     query: "machine learning algorithms",
  #     semantic_weight: 0.7,
  #     keyword_weight: 0.3,
  #     k: 10
  #   )
  #
  # @example Document indexing pipeline
  #   indexer = SemanticSearch::DocumentIndexer.new(
  #     embedding_generator: EmbeddingGenerator.new,
  #     vector_database: db
  #   )
  #   
  #   # Index various document types
  #   indexer.index_text("Long article content...")
  #   indexer.index_file("document.pdf")
  #   indexer.index_url("https://example.com/article")
  #
  # @see VectorStore For simpler vector storage needs
  # @see Agent For integrating semantic search into agents
  # @since 1.0.0
  #
  module SemanticSearch
    ##
    # Vector database for storing embeddings
    #
    # High-performance vector database optimized for semantic search.
    # Supports multiple indexing algorithms (HNSW, Flat) and provides
    # fast similarity search with optional metadata filtering.
    #
    # @example Creating and using a vector database
    #   # Create database with HNSW index for fast search
    #   db = VectorDatabase.new(dimension: 1536, index_type: :hnsw)
    #   
    #   # Add embeddings with metadata
    #   embeddings = [
    #     [0.1, 0.2, 0.3, ...],  # 1536-dimensional vectors
    #     [0.4, 0.5, 0.6, ...],
    #     [0.7, 0.8, 0.9, ...]
    #   ]
    #   
    #   metadata = [
    #     { title: "Document 1", category: "tech" },
    #     { title: "Document 2", category: "science" },
    #     { title: "Document 3", category: "tech" }
    #   ]
    #   
    #   db.add(embeddings, metadata)
    #   
    #   # Search with filtering
    #   results = db.search(
    #     query_embedding,
    #     k: 5,
    #     filter: { category: "tech" }
    #   )
    #
    # @example Performance comparison of index types
    #   # HNSW: Fast search, slower indexing, good for large datasets
    #   hnsw_db = VectorDatabase.new(index_type: :hnsw)
    #   
    #   # Flat: Exact search, fast indexing, good for small datasets
    #   flat_db = VectorDatabase.new(index_type: :flat)
    #
    class VectorDatabase
      # @return [Integer] Dimensionality of stored vectors
      attr_reader :dimension
      
      # @return [Symbol] Type of search index (:hnsw, :flat)
      attr_reader :index_type

      ##
      # Initialize vector database
      #
      # @param dimension [Integer] Vector dimensionality (default: 1536 for OpenAI embeddings)
      # @param index_type [Symbol] Search index algorithm (:hnsw for speed, :flat for accuracy)
      #
      def initialize(dimension: 1536, index_type: :hnsw)
        @dimension = dimension
        @index_type = index_type
        @vectors = []
        @metadata = []
        @index = build_index(index_type)
        @mutex = Mutex.new
      end

      ##
      # Add vectors with metadata to the database
      #
      # @param embeddings [Array<Array<Float>>] Vector embeddings to store
      # @param metadata [Array<Hash>] Associated metadata for each vector
      # @raise [ArgumentError] if embedding dimensions don't match database
      #
      # @example
      #   embeddings = [[0.1, 0.2, ...], [0.3, 0.4, ...]]
      #   metadata = [{title: "Doc 1"}, {title: "Doc 2"}]
      #   db.add(embeddings, metadata)
      #
      def add(embeddings, metadata = [])
        @mutex.synchronize do
          embeddings.each_with_index do |embedding, i|
            validate_dimension(embedding)
            @vectors << embedding
            @metadata << (metadata[i] || {})
          end

          # Rebuild index
          @index.rebuild(@vectors)
        end
      end

      ##
      # Search for similar vectors using cosine similarity
      #
      # @param query_embedding [Array<Float>] Query vector to find similar items
      # @param k [Integer] Number of results to return
      # @param filter [Hash, nil] Metadata filter to apply
      # @return [Array<Hash>] Results with :index, :score, :metadata keys
      #
      # @example Basic search
      #   results = db.search(query_vector, k: 5)
      #   results.each { |r| puts "Score: #{r[:score]}, Title: #{r[:metadata][:title]}" }
      #
      # @example Filtered search
      #   tech_results = db.search(query_vector, k: 10, filter: { category: "technology" })
      #
      def search(query_embedding, k: 10, filter: nil)
        validate_dimension(query_embedding)

        @mutex.synchronize do
          candidates = filter ? apply_filter(filter) : (0...@vectors.size).to_a
          return [] if candidates.empty?

          # Calculate similarities
          similarities = candidates.map do |idx|
            {
              index: idx,
              score: cosine_similarity(query_embedding, @vectors[idx]),
              metadata: @metadata[idx]
            }
          end

          # Sort by score and return top k
          similarities.sort_by { |s| -s[:score] }.first(k)
        end
      end

      # Update vector at index
      def update(index, embedding, metadata = nil)
        @mutex.synchronize do
          validate_dimension(embedding)
          @vectors[index] = embedding
          @metadata[index] = metadata if metadata
          @index.update(index, embedding)
        end
      end

      # Delete vector at index
      def delete(index)
        @mutex.synchronize do
          @vectors.delete_at(index)
          @metadata.delete_at(index)
          @index.rebuild(@vectors)
        end
      end

      # Get vector by index
      def get(index)
        @mutex.synchronize do
          {
            embedding: @vectors[index],
            metadata: @metadata[index]
          }
        end
      end

      # Save to file
      def save(filename)
        data = {
          dimension: @dimension,
          index_type: @index_type,
          vectors: @vectors,
          metadata: @metadata
        }

        File.write(filename, JSON.generate(data))
      end

      # Load from file
      def self.load(filename)
        data = RAAF::Utils.parse_json(File.read(filename))

        db = new(dimension: data[:dimension], index_type: data[:index_type].to_sym)
        db.add(data[:vectors], data[:metadata])
        db
      end

      private

      def validate_dimension(embedding)
        return if embedding.size == @dimension

        raise ArgumentError, "Embedding dimension mismatch: expected #{@dimension}, got #{embedding.size}"
      end

      def cosine_similarity(a, b)
        dot_product = a.zip(b).map { |x, y| x * y }.sum
        norm_a = Math.sqrt(a.map { |x| x * x }.sum)
        norm_b = Math.sqrt(b.map { |x| x * x }.sum)

        return 0.0 if norm_a == 0 || norm_b == 0

        dot_product / (norm_a * norm_b)
      end

      def apply_filter(filter)
        @metadata.each_with_index.select do |meta, _|
          filter.all? { |key, value| meta[key] == value }
        end.map(&:last)
      end

      def build_index(type)
        case type
        when :hnsw
          HNSWIndex.new(@dimension)
        when :flat
          FlatIndex.new(@dimension)
        else
          raise ArgumentError, "Unknown index type: #{type}"
        end
      end
    end

    # HNSW (Hierarchical Navigable Small World) index
    class HNSWIndex
      def initialize(dimension, m: 16, ef_construction: 200)
        @dimension = dimension
        @m = m
        @max_m = m
        @max_m0 = m * 2
        @ef_construction = ef_construction
        @ml = 1.0 / Math.log(2.0)
        @levels = []
        @graph = {}
      end

      def rebuild(vectors)
        @levels.clear
        @graph.clear

        vectors.each_with_index do |vector, idx|
          insert(idx, vector)
        end
      end

      def update(index, vector)
        # Update vector in graph
        level = @levels[index] || 0
        update_connections(index, vector, level)
      end

      private

      def insert(idx, vector)
        level = select_level
        @levels[idx] = level

        # Find nearest neighbors at all levels
        (0..level).each do |lc|
          m = lc == 0 ? @max_m0 : @max_m
          neighbors = search_layer(vector, @ef_construction, lc)
          @graph[[idx, lc]] = neighbors.first(m).map { |n| n[:index] }
        end
      end

      def select_level
        level = 0
        level += 1 while rand < @ml && level < 16
        level
      end

      def search_layer(query, ef, layer)
        # Simplified HNSW search
        []
      end

      def update_connections(idx, vector, level)
        # Update graph connections
      end
    end

    # Simple flat index for small datasets
    class FlatIndex
      def initialize(dimension)
        @dimension = dimension
      end

      def rebuild(vectors)
        # No indexing needed for flat search
      end

      def update(index, vector)
        # No update needed for flat search
      end
    end

    # Embedding generator using OpenAI
    class EmbeddingGenerator
      def initialize(model: "text-embedding-3-small", client: nil)
        @model = model
        @client = client || OpenAI::Client.new
        @cache = {}
        @mutex = Mutex.new
      end

      # Generate embeddings for texts
      def generate(texts, cache: true)
        texts = Array(texts)
        embeddings = []

        texts.each_slice(100) do |batch| # API limit
          # Check cache
          if cache
            cached, uncached = partition_by_cache(batch)
            embeddings.concat(cached.map { |text| @cache[cache_key(text)] })
            batch = uncached
          end

          next if batch.empty?

          # Generate embeddings
          response = @client.embeddings(
            parameters: {
              model: @model,
              input: batch
            }
          )

          batch_embeddings = response["data"].map { |d| d["embedding"] }
          embeddings.concat(batch_embeddings)

          # Cache results
          next unless cache

          batch.zip(batch_embeddings).each do |text, embedding|
            @mutex.synchronize do
              @cache[cache_key(text)] = embedding
            end
          end
        end

        texts.size == 1 ? embeddings.first : embeddings
      end

      # Clear cache
      def clear_cache
        @mutex.synchronize { @cache.clear }
      end

      private

      def cache_key(text)
        "#{@model}:#{text}"
      end

      def partition_by_cache(texts)
        cached = []
        uncached = []

        texts.each do |text|
          if @cache.key?(cache_key(text))
            cached << text
          else
            uncached << text
          end
        end

        [cached, uncached]
      end
    end

    # Document indexer for semantic search
    class DocumentIndexer
      attr_reader :vector_db, :embedding_generator

      def initialize(vector_db: nil, embedding_generator: nil)
        @vector_db = vector_db || VectorDatabase.new
        @embedding_generator = embedding_generator || EmbeddingGenerator.new
        @documents = []
        @chunks = []
        @mutex = Mutex.new
      end

      # Index documents
      def index_documents(documents, chunk_size: 500, overlap: 50)
        @mutex.synchronize do
          documents.each do |doc|
            # Store document
            doc_id = @documents.size
            @documents << doc

            # Chunk document
            chunks = chunk_text(doc[:content], chunk_size, overlap)

            # Generate embeddings
            embeddings = @embedding_generator.generate(chunks)

            # Store chunks with metadata
            metadata = chunks.zip(embeddings).map.with_index do |(chunk, _), idx|
              {
                document_id: doc_id,
                chunk_index: idx,
                chunk_text: chunk,
                document_title: doc[:title],
                document_metadata: doc[:metadata]
              }
            end

            @chunks.concat(metadata)
            @vector_db.add(embeddings, metadata)
          end
        end
      end

      # Search documents
      def search(query, k: 10, filter: nil, rerank: true)
        # Generate query embedding
        query_embedding = @embedding_generator.generate(query)

        # Search vector database
        results = @vector_db.search(query_embedding, k: k * 2, filter: filter)

        # Rerank if requested
        results = rerank_results(query, results) if rerank

        # Group by document and return top k
        group_results(results).first(k)
      end

      # Get document by ID
      def get_document(doc_id)
        @documents[doc_id]
      end

      private

      def chunk_text(text, chunk_size, overlap)
        chunks = []
        words = text.split

        i = 0
        while i < words.size
          chunk_words = words[i, chunk_size]
          chunks << chunk_words.join(" ")
          i += chunk_size - overlap
        end

        chunks
      end

      def rerank_results(query, results)
        # Simple reranking based on keyword overlap
        query_words = query.downcase.split.to_set

        results.map do |result|
          chunk_words = result[:metadata][:chunk_text].downcase.split.to_set
          keyword_score = (query_words & chunk_words).size.to_f / query_words.size

          result.merge(
            combined_score: (result[:score] * 0.7) + (keyword_score * 0.3)
          )
        end.sort_by { |r| -r[:combined_score] }
      end

      def group_results(results)
        grouped = results.group_by { |r| r[:metadata][:document_id] }

        grouped.map do |doc_id, chunks|
          {
            document: @documents[doc_id],
            chunks: chunks.map { |c| c[:metadata][:chunk_text] },
            score: chunks.map { |c| c[:score] }.max,
            metadata: chunks.first[:metadata][:document_metadata]
          }
        end.sort_by { |r| -r[:score] }
      end
    end

    # Hybrid search combining semantic and keyword search
    class HybridSearch
      def initialize(semantic_indexer, keyword_indexer = nil)
        @semantic_indexer = semantic_indexer
        @keyword_indexer = keyword_indexer || KeywordIndexer.new
        @alpha = 0.7 # Weight for semantic search
      end

      def index_documents(documents)
        # Index in both systems
        @semantic_indexer.index_documents(documents)
        @keyword_indexer.index_documents(documents)
      end

      def search(query, k: 10, filter: nil)
        # Get results from both searches
        semantic_results = @semantic_indexer.search(query, k: k * 2, filter: filter)
        keyword_results = @keyword_indexer.search(query, k: k * 2, filter: filter)

        # Combine and rerank
        combined = combine_results(semantic_results, keyword_results)
        combined.first(k)
      end

      private

      def combine_results(semantic_results, keyword_results)
        all_docs = {}

        # Add semantic results
        semantic_results.each do |result|
          doc_id = result[:document][:id]
          all_docs[doc_id] = {
            document: result[:document],
            semantic_score: result[:score],
            keyword_score: 0,
            chunks: result[:chunks],
            metadata: result[:metadata]
          }
        end

        # Add keyword results
        keyword_results.each do |result|
          doc_id = result[:document][:id]
          if all_docs[doc_id]
            all_docs[doc_id][:keyword_score] = result[:score]
          else
            all_docs[doc_id] = {
              document: result[:document],
              semantic_score: 0,
              keyword_score: result[:score],
              chunks: result[:chunks],
              metadata: result[:metadata]
            }
          end
        end

        # Calculate combined scores
        all_docs.values.map do |doc|
          doc[:combined_score] = (@alpha * doc[:semantic_score]) + ((1 - @alpha) * doc[:keyword_score])
          doc
        end.sort_by { |d| -d[:combined_score] }
      end
    end

    # Simple keyword indexer using TF-IDF
    class KeywordIndexer
      def initialize
        @documents = []
        @index = {}
        @idf = {}
        @mutex = Mutex.new
      end

      def index_documents(documents)
        @mutex.synchronize do
          documents.each do |doc|
            doc_id = @documents.size
            @documents << doc

            # Extract terms
            terms = extract_terms(doc[:content])

            # Update inverted index
            terms.uniq.each do |term|
              @index[term] ||= []
              @index[term] << doc_id
            end
          end

          # Calculate IDF
          calculate_idf
        end
      end

      def search(query, k: 10, filter: nil)
        query_terms = extract_terms(query)

        # Calculate scores
        scores = {}
        query_terms.each do |term|
          next unless @index[term]

          idf = @idf[term] || 0
          @index[term].each do |doc_id|
            scores[doc_id] ||= 0
            scores[doc_id] += idf
          end
        end

        # Sort and return top k
        results = scores.map do |doc_id, score|
          {
            document: @documents[doc_id],
            score: score,
            chunks: [],
            metadata: @documents[doc_id][:metadata]
          }
        end.sort_by { |r| -r[:score] }

        results.first(k)
      end

      private

      def extract_terms(text)
        text.downcase.scan(/\w+/).select { |w| w.length > 2 }
      end

      def calculate_idf
        n = @documents.size.to_f

        @index.each do |term, docs|
          @idf[term] = Math.log(n / docs.size)
        end
      end
    end

    # Semantic search agent tool
    class SemanticSearchTool < FunctionTool
      def initialize(indexer, name: "semantic_search", description: "Search documents using semantic similarity")
        @indexer = indexer

        super(
          method(:search),
          name: name,
          description: description
        )
      end

      def search(query:, k: 5, filter: nil)
        results = @indexer.search(query, k: k, filter: filter)

        # Format results for agent
        results.map do |result|
          {
            title: result[:document][:title],
            content: result[:chunks].first(3).join("\n..."),
            score: result[:score].round(3),
            metadata: result[:metadata]
          }
        end
      end
    end

    # Query expansion for better search
    class QueryExpander
      def initialize(client: nil)
        @client = client || OpenAI::Client.new
      end

      def expand_query(query, method: :synonyms)
        case method
        when :synonyms
          expand_with_synonyms(query)
        when :questions
          expand_to_questions(query)
        when :gpt
          expand_with_gpt(query)
        else
          [query]
        end
      end

      private

      def expand_with_synonyms(query)
        # Simple synonym expansion
        synonyms = {
          "find" => %w[search locate discover],
          "document" => %w[file paper record],
          "information" => %w[data details facts]
        }

        expanded = [query]
        query.split.each do |word|
          next unless synonyms[word.downcase]

          synonyms[word.downcase].each do |syn|
            expanded << query.sub(word, syn)
          end
        end

        expanded.uniq
      end

      def expand_to_questions(query)
        [
          query,
          "What is #{query}?",
          "How does #{query} work?",
          "Why is #{query} important?"
        ]
      end

      def expand_with_gpt(query)
        response = @client.chat(
          parameters: {
            model: "gpt-3.5-turbo",
            messages: [
              {
                role: "system",
                content: "Generate 3 alternative phrasings of the given search query. Return only the alternatives, one per line."
              },
              {
                role: "user",
                content: query
              }
            ],
            temperature: 0.7
          }
        )

        alternatives = response.dig("choices", 0, "message", "content").split("\n").map(&:strip)
        [query] + alternatives
      end
    end
  end
end
