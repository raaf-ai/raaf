# frozen_string_literal: true

require_relative "base_evaluator"

module RAAF
  module Eval
    module Evaluators
      module LLM
        # Hallucination Evaluator
        #
        # Detects factually incorrect content by comparing LLM output against provided context.
        # Uses LLM-as-judge to evaluate whether the output contains information not supported
        # by the context (hallucinations).
        #
        # Score Range: 0.0 (complete hallucination) to 1.0 (no hallucination)
        #
        # Default Thresholds:
        # - Good: ≥ 0.90 (minimal or no hallucination)
        # - Average: ≥ 0.70 (some factual inconsistencies)
        # - Bad: < 0.70 (significant hallucination)
        #
        # @example Basic usage
        #   evaluator = Hallucination.new
        #   result = evaluator.evaluate(field_context, context: retrieval_context)
        #
        # @example Strict production settings
        #   evaluator = Hallucination.new(good_threshold: 0.98, average_threshold: 0.90)
        #   result = evaluator.evaluate(field_context, context: retrieval_context)
        #
        # @example Per-call override
        #   evaluator = Hallucination.new
        #   result = evaluator.evaluate(field_context,
        #     context: retrieval_context,
        #     good_threshold: 0.95,
        #     average_threshold: 0.85
        #   )
        #
        class Hallucination < BaseEvaluator
          evaluator_name :hallucination

          DEFAULT_GOOD_THRESHOLD = 0.90
          DEFAULT_AVERAGE_THRESHOLD = 0.70

          # Evaluate output for hallucinations against provided context
          #
          # @param field_context [RAAF::Eval::DSL::FieldContext] Field context with output value
          # @param options [Hash] Evaluation options
          # @option options [String, Array<String>] :context Context to compare against (required)
          # @option options [Float] :good_threshold Override good threshold
          # @option options [Float] :average_threshold Override average threshold
          # @option options [String] :model LLM model to use for judging (optional)
          # @return [Hash] Result with label, score, message, and details
          def evaluate(field_context, **options)
            good_threshold, average_threshold = resolve_thresholds(options)

            # Validate context is provided
            context = options[:context] || field_context.context
            raise ArgumentError, "Context is required for hallucination detection" unless context

            # Use LLM judge to detect hallucinations
            score = llm_judge_hallucination(
              output: field_context.value,
              context: context,
              model: options[:model]
            )

            label = calculate_label(score,
                                   good_threshold: good_threshold,
                                   average_threshold: average_threshold)

            build_result(score, label, good_threshold, average_threshold,
              evaluated_field: field_context.field_name,
              method: "llm_judge",
              context_provided: true,
              context_chunks: context.is_a?(Array) ? context.size : 1,
              factual_accuracy_percentage: (score * 100).round,
              evaluation_note: hallucination_note(score, good_threshold, average_threshold)
            )
          end

          private

          # Use LLM as judge to detect hallucinations
          #
          # @param output [String] LLM output to evaluate
          # @param context [String, Array<String>] Context to compare against
          # @param model [String, nil] LLM model for judging
          # @return [Float] Score from 0.0 (complete hallucination) to 1.0 (no hallucination)
          def llm_judge_hallucination(output:, context:, model: nil)
            # Normalize context to string
            context_text = context.is_a?(Array) ? context.join("\n\n") : context

            # Build evaluation prompt
            prompt = build_hallucination_prompt(output, context_text)

            # Call LLM for evaluation
            # TODO: Replace with actual RAAF LLM call
            # For now, return a mock score based on simple heuristic
            mock_hallucination_score(output, context_text)
          end

          # Build prompt for hallucination detection
          #
          # @param output [String] Output to evaluate
          # @param context [String] Context to compare against
          # @return [String] Evaluation prompt
          def build_hallucination_prompt(output, context)
            <<~PROMPT
              You are an expert fact-checker. Your task is to determine if the given output contains
              any hallucinations (factually incorrect information not supported by the provided context).

              CONTEXT:
              #{context}

              OUTPUT TO EVALUATE:
              #{output}

              TASK:
              Analyze the output and determine:
              1. Is every claim in the output supported by the context?
              2. Does the output add information not present in the context?
              3. Does the output contradict any information in the context?

              Provide a score from 0.0 to 1.0:
              - 1.0 = No hallucinations, fully supported by context
              - 0.8-0.9 = Minor unsupported details, mostly accurate
              - 0.6-0.7 = Some factual inconsistencies or additions
              - 0.4-0.5 = Significant hallucinations
              - 0.0-0.3 = Mostly or completely hallucinated

              Return ONLY a JSON object with this format:
              {
                "score": 0.85,
                "reasoning": "Brief explanation of the score"
              }
            PROMPT
          end

          # Mock hallucination scoring (placeholder for actual LLM call)
          #
          # @param output [String] Output to evaluate
          # @param context [String] Context to compare against
          # @return [Float] Mock score
          def mock_hallucination_score(output, context)
            # Simple heuristic: check if output is much longer than context
            # (likely hallucinating if adding lots of information)
            output_length = output.length
            context_length = context.length

            return 0.95 if output_length <= context_length

            length_ratio = context_length.to_f / output_length
            [0.5 + (length_ratio * 0.4), 1.0].min
          end

          # Generate evaluation note based on score
          #
          # @param score [Float] Hallucination score
          # @param good_threshold [Float] Good threshold
          # @param average_threshold [Float] Average threshold
          # @return [String] Human-readable note
          def hallucination_note(score, good_threshold, average_threshold)
            if score >= good_threshold
              "Output is factually accurate and well-supported by context"
            elsif score >= average_threshold
              "Output has minor inconsistencies or unsupported details"
            else
              "Output contains significant hallucinations or factual errors"
            end
          end
        end
      end
    end
  end
end
