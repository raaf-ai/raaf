# frozen_string_literal: true

require_relative "base_evaluator"

module RAAF
  module Eval
    module Evaluators
      module LLM
        # Faithfulness Evaluator (RAG-specific)
        #
        # Evaluates whether the LLM output is consistent with the provided retrieval context.
        # Critical for RAG (Retrieval Augmented Generation) applications where outputs must
        # be faithful to the retrieved documents.
        #
        # Score Range: 0.0 (completely unfaithful) to 1.0 (fully faithful)
        #
        # Default Thresholds:
        # - Good: ≥ 0.90 (strictly adheres to context)
        # - Average: ≥ 0.75 (mostly faithful with minor deviations)
        # - Bad: < 0.75 (significant unfaithful content)
        #
        # @example Basic RAG evaluation
        #   evaluator = Faithfulness.new
        #   result = evaluator.evaluate(field_context, retrieval_context: retrieved_docs)
        #
        # @example Strict production RAG settings
        #   evaluator = Faithfulness.new(good_threshold: 0.95, average_threshold: 0.85)
        #   result = evaluator.evaluate(field_context, retrieval_context: retrieved_docs)
        #
        class Faithfulness < BaseEvaluator
          DEFAULT_GOOD_THRESHOLD = 0.90
          DEFAULT_AVERAGE_THRESHOLD = 0.75

          # Evaluate answer faithfulness to retrieval context
          #
          # @param field_context [RAAF::Eval::DSL::FieldContext] Field context with answer
          # @param options [Hash] Evaluation options
          # @option options [String, Array<String>] :retrieval_context Retrieved context (required)
          # @option options [Float] :good_threshold Override good threshold
          # @option options [Float] :average_threshold Override average threshold
          # @option options [String] :model LLM model to use for judging (optional)
          # @return [Hash] Result with label, score, message, and details
          def evaluate(field_context, **options)
            good_threshold, average_threshold = resolve_thresholds(options)

            # Validate retrieval context is provided
            retrieval_context = options[:retrieval_context] || field_context.context
            unless retrieval_context
              raise ArgumentError, "Retrieval context is required for faithfulness evaluation"
            end

            # Use LLM judge to evaluate faithfulness
            score = llm_judge_faithfulness(
              answer: field_context.value,
              context: retrieval_context,
              model: options[:model]
            )

            label = calculate_label(score,
                                   good_threshold: good_threshold,
                                   average_threshold: average_threshold)

            build_result(score, label, good_threshold, average_threshold,
              evaluated_field: field_context.field_name,
              method: "llm_judge_rag",
              context_chunks: context_chunk_count(retrieval_context),
              faithfulness_percentage: (score * 100).round,
              evaluation_note: faithfulness_note(score, good_threshold, average_threshold)
            )
          end

          private

          # Use LLM as judge to evaluate faithfulness
          #
          # @param answer [String] Answer to evaluate
          # @param context [String, Array<String>] Retrieval context
          # @param model [String, nil] LLM model for judging
          # @return [Float] Score from 0.0 (unfaithful) to 1.0 (fully faithful)
          def llm_judge_faithfulness(answer:, context:, model: nil)
            # Normalize context to string
            context_text = context.is_a?(Array) ? context.join("\n\n---\n\n") : context

            # Build evaluation prompt
            prompt = build_faithfulness_prompt(answer, context_text)

            # Call LLM for evaluation
            # TODO: Replace with actual RAAF LLM call
            # For now, return a mock score based on simple heuristic
            mock_faithfulness_score(answer, context_text)
          end

          # Build prompt for faithfulness evaluation
          #
          # @param answer [String] Answer to evaluate
          # @param context [String] Retrieval context
          # @return [String] Evaluation prompt
          def build_faithfulness_prompt(answer, context)
            <<~PROMPT
              You are an expert RAG (Retrieval Augmented Generation) evaluator. Your task is to
              determine if the given answer is faithful to the provided retrieval context.

              RETRIEVAL CONTEXT:
              #{context}

              ANSWER TO EVALUATE:
              #{answer}

              TASK:
              Evaluate the answer's faithfulness to the retrieval context:
              1. Are all claims in the answer supported by information in the context?
              2. Does the answer introduce any information not present in the context?
              3. Does the answer correctly interpret the context without distorting meaning?
              4. Is the answer grounded in the retrieved documents?

              Provide a score from 0.0 to 1.0:
              - 1.0 = Perfectly faithful, every claim supported by context
              - 0.8-0.9 = Highly faithful, minor interpretations but well-grounded
              - 0.7-0.8 = Mostly faithful, some unsupported details
              - 0.5-0.6 = Partially faithful, significant additions to context
              - 0.0-0.4 = Unfaithful, introduces claims not in context

              Return ONLY a JSON object with this format:
              {
                "score": 0.90,
                "reasoning": "Brief explanation of faithfulness assessment"
              }
            PROMPT
          end

          # Mock faithfulness scoring (placeholder for actual LLM call)
          #
          # @param answer [String] Answer to evaluate
          # @param context [String] Retrieval context
          # @return [Float] Mock score
          def mock_faithfulness_score(answer, context)
            # Simple heuristic: check if answer contains context words
            context_words = context.downcase.split.uniq
            answer_words = answer.downcase.split.uniq

            return 0.6 if context_words.empty?

            # Count how many answer words are in context
            grounded_count = answer_words.count { |word| context_words.include?(word) }
            grounded_ratio = answer_words.empty? ? 0 : grounded_count.to_f / answer_words.size

            # Convert to faithfulness score (0.6-1.0 range)
            0.6 + (grounded_ratio * 0.4)
          end

          # Generate evaluation note based on score
          #
          # @param score [Float] Faithfulness score
          # @param good_threshold [Float] Good threshold
          # @param average_threshold [Float] Average threshold
          # @return [String] Human-readable note
          def faithfulness_note(score, good_threshold, average_threshold)
            if score >= good_threshold
              "Answer is highly faithful to the retrieval context"
            elsif score >= average_threshold
              "Answer is mostly faithful but includes some unsupported details"
            else
              "Answer contains significant unfaithful content not supported by context"
            end
          end

          # Count context chunks
          #
          # @param context [String, Array] Context to count
          # @return [Integer] Number of chunks
          def context_chunk_count(context)
            context.is_a?(Array) ? context.size : 1
          end
        end
      end
    end
  end
end
