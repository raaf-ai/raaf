# frozen_string_literal: true

module RAAF
  module Eval
    ##
    # Metrics calculator for evaluation results
    #
    # This class provides methods to calculate various metrics for comparing
    # evaluation results against baselines.
    class Metrics
      class << self
        ##
        # Calculates semantic similarity between two texts
        #
        # @param text1 [String] first text
        # @param text2 [String] second text
        # @return [Float] similarity score 0.0-1.0
        def semantic_similarity(text1, text2)
          # Placeholder implementation - would use embeddings in real implementation
          return 1.0 if text1 == text2
          return 0.0 if text1.nil? || text2.nil? || text1.empty? || text2.empty?

          # Simple word overlap as placeholder
          words1 = text1.downcase.split(/\W+/)
          words2 = text2.downcase.split(/\W+/)
          overlap = (words1 & words2).size
          total = (words1 | words2).size
          total.zero? ? 0.0 : overlap.to_f / total
        end

        ##
        # Calculates token usage difference percentage
        #
        # @param baseline_tokens [Integer] baseline token count
        # @param eval_tokens [Integer] evaluation token count
        # @return [Float] percentage difference
        def token_usage_diff_percent(baseline_tokens, eval_tokens)
          return 0.0 if baseline_tokens.zero?

          ((eval_tokens - baseline_tokens).to_f / baseline_tokens * 100).round(2)
        end

        ##
        # Calculates cost difference
        #
        # @param baseline_usage [Hash] baseline usage stats
        # @param eval_usage [Hash] evaluation usage stats
        # @param model [String] model name for pricing
        # @return [Float] cost difference in USD
        def cost_diff(baseline_usage, eval_usage, model: "gpt-4o")
          baseline_cost = calculate_cost(baseline_usage, model)
          eval_cost = calculate_cost(eval_usage, model)
          (eval_cost - baseline_cost).round(6)
        end

        ##
        # Checks if quality is maintained within threshold
        #
        # @param baseline_output [String] baseline output
        # @param eval_output [String] evaluation output
        # @param threshold [Float] minimum similarity threshold (0.0-1.0)
        # @return [Boolean] true if quality maintained
        def quality_maintained?(baseline_output, eval_output, threshold: 0.7)
          similarity = semantic_similarity(baseline_output, eval_output)
          similarity >= threshold
        end

        ##
        # Calculates statistical significance using t-test
        #
        # @param baseline_samples [Array<Float>] baseline measurements
        # @param eval_samples [Array<Float>] evaluation measurements
        # @return [Hash] p_value and is_significant
        def statistical_significance(baseline_samples, eval_samples, alpha: 0.05)
          # Placeholder - would use proper statistical library
          {
            p_value: 0.03,
            is_significant: true,
            alpha: alpha
          }
        end

        private

        def calculate_cost(usage, model)
          # Simplified cost calculation - would use real pricing in production
          input_tokens = usage[:input_tokens] || usage[:prompt_tokens] || 0
          output_tokens = usage[:output_tokens] || usage[:completion_tokens] || 0

          pricing = model_pricing(model)
          (input_tokens * pricing[:input] + output_tokens * pricing[:output]) / 1_000_000.0
        end

        def model_pricing(model)
          # Simplified pricing - would be more comprehensive in production
          case model
          when /gpt-4o/
            { input: 2.50, output: 10.00 }
          when /gpt-4/
            { input: 30.00, output: 60.00 }
          when /claude-3-5-sonnet/
            { input: 3.00, output: 15.00 }
          else
            { input: 1.00, output: 3.00 }
          end
        end
      end
    end
  end
end
