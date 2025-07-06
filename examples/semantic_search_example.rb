#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/openai_agents"
require_relative "../lib/openai_agents/semantic_search"

# Set API key from environment
OpenAI.configure do |config|
  config.access_token = ENV.fetch("OPENAI_API_KEY", nil)
end

puts "=== Semantic Search Example ==="
puts

# Example 1: Basic Vector Database
puts "Example 1: Basic Vector Database"
puts "-" * 50

# Create vector database
vector_db = OpenAIAgents::SemanticSearch::VectorDatabase.new(dimension: 5)  # Small dimension for demo

# Add some vectors
vectors = [
  [0.1, 0.2, 0.3, 0.4, 0.5],
  [0.2, 0.3, 0.4, 0.5, 0.6],
  [0.9, 0.8, 0.7, 0.6, 0.5],
  [0.1, 0.1, 0.1, 0.9, 0.9]
]

metadata = [
  { title: "Introduction to Ruby", category: "programming" },
  { title: "Advanced Ruby Patterns", category: "programming" },
  { title: "Machine Learning Basics", category: "ai" },
  { title: "Data Science with Python", category: "data" }
]

vector_db.add(vectors, metadata)

# Search for similar vectors
query = [0.15, 0.25, 0.35, 0.45, 0.55]
results = vector_db.search(query, k: 3)

puts "Query vector: #{query}"
puts "\nTop 3 similar vectors:"
results.each_with_index do |result, i|
  puts "  #{i + 1}. #{result[:metadata][:title]} (score: #{result[:score].round(3)})"
end
puts

# Example 2: Embedding Generation (with mock for demo)
puts "Example 2: Embedding Generation"
puts "-" * 50

# For demo purposes, we'll use a mock embedding generator
class MockEmbeddingGenerator
  def generate(texts, cache: true)
    # Simulate embeddings
    Array(texts).map do |text|
      # Simple hash-based embedding simulation
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

# Example 3: Document Indexing
puts "Example 3: Document Indexing"
puts "-" * 50

# Create document indexer
indexer = OpenAIAgents::SemanticSearch::DocumentIndexer.new(
  vector_db: OpenAIAgents::SemanticSearch::VectorDatabase.new(dimension: 5),
  embedding_generator: MockEmbeddingGenerator.new
)

# Index some documents
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

puts "Indexing #{documents.size} documents..."
indexer.index_documents(documents, chunk_size: 50, overlap: 10)
puts "Documents indexed successfully"
puts

# Search documents
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

# Example 4: Hybrid Search
puts "Example 4: Hybrid Search (Semantic + Keyword)"
puts "-" * 50

# Create keyword indexer
keyword_indexer = OpenAIAgents::SemanticSearch::KeywordIndexer.new
keyword_indexer.index_documents(documents)

# Create hybrid search
hybrid_search = OpenAIAgents::SemanticSearch::HybridSearch.new(indexer, keyword_indexer)

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

# Example 5: Semantic Search Tool for Agents
puts "Example 5: Semantic Search Tool for Agents"
puts "-" * 50

# Create semantic search tool
search_tool = OpenAIAgents::SemanticSearch::SemanticSearchTool.new(indexer)

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

# Example 6: Query Expansion
puts "Example 6: Query Expansion"
puts "-" * 50

query_expander = OpenAIAgents::SemanticSearch::QueryExpander.new

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

# Example 7: Vector Database Operations
puts "Example 7: Vector Database Operations"
puts "-" * 50

# Save vector database
db_file = "vector_db_demo.json"
vector_db.save(db_file)
puts "Vector database saved to #{db_file}"

# Load vector database
loaded_db = OpenAIAgents::SemanticSearch::VectorDatabase.load(db_file)
puts "Vector database loaded from #{db_file}"

# Verify loaded data
loaded_results = loaded_db.search(query, k: 1)
puts "Verification search result: #{loaded_results.first[:metadata][:title]}"

# Clean up
File.delete(db_file) if File.exist?(db_file)
puts

# Example 8: Filtering Search Results
puts "Example 8: Filtering Search Results"
puts "-" * 50

# Search with filter
filter = { category: "programming" }
filtered_results = vector_db.search(query, k: 5, filter: filter)

puts "Search with filter (category: programming):"
filtered_results.each do |result|
  puts "  - #{result[:metadata][:title]} (#{result[:metadata][:category]})"
end
puts

# Example 9: Performance Considerations
puts "Example 9: Performance Considerations"
puts "-" * 50

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

# Example 10: Real OpenAI Embeddings (commented out)
puts "Example 10: Real OpenAI Embeddings"
puts "-" * 50

puts "To use real OpenAI embeddings:"
puts
puts "```ruby"
puts "# Create real embedding generator"
puts "embedding_gen = OpenAIAgents::SemanticSearch::EmbeddingGenerator.new("
puts "  model: 'text-embedding-3-small'"
puts ")"
puts
puts "# Generate embeddings"
puts "texts = ['Ruby programming', 'Python data science']"
puts "embeddings = embedding_gen.generate(texts)"
puts
puts "# Create vector DB with correct dimension"
puts "vector_db = OpenAIAgents::SemanticSearch::VectorDatabase.new("
puts "  dimension: 1536  # for text-embedding-3-small"
puts ")"
puts "```"
puts

# Best practices
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