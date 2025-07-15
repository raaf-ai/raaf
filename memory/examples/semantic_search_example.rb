#!/usr/bin/env ruby
# frozen_string_literal: true

# This example demonstrates semantic search capabilities in OpenAI Agents Ruby.
# Semantic search goes beyond keyword matching to understand the meaning and context
# of queries and documents. Using vector embeddings, it finds conceptually similar
# content even when exact words don't match. This is essential for building intelligent
# search systems, knowledge bases, and context-aware AI assistants. The example covers
# vector databases, embedding generation, document indexing, hybrid search, and
# integration with AI agents.

require_relative "../lib/openai_agents"

# Semantic search modules (these will be implemented in future versions)
begin
  require_relative "../lib/openai_agents/semantic_search"
rescue LoadError
  puts "Note: Semantic search modules are not yet implemented. This example shows planned functionality."
  puts "The code demonstrates the API and usage patterns for future semantic search features.\n"
end

# Set API key from environment for embedding generation
# Real embeddings require OpenAI API access
begin
  OpenAI.configure do |config|
    config.access_token = ENV.fetch("OPENAI_API_KEY", nil)
  end
rescue NameError
  # OpenAI gem not loaded, using mocks
end

puts "=== Semantic Search Example ==="
puts

# ============================================================================
# EXAMPLE 1: BASIC VECTOR DATABASE
# ============================================================================
# Vector databases are the foundation of semantic search. They store high-dimensional
# vector representations (embeddings) of text that capture semantic meaning. Unlike
# traditional databases that match exact keywords, vector databases find items based
# on conceptual similarity using distance metrics like cosine similarity.

puts "Example 1: Basic Vector Database"
puts "-" * 50

# Create vector database with specified dimensionality
# In production, dimension matches your embedding model (e.g., 1536 for OpenAI)
# Using small dimension here for demonstration clarity
if defined?(OpenAIAgents::SemanticSearch::VectorDatabase)
  vector_db = OpenAIAgents::SemanticSearch::VectorDatabase.new(dimension: 5)
else
  # Mock implementation for demonstration
  class VectorDatabase
    def initialize(dimension:)
      @dimension = dimension
      @vectors = []
      @metadata = []
    end
    
    def add(vectors, metadata)
      @vectors.concat(vectors)
      @metadata.concat(metadata)
    end
    
    def search(query, k:, filter: nil)
      # Simple cosine similarity search
      scores = @vectors.map do |vec|
        dot = vec.zip(query).map { |a, b| a * b }.sum
        norm_a = Math.sqrt(vec.map { |x| x**2 }.sum)
        norm_b = Math.sqrt(query.map { |x| x**2 }.sum)
        dot / (norm_a * norm_b)
      end
      
      results = scores.each_with_index.map { |score, i| 
        { score: score, vector: @vectors[i], metadata: @metadata[i] }
      }
      
      # Apply filter if provided
      if filter
        results = results.select do |r|
          filter.all? { |k, v| r[:metadata][k] == v }
        end
      end
      
      results.sort_by { |r| -r[:score] }.first(k)
    end
    
    def save(path)
      require 'json'
      File.write(path, { vectors: @vectors, metadata: @metadata }.to_json)
    end
    
    def self.load(path)
      require 'json'
      data = JSON.parse(File.read(path), symbolize_names: true)
      db = new(dimension: data[:vectors].first.size)
      db.add(data[:vectors], data[:metadata])
      db
    end
  end
  
  vector_db = VectorDatabase.new(dimension: 5)
end

# Define sample vectors representing document embeddings
# In real applications, these would be generated from text using embedding models
# Each vector represents semantic features of the document
vectors = [
  [0.1, 0.2, 0.3, 0.4, 0.5],  # Similar to programming topics
  [0.2, 0.3, 0.4, 0.5, 0.6],  # Also programming, slightly different
  [0.9, 0.8, 0.7, 0.6, 0.5],  # Different pattern - AI/ML topics
  [0.1, 0.1, 0.1, 0.9, 0.9]   # Data science pattern
]

# Metadata provides human-readable context and filtering capabilities
# This allows combining semantic similarity with structured queries
metadata = [
  { title: "Introduction to Ruby", category: "programming" },
  { title: "Advanced Ruby Patterns", category: "programming" },
  { title: "Machine Learning Basics", category: "ai" },
  { title: "Data Science with Python", category: "data" }
]

# Index vectors with their metadata
# This creates the searchable knowledge base
vector_db.add(vectors, metadata)

# Perform similarity search with a query vector
# The query vector represents the semantic meaning of a search query
# k parameter limits results to top 3 most similar
query = [0.15, 0.25, 0.35, 0.45, 0.55]  # Similar to programming topics
results = vector_db.search(query, k: 3)

puts "Query vector: #{query}"
puts "\nTop 3 similar vectors:"
results.each_with_index do |result, i|
  puts "  #{i + 1}. #{result[:metadata][:title]} (score: #{result[:score].round(3)})"
end
puts

# ============================================================================
# EXAMPLE 2: EMBEDDING GENERATION
# ============================================================================
# Embeddings are dense vector representations of text that capture semantic meaning.
# Modern embedding models like OpenAI's text-embedding-3 convert text into vectors
# where similar meanings result in vectors close together in high-dimensional space.
# This enables semantic search, clustering, and similarity comparisons.

puts "Example 2: Embedding Generation"
puts "-" * 50

# Mock embedding generator simulates the OpenAI embedding API
# Real implementation would call OpenAI's text-embedding endpoint
# Cache parameter enables storing computed embeddings for efficiency
class MockEmbeddingGenerator
  def generate(texts, cache: true)
    # In production, this would:
    # 1. Check cache for existing embeddings
    # 2. Call OpenAI API for missing embeddings
    # 3. Store new embeddings in cache
    # 4. Return normalized vectors
    Array(texts).map do |text|
      # Simplified: convert characters to floats
      # Real embeddings capture semantic relationships
      text.chars.map { |c| c.ord / 255.0 }.first(5).fill(0.5, 5)
    end
  end
end

embedding_gen = MockEmbeddingGenerator.new

texts = [
  "Ruby is a dynamic programming language",
  "Python is great for data science",
  "JavaScript runs in the browser"
]

puts "Generating embeddings for:"
texts.each { |t| puts "  - #{t}" }

embeddings = embedding_gen.generate(texts)
puts "\nGenerated #{embeddings.size} embeddings"
puts

# ============================================================================
# EXAMPLE 3: DOCUMENT INDEXING
# ============================================================================
# Document indexing prepares text for semantic search by chunking, embedding,
# and storing documents. Proper indexing is crucial for search quality. It involves
# splitting documents into semantically meaningful chunks, generating embeddings,
# and maintaining relationships between chunks and source documents.

puts "Example 3: Document Indexing"
puts "-" * 50

# Create document indexer combining vector storage and embedding generation
# The indexer handles the complete pipeline from raw text to searchable vectors
if defined?(OpenAIAgents::SemanticSearch::DocumentIndexer)
  indexer = OpenAIAgents::SemanticSearch::DocumentIndexer.new(
    vector_db: OpenAIAgents::SemanticSearch::VectorDatabase.new(dimension: 5),
    embedding_generator: MockEmbeddingGenerator.new
  )
else
  # Mock indexer for demonstration
  class DocumentIndexer
    def initialize(vector_db:, embedding_generator:)
      @vector_db = vector_db
      @embedding_generator = embedding_generator
      @documents = {}
    end
    
    def index_documents(documents, chunk_size: 50, overlap: 10)
      documents.each do |doc|
        # Chunk document into overlapping segments
        chunks = chunk_text(doc[:content], chunk_size, overlap)
        
        # Generate embeddings for chunks
        embeddings = @embedding_generator.generate(chunks)
        
        # Store with metadata
        metadata = chunks.map.with_index do |chunk, i|
          {
            document_id: doc[:id],
            title: doc[:title],
            chunk_index: i,
            chunk_text: chunk,
            **doc[:metadata]
          }
        end
        
        @vector_db.add(embeddings, metadata)
        @documents[doc[:id]] = doc
      end
    end
    
    def search(query, k: 5)
      # Generate query embedding
      query_embedding = @embedding_generator.generate([query]).first
      
      # Search vector database
      results = @vector_db.search(query_embedding, k: k)
      
      # Enrich with document data
      results.map do |result|
        doc_id = result[:metadata][:document_id]
        {
          document: @documents[doc_id],
          chunks: [[result[:metadata][:chunk_text], result[:metadata][:chunk_index]]],
          score: result[:score]
        }
      end
    end
    
    private
    
    def chunk_text(text, size, overlap)
      words = text.split
      chunks = []
      i = 0
      while i < words.length
        chunk = words[i...(i + size)].join(' ')
        chunks << chunk
        i += size - overlap
      end
      chunks
    end
  end
  
  indexer = DocumentIndexer.new(
    vector_db: vector_db,
    embedding_generator: MockEmbeddingGenerator.new
  )
end

# Sample documents representing a knowledge base
# Each document has structured metadata and unstructured content
# The indexer will process these into searchable chunks
documents = [
  {
    id: "doc1",
    title: "Ruby Programming Guide",
    content: "Ruby is a dynamic, open source programming language with a focus on simplicity and productivity. It has an elegant syntax that is natural to read and easy to write. Ruby was created by Yukihiro Matsumoto in the mid-1990s.",
    metadata: { author: "Matz", year: 1995 }
  },
  {
    id: "doc2",
    title: "Python for Data Science",
    content: "Python has become the go-to language for data science and machine learning. With libraries like NumPy, Pandas, and Scikit-learn, Python provides a comprehensive ecosystem for data analysis and modeling.",
    metadata: { author: "Data Team", year: 2023 }
  },
  {
    id: "doc3",
    title: "Web Development with Rails",
    content: "Ruby on Rails is a web application framework written in Ruby. Rails is a model-view-controller framework, providing default structures for databases, web services, and web pages.",
    metadata: { author: "DHH", year: 2004 }
  }
]

# Index documents with chunking parameters
# chunk_size: words per chunk (affects context window)
# overlap: words shared between chunks (maintains context)
puts "Indexing #{documents.size} documents..."
indexer.index_documents(documents, chunk_size: 50, overlap: 10)
puts "Documents indexed successfully"
puts

# Perform semantic search on indexed documents
# The query doesn't need exact keyword matches
# Semantic similarity finds relevant content
query = "programming language syntax"
results = indexer.search(query, k: 2)

puts "Search query: '#{query}'"
puts "\nSearch results:"
results.each_with_index do |result, i|
  puts "  #{i + 1}. #{result[:document][:title]}"
  puts "     Score: #{result[:score].round(3)}"
  puts "     Preview: #{result[:chunks].first[0..100]}..."
  puts
end

# ============================================================================
# EXAMPLE 4: HYBRID SEARCH (SEMANTIC + KEYWORD)
# ============================================================================
# Hybrid search combines the strengths of semantic and keyword-based search.
# Semantic search excels at understanding concepts and relationships, while
# keyword search ensures exact matches aren't missed. The combination provides
# better recall and precision than either approach alone.

puts "Example 4: Hybrid Search (Semantic + Keyword)"
puts "-" * 50

# Create keyword indexer for traditional text matching
# Uses techniques like TF-IDF or BM25 for relevance scoring
if defined?(OpenAIAgents::SemanticSearch::KeywordIndexer)
  keyword_indexer = OpenAIAgents::SemanticSearch::KeywordIndexer.new
  keyword_indexer.index_documents(documents)
  
  # Combine semantic and keyword search strategies
  # Weights can be adjusted based on use case
  hybrid_search = OpenAIAgents::SemanticSearch::HybridSearch.new(indexer, keyword_indexer)
else
  # Mock implementation
  class KeywordIndexer
    def initialize
      @documents = {}
      @index = Hash.new { |h, k| h[k] = [] }
    end
    
    def index_documents(documents)
      documents.each do |doc|
        @documents[doc[:id]] = doc
        # Simple word-based indexing
        words = (doc[:content] + " " + doc[:title]).downcase.split(/\W+/)
        words.uniq.each do |word|
          @index[word] << doc[:id]
        end
      end
    end
    
    def search(query, k: 5)
      # Simple keyword matching
      query_words = query.downcase.split(/\W+/)
      scores = Hash.new(0)
      
      query_words.each do |word|
        @index[word].each do |doc_id|
          scores[doc_id] += 1
        end
      end
      
      scores.sort_by { |_, score| -score }
            .first(k)
            .map { |doc_id, score| 
              { document: @documents[doc_id], score: score.to_f / query_words.length }
            }
    end
  end
  
  class HybridSearch
    def initialize(semantic_indexer, keyword_indexer, semantic_weight: 0.7)
      @semantic_indexer = semantic_indexer
      @keyword_indexer = keyword_indexer
      @semantic_weight = semantic_weight
      @keyword_weight = 1 - semantic_weight
    end
    
    def search(query, k: 5)
      # Get results from both search methods
      semantic_results = @semantic_indexer.search(query, k: k * 2)
      keyword_results = @keyword_indexer.search(query, k: k * 2)
      
      # Combine and rerank
      combined = {}
      
      semantic_results.each do |result|
        doc_id = result[:document][:id]
        combined[doc_id] = {
          document: result[:document],
          semantic_score: result[:score],
          keyword_score: 0,
          combined_score: result[:score] * @semantic_weight
        }
      end
      
      keyword_results.each do |result|
        doc_id = result[:document][:id]
        if combined[doc_id]
          combined[doc_id][:keyword_score] = result[:score]
          combined[doc_id][:combined_score] += result[:score] * @keyword_weight
        else
          combined[doc_id] = {
            document: result[:document],
            semantic_score: 0,
            keyword_score: result[:score],
            combined_score: result[:score] * @keyword_weight
          }
        end
      end
      
      combined.values.sort_by { |r| -r[:combined_score] }.first(k)
    end
  end
  
  keyword_indexer = KeywordIndexer.new
  keyword_indexer.index_documents(documents)
  hybrid_search = HybridSearch.new(indexer, keyword_indexer)
end

# Search using hybrid approach
hybrid_query = "Ruby Rails web framework"
hybrid_results = hybrid_search.search(hybrid_query, k: 2)

puts "Hybrid search query: '#{hybrid_query}'"
puts "\nHybrid search results:"
hybrid_results.each_with_index do |result, i|
  puts "  #{i + 1}. #{result[:document][:title]}"
  puts "     Combined score: #{result[:combined_score].round(3)}"
  puts "     Semantic score: #{result[:semantic_score].round(3)}"
  puts "     Keyword score: #{result[:keyword_score].round(3)}"
  puts
end

# ============================================================================
# EXAMPLE 5: SEMANTIC SEARCH TOOL FOR AGENTS
# ============================================================================
# Integrating semantic search as a tool enables AI agents to access and reason
# over large knowledge bases. The agent can search for relevant information
# dynamically during conversations, making it context-aware and more helpful.
# This pattern is essential for RAG (Retrieval Augmented Generation) systems.

puts "Example 5: Semantic Search Tool for Agents"
puts "-" * 50

# Create semantic search tool wrapping the indexer
# The tool provides a clean interface for agents to search
if defined?(OpenAIAgents::SemanticSearch::SemanticSearchTool)
  search_tool = OpenAIAgents::SemanticSearch::SemanticSearchTool.new(indexer)
else
  # Mock search tool
  class SemanticSearchTool
    def initialize(indexer)
      @indexer = indexer
    end
    
    def name
      "semantic_search"
    end
    
    def description
      "Search through indexed documents using semantic similarity"
    end
    
    def search(query:, k: 3)
      results = @indexer.search(query, k: k)
      # Format for agent consumption
      results.map do |r|
        {
          title: r[:document][:title],
          content: r[:chunks].first[0],
          score: r[:score].round(3)
        }
      end
    end
    
    def to_openai_format
      {
        type: "function",
        function: {
          name: name,
          description: description,
          parameters: {
            type: "object",
            properties: {
              query: { type: "string", description: "Search query" },
              k: { type: "integer", description: "Number of results", default: 3 }
            },
            required: ["query"]
          }
        }
      }
    end
  end
  
  search_tool = SemanticSearchTool.new(indexer)
end

# Create agent with search tool
agent = OpenAIAgents::Agent.new(
  name: "ResearchAssistant",
  model: "gpt-4o-mini",
  instructions: "You are a helpful research assistant. Use the semantic search tool to find relevant information."
)

agent.add_tool(search_tool)

puts "Created agent with semantic search capability"
puts "Agent tools: #{agent.tools.map(&:name).join(', ')}"
puts

# Simulate tool usage
search_results = search_tool.search(query: "Ruby programming", k: 2)
puts "Search tool results for 'Ruby programming':"
search_results.each do |result|
  puts "  - #{result[:title]} (score: #{result[:score]})"
end
puts

# ============================================================================
# EXAMPLE 6: QUERY EXPANSION
# ============================================================================
# Query expansion improves search recall by generating related queries.
# Techniques include synonym expansion, question generation, and concept
# broadening. This helps find relevant content that might use different
# terminology than the original query.

puts "Example 6: Query Expansion"
puts "-" * 50

if defined?(OpenAIAgents::SemanticSearch::QueryExpander)
  query_expander = OpenAIAgents::SemanticSearch::QueryExpander.new
else
  # Mock query expander
  class QueryExpander
    def expand_query(query, method: :synonyms)
      case method
      when :synonyms
        # Simple synonym expansion
        synonyms = {
          "find" => ["search", "locate", "discover"],
          "documentation" => ["docs", "manual", "guide"],
          "ruby" => ["Ruby", "ruby-lang", "Ruby language"]
        }
        
        expanded = [query]
        query.downcase.split.each do |word|
          if synonyms[word]
            synonyms[word].each do |syn|
              expanded << query.sub(/\b#{word}\b/i, syn)
            end
          end
        end
        expanded.uniq
        
      when :questions
        # Generate question variations
        base = query.downcase
        [
          "What is #{base}?",
          "How does #{base} work?",
          "Why use #{base}?",
          "#{base} examples",
          "#{base} tutorial"
        ]
      end
    end
  end
  
  query_expander = QueryExpander.new
end

original_query = "find Ruby documentation"

# Synonym expansion
synonym_queries = query_expander.expand_query(original_query, method: :synonyms)
puts "Original query: '#{original_query}'"
puts "\nSynonym expansion:"
synonym_queries.each { |q| puts "  - #{q}" }

# Question expansion
question_queries = query_expander.expand_query("semantic search", method: :questions)
puts "\nQuestion expansion for 'semantic search':"
question_queries.each { |q| puts "  - #{q}" }
puts

# ============================================================================
# EXAMPLE 7: VECTOR DATABASE PERSISTENCE
# ============================================================================
# Persisting vector databases enables reuse without regenerating embeddings.
# This is crucial for production systems where embedding generation is expensive.
# Common formats include JSON for small datasets and specialized formats like
# FAISS or Annoy for large-scale deployments.

puts "Example 7: Vector Database Operations"
puts "-" * 50

# Save vector database to disk
# In production, consider binary formats for efficiency
db_file = "vector_db_demo.json"
vector_db.save(db_file)
puts "Vector database saved to #{db_file}"

# Load vector database from disk
# Preserves all vectors and metadata
if defined?(OpenAIAgents::SemanticSearch::VectorDatabase)
  loaded_db = OpenAIAgents::SemanticSearch::VectorDatabase.load(db_file)
else
  loaded_db = VectorDatabase.load(db_file)
end
puts "Vector database loaded from #{db_file}"

# Verify loaded data integrity
# Ensures save/load cycle preserves search functionality
loaded_results = loaded_db.search(query, k: 1)
puts "Verification search result: #{loaded_results.first[:metadata][:title]}"

# Clean up temporary file
require 'fileutils'
FileUtils.rm_f(db_file)
puts

# ============================================================================
# EXAMPLE 8: FILTERING SEARCH RESULTS
# ============================================================================
# Metadata filtering combines semantic search with structured queries.
# This enables precise searches like "find similar documents but only from
# category X" or "search within date range Y". Filters reduce the search
# space before similarity scoring, improving both performance and relevance.

puts "Example 8: Filtering Search Results"
puts "-" * 50

# Apply metadata filter during search
# Only documents matching filter criteria are considered
# This is more efficient than post-filtering results
filter = { category: "programming" }
filtered_results = vector_db.search(query, k: 5, filter: filter)

puts "Search with filter (category: programming):"
filtered_results.each do |result|
  puts "  - #{result[:metadata][:title]} (#{result[:metadata][:category]})"
end
puts

# ============================================================================
# EXAMPLE 9: PERFORMANCE OPTIMIZATION
# ============================================================================
# Semantic search performance depends on embedding generation speed, vector
# search efficiency, and result processing. Optimization strategies vary by
# scale but generally focus on batching, caching, and appropriate index
# selection for the dataset size.

puts "Example 9: Performance Considerations"
puts "-" * 50

# Performance optimization guidelines based on production experience
# These tips help build systems that scale from thousands to millions of documents
puts "Performance tips for semantic search:"
puts "1. Embedding Generation:"
puts "   - Batch multiple texts (up to 100) in single API call"
puts "   - Cache embeddings to avoid regeneration"
puts "   - Use smaller embedding models for faster processing"
puts
puts "2. Vector Search:"
puts "   - Use HNSW index for large datasets (>10k vectors)"
puts "   - Consider approximate search for better performance"
puts "   - Implement pagination for large result sets"
puts
puts "3. Document Chunking:"
puts "   - Balance chunk size (300-500 tokens typical)"
puts "   - Use appropriate overlap (10-20%)"
puts "   - Consider hierarchical chunking for long documents"
puts

# ============================================================================
# EXAMPLE 10: PRODUCTION OPENAI EMBEDDINGS
# ============================================================================
# OpenAI's embedding models convert text to high-dimensional vectors that
# capture semantic meaning. The text-embedding-3 series offers different
# size/performance tradeoffs. Proper configuration ensures optimal results
# for your specific use case and scale requirements.

puts "Example 10: Real OpenAI Embeddings"
puts "-" * 50

# Example code for production embedding generation
# Replace mock embeddings with OpenAI's powerful models
puts "To use real OpenAI embeddings:"
puts
puts "```ruby"
puts "# Create real embedding generator"
puts "embedding_gen = OpenAIAgents::SemanticSearch::EmbeddingGenerator.new("
puts "  model: 'text-embedding-3-small'  # 1536 dimensions, fast and efficient"
puts ")"
puts
puts "# Alternative models:"
puts "# - text-embedding-3-large: 3072 dimensions, highest quality"
puts "# - text-embedding-ada-002: 1536 dimensions, legacy model"
puts
puts "# Generate embeddings with batching"
puts "texts = ['Ruby programming', 'Python data science']"
puts "embeddings = embedding_gen.generate(texts, cache: true)"
puts
puts "# Create vector DB with correct dimension"
puts "vector_db = OpenAIAgents::SemanticSearch::VectorDatabase.new("
puts "  dimension: 1536,  # Must match embedding model"
puts "  index_type: :hnsw  # Hierarchical Navigable Small World for fast search"
puts ")"
puts "```"
puts

# ============================================================================
# SEMANTIC SEARCH BEST PRACTICES
# ============================================================================
# Building effective semantic search systems requires careful attention to
# document preparation, indexing strategies, and search optimization. These
# practices are derived from production deployments and cover the full
# lifecycle from data preparation to continuous improvement.

puts "\n=== Semantic Search Best Practices ==="
puts "-" * 50
puts <<~PRACTICES
  1. Document Preparation:
     - Clean and normalize text before indexing
     - Include relevant metadata for filtering
     - Consider document structure and hierarchy
     - Remove redundant information
  
  2. Chunking Strategy:
     - Use semantic boundaries (paragraphs, sections)
     - Maintain context with overlap
     - Include document metadata in chunks
     - Test different chunk sizes
  
  3. Embedding Models:
     - Choose model based on use case
     - Consider multilingual needs
     - Balance quality vs speed/cost
     - Keep embeddings up to date
  
  4. Search Optimization:
     - Implement query expansion
     - Use hybrid search for better recall
     - Add reranking for precision
     - Cache frequent queries
  
  5. Scalability:
     - Use appropriate index types
     - Implement sharding for large datasets
     - Consider distributed search
     - Monitor performance metrics
  
  6. Quality Improvements:
     - Collect user feedback
     - A/B test different approaches
     - Fine-tune ranking algorithms
     - Regular evaluation with test queries
PRACTICES

puts "\nSemantic search example completed!"
