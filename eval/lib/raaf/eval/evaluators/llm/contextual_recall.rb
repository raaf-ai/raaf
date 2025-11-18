# frozen_string_literal: true

module RAAF
  module Eval
    module Evaluators
      module LLM
        ##
        # Contextual Recall Evaluator
        #
        # Evaluates the recall of retrieved context in RAG systems - what proportion
        # of relevant documents were actually retrieved.
        #
        # Fields required:
        # - :query - The user's input question or search query
        # - :retrieved_context - Documents that were retrieved
        # - :available_context OR :ground_truth - All available documents or expected relevant documents
        #
        # Example usage:
        #   evaluator = ContextualRecall.new
        #   result = evaluator.evaluate(field_context)
        #   # => { label: "good", score: 0.85, ... }
        class ContextualRecall < BaseEvaluator
          DEFAULT_GOOD_THRESHOLD = 0.75
          DEFAULT_AVERAGE_THRESHOLD = 0.50
          RELEVANCE_THRESHOLD = 0.60  # Threshold for considering a document relevant

          ##
          # Evaluate contextual recall
          #
          # @param field_context [FieldContext] Contains :query, :retrieved_context, and :available_context fields
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

            # Extract query, retrieved context, and available/ground truth context
            query = extract_query(field_context)
            retrieved_docs = extract_retrieved_context(field_context)
            available_docs = extract_available_context(field_context)

            # Validate required fields
            raise ArgumentError, "Query cannot be empty" if query.nil? || query.strip.empty?
            raise ArgumentError, "Retrieved context cannot be empty" if retrieved_docs.nil? || retrieved_docs.empty?
            raise ArgumentError, "Available/ground truth context cannot be empty" if available_docs.nil? || available_docs.empty?

            # Perform recall calculation
            score, reasoning, doc_analysis = calculate_recall(
              query: query,
              retrieved_docs: retrieved_docs,
              available_docs: available_docs,
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
              method: "contextual_recall",
              query: query,
              retrieved_count: doc_analysis[:retrieved_count],
              available_count: doc_analysis[:available_count],
              relevant_count: doc_analysis[:relevant_count],
              retrieved_relevant_count: doc_analysis[:retrieved_relevant_count],
              missed_relevant_count: doc_analysis[:missed_relevant_count],
              document_analysis: doc_analysis[:documents],
              recall_reasoning: reasoning,
              relevance_threshold: relevance_threshold,
              evaluation_note: recall_note(score, good_threshold, average_threshold)
            )
          end

          private

          ##
          # Extract query from field context
          def extract_query(field_context)
            value = field_context.value

            case value
            when Hash
              value[:query] || value["query"] || value[:input] || value["input"]
            when String
              field_context.field_name.to_s == "query" ? value : nil
            else
              nil
            end
          end

          ##
          # Extract retrieved context (what was actually retrieved)
          def extract_retrieved_context(field_context)
            value = field_context.value

            case value
            when Hash
              ctx = value[:retrieved_context] || value["retrieved_context"] ||
                    value[:retrieved] || value["retrieved"] ||
                    value[:context] || value["context"]
              format_documents(ctx)
            when Array
              value.map { |doc| extract_document_content(doc) }
            when String
              field_context.field_name.to_s == "retrieved_context" ? [value] : nil
            else
              nil
            end
          end

          ##
          # Extract available context (all documents) or ground truth (expected relevant documents)
          def extract_available_context(field_context)
            value = field_context.value

            return nil unless value.is_a?(Hash)

            ctx = value[:available_context] || value["available_context"] ||
                  value[:ground_truth] || value["ground_truth"] ||
                  value[:all_documents] || value["all_documents"]

            format_documents(ctx)
          end

          ##
          # Format documents into array of strings
          def format_documents(context)
            case context
            when Array
              context.map { |doc| extract_document_content(doc) }
            when String
              # Split by double newlines if present
              docs = context.split(/\n\n+/).map(&:strip).reject(&:empty?)
              docs.empty? ? [context.strip] : docs
            when Hash
              [extract_document_content(context)]
            else
              nil
            end
          end

          ##
          # Extract content from document (handle Hash or String)
          def extract_document_content(doc)
            case doc
            when Hash
              doc[:content] || doc["content"] || doc.to_s
            when String
              doc
            else
              doc.to_s
            end
          end

          ##
          # Calculate recall score
          # TODO: Replace with actual LLM call
          def calculate_recall(query:, retrieved_docs:, available_docs:, relevance_threshold:, model: nil)
            # MOCK IMPLEMENTATION - Replace with actual LLM call

            # Identify which available documents are relevant to the query
            relevant_docs_analysis = available_docs.map.with_index do |doc, idx|
              relevance_score = calculate_document_relevance(query, doc)
              relevant = relevance_score >= relevance_threshold
              retrieved = retrieved_docs.any? { |retrieved| documents_match?(doc, retrieved) }

              {
                index: idx,
                content: truncate_text(doc, 100),
                relevance_score: relevance_score.round(2),
                relevant: relevant,
                retrieved: retrieved,
                status: determine_status(relevant, retrieved)
              }
            end

            # Calculate recall metrics
            relevant_docs = relevant_docs_analysis.select { |d| d[:relevant] }
            retrieved_relevant = relevant_docs.count { |d| d[:retrieved] }
            missed_relevant = relevant_docs.count { |d| !d[:retrieved] }

            # Recall = retrieved_relevant / total_relevant
            recall = relevant_docs.empty? ? 1.0 : retrieved_relevant.to_f / relevant_docs.size

            doc_analysis = {
              retrieved_count: retrieved_docs.size,
              available_count: available_docs.size,
              relevant_count: relevant_docs.size,
              retrieved_relevant_count: retrieved_relevant,
              missed_relevant_count: missed_relevant,
              documents: relevant_docs_analysis
            }

            reasoning = generate_reasoning(query, doc_analysis, recall)

            [recall, reasoning, doc_analysis]
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
          # Check if two documents match (fuzzy matching on content)
          def documents_match?(doc1, doc2)
            # Simple content-based matching (trim whitespace and compare)
            normalize_content(doc1) == normalize_content(doc2)
          end

          ##
          # Normalize document content for comparison
          def normalize_content(doc)
            doc.strip.gsub(/\s+/, " ")
          end

          ##
          # Determine status of document (retrieved_relevant, missed_relevant, retrieved_irrelevant, not_retrieved_irrelevant)
          def determine_status(relevant, retrieved)
            if relevant && retrieved
              "retrieved_relevant"
            elsif relevant && !retrieved
              "missed_relevant"
            elsif !relevant && retrieved
              "retrieved_irrelevant"
            else
              "not_retrieved_irrelevant"
            end
          end

          ##
          # Generate reasoning explanation
          # TODO: Replace with actual LLM-generated reasoning
          def generate_reasoning(query, doc_analysis, recall)
            reasoning = "Contextual Recall Analysis:\n\n"
            reasoning += "Query: \"#{truncate_text(query, 100)}\"\n"
            reasoning += "Available Documents: #{doc_analysis[:available_count]}\n"
            reasoning += "Retrieved Documents: #{doc_analysis[:retrieved_count]}\n"
            reasoning += "Relevant Documents (in available): #{doc_analysis[:relevant_count]}\n"
            reasoning += "Relevant Documents Retrieved: #{doc_analysis[:retrieved_relevant_count]}\n"
            reasoning += "Relevant Documents Missed: #{doc_analysis[:missed_relevant_count]}\n"
            reasoning += "Recall Score: #{(recall * 100).round}%\n\n"

            reasoning += "Document Analysis:\n"
            doc_analysis[:documents].each do |doc|
              case doc[:status]
              when "retrieved_relevant"
                reasoning += "  ✓ RETRIEVED & RELEVANT (Doc #{doc[:index] + 1}): #{doc[:relevance_score]}\n"
              when "missed_relevant"
                reasoning += "  ✗ MISSED & RELEVANT (Doc #{doc[:index] + 1}): #{doc[:relevance_score]}\n"
              when "retrieved_irrelevant"
                reasoning += "  ⚠ RETRIEVED & IRRELEVANT (Doc #{doc[:index] + 1}): #{doc[:relevance_score]}\n"
              else
                reasoning += "  - NOT RETRIEVED & IRRELEVANT (Doc #{doc[:index] + 1}): #{doc[:relevance_score]}\n"
              end
              reasoning += "    \"#{doc[:content]}...\"\n"
            end

            reasoning += "\n"
            case recall
            when 0.75..Float::INFINITY
              reasoning += "Assessment: HIGH RECALL - Most relevant documents were successfully retrieved. "
              reasoning += "The retrieval system is capturing the majority of pertinent information."
            when 0.50..0.75
              reasoning += "Assessment: MODERATE RECALL - About half of relevant documents were retrieved. "
              reasoning += "Some important information may have been missed."
            else
              reasoning += "Assessment: LOW RECALL - Many relevant documents were not retrieved. "
              reasoning += "The retrieval system needs improvement to capture more pertinent information."
            end

            reasoning
          end

          ##
          # Generate evaluation note based on score
          def recall_note(score, good_threshold, average_threshold)
            return "High recall - captured most relevant documents" if score >= good_threshold
            return "Moderate recall - missed some relevant documents" if score >= average_threshold

            "Low recall - many relevant documents missed, need broader retrieval"
          end

          ##
          # Tokenize text into words
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
