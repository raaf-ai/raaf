# frozen_string_literal: true

module RAAF
  module Eval
    module Evaluators
      module LLM
        ##
        # Contextual Relevancy Evaluator
        #
        # Evaluates how relevant the retrieved context is to the input query in RAG systems.
        # Measures whether the retrieved documents/passages actually help answer the query.
        #
        # Fields required:
        # - :query - The user's input question or search query
        # - :context - Retrieved documents/passages (can be array or string)
        #
        # Example usage:
        #   evaluator = ContextualRelevancy.new
        #   result = evaluator.evaluate(field_context)
        #   # => { label: "good", score: 0.85, ... }
        class ContextualRelevancy < BaseEvaluator
          evaluator_name :contextual_relevancy

          DEFAULT_GOOD_THRESHOLD = 0.75
          DEFAULT_AVERAGE_THRESHOLD = 0.50

          ##
          # Evaluate contextual relevancy
          #
          # @param field_context [FieldContext] Contains :query and :context fields
          # @param options [Hash] Optional evaluation parameters
          # @option options [Float] :good_threshold Override good threshold
          # @option options [Float] :average_threshold Override average threshold
          # @option options [String] :model Optional model override for LLM judge
          #
          # @return [Hash] Evaluation result with score, label, and details
          def evaluate(field_context, **options)
            good_threshold, average_threshold = resolve_thresholds(options)

            # Extract query and context from field_context
            query = extract_query(field_context)
            context = extract_context(field_context)

            # Validate required fields
            raise ArgumentError, "Query cannot be empty" if query.nil? || query.strip.empty?
            raise ArgumentError, "Context cannot be empty" if context.nil? || context.strip.empty?

            # Perform LLM-based relevancy evaluation
            score, reasoning = llm_judge_relevancy(
              query: query,
              context: context,
              model: options[:model]
            )

            # Determine label based on score
            label = calculate_label(score,
                                   good_threshold: good_threshold,
                                   average_threshold: average_threshold)

            # Build result hash
            build_result(score, label, good_threshold, average_threshold,
              evaluated_field: field_context.field_name.to_sym,
              method: "contextual_relevancy",
              query: query,
              context_preview: truncate_text(context, 200),
              context_length: context.length,
              relevancy_reasoning: reasoning,
              evaluation_note: relevancy_note(score, good_threshold, average_threshold)
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
          # LLM-based relevancy judgment
          # TODO: Replace with actual LLM API call
          def llm_judge_relevancy(query:, context:, model: nil)
            # MOCK IMPLEMENTATION - Replace with actual LLM call
            # For now, use heuristic scoring based on keyword overlap

            score = calculate_mock_relevancy_score(query, context)
            reasoning = generate_mock_reasoning(query, context, score)

            [score, reasoning]
          end

          ##
          # Calculate mock relevancy score based on keyword overlap
          # TODO: Replace with actual LLM evaluation
          def calculate_mock_relevancy_score(query, context)
            # Normalize and tokenize
            query_words = tokenize(query.downcase)
            context_words = tokenize(context.downcase)

            return 0.0 if query_words.empty?

            # Filter out stop words from query (common words that don't indicate relevancy)
            stop_words = %w[what is are the a an how do does why when where which who]
            meaningful_query_words = query_words - stop_words

            # Use meaningful words if available, otherwise all words
            keywords_to_match = meaningful_query_words.any? ? meaningful_query_words : query_words

            # Calculate keyword overlap
            overlap = (keywords_to_match & context_words).size
            query_coverage = overlap.to_f / [keywords_to_match.size, 1].max

            # Adjust score based on coverage
            # High coverage (>=60%) = good relevancy (accounts for stop words)
            # Medium coverage (30-60%) = average relevancy
            # Low coverage (<30%) = poor relevancy
            case query_coverage
            when 0.6..Float::INFINITY
              0.80 + (rand * 0.20) # 0.80 - 1.0
            when 0.3..0.6
              0.55 + (rand * 0.20) # 0.55 - 0.75
            else
              0.2 + (rand * 0.30) # 0.20 - 0.50
            end
          end

          ##
          # Generate mock reasoning explanation
          # TODO: Replace with actual LLM-generated reasoning
          def generate_mock_reasoning(query, context, score)
            query_words = tokenize(query.downcase)
            context_words = tokenize(context.downcase)

            # Filter stop words
            stop_words = %w[what is are the a an how do does why when where which who]
            meaningful_query_words = query_words - stop_words
            keywords_to_match = meaningful_query_words.any? ? meaningful_query_words : query_words

            overlap = (keywords_to_match & context_words)
            coverage = overlap.size.to_f / [keywords_to_match.size, 1].max

            reasoning = "Contextual Relevancy Analysis:\n\n"
            reasoning += "Query: \"#{truncate_text(query, 100)}\"\n"
            reasoning += "Context: \"#{truncate_text(context, 150)}...\"\n\n"
            reasoning += "Meaningful Keywords: #{keywords_to_match.join(', ')}\n"
            reasoning += "Keyword Coverage: #{(coverage * 100).round}% (#{overlap.size}/#{keywords_to_match.size} keywords found)\n"
            reasoning += "Overlapping Terms: #{overlap.take(5).join(', ')}#{overlap.size > 5 ? '...' : ''}\n\n"

            case score
            when 0.75..Float::INFINITY
              reasoning += "Assessment: HIGH RELEVANCY - The retrieved context directly addresses the query intent. "
              reasoning += "Most meaningful query keywords are present, suggesting the context is highly relevant."
            when 0.50..0.75
              reasoning += "Assessment: MODERATE RELEVANCY - The context has some relevance to the query. "
              reasoning += "Some meaningful keywords are present, but coverage could be better."
            else
              reasoning += "Assessment: LOW RELEVANCY - The context appears weakly related to the query. "
              reasoning += "Few meaningful keywords are present, suggesting poor retrieval quality."
            end

            reasoning
          end

          ##
          # Generate evaluation note based on score
          def relevancy_note(score, good_threshold, average_threshold)
            return "Retrieved context is highly relevant to the query" if score >= good_threshold
            return "Retrieved context has moderate relevance to the query" if score >= average_threshold

            "Retrieved context has low relevance to the query - consider improving retrieval strategy"
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
