# frozen_string_literal: true

require_relative "../../dsl/evaluator"

module RAAF
  module Eval
    module Evaluators
      module Custom
        # Example custom evaluator: Citation Grounding
        # Verifies that citations in text are grounded in a knowledge base
        #
        # This is a reference implementation showing best practices for:
        # - Using FieldContext to access evaluated field
        # - Accessing configuration via options parameter
        # - Cross-field context access for additional data
        # - Proper result structure with all required fields
        #
        # @example Register and use
        #   RAAF::Eval.register_evaluator(:citation_grounding, CitationGroundingEvaluator)
        #   
        #   evaluator = RAAF::Eval.define do
        #     evaluate_field :output do
        #       evaluate_with :citation_grounding, knowledge_base: ["1", "2", "3"]
        #     end
        #   end
        class CitationGrounding
          include RAAF::Eval::DSL::Evaluator

          evaluator_name :citation_grounding

          # Evaluate citation grounding against knowledge base
          # @param field_context [FieldContext] The field context containing value and result access
          # @param options [Hash] Options including :knowledge_base (array of valid citation IDs)
          # @return [Hash] Evaluation result with :passed, :score, :details, :message
          def evaluate(field_context, **options)
            text = field_context.value
            knowledge_base = options[:knowledge_base] || []

            # Extract citations from text
            citations = extract_citations(text)
            
            # Verify citations against knowledge base
            grounded = verify_citations(citations, knowledge_base)

            # Access other fields for context (optional)
            model = field_context[:configuration][:model] rescue "unknown"
            tokens = field_context[:usage][:total_tokens] rescue 0

            {
              passed: grounded[:unverified].empty?,
              score: grounded[:verified_ratio],
              details: {
                field_evaluated: field_context.field_name,
                total_citations: citations.count,
                verified: grounded[:verified].count,
                unverified: grounded[:unverified],
                ratio: grounded[:verified_ratio],
                context: {
                  model: model,
                  tokens: tokens
                }
              },
              message: "#{grounded[:verified].count}/#{citations.count} citations grounded in #{field_context.field_name}"
            }
          end

          private

          # Extract citation references from text
          # Looks for [1], [2], etc. patterns
          # @param text [String] The text to extract citations from
          # @return [Array<Integer>] Array of citation numbers
          def extract_citations(text)
            return [] unless text.is_a?(String)
            text.scan(/\[(\d+)\]/).flatten.map(&:to_i)
          end

          # Verify citations against knowledge base
          # @param citations [Array<Integer>] Citation numbers to verify
          # @param kb [Array<String>] Knowledge base of valid citation IDs
          # @return [Hash] Hash with :verified, :unverified, :verified_ratio
          def verify_citations(citations, kb)
            verified = citations.select { |c| kb.include?(c.to_s) }
            {
              verified: verified,
              unverified: citations - verified,
              verified_ratio: citations.empty? ? 1.0 : verified.count.to_f / citations.count
            }
          end
        end
      end
    end
  end
end
