# frozen_string_literal: true

module RAAF
  module Eval
    module Evaluators
      module LLM
        ##
        # Contextual Precision Evaluator
        #
        # Evaluates the precision of retrieved context in RAG systems - what proportion
        # of retrieved documents are actually relevant to the query.
        #
        # Fields required:
        # - :query - The user's input question or search query
        # - :context - Retrieved documents/passages (can be array or string)
        #
        # Example usage:
        #   evaluator = ContextualPrecision.new
        #   result = evaluator.evaluate(field_context)
        #   # => { label: "good", score: 0.85, ... }
        class ContextualPrecision < BaseEvaluator
          evaluator_name :contextual_precision

          DEFAULT_GOOD_THRESHOLD = 0.75
          DEFAULT_AVERAGE_THRESHOLD = 0.50
          RELEVANCE_THRESHOLD = 0.60  # Threshold for considering a document relevant

          ##
          # Evaluate contextual precision
          #
          # @param field_context [FieldContext] Contains :query and :context fields
          # @param options [Hash] Optional evaluation parameters
          # @option options [Float] :good_threshold Override good threshold
          # @option options [Float] :average_threshold Override average threshold
          # @option options [Float] :relevance_threshold Override relevance threshold for documents
          # @option options [String] :model Optional model override for LLM judge
          #
          # @return [Hash] Evaluation result with score, label, and details
          def evaluate(field_context, **options)
            good_threshold, average_threshold = resolve_thresholds(options)
            relevance_threshold = options[:relevance_threshold] || RELEVANCE_THRESHOLD

            # Extract query and context from field_context
            query = extract_query(field_context)
            context = extract_context(field_context)

            # Validate required fields
            raise ArgumentError, "Query cannot be empty" if query.nil? || query.strip.empty?
            raise ArgumentError, "Context cannot be empty" if context.nil? || context.strip.empty?

            # Split context into documents
            documents = split_into_documents(context)
            raise ArgumentError, "At least one document required" if documents.empty?

            # Perform precision calculation
            score, reasoning, doc_relevance = calculate_precision(
              query: query,
              documents: documents,
              relevance_threshold: relevance_threshold,
              model: options[:model]
            )

            # Determine label based on score
            label = calculate_label(score,
                                   good_threshold: good_threshold,
                                   average_threshold: average_threshold)

            # Build result hash
            build_result(score, label, good_threshold, average_threshold,
              evaluated_field: field_context.field_name.to_sym,
              method: "contextual_precision",
              query: query,
              document_count: documents.length,
              relevant_count: doc_relevance.count { |rel| rel[:relevant] },
              irrelevant_count: doc_relevance.count { |rel| !rel[:relevant] },
              document_relevance: doc_relevance,
              precision_reasoning: reasoning,
              relevance_threshold: relevance_threshold,
              evaluation_note: precision_note(score, good_threshold, average_threshold)
            )
          end

          private

          ##
          # Extract query from field context
          # Supports both direct :query field and nested structures
          def extract_query(field_context)
            value = field_context.value

            case value
            when Hash
              value[:query] || value["query"] || value[:input] || value["input"]
            when String
              # If field_context is for query field directly
              field_context.field_name.to_s == "query" ? value : nil
            else
              nil
            end
          end

          ##
          # Extract context from field context
          # Handles arrays of documents and single strings
          def extract_context(field_context)
            value = field_context.value

            case value
            when Hash
              ctx = value[:context] || value["context"] || value[:retrieved] || value["retrieved"]
              format_context(ctx)
            when Array
              # Array of documents - join them
              value.map { |doc| doc.is_a?(Hash) ? (doc[:content] || doc["content"] || doc.to_s) : doc.to_s }.join("\n\n")
            when String
              # If field_context is for context field directly
              field_context.field_name.to_s == "context" ? value : nil
            else
              nil
            end
          end

          ##
          # Format context into evaluable string
          def format_context(context)
            case context
            when Array
              context.map { |doc| doc.is_a?(Hash) ? (doc[:content] || doc["content"] || doc.to_s) : doc.to_s }.join("\n\n")
            when String
              context
            when Hash
              context[:content] || context["content"] || context.to_s
            else
              context.to_s
            end
          end

          ##
          # Split context into documents
          # If context is already array-like (contains \n\n), split it
          # Otherwise treat as single document
          def split_into_documents(context)
            # Split by double newlines (paragraph separator)
            docs = context.split(/\n\n+/).map(&:strip).reject(&:empty?)

            # If no splits found, treat entire context as single document
            docs.empty? ? [context.strip] : docs
          end

          ##
          # Calculate precision score
          # TODO: Replace with actual LLM call
          def calculate_precision(query:, documents:, relevance_threshold:, model: nil)
            # MOCK IMPLEMENTATION - Replace with actual LLM call

            # Calculate relevance for each document
            doc_relevance = documents.map.with_index do |doc, idx|
              relevance_score = calculate_document_relevance(query, doc)
              relevant = relevance_score >= relevance_threshold

              {
                index: idx,
                content: truncate_text(doc, 100),
                relevance_score: relevance_score.round(2),
                relevant: relevant
              }
            end

            # Calculate precision: relevant_docs / total_docs
            relevant_count = doc_relevance.count { |dr| dr[:relevant] }
            precision = relevant_count.to_f / documents.length

            reasoning = generate_reasoning(query, documents, doc_relevance, precision)

            [precision, reasoning, doc_relevance]
          end

          ##
          # Calculate document relevance to query using keyword overlap
          # TODO: Replace with actual LLM evaluation
          def calculate_document_relevance(query, document)
            query_words = tokenize(query.downcase)
            doc_words = tokenize(document.downcase)

            # Filter stop words
            stop_words = %w[what is are the a an how do does why when where which who]
            meaningful_query_words = query_words - stop_words
            keywords_to_match = meaningful_query_words.any? ? meaningful_query_words : query_words

            return 0.0 if keywords_to_match.empty?

            # Calculate keyword overlap
            overlap = (keywords_to_match & doc_words).size
            coverage = overlap.to_f / [keywords_to_match.size, 1].max

            # Convert coverage to relevance score with some randomness
            case coverage
            when 0.6..Float::INFINITY
              0.75 + (rand * 0.25)  # 0.75 - 1.0
            when 0.3..0.6
              0.50 + (rand * 0.25)  # 0.50 - 0.75
            else
              0.20 + (rand * 0.30)  # 0.20 - 0.50
            end
          end

          ##
          # Generate reasoning explanation
          # TODO: Replace with actual LLM-generated reasoning
          def generate_reasoning(query, documents, doc_relevance, precision)
            relevant_count = doc_relevance.count { |dr| dr[:relevant] }
            irrelevant_count = documents.length - relevant_count

            reasoning = "Contextual Precision Analysis:\n\n"
            reasoning += "Query: \"#{truncate_text(query, 100)}\"\n"
            reasoning += "Retrieved Documents: #{documents.length}\n"
            reasoning += "Relevant Documents: #{relevant_count}\n"
            reasoning += "Irrelevant Documents: #{irrelevant_count}\n"
            reasoning += "Precision Score: #{(precision * 100).round}%\n\n"

            reasoning += "Document Relevance Breakdown:\n"
            doc_relevance.each do |dr|
              status = dr[:relevant] ? "✓ RELEVANT" : "✗ IRRELEVANT"
              reasoning += "  Doc #{dr[:index] + 1}: #{status} (score: #{dr[:relevance_score]})\n"
              reasoning += "    \"#{dr[:content]}...\"\n"
            end

            reasoning += "\n"
            case precision
            when 0.75..Float::INFINITY
              reasoning += "Assessment: HIGH PRECISION - Most retrieved documents are relevant to the query. "
              reasoning += "The retrieval system is effectively filtering out irrelevant information."
            when 0.50..0.75
              reasoning += "Assessment: MODERATE PRECISION - About half of retrieved documents are relevant. "
              reasoning += "Some irrelevant documents are being retrieved, suggesting room for improvement."
            else
              reasoning += "Assessment: LOW PRECISION - Most retrieved documents are not relevant to the query. "
              reasoning += "The retrieval system needs significant improvement in filtering irrelevant information."
            end

            reasoning
          end

          ##
          # Generate evaluation note based on score
          def precision_note(score, good_threshold, average_threshold)
            return "High precision - most retrieved documents are relevant" if score >= good_threshold
            return "Moderate precision - some irrelevant documents retrieved" if score >= average_threshold

            "Low precision - many irrelevant documents retrieved, need better filtering"
          end

          ##
          # Tokenize text into words (simple implementation)
          def tokenize(text)
            text.scan(/\w+/)
          end

          ##
          # Truncate text to specified length
          def truncate_text(text, max_length)
            return text if text.length <= max_length

            "#{text[0...max_length - 3]}..."
          end
        end
      end
    end
  end
end
