# frozen_string_literal: true

begin
  require_relative "../vector_store"
  require_relative "../../../../core/lib/raaf/utils"
rescue LoadError
  # Vector store not available, tool will be disabled
end

module RAAF
  module Tools
    # Tool for searching in vector stores
    class VectorSearchTool
      attr_reader :name, :description, :vector_store

      def initialize(vector_store:, name: "vector_search", description: nil)
        @vector_store = vector_store
        @name = name
        @description = description || "Search for similar documents in #{vector_store.name}"
      end

      def to_tool_definition
        {
          type: "function",
          function: {
            name: @name,
            description: @description,
            parameters: {
              type: "object",
              properties: {
                query: {
                  type: "string",
                  description: "The search query"
                },
                k: {
                  type: "integer",
                  description: "Number of results to return (default: 5)",
                  default: 5
                },
                namespace: {
                  type: "string",
                  description: "Namespace to search in"
                },
                filter: {
                  type: "object",
                  description: "Metadata filters to apply",
                  additionalProperties: true
                }
              },
              required: ["query"]
            }
          }
        }
      end

      def call(arguments)
        # Convert to indifferent access for consistent key handling
        args = Utils.indifferent_access(arguments)
        
        query = args[:query]
        k = args[:k] || 5
        namespace = args[:namespace]
        filter = args[:filter]

        results = @vector_store.search(
          query,
          k: k,
          namespace: namespace,
          filter: filter,
          include_scores: true
        )

        format_results(results)
      rescue StandardError => e
        { error: "Vector search failed: #{e.message}" }
      end

      private

      def format_results(results)
        if results.empty?
          "No relevant documents found."
        else
          formatted = results.map.with_index do |result, idx|
            score = result[:score] ? " (score: #{result[:score].round(3)})" : ""
            metadata = result[:metadata].empty? ? "" : " [#{format_metadata(result[:metadata])}]"

            "#{idx + 1}. #{result[:content].strip}#{score}#{metadata}"
          end.join("\n\n")

          "Found #{results.size} relevant documents:\n\n#{formatted}"
        end
      end

      def format_metadata(metadata)
        metadata.map { |k, v| "#{k}: #{v}" }.join(", ")
      end
    end

    # Tool for adding documents to vector store
    class VectorIndexTool
      attr_reader :name, :description, :vector_store

      def initialize(vector_store:, name: "vector_index", description: nil)
        @vector_store = vector_store
        @name = name
        @description = description || "Add documents to #{vector_store.name} for later retrieval"
      end

      def to_tool_definition
        {
          type: "function",
          function: {
            name: @name,
            description: @description,
            parameters: {
              type: "object",
              properties: {
                documents: {
                  type: "array",
                  description: "Documents to index",
                  items: {
                    oneOf: [
                      { type: "string" },
                      {
                        type: "object",
                        properties: {
                          content: { type: "string" },
                          metadata: {
                            type: "object",
                            additionalProperties: true
                          }
                        },
                        required: ["content"]
                      }
                    ]
                  }
                },
                namespace: {
                  type: "string",
                  description: "Namespace to store documents in"
                }
              },
              required: ["documents"]
            }
          }
        }
      end

      def call(arguments)
        # Convert to indifferent access for consistent key handling
        args = Utils.indifferent_access(arguments)
        
        documents = args[:documents]
        namespace = args[:namespace]

        # Normalize documents
        normalized_docs = documents.map do |doc|
          if doc.is_a?(String)
            { content: doc }
          else
            doc
          end
        end

        # Add to vector store
        ids = @vector_store.add_documents(normalized_docs, namespace: namespace)

        "Successfully indexed #{ids.length} documents. Document IDs: #{ids.join(", ")}"
      rescue StandardError => e
        { error: "Vector indexing failed: #{e.message}" }
      end
    end

    # Tool for managing vector store
    class VectorManagementTool
      attr_reader :name, :description, :vector_store

      def initialize(vector_store:, name: "vector_manage", description: nil)
        @vector_store = vector_store
        @name = name
        @description = description || "Manage documents in #{vector_store.name}"
      end

      def to_tool_definition
        {
          type: "function",
          function: {
            name: @name,
            description: @description,
            parameters: {
              type: "object",
              properties: {
                action: {
                  type: "string",
                  description: "Action to perform",
                  enum: %w[get update delete stats namespaces clear]
                },
                id: {
                  type: "string",
                  description: "Document ID (for get, update, delete)"
                },
                ids: {
                  type: "array",
                  description: "Document IDs (for bulk delete)",
                  items: { type: "string" }
                },
                namespace: {
                  type: "string",
                  description: "Namespace to operate in"
                },
                content: {
                  type: "string",
                  description: "New content (for update)"
                },
                metadata: {
                  type: "object",
                  description: "New metadata (for update)",
                  additionalProperties: true
                },
                filter: {
                  type: "object",
                  description: "Filter for delete operation",
                  additionalProperties: true
                }
              },
              required: ["action"]
            }
          }
        }
      end

      def call(arguments)
        # Convert to indifferent access for consistent key handling
        args = Utils.indifferent_access(arguments)
        
        action = args[:action]

        case action
        when "get"
          get_document(args)
        when "update"
          update_document(args)
        when "delete"
          delete_documents(args)
        when "stats"
          get_stats(args)
        when "namespaces"
          list_namespaces
        when "clear"
          clear_namespace(args)
        else
          { error: "Unknown action: #{action}" }
        end
      rescue StandardError => e
        { error: "Vector management failed: #{e.message}" }
      end

      private

      def get_document(args)
        id = args[:id]
        namespace = args[:namespace]

        return { error: "Document ID required" } unless id

        doc = @vector_store.get_document(id, namespace: namespace)

        if doc
          "Document #{id}:\nContent: #{doc[:content]}\nMetadata: #{doc[:metadata]}"
        else
          "Document #{id} not found"
        end
      end

      def update_document(args)
        id = args[:id]
        namespace = args[:namespace]
        content = args[:content]
        metadata = args[:metadata]

        return { error: "Document ID required" } unless id
        return { error: "Content or metadata required" } unless content || metadata

        success = @vector_store.update_document(
          id,
          content: content,
          metadata: metadata,
          namespace: namespace
        )

        if success
          "Document #{id} updated successfully"
        else
          "Failed to update document #{id}"
        end
      end

      def delete_documents(args)
        id = args[:id]
        ids = args[:ids]
        filter = args[:filter]
        namespace = args[:namespace]

        ids = [id] if id

        count = @vector_store.delete_documents(
          ids: ids,
          filter: filter,
          namespace: namespace
        )

        "Deleted #{count} documents"
      end

      def get_stats(args)
        namespace = args[:namespace] || args["namespace"]
        stats = @vector_store.stats(namespace: namespace)

        lines = ["Vector store statistics:"]
        stats.each do |ns, count|
          lines << "  #{ns}: #{count} documents"
        end

        lines.join("\n")
      end

      def list_namespaces
        namespaces = @vector_store.namespaces

        if namespaces.empty?
          "No namespaces found"
        else
          "Namespaces: #{namespaces.join(", ")}"
        end
      end

      def clear_namespace(args)
        namespace = args[:namespace] || args["namespace"]

        @vector_store.clear(namespace: namespace)

        if namespace
          "Cleared namespace: #{namespace}"
        else
          "Cleared all namespaces"
        end
      end
    end

    # Combined vector RAG tool
    class VectorRAGTool
      attr_reader :name, :description, :vector_store

      def initialize(vector_store:, name: "vector_rag", description: nil)
        @vector_store = vector_store
        @name = name
        @description = description || "Retrieval-augmented generation using #{vector_store.name}"

        # Create sub-tools
        @search_tool = VectorSearchTool.new(vector_store: vector_store)
        @index_tool = VectorIndexTool.new(vector_store: vector_store)
        @manage_tool = VectorManagementTool.new(vector_store: vector_store)
      end

      def to_tool_definition
        {
          type: "function",
          function: {
            name: @name,
            description: @description,
            parameters: {
              type: "object",
              properties: {
                operation: {
                  type: "string",
                  description: "Operation to perform",
                  enum: %w[search index manage]
                },
                arguments: {
                  type: "object",
                  description: "Arguments for the operation",
                  additionalProperties: true
                }
              },
              required: %w[operation arguments]
            }
          }
        }
      end

      def call(arguments)
        # Convert to indifferent access for consistent key handling
        args = Utils.indifferent_access(arguments)
        
        operation = args[:operation]
        op_args = args[:arguments] || {}

        case operation
        when "search"
          @search_tool.call(op_args)
        when "index"
          @index_tool.call(op_args)
        when "manage"
          @manage_tool.call(op_args)
        else
          { error: "Unknown operation: #{operation}" }
        end
      end
    end
  end
end
