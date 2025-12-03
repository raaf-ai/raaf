# frozen_string_literal: true

module RAAF
  module Eval
    module LLMJudge
      ##
      # MultiJudgeEvaluator implements consensus-based evaluation using multiple LLM judges.
      #
      # Using multiple judges helps mitigate individual model biases and provides
      # more robust evaluation results. This approach is recommended by the
      # LLMs-as-Judges survey for reducing evaluation variance.
      #
      # ## Aggregation Strategies
      #
      # - **Majority Vote**: Simple majority determines outcome
      # - **Weighted Vote**: Judges weighted by their calibrated accuracy
      # - **Unanimous**: All judges must agree for a positive outcome
      # - **Threshold**: Configurable percentage must agree
      #
      # ## Benefits
      #
      # 1. **Reduced Bias**: Different models have different biases that can cancel out
      # 2. **Higher Confidence**: Agreement among judges increases reliability
      # 3. **Disagreement Detection**: Identifies ambiguous cases for human review
      #
      # @example Basic usage with multiple models
      #   evaluator = MultiJudgeEvaluator.new(
      #     models: ["gpt-4o", "claude-3-5-sonnet", "gemini-1.5-pro"]
      #   )
      #
      #   result = evaluator.evaluate(
      #     input: "What is 2+2?",
      #     output: "4",
      #     criteria: "Is the answer mathematically correct?"
      #   )
      #
      #   puts result[:consensus]        # true/false
      #   puts result[:agreement_rate]   # 0.0-1.0
      #   puts result[:individual_votes] # Array of individual judgments
      #
      # @example With calibrated judges
      #   judges = [
      #     StatisticalJudge.new(model: "gpt-4o"),
      #     StatisticalJudge.new(model: "claude-3-5-sonnet")
      #   ]
      #
      #   judges.each { |j| j.calibrate(calibration_set) }
      #
      #   evaluator = MultiJudgeEvaluator.new(judges: judges)
      #   result = evaluator.evaluate_weighted(input: "...", output: "...", criteria: "...")
      #
      # @see https://github.com/CSHaitao/Awesome-LLMs-as-Judges
      #
      class MultiJudgeEvaluator
        # @return [Array<StatisticalJudge>] The judges used for evaluation
        attr_reader :judges

        # @return [Symbol] The default aggregation strategy
        attr_reader :default_strategy

        ##
        # Creates a new multi-judge evaluator
        #
        # @param judges [Array<StatisticalJudge>] Pre-configured judge instances
        # @param models [Array<String>] Model names to create judges from
        # @param default_strategy [Symbol] Default aggregation (:majority, :weighted, :unanimous, :threshold)
        # @param temperature [Float] Temperature for unconfigured judges
        # @param cache [Boolean] Whether to cache results
        def initialize(judges: nil, models: nil, default_strategy: :majority, temperature: 0.0, cache: true)
          raise ArgumentError, "Must provide either judges or models" if judges.nil? && models.nil?

          @judges = judges || models.map do |model|
            StatisticalJudge.new(model: model, temperature: temperature, cache: cache)
          end

          raise ArgumentError, "Must have at least 2 judges for consensus" if @judges.size < 2

          @default_strategy = default_strategy
          @temperature = temperature
          @cache_enabled = cache
        end

        ##
        # Calibrates all judges with the same calibration set
        #
        # @param calibration_set [CalibrationSet] Ground-truth labeled data
        # @param criteria [String] Evaluation criteria
        # @return [Hash] Calibration results for all judges
        def calibrate_all(calibration_set, criteria:)
          results = {}
          @judges.each_with_index do |judge, i|
            results["judge_#{i}_#{judge.model}"] = judge.calibrate(calibration_set, criteria: criteria)
          end
          results
        end

        ##
        # Evaluates using majority vote
        #
        # @param input [String] The input/prompt
        # @param output [String] The output to evaluate
        # @param criteria [String] Evaluation criteria
        # @return [Hash] Evaluation result with consensus and individual votes
        def evaluate(input:, output:, criteria:)
          votes = collect_votes(input, output, criteria)
          aggregate_votes(votes, strategy: @default_strategy)
        end

        ##
        # Evaluates using weighted voting based on calibrated accuracy
        #
        # Judges with higher sensitivity + specificity get more weight.
        #
        # @param input [String] The input/prompt
        # @param output [String] The output to evaluate
        # @param criteria [String] Evaluation criteria
        # @return [Hash] Weighted evaluation result
        def evaluate_weighted(input:, output:, criteria:)
          votes = collect_votes(input, output, criteria)
          aggregate_weighted(votes)
        end

        ##
        # Evaluates requiring unanimous agreement
        #
        # All judges must agree for a positive consensus.
        #
        # @param input [String] The input/prompt
        # @param output [String] The output to evaluate
        # @param criteria [String] Evaluation criteria
        # @return [Hash] Unanimous evaluation result
        def evaluate_unanimous(input:, output:, criteria:)
          votes = collect_votes(input, output, criteria)
          aggregate_votes(votes, strategy: :unanimous)
        end

        ##
        # Evaluates with a custom agreement threshold
        #
        # @param input [String] The input/prompt
        # @param output [String] The output to evaluate
        # @param criteria [String] Evaluation criteria
        # @param threshold [Float] Required agreement rate (0.0-1.0)
        # @return [Hash] Threshold-based evaluation result
        def evaluate_threshold(input:, output:, criteria:, threshold: 0.66)
          votes = collect_votes(input, output, criteria)
          aggregate_votes(votes, strategy: :threshold, threshold: threshold)
        end

        ##
        # Evaluates a batch of samples
        #
        # @param samples [Array<Hash>] Array of {input:, output:} hashes
        # @param criteria [String] Evaluation criteria
        # @param strategy [Symbol] Aggregation strategy
        # @return [Hash] Batch results with aggregate statistics
        def evaluate_batch(samples, criteria:, strategy: nil)
          strategy ||= @default_strategy

          results = samples.map do |sample|
            votes = collect_votes(sample[:input], sample[:output], criteria)
            aggregate_votes(votes, strategy: strategy)
          end

          {
            results: results,
            consensus_rate: results.count { |r| r[:consensus] }.to_f / results.size,
            average_agreement: results.sum { |r| r[:agreement_rate] } / results.size,
            high_disagreement_count: results.count { |r| r[:agreement_rate] < 0.5 },
            unanimous_count: results.count { |r| r[:agreement_rate] == 1.0 }
          }
        end

        ##
        # Identifies samples with high disagreement for human review
        #
        # @param samples [Array<Hash>] Array of {input:, output:} hashes
        # @param criteria [String] Evaluation criteria
        # @param disagreement_threshold [Float] Agreement rate below which to flag
        # @return [Array<Hash>] Samples needing human review
        def flag_for_human_review(samples, criteria:, disagreement_threshold: 0.5)
          flagged = []

          samples.each do |sample|
            votes = collect_votes(sample[:input], sample[:output], criteria)
            result = aggregate_votes(votes, strategy: @default_strategy)

            if result[:agreement_rate] < disagreement_threshold
              flagged << {
                sample: sample,
                result: result,
                reason: "Low agreement: #{(result[:agreement_rate] * 100).round(1)}%"
              }
            end
          end

          flagged
        end

        ##
        # Returns inter-rater reliability statistics
        #
        # @param samples [Array<Hash>] Array of {input:, output:} hashes
        # @param criteria [String] Evaluation criteria
        # @return [Hash] Reliability statistics including Cohen's Kappa (for 2 judges)
        def inter_rater_reliability(samples, criteria:)
          all_votes = samples.map do |sample|
            collect_votes(sample[:input], sample[:output], criteria)
          end

          # Calculate pairwise agreement
          pairwise_agreements = []
          @judges.each_with_index do |_judge1, i|
            ((i + 1)...@judges.size).each do |j|
              agreements = all_votes.count do |votes|
                votes[i][:passed] == votes[j][:passed]
              end
              pairwise_agreements << agreements.to_f / samples.size
            end
          end

          # Calculate overall statistics
          {
            mean_pairwise_agreement: pairwise_agreements.sum / pairwise_agreements.size,
            min_pairwise_agreement: pairwise_agreements.min,
            max_pairwise_agreement: pairwise_agreements.max,
            fleiss_kappa: calculate_fleiss_kappa(all_votes),
            num_judges: @judges.size,
            num_samples: samples.size
          }
        end

        ##
        # Returns summary of all judges
        #
        # @return [Array<Hash>] Summary for each judge
        def judges_summary
          @judges.map.with_index do |judge, i|
            judge.summary.merge(index: i)
          end
        end

        private

        def collect_votes(input, output, criteria)
          @judges.map do |judge|
            judge.evaluate(input: input, output: output, criteria: criteria)
          end
        end

        def aggregate_votes(votes, strategy:, threshold: nil)
          positive_votes = votes.count { |v| v[:passed] }
          total_votes = votes.size
          agreement_rate = [positive_votes, total_votes - positive_votes].max.to_f / total_votes

          consensus = case strategy
                      when :majority
                        positive_votes > total_votes / 2.0
                      when :unanimous
                        positive_votes == total_votes || positive_votes.zero?
                      when :threshold
                        threshold ||= 0.66
                        positive_votes.to_f / total_votes >= threshold
                      else
                        positive_votes > total_votes / 2.0
                      end

          # For unanimous strategy, consensus follows majority direction
          if strategy == :unanimous
            consensus = positive_votes == total_votes
          end

          {
            consensus: consensus,
            positive_votes: positive_votes,
            negative_votes: total_votes - positive_votes,
            total_judges: total_votes,
            agreement_rate: agreement_rate,
            strategy: strategy,
            individual_votes: votes.map.with_index do |v, i|
              {
                judge: "#{@judges[i].model}",
                passed: v[:passed],
                confidence: v[:confidence],
                reasoning: v[:reasoning]
              }
            end
          }
        end

        def aggregate_weighted(votes)
          # Weight by calibration quality (sensitivity + specificity)
          weights = @judges.map do |judge|
            if judge.calibrated?
              judge.sensitivity + judge.specificity - 1  # Higher = better
            else
              1.0  # Default weight for uncalibrated judges
            end
          end

          # Normalize weights
          total_weight = weights.sum
          normalized_weights = weights.map { |w| w / total_weight }

          # Weighted vote
          weighted_positive = votes.each_with_index.sum do |vote, i|
            vote[:passed] ? normalized_weights[i] : 0
          end

          weighted_negative = votes.each_with_index.sum do |vote, i|
            vote[:passed] ? 0 : normalized_weights[i]
          end

          {
            consensus: weighted_positive > weighted_negative,
            weighted_positive_score: weighted_positive,
            weighted_negative_score: weighted_negative,
            weights: normalized_weights.map.with_index { |w, i| { model: @judges[i].model, weight: w } },
            positive_votes: votes.count { |v| v[:passed] },
            negative_votes: votes.count { |v| !v[:passed] },
            total_judges: votes.size,
            strategy: :weighted,
            individual_votes: votes.map.with_index do |v, i|
              {
                judge: @judges[i].model,
                passed: v[:passed],
                confidence: v[:confidence],
                reasoning: v[:reasoning],
                weight: normalized_weights[i]
              }
            end
          }
        end

        def calculate_fleiss_kappa(all_votes)
          # Fleiss' Kappa for inter-rater reliability with multiple raters
          n = all_votes.size  # Number of samples
          k = @judges.size    # Number of raters
          return 0.0 if n.zero? || k < 2

          # Count agreements for each sample
          p_i = all_votes.map do |votes|
            n_positive = votes.count { |v| v[:passed] }
            n_negative = k - n_positive

            # Proportion of agreement for this sample
            (n_positive * (n_positive - 1) + n_negative * (n_negative - 1)).to_f / (k * (k - 1))
          end

          # Mean observed agreement
          p_bar = p_i.sum / n

          # Expected agreement by chance
          total_positive = all_votes.sum { |votes| votes.count { |v| v[:passed] } }
          p_positive = total_positive.to_f / (n * k)
          p_negative = 1 - p_positive

          p_e = p_positive ** 2 + p_negative ** 2

          # Kappa
          return 1.0 if (1 - p_e).abs < 0.0001  # Perfect agreement case

          (p_bar - p_e) / (1 - p_e)
        end
      end
    end
  end
end
