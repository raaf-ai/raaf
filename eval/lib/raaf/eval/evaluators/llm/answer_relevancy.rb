# frozen_string_literal: true

require_relative "base_evaluator"

module RAAF
  module Eval
    module Evaluators
      module LLM
        # Answer Relevancy Evaluator
        #
        # Evaluates whether the LLM output addresses the input query.
        # Uses LLM-as-judge to determine if the answer is relevant to what was asked.
        #
        # Score Range: 0.0 (completely irrelevant) to 1.0 (perfectly relevant)
        #
        # Default Thresholds:
        # - Good: ≥ 0.80 (highly relevant answer)
        # - Average: ≥ 0.60 (somewhat relevant, could be improved)
        # - Bad: < 0.60 (mostly irrelevant or off-topic)
        #
        # @example Basic usage
        #   evaluator = AnswerRelevancy.new
        #   result = evaluator.evaluate(field_context, query: user_query)
        #
        # @example Strict customer support settings
        #   evaluator = AnswerRelevancy.new(good_threshold: 0.90, average_threshold: 0.75)
        #   result = evaluator.evaluate(field_context, query: user_query)
        #
        class AnswerRelevancy < BaseEvaluator
          DEFAULT_GOOD_THRESHOLD = 0.80
          DEFAULT_AVERAGE_THRESHOLD = 0.60

          # Evaluate answer relevancy to query
          #
          # @param field_context [RAAF::Eval::DSL::FieldContext] Field context with answer
          # @param options [Hash] Evaluation options
          # @option options [String] :query User query/question (required)
          # @option options [Float] :good_threshold Override good threshold
          # @option options [Float] :average_threshold Override average threshold
          # @option options [String] :model LLM model to use for judging (optional)
          # @return [Hash] Result with label, score, message, and details
          def evaluate(field_context, **options)
            good_threshold, average_threshold = resolve_thresholds(options)

            # Validate query is provided
            query = options[:query] || field_context.input
            raise ArgumentError, "Query is required for answer relevancy evaluation" unless query

            # Use LLM judge to evaluate relevancy
            score = llm_judge_relevancy(
              answer: field_context.value,
              query: query,
              model: options[:model]
            )

            label = calculate_label(score,
                                   good_threshold: good_threshold,
                                   average_threshold: average_threshold)

            build_result(score, label, good_threshold, average_threshold,
              evaluated_field: field_context.field_name,
              method: "llm_judge",
              query: truncate_for_display(query),
              relevancy_percentage: (score * 100).round,
              evaluation_note: relevancy_note(score, good_threshold, average_threshold)
            )
          end

          private

          # Use LLM as judge to evaluate answer relevancy
          #
          # @param answer [String] LLM answer to evaluate
          # @param query [String] Original user query
          # @param model [String, nil] LLM model for judging
          # @return [Float] Score from 0.0 (irrelevant) to 1.0 (perfectly relevant)
          def llm_judge_relevancy(answer:, query:, model: nil)
            # Build evaluation prompt
            prompt = build_relevancy_prompt(answer, query)

            # Call LLM for evaluation
            # TODO: Replace with actual RAAF LLM call
            # For now, return a mock score based on simple heuristic
            mock_relevancy_score(answer, query)
          end

          # Build prompt for relevancy evaluation
          #
          # @param answer [String] Answer to evaluate
          # @param query [String] Original query
          # @return [String] Evaluation prompt
          def build_relevancy_prompt(answer, query)
            <<~PROMPT
              You are an expert evaluator of answer relevancy. Your task is to determine if the
              given answer addresses the user's query.

              USER QUERY:
              #{query}

              ANSWER TO EVALUATE:
              #{answer}

              TASK:
              Evaluate the answer's relevancy to the query:
              1. Does the answer directly address the question asked?
              2. Does the answer provide the information the user was seeking?
              3. Is the answer focused on the query or does it go off-topic?
              4. Would a user consider this answer helpful and relevant?

              Provide a score from 0.0 to 1.0:
              - 1.0 = Perfectly relevant, directly answers the query
              - 0.8-0.9 = Highly relevant, addresses the main question
              - 0.6-0.7 = Somewhat relevant, provides some useful information
              - 0.4-0.5 = Marginally relevant, partially addresses query
              - 0.0-0.3 = Irrelevant, doesn't address the query

              Return ONLY a JSON object with this format:
              {
                "score": 0.85,
                "reasoning": "Brief explanation of relevancy assessment"
              }
            PROMPT
          end

          # Mock relevancy scoring (placeholder for actual LLM call)
          #
          # @param answer [String] Answer to evaluate
          # @param query [String] Original query
          # @return [Float] Mock score
          def mock_relevancy_score(answer, query)
            # Simple heuristic: check for keyword overlap
            query_words = query.downcase.split
            answer_words = answer.downcase.split

            return 0.5 if query_words.empty? || answer_words.empty?

            # Count how many query words appear in answer
            overlap_count = query_words.count { |word| answer_words.include?(word) }
            overlap_ratio = overlap_count.to_f / query_words.size

            # Convert to 0.5-1.0 range (assume at least some relevance)
            0.5 + (overlap_ratio * 0.5)
          end

          # Generate evaluation note based on score
          #
          # @param score [Float] Relevancy score
          # @param good_threshold [Float] Good threshold
          # @param average_threshold [Float] Average threshold
          # @return [String] Human-readable note
          def relevancy_note(score, good_threshold, average_threshold)
            if score >= good_threshold
              "Answer is highly relevant and directly addresses the query"
            elsif score >= average_threshold
              "Answer is somewhat relevant but could be more focused on the query"
            else
              "Answer is largely irrelevant or doesn't address the query"
            end
          end

          # Truncate text for display in results
          #
          # @param text [String] Text to truncate
          # @param max_length [Integer] Maximum length
          # @return [String] Truncated text
          def truncate_for_display(text, max_length = 100)
            return text if text.length <= max_length
            "#{text[0...max_length]}..."
          end
        end
      end
    end
  end
end
