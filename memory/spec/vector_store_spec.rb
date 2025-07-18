# frozen_string_literal: true

require "spec_helper"
require "openai_agents/vector_store"

RSpec.describe RAAF::VectorStore do
  let(:store) { described_class.new(name: "test_store", dimensions: 10) }
  
  describe "#initialize" do
    it "creates a new vector store" do
      expect(store.name).to eq("test_store")
      expect(store.dimensions).to eq(10)
    end
    
    it "uses default dimensions" do
      default_store = described_class.new(name: "default")
      expect(default_store.dimensions).to eq(1536)
    end
  end
  
  describe "#add_documents" do
    it "adds string documents" do
      ids = store.add_documents(["Hello world", "Test document"])
      
      expect(ids).to be_an(Array)
      expect(ids.length).to eq(2)
    end
    
    it "adds documents with metadata" do
      docs = [
        { content: "Document 1", metadata: { category: "test" } },
        { content: "Document 2", metadata: { category: "example" } }
      ]
      
      ids = store.add_documents(docs)
      expect(ids.length).to eq(2)
      
      # Verify document can be retrieved
      doc = store.get_document(ids[0])
      expect(doc[:content]).to eq("Document 1")
      expect(doc[:metadata][:category]).to eq("test")
    end
    
    it "adds documents to namespace" do
      ids = store.add_documents(["Namespace doc"], namespace: "custom")
      
      doc = store.get_document(ids[0], namespace: "custom")
      expect(doc[:content]).to eq("Namespace doc")
      
      # Should not find in default namespace
      doc = store.get_document(ids[0])
      expect(doc).to be_nil
    end
  end
  
  describe "#search" do
    before do
      store.add_documents([
                            { content: "Ruby programming language", metadata: { type: "language" } },
                            { content: "Python programming language", metadata: { type: "language" } },
                            { content: "JavaScript for web development", metadata: { type: "language" } },
                            { content: "Coffee is a beverage", metadata: { type: "drink" } }
                          ])
    end
    
    it "searches for similar documents" do
      results = store.search("programming languages", k: 3)
      
      expect(results.length).to eq(3)
      expect(results[0][:content]).to include("programming")
    end
    
    it "includes scores when requested" do
      results = store.search("Ruby", k: 2, include_scores: true)
      
      expect(results[0]).to have_key(:score)
      expect(results[0][:score]).to be_between(-1, 1)
    end
    
    it "filters by metadata" do
      results = store.search("anything", k: 10, filter: { type: "language" })
      
      expect(results.length).to eq(3)
      expect(results.all? { |r| r[:metadata][:type] == "language" }).to be true
    end
    
    it "searches within namespace" do
      store.add_documents(["Special document"], namespace: "special")
      
      results = store.search("document", namespace: "special")
      expect(results.length).to eq(1)
      expect(results[0][:content]).to eq("Special document")
    end
  end
  
  describe "#update_document" do
    it "updates document content" do
      ids = store.add_documents(["Original content"])
      id = ids[0]
      
      store.update_document(id, content: "Updated content")
      
      doc = store.get_document(id)
      expect(doc[:content]).to eq("Updated content")
    end
    
    it "updates document metadata" do
      ids = store.add_documents([{ content: "Test", metadata: { version: 1 } }])
      id = ids[0]
      
      store.update_document(id, metadata: { version: 2, updated: true })
      
      doc = store.get_document(id)
      expect(doc[:metadata][:version]).to eq(2)
      expect(doc[:metadata][:updated]).to be true
    end
  end
  
  describe "#delete_documents" do
    before do
      store.add_documents([
                            { content: "Doc 1", metadata: { keep: false } },
                            { content: "Doc 2", metadata: { keep: true } },
                            { content: "Doc 3", metadata: { keep: false } }
                          ])
    end
    
    it "deletes by IDs" do
      all_docs = store.search("Doc", k: 10)
      ids_to_delete = all_docs.select { |d| d[:metadata][:keep] == false }.map { |d| d[:id] }
      
      count = store.delete_documents(ids: ids_to_delete)
      expect(count).to eq(2)
      
      remaining = store.search("Doc", k: 10)
      expect(remaining.length).to eq(1)
      expect(remaining[0][:content]).to eq("Doc 2")
    end
    
    it "deletes by filter" do
      count = store.delete_documents(filter: { keep: false })
      expect(count).to eq(2)
      
      remaining = store.search("Doc", k: 10)
      expect(remaining.length).to eq(1)
    end
  end
  
  describe "#namespaces" do
    it "lists all namespaces" do
      store.add_documents(["Doc 1"])
      store.add_documents(["Doc 2"], namespace: "namespace1")
      store.add_documents(["Doc 3"], namespace: "namespace2")
      
      namespaces = store.namespaces
      expect(namespaces).to include("default", "namespace1", "namespace2")
    end
  end
  
  describe "#stats" do
    it "returns statistics for all namespaces" do
      store.add_documents(["Doc 1", "Doc 2"])
      store.add_documents(["Doc 3"], namespace: "other")
      
      stats = store.stats
      expect(stats["default"]).to eq(2)
      expect(stats["other"]).to eq(1)
    end
    
    it "returns statistics for specific namespace" do
      store.add_documents(["Doc 1", "Doc 2"])
      store.add_documents(["Doc 3"], namespace: "other")
      
      stats = store.stats(namespace: "default")
      expect(stats["default"]).to eq(2)
      expect(stats).not_to have_key("other")
    end
  end
  
  describe "#clear" do
    before do
      store.add_documents(["Doc 1", "Doc 2"])
      store.add_documents(["Doc 3"], namespace: "other")
    end
    
    it "clears specific namespace" do
      store.clear(namespace: "other")
      
      stats = store.stats
      expect(stats["default"]).to eq(2)
      expect(stats["other"]).to be_nil
    end
    
    it "clears all namespaces" do
      store.clear
      
      stats = store.stats
      expect(stats).to be_empty
    end
  end
  
  describe "#export and #import" do
    it "exports and imports store data" do
      # Add some documents
      store.add_documents([
                            { content: "Doc 1", metadata: { id: 1 } },
                            { content: "Doc 2", metadata: { id: 2 } }
                          ])
      store.add_documents(["Doc 3"], namespace: "other")
      
      # Export
      export_path = "tmp/vector_store_export.json"
      FileUtils.mkdir_p("tmp")
      store.export(export_path)
      
      # Create new store and import
      new_store = described_class.new(name: "imported", dimensions: 10)
      new_store.import(export_path)
      
      # Verify data
      expect(new_store.name).to eq("test_store")
      expect(new_store.stats).to eq(store.stats)
      
      results = new_store.search("Doc", k: 10)
      expect(results.length).to eq(2)
      
      # Clean up
      FileUtils.rm_f(export_path)
    end
  end
end

RSpec.describe RAAF::Adapters::InMemoryAdapter do
  let(:adapter) { described_class.new }
  
  before do
    adapter.initialize_store("test", 10)
  end
  
  describe "#add_records and #search" do
    it "adds and searches records" do
      records = [
        {
          id: "1",
          content: "Test content",
          embedding: [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0],
          metadata: { category: "test" }
        }
      ]
      
      adapter.add_records(records)
      
      query_embedding = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 0.9]
      results = adapter.search(query_embedding, k: 1)
      
      expect(results.length).to eq(1)
      expect(results[0][:id]).to eq("1")
      expect(results[0][:score]).to be > 0.9
    end
  end
  
  describe "cosine similarity" do
    it "calculates similarity correctly" do
      records = [
        {
          id: "identical",
          content: "Identical",
          embedding: [1.0, 0.0, 0.0],
          metadata: {}
        },
        {
          id: "orthogonal",
          content: "Orthogonal",
          embedding: [0.0, 1.0, 0.0],
          metadata: {}
        },
        {
          id: "opposite",
          content: "Opposite",
          embedding: [-1.0, 0.0, 0.0],
          metadata: {}
        }
      ]
      
      adapter.add_records(records)
      
      query = [1.0, 0.0, 0.0]
      results = adapter.search(query, k: 3)
      
      # Should be ordered by similarity
      expect(results[0][:id]).to eq("identical")
      expect(results[0][:score]).to be_within(0.001).of(1.0)
      
      expect(results[1][:id]).to eq("orthogonal")
      expect(results[1][:score]).to be_within(0.001).of(0.0)
      
      expect(results[2][:id]).to eq("opposite")
      expect(results[2][:score]).to be_within(0.001).of(-1.0)
    end
  end
  
  describe "filtering" do
    before do
      adapter.add_records([
                            { id: "1", content: "A", embedding: [1, 0], metadata: { type: "doc", status: "active" } },
                            { id: "2", content: "B", embedding: [0, 1], metadata: { type: "doc", status: "archived" } },
                            { id: "3", content: "C", embedding: [1, 1], metadata: { type: "image", status: "active" } }
                          ])
    end
    
    it "filters by exact match" do
      results = adapter.search([1, 0], k: 10, filter: { type: "doc" })
      expect(results.length).to eq(2)
      expect(results.map { |r| r[:id] }).to contain_exactly("1", "2")
    end
    
    it "filters by regex" do
      results = adapter.search([1, 0], k: 10, filter: { status: /^act/ })
      expect(results.length).to eq(2)
      expect(results.map { |r| r[:id] }).to contain_exactly("1", "3")
    end
    
    it "filters by array inclusion" do
      results = adapter.search([1, 0], k: 10, filter: { type: %w[doc video] })
      expect(results.length).to eq(2)
      expect(results.map { |r| r[:id] }).to contain_exactly("1", "2")
    end
  end
end