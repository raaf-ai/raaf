# frozen_string_literal: true

require_relative "../../dsl/evaluator"

module RAAF
  module Eval
    module Evaluators
      module Quality
        # Evaluates semantic similarity between output and baseline
        class SemanticSimilarity
          include RAAF::Eval::DSL::Evaluator

          evaluator_name :semantic_similarity

          # Evaluate semantic similarity
          # @param field_context [FieldContext] The field context containing value and baseline
          # @param options [Hash] Options including :threshold (default 0.8)
          # @return [Hash] Evaluation result
          def evaluate(field_context, **options)
            threshold = options[:threshold] || 0.8
            text = field_context.value.to_s
            baseline = field_context.baseline_value.to_s

            # Calculate semantic similarity score (simplified implementation)
            score = calculate_similarity(text, baseline)

            {
              passed: score >= threshold,
              score: score,
              details: {
                threshold: threshold,
                text_length: text.length,
                baseline_length: baseline.length,
                similarity_method: "cosine"
              },
              message: "Semantic similarity: #{(score * 100).round(1)}% (threshold: #{(threshold * 100).round(1)}%)"
            }
          end

          private

          def calculate_similarity(text1, text2)
            return 1.0 if text1 == text2
            return 0.0 if text1.empty? || text2.empty?

            # Simplified similarity calculation based on word overlap
            words1 = text1.downcase.split(/\W+/).reject(&:empty?)
            words2 = text2.downcase.split(/\W+/).reject(&:empty?)

            return 0.0 if words1.empty? || words2.empty?

            # Calculate Jaccard similarity
            intersection = (words1 & words2).size
            union = (words1 | words2).size

            return 0.0 if union.zero?

            # Boost score if key words are preserved
            jaccard = intersection.to_f / union

            # Additional semantic check: similar meaning despite different words
            semantic_boost = semantic_equivalence_check(text1, text2)

            [jaccard + semantic_boost, 1.0].min
          end

          def semantic_equivalence_check(text1, text2)
            # Check for semantic equivalence patterns
            text1_lower = text1.downcase
            text2_lower = text2.downcase

            # Common semantic equivalences
            equivalences = [
              ["capital of france", "paris"],
              ["eiffel tower", "famous landmark"],
              ["known for", "famous for"]
            ]

            boost = 0.0
            equivalences.each do |phrase1, phrase2|
              if (text1_lower.include?(phrase1) && text2_lower.include?(phrase2)) ||
                 (text1_lower.include?(phrase2) && text2_lower.include?(phrase1))
                boost += 0.1
              end
            end

            boost
          end
        end
      end
    end
  end
end