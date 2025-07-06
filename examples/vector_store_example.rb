#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/openai_agents"
require_relative "../lib/openai_agents/vector_store"
require_relative "../lib/openai_agents/tools/vector_search_tool"

# Set API key from environment
OpenAI.configure do |config|
  config.access_token = ENV.fetch("OPENAI_API_KEY", nil)
end

puts "=== Vector Store Example ==="
puts

# Create a vector store for knowledge base
knowledge_store = OpenAIAgents::VectorStore.new(
  name: "company_knowledge",
  dimensions: 1536  # OpenAI embedding dimensions
)

# Add company documents
puts "1. Adding company documents to vector store..."
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

ids = knowledge_store.add_documents(documents)
puts "Added #{ids.length} documents to the knowledge base"
puts

# Create vector search tools
search_tool = OpenAIAgents::Tools::VectorSearchTool.new(
  vector_store: knowledge_store,
  name: "search_knowledge",
  description: "Search the company knowledge base"
)

index_tool = OpenAIAgents::Tools::VectorIndexTool.new(
  vector_store: knowledge_store,
  name: "add_knowledge",
  description: "Add new information to the knowledge base"
)

manage_tool = OpenAIAgents::Tools::VectorManagementTool.new(
  vector_store: knowledge_store,
  name: "manage_knowledge",
  description: "Manage documents in the knowledge base"
)

# Create an agent with vector search capabilities
agent = OpenAIAgents::Agent.new(
  name: "KnowledgeAssistant",
  model: "gpt-4o",
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
agent.add_tool(search_tool)
agent.add_tool(index_tool)
agent.add_tool(manage_tool)

# Create runner
runner = OpenAIAgents::Runner.new(agent: agent)

# Example 1: Search for information
puts "2. Searching for company information..."
puts "-" * 50
result = runner.run("What products does the company offer?")
puts result.messages.last[:content]
puts

# Example 2: Search with specific criteria
puts "3. Searching for pricing information..."
puts "-" * 50
result = runner.run("What are the pricing options? I need details about all plans.")
puts result.messages.last[:content]
puts

# Example 3: Add new information
puts "4. Adding new information to knowledge base..."
puts "-" * 50
result = runner.run(<<~PROMPT)
  Please add this new information to the knowledge base:
  "We recently launched a new feature called AI Vision that allows image analysis and generation. It's available on Professional and Enterprise plans."
PROMPT
puts result.messages.last[:content]
puts

# Example 4: Complex query
puts "5. Complex query requiring multiple searches..."
puts "-" * 50
result = runner.run(<<~PROMPT)
  A potential enterprise customer wants to know:
  1. Where are your offices located?
  2. What support options are available?
  3. Do you have enterprise pricing?
  
  Please provide comprehensive information.
PROMPT
puts result.messages.last[:content]
puts

# Example 6: Demonstrate namespaces
puts "6. Using namespaces for document organization..."
puts "-" * 50

# Add technical documentation to a separate namespace
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

# Demonstrate filtering
puts "8. Advanced search with filters..."
puts "-" * 50

# Search only in specific categories
filtered_results = knowledge_store.search(
  "company information",
  k: 5,
  filter: { category: "company" }
)

puts "Documents in 'company' category:"
filtered_results.each do |doc|
  puts "  - #{doc[:content][0..60]}..."
end
puts

# Example 9: RAG (Retrieval Augmented Generation)
puts "9. Using RAG for comprehensive answers..."
puts "-" * 50

# Create a specialized RAG tool
rag_tool = OpenAIAgents::Tools::VectorRAGTool.new(
  vector_store: knowledge_store,
  name: "knowledge_rag",
  description: "Advanced retrieval-augmented generation for comprehensive answers"
)

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

rag_agent.add_tool(rag_tool)
rag_runner = OpenAIAgents::Runner.new(agent: rag_agent)

result = rag_runner.run(<<~PROMPT)
  I'm evaluating your company for a potential partnership. Can you provide a comprehensive overview including your products, pricing, support, and company background?
PROMPT
puts result.messages.last[:content]

# Export knowledge base
puts "\n10. Exporting knowledge base..."
export_path = "tmp/knowledge_base_export.json"
FileUtils.mkdir_p("tmp")
knowledge_store.export(export_path)
puts "Knowledge base exported to: #{export_path}"

# Show what's in the export
export_data = JSON.parse(File.read(export_path))
puts "Export contains #{export_data['records'].values.map(&:size).sum} total documents across #{export_data['records'].size} namespaces"

# Clean up
FileUtils.rm_f(export_path)

puts "\nExample completed!"