# frozen_string_literal: true

require_relative "../../dsl/evaluator"

module RAAF
  module Eval
    module Evaluators
      module Custom
        # Example custom evaluator: Smart Quality
        # Context-aware quality evaluation that adjusts expectations based on model
        #
        # This is a reference implementation showing best practices for:
        # - Cross-field context access (tokens, model, latency)
        # - Model-specific expectation adjustment
        # - Efficiency-aware quality scoring
        # - Rich detail reporting
        #
        # @example Register and use
        #   RAAF::Eval.register_evaluator(:smart_quality, SmartQualityEvaluator)
        #   
        #   evaluator = RAAF::Eval.define do
        #     evaluate_field :output do
        #       evaluate_with :smart_quality, min_score: 0.7
        #     end
        #   end
        class SmartQuality
          include RAAF::Eval::DSL::Evaluator

          evaluator_name :smart_quality

          # Evaluate output quality with context awareness
          # @param field_context [FieldContext] The field context containing value and result access
          # @param options [Hash] Options including :min_score (default 0.7)
          # @return [Hash] Evaluation result with :passed, :score, :details, :message
          def evaluate(field_context, **options)
            output = field_context.value
            min_score = options[:min_score] || 0.7
            good_threshold = options[:good_threshold] || 0.8
            average_threshold = options[:average_threshold] || 0.6

            # Access cross-field context
            tokens = field_context[:usage][:total_tokens] rescue 0
            latency = field_context[:latency_ms] rescue 0
            model = field_context[:configuration][:model] rescue "unknown"

            # Calculate base quality
            base_score = calculate_quality(output)

            # Adjust expectations based on model
            adjusted_score = adjust_for_model(base_score, model)

            # Penalize inefficiency
            efficiency_penalty = calculate_efficiency_penalty(output, tokens)

            # Calculate final score
            final_score = [adjusted_score - efficiency_penalty, 0].max

            label = calculate_label(final_score, good_threshold: good_threshold, average_threshold: average_threshold)

            {
              label: label,
              score: final_score,
              details: {
                evaluated_field: field_context.field_name,
                base_quality: base_score,
                model_adjustment: adjusted_score - base_score,
                efficiency_penalty: efficiency_penalty,
                threshold_good: good_threshold,
                threshold_average: average_threshold,
                context: {
                  model: model,
                  tokens: tokens,
                  latency: latency
                }
              },
              message: "[#{label.upcase}] Quality: #{(final_score * 100).round}% (model: #{model}, tokens: #{tokens})"
            }
          end

          private

          # Calculate base quality score
          # @param text [String] The output text
          # @return [Float] Quality score 0.0-1.0
          def calculate_quality(text)
            return 0.0 if text.to_s.empty?
            return 0.5 if text.to_s.length < 10

            # Simplified quality calculation
            # In real implementation, would use:
            # - Coherence metrics
            # - Grammar checking
            # - Relevance scoring
            # - Hallucination detection
            0.85
          end

          # Adjust score based on model expectations
          # @param base_score [Float] Base quality score
          # @param model [String] Model name
          # @return [Float] Adjusted score
          def adjust_for_model(base_score, model)
            case model
            when "gpt-4o"
              base_score * 1.0  # Expect high quality
            when "gpt-3.5-turbo"
              base_score * 1.1  # More lenient
            when /^gpt-4/
              base_score * 1.0  # Expect high quality
            else
              base_score
            end
          end

          # Calculate efficiency penalty
          # Penalize using many tokens for short output
          # @param text [String] The output text
          # @param tokens [Integer] Token count
          # @return [Float] Penalty 0.0-1.0
          def calculate_efficiency_penalty(text, tokens)
            return 0.0 if tokens.zero?

            output_length = text.to_s.length

            # Penalize if using many tokens for short output
            if tokens > 1000 && output_length < 200
              0.1
            elsif tokens > 500 && output_length < 100
              0.15
            else
              0.0
            end
          end
        end
      end
    end
  end
end
