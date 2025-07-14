#!/usr/bin/env ruby
# frozen_string_literal: true

# This example demonstrates vector store capabilities in OpenAI Agents Ruby.
# Vector stores enable semantic search over large document collections using
# embeddings. Documents are converted to high-dimensional vectors that capture
# semantic meaning, allowing similarity-based retrieval. This is the foundation
# for RAG (Retrieval Augmented Generation) systems where AI agents can access
# and reason over large knowledge bases. Essential for building AI assistants
# with domain-specific knowledge.

require_relative "../lib/openai_agents"

# Vector store modules (these will be implemented in future versions)
begin
  require_relative "../lib/openai_agents/vector_store"
  require_relative "../lib/openai_agents/tools/vector_search_tool"
rescue LoadError
  puts "Note: Vector store modules are not yet implemented. This example shows planned functionality."
  puts "The code demonstrates the API and usage patterns for future vector store features.\n"
end

# Set API key from environment for embedding generation
# Real vector stores require embeddings from OpenAI API
begin
  OpenAI.configure do |config|
    config.access_token = ENV.fetch("OPENAI_API_KEY", nil)
  end
rescue NameError
  # OpenAI gem not loaded, using mocks
end

puts "=== Vector Store Example ==="
puts

# ============================================================================
# VECTOR STORE INITIALIZATION
# ============================================================================
# Vector stores are specialized databases optimized for similarity search.
# They store document embeddings (vector representations) and enable fast
# nearest-neighbor queries. The dimension must match the embedding model -
# OpenAI's text-embedding-3-small uses 1536 dimensions.

# Create a vector store for company knowledge base
# In production, this might be backed by Pinecone, Weaviate, or Chroma
if defined?(OpenAIAgents::VectorStore)
  knowledge_store = OpenAIAgents::VectorStore.new(
    name: "company_knowledge",       # Unique identifier for the store
    dimensions: 1536                # Must match embedding model dimensions
  )
else
  # Mock implementation for demonstration
  class VectorStore
    def initialize(name:, dimensions:)
      @name = name
      @dimensions = dimensions
      @documents = {}
      @embeddings = {}
      @namespaces = { "default" => {} }
    end
    
    def add_documents(documents, namespace: "default")
      @namespaces[namespace] ||= {}
      documents.map.with_index do |doc, i|
        id = "doc_#{Time.now.to_f}_#{i}"
        @namespaces[namespace][id] = doc
        # In production, generate real embeddings here
        id
      end
    end
    
    def search(query, k: 5, filter: nil, namespace: "default")
      # Mock search implementation
      docs = @namespaces[namespace] || {}
      results = docs.values
      
      # Apply filter if provided
      if filter
        results = results.select do |doc|
          filter.all? { |key, value| doc[:metadata][key] == value }
        end
      end
      
      # Return top k results (mock relevance)
      results.first(k)
    end
    
    def stats
      @namespaces.transform_values(&:size)
    end
    
    def export(path)
      require 'json'
      File.write(path, JSON.pretty_generate({
        name: @name,
        dimensions: @dimensions,
        records: @namespaces
      }))
    end
  end
  
  knowledge_store = VectorStore.new(
    name: "company_knowledge",
    dimensions: 1536
  )
end

# ============================================================================
# DOCUMENT INGESTION
# ============================================================================
# Documents are the core content units in a vector store. Each document
# includes the text content and metadata for filtering and organization.
# Metadata enables hybrid search combining semantic similarity with
# structured queries (e.g., "find similar documents from 2024").

puts "1. Adding company documents to vector store..."

# Define knowledge base documents with rich metadata
# Content: The actual text that will be embedded and searched
# Metadata: Structured data for filtering, categorization, and context
documents = [
  {
    content: "Our company was founded in 2020 with a mission to democratize AI. We believe that AI should be accessible to everyone.",
    metadata: { type: "about", category: "company", date: "2024-01-01" }
  },
  {
    content: "We offer three main products: AI Assistant Pro for enterprises, AI Developer SDK for building custom solutions, and AI Analytics for data insights.",
    metadata: { type: "products", category: "offerings", date: "2024-01-15" }
  },
  {
    content: "Our pricing starts at $99/month for the basic plan, $299/month for professional, and custom pricing for enterprise customers.",
    metadata: { type: "pricing", category: "sales", date: "2024-02-01" }
  },
  {
    content: "The company headquarters is located in San Francisco, with additional offices in New York, London, and Tokyo.",
    metadata: { type: "locations", category: "company", date: "2024-01-01" }
  },
  {
    content: "Our support team is available 24/7 via email at support@example.com, phone at 1-800-AI-HELP, or through our live chat system.",
    metadata: { type: "support", category: "contact", date: "2024-01-20" }
  }
]

# Add documents to vector store
# The store generates embeddings and indexes them for fast retrieval
# Returns document IDs for future reference
ids = knowledge_store.add_documents(documents)
puts "Added #{ids.length} documents to the knowledge base"
puts

# ============================================================================
# VECTOR STORE TOOLS
# ============================================================================
# Tools provide AI agents with capabilities to interact with the vector store.
# Different tools serve different purposes: search for retrieval, index for
# adding content, and manage for maintenance operations. This separation
# follows the principle of least privilege.

# Search tool for semantic retrieval
# Converts queries to embeddings and finds similar documents
if defined?(OpenAIAgents::Tools::VectorSearchTool)
  search_tool = OpenAIAgents::Tools::VectorSearchTool.new(
    vector_store: knowledge_store,
    name: "search_knowledge",
    description: "Search the company knowledge base"
  )
  
  # Indexing tool for adding new knowledge
  # Allows the agent to expand the knowledge base dynamically
  index_tool = OpenAIAgents::Tools::VectorIndexTool.new(
    vector_store: knowledge_store,
    name: "add_knowledge",
    description: "Add new information to the knowledge base"
  )
  
  # Management tool for document operations
  # Update, delete, or reorganize documents
  manage_tool = OpenAIAgents::Tools::VectorManagementTool.new(
    vector_store: knowledge_store,
    name: "manage_knowledge",
    description: "Manage documents in the knowledge base"
  )
else
  # Mock tools for demonstration
  class VectorSearchTool
    def initialize(vector_store:, name:, description:)
      @vector_store = vector_store
      @name = name
      @description = description
    end
    
    attr_reader :name, :description
    
    def search(query:, k: 5, filter: nil)
      @vector_store.search(query, k: k, filter: filter)
    end
  end
  
  class VectorIndexTool < VectorSearchTool
    def add(content:, metadata: {})
      @vector_store.add_documents([{ content: content, metadata: metadata }])
    end
  end
  
  class VectorManagementTool < VectorSearchTool
    def stats
      @vector_store.stats
    end
  end
  
  search_tool = VectorSearchTool.new(
    vector_store: knowledge_store,
    name: "search_knowledge",
    description: "Search the company knowledge base"
  )
  
  index_tool = VectorIndexTool.new(
    vector_store: knowledge_store,
    name: "add_knowledge",
    description: "Add new information to the knowledge base"
  )
  
  manage_tool = VectorManagementTool.new(
    vector_store: knowledge_store,
    name: "manage_knowledge",
    description: "Manage documents in the knowledge base"
  )
end

# ============================================================================
# KNOWLEDGE-ENABLED AGENT
# ============================================================================
# This agent demonstrates RAG (Retrieval Augmented Generation) pattern.
# Instead of relying solely on training data, the agent retrieves relevant
# information from the vector store before generating responses. This ensures
# accurate, up-to-date answers grounded in authoritative sources.

# Create an agent with vector search capabilities
agent = OpenAIAgents::Agent.new(
  name: "KnowledgeAssistant",
  model: "gpt-4o",
  
  # Instructions emphasize retrieval-first approach
  # The agent should always search before answering
  instructions: <<~INSTRUCTIONS
    You are a helpful assistant with access to the company knowledge base.
    
    When users ask questions:
    1. Search the knowledge base for relevant information
    2. Provide accurate answers based on the search results
    3. If information is not found, say so clearly
    4. You can also add new information to the knowledge base when provided
    
    Always cite which documents you're basing your answer on.
  INSTRUCTIONS
)

# Add tools to agent
# Tools must be wrapped as FunctionTools for the agent
if defined?(OpenAIAgents::Tools::VectorSearchTool) && search_tool.respond_to?(:call)
  # Convert vector tools to FunctionTools
  agent.add_tool(
    OpenAIAgents::FunctionTool.new(
      search_tool.method(:call),
      name: search_tool.name,
      description: search_tool.description
    )
  )
  agent.add_tool(
    OpenAIAgents::FunctionTool.new(
      index_tool.method(:call),
      name: index_tool.name,
      description: index_tool.description
    )
  )
  agent.add_tool(
    OpenAIAgents::FunctionTool.new(
      manage_tool.method(:call),
      name: manage_tool.name,
      description: manage_tool.description
    )
  )
else
  # For mocks, create function wrappers
  search_function = lambda do |query:, k: 5, filter: nil|
    results = knowledge_store.search(query, k: k, filter: filter)
    "Found #{results.length} relevant documents:\n" +
    results.map { |r| "- #{r[:content][0..100]}..." }.join("\n")
  end
  
  add_function = lambda do |content:, metadata: {}|
    ids = knowledge_store.add_documents([{ content: content, metadata: metadata }])
    "Added document with ID: #{ids.first}"
  end
  
  stats_function = lambda do
    stats = knowledge_store.stats
    "Knowledge base statistics:\n" +
    stats.map { |ns, count| "- #{ns}: #{count} documents" }.join("\n")
  end
  
  agent.add_tool(
    OpenAIAgents::FunctionTool.new(
      search_function,
      name: "search_knowledge",
      description: "Search the company knowledge base"
    )
  )
  
  agent.add_tool(
    OpenAIAgents::FunctionTool.new(
      add_function,
      name: "add_knowledge",
      description: "Add new information to the knowledge base"
    )
  )
  
  agent.add_tool(
    OpenAIAgents::FunctionTool.new(
      stats_function,
      name: "manage_knowledge",
      description: "Get knowledge base statistics"
    )
  )
end

# Create runner
runner = OpenAIAgents::Runner.new(agent: agent)

# ============================================================================
# EXAMPLE 1: BASIC SEMANTIC SEARCH
# ============================================================================
# Demonstrates how the agent uses vector search to find relevant information.
# The query doesn't need exact keyword matches - semantic similarity finds
# conceptually related content. The agent will search, retrieve, and synthesize.

puts "2. Searching for company information..."
puts "-" * 50

# Simple product query triggers vector search
# Agent will find the products document and extract information
result = runner.run("What products does the company offer?")
puts result.messages.last[:content]
puts

# Example 2: Search with specific criteria
puts "3. Searching for pricing information..."
puts "-" * 50
result = runner.run("What are the pricing options? I need details about all plans.")
puts result.messages.last[:content]
puts

# ============================================================================
# EXAMPLE 3: DYNAMIC KNOWLEDGE BASE EXPANSION
# ============================================================================
# Vector stores can grow dynamically as new information becomes available.
# The agent can add documents, expanding its knowledge without retraining.
# This is essential for maintaining current information in production systems.

puts "4. Adding new information to knowledge base..."
puts "-" * 50

# Request to add new product feature information
# The agent will use the index tool to add this as a new document
result = runner.run(<<~PROMPT)
  Please add this new information to the knowledge base:
  "We recently launched a new feature called AI Vision that allows image analysis and generation. It's available on Professional and Enterprise plans."
PROMPT
puts result.messages.last[:content]
puts

# ============================================================================
# EXAMPLE 4: MULTI-ASPECT QUERIES
# ============================================================================
# Complex queries require multiple vector searches and information synthesis.
# The agent must retrieve different types of information, combine them, and
# present a coherent response. This showcases the power of semantic search
# over simple keyword matching.

puts "5. Complex query requiring multiple searches..."
puts "-" * 50

# Multi-part query simulating real customer interaction
# Agent will perform multiple searches and synthesize results
result = runner.run(<<~PROMPT)
  A potential enterprise customer wants to know:
  1. Where are your offices located?
  2. What support options are available?
  3. Do you have enterprise pricing?
  
  Please provide comprehensive information.
PROMPT
puts result.messages.last[:content]
puts

# ============================================================================
# EXAMPLE 6: NAMESPACE ORGANIZATION
# ============================================================================
# Namespaces partition the vector store into logical sections. This enables
# organizing different types of content (technical docs, marketing, legal)
# and controlling search scope. Essential for multi-tenant applications or
# separating content domains.

puts "6. Using namespaces for document organization..."
puts "-" * 50

# Technical documentation in separate namespace
# Keeps API docs separate from general company information
tech_docs = [
  {
    content: "To use the AI Assistant API, first obtain an API key from your dashboard. Include it in the Authorization header: 'Bearer YOUR_API_KEY'",
    metadata: { type: "api", topic: "authentication" }
  },
  {
    content: "Rate limits: Basic plan - 100 requests/minute, Professional - 1000 requests/minute, Enterprise - unlimited",
    metadata: { type: "api", topic: "limits" }
  }
]

knowledge_store.add_documents(tech_docs, namespace: "technical")

result = runner.run(<<~PROMPT)
  Search in the technical documentation namespace for information about API authentication.
PROMPT
puts result.messages.last[:content]
puts

# Show statistics
puts "7. Knowledge base statistics:"
puts "-" * 50
stats = knowledge_store.stats
stats.each do |namespace, count|
  puts "  #{namespace}: #{count} documents"
end
puts

# ============================================================================
# EXAMPLE 8: FILTERED SEARCH
# ============================================================================
# Metadata filtering combines semantic search with structured queries.
# This enables precise searches like "find similar content but only from
# category X" or "documents updated after date Y". Filters improve both
# relevance and performance by reducing the search space.

puts "8. Advanced search with filters..."
puts "-" * 50

# Combine semantic search with metadata filters
# Only searches within documents categorized as "company"
filtered_results = knowledge_store.search(
  "company information",
  k: 5,
  filter: { category: "company" }  # Structured filter on metadata
)

puts "Documents in 'company' category:"
filtered_results.each do |doc|
  puts "  - #{doc[:content][0..60]}..."
end
puts

# ============================================================================
# EXAMPLE 9: ADVANCED RAG (RETRIEVAL AUGMENTED GENERATION)
# ============================================================================
# RAG combines the best of retrieval and generation. The system retrieves
# relevant documents, provides them as context to the LLM, and generates
# responses grounded in factual information. This reduces hallucinations
# and ensures accuracy while maintaining natural, coherent responses.

puts "9. Using RAG for comprehensive answers..."
puts "-" * 50

# Create specialized RAG tool with enhanced capabilities
# RAG tools typically retrieve more context and use advanced prompting
if defined?(OpenAIAgents::Tools::VectorRAGTool)
  rag_tool = OpenAIAgents::Tools::VectorRAGTool.new(
    vector_store: knowledge_store,
    name: "knowledge_rag",
    description: "Advanced retrieval-augmented generation for comprehensive answers"
  )
else
  # Mock RAG tool
  class VectorRAGTool < VectorSearchTool
    def rag_search(query:, k: 10)
      # RAG typically retrieves more documents for context
      results = @vector_store.search(query, k: k)
      # Format results for LLM context
      results.map { |r| r[:content] }.join("\n\n")
    end
  end
  
  rag_tool = VectorRAGTool.new(
    vector_store: knowledge_store,
    name: "knowledge_rag",
    description: "Advanced retrieval-augmented generation for comprehensive answers"
  )
end

# Create a new agent optimized for RAG
rag_agent = OpenAIAgents::Agent.new(
  name: "RAGExpert",
  model: "gpt-4o",
  instructions: <<~INSTRUCTIONS
    You are an expert at providing comprehensive answers using retrieval-augmented generation.
    
    When answering questions:
    1. First search for ALL relevant information
    2. Synthesize information from multiple sources
    3. Provide detailed, accurate answers
    4. Always indicate the confidence level of your answer
    5. Suggest related topics the user might be interested in
  INSTRUCTIONS
)

if defined?(OpenAIAgents::Tools::VectorRAGTool) && rag_tool.respond_to?(:call)
  rag_agent.add_tool(
    OpenAIAgents::FunctionTool.new(
      rag_tool.method(:call),
      name: rag_tool.name,
      description: rag_tool.description
    )
  )
else
  # Mock RAG function
  rag_function = lambda do |query:, k: 10|
    results = knowledge_store.search(query, k: k)
    context = results.map { |r| r[:content] }.join("\n\n---\n\n")
    "Retrieved #{results.length} relevant documents for context. Based on the knowledge base:\n\n#{context}"
  end
  
  rag_agent.add_tool(
    OpenAIAgents::FunctionTool.new(
      rag_function,
      name: "knowledge_rag",
      description: "Advanced retrieval-augmented generation for comprehensive answers"
    )
  )
end
rag_runner = OpenAIAgents::Runner.new(agent: rag_agent)

result = rag_runner.run(<<~PROMPT)
  I'm evaluating your company for a potential partnership. Can you provide a comprehensive overview including your products, pricing, support, and company background?
PROMPT
puts result.messages.last[:content]

# ============================================================================
# KNOWLEDGE BASE PERSISTENCE
# ============================================================================
# Vector stores must be persistent for production use. Export/import enables
# backup, migration, and sharing of knowledge bases. The export includes
# embeddings, documents, and metadata - everything needed to recreate the store.

puts "\n10. Exporting knowledge base..."

# Create export directory
require 'fileutils'
export_path = "tmp/knowledge_base_export.json"
FileUtils.mkdir_p("tmp")

# Export complete vector store
# Includes documents, embeddings, metadata, and configuration
knowledge_store.export(export_path)
puts "Knowledge base exported to: #{export_path}"

# Analyze export contents
# Useful for debugging and understanding store structure
require 'json'
export_data = JSON.parse(File.read(export_path))
total_docs = export_data['records'].values.map(&:size).sum
namespace_count = export_data['records'].size
puts "Export contains #{total_docs} total documents across #{namespace_count} namespaces"

# Clean up temporary files
FileUtils.rm_f(export_path)

# ============================================================================
# SUMMARY
# ============================================================================

puts "\n=== Vector Store Best Practices ==="
puts "1. Document Preparation:"
puts "   - Include rich metadata for filtering"
puts "   - Keep documents focused and atomic"
puts "   - Use consistent formatting"
puts
puts "2. Embedding Strategy:"
puts "   - Choose appropriate model for your domain"
puts "   - Consider multilingual needs"
puts "   - Monitor embedding costs"
puts
puts "3. Search Optimization:"
puts "   - Use namespaces for logical separation"
puts "   - Combine semantic search with filters"
puts "   - Tune k parameter for precision/recall"
puts
puts "4. Maintenance:"
puts "   - Regular backups via export"
puts "   - Monitor store size and performance"
puts "   - Update documents as information changes"

puts "\nExample completed!"
