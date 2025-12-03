# frozen_string_literal: true

module RAAF
  module Eval
    module LLMJudge
      ##
      # BiasMitigation provides utilities for mitigating common LLM judge biases.
      #
      # LLM judges exhibit several well-documented biases that can skew evaluation results:
      #
      # 1. **Position Bias**: Preferring items appearing first or last
      # 2. **Length Bias**: Favoring longer or shorter responses
      # 3. **Format Bias**: Preferring certain formatting styles
      # 4. **Verbosity Bias**: Preferring more detailed explanations
      # 5. **Self-Enhancement Bias**: Preferring outputs similar to own style
      #
      # This module provides techniques to detect and mitigate these biases.
      #
      # @see https://github.com/CSHaitao/Awesome-LLMs-as-Judges (LLMs-as-Judges Survey)
      # @see https://arxiv.org/abs/2511.21140 (LLM-as-a-Judge Reporting)
      #
      module BiasMitigation
        ##
        # Position bias mitigation through order permutation
        #
        # Evaluates comparisons in multiple orderings and averages results
        # to cancel out position bias effects.
        #
        class PositionDebiaser
          ##
          # Creates a new position debiaser
          #
          # @param judge [StatisticalJudge] The judge to use
          # @param permutations [Integer] Number of orderings to try (default: 2 for A/B swap)
          def initialize(judge:, permutations: 2)
            @judge = judge
            @permutations = permutations
          end

          ##
          # Compares two outputs with position debiasing
          #
          # Evaluates "Is A better than B?" and "Is B better than A?" then
          # combines results to cancel position bias.
          #
          # @param input [String] The input/prompt
          # @param output_a [String] First output to compare
          # @param output_b [String] Second output to compare
          # @param criteria [String] Comparison criteria
          # @return [Hash] Debiased comparison result
          #
          # @example
          #   debiaser = PositionDebiaser.new(judge: judge)
          #
          #   result = debiaser.compare(
          #     input: "Write a poem about Ruby",
          #     output_a: "Ruby shines bright...",
          #     output_b: "In the land of code...",
          #     criteria: "Which poem is more creative and well-structured?"
          #   )
          #
          #   puts result[:winner]           # :a, :b, or :tie
          #   puts result[:position_bias_detected]
          #
          def compare(input:, output_a:, output_b:, criteria:)
            # Evaluate A vs B (A first)
            forward_result = evaluate_comparison(input, output_a, output_b, criteria, "A", "B")

            # Evaluate B vs A (B first)
            reverse_result = evaluate_comparison(input, output_b, output_a, criteria, "B", "A")

            # Combine results
            combine_comparison_results(forward_result, reverse_result)
          end

          ##
          # Ranks multiple outputs with position debiasing
          #
          # Uses pairwise comparisons with position swapping to create
          # a robust ranking.
          #
          # @param input [String] The input/prompt
          # @param outputs [Array<String>] Outputs to rank
          # @param criteria [String] Ranking criteria
          # @return [Hash] Ranking with scores and position bias indicators
          #
          def rank(input:, outputs:, criteria:)
            scores = Hash.new(0)
            comparisons = []

            # Pairwise comparisons
            outputs.each_with_index do |output_a, i|
              ((i + 1)...outputs.size).each do |j|
                output_b = outputs[j]

                result = compare(
                  input: input,
                  output_a: output_a,
                  output_b: output_b,
                  criteria: criteria
                )

                comparisons << {
                  pair: [i, j],
                  winner: result[:winner],
                  position_bias_detected: result[:position_bias_detected]
                }

                case result[:winner]
                when :a then scores[i] += 1
                when :b then scores[j] += 1
                else
                  scores[i] += 0.5
                  scores[j] += 0.5
                end
              end
            end

            # Create ranking
            ranked_indices = scores.sort_by { |_k, v| -v }.map(&:first)

            {
              ranking: ranked_indices.map { |i| { index: i, output: outputs[i], score: scores[i] } },
              comparisons: comparisons,
              position_bias_count: comparisons.count { |c| c[:position_bias_detected] },
              total_comparisons: comparisons.size
            }
          end

          private

          def evaluate_comparison(input, first_output, second_output, criteria, first_label, second_label)
            prompt = build_comparison_prompt(input, first_output, second_output, criteria, first_label, second_label)
            result = @judge.evaluate(input: prompt, output: "", criteria: "Determine which output is better")

            {
              first_label: first_label,
              second_label: second_label,
              prefers_first: result[:passed],
              confidence: result[:confidence],
              reasoning: result[:reasoning]
            }
          end

          def build_comparison_prompt(input, first_output, second_output, criteria, first_label, second_label)
            <<~PROMPT
              Compare these two outputs and determine which is better.

              ## Original Input
              #{input}

              ## Evaluation Criteria
              #{criteria}

              ## Output #{first_label}
              #{first_output}

              ## Output #{second_label}
              #{second_output}

              Which output better satisfies the criteria? Respond with:
              - "passed": true if Output #{first_label} is better
              - "passed": false if Output #{second_label} is better
            PROMPT
          end

          def combine_comparison_results(forward, reverse)
            # Check for consistency
            # Forward prefers A means A > B
            # Reverse prefers A means A > B (when positions swapped)

            forward_prefers_a = forward[:prefers_first]  # A was first, so prefers_first = prefers A
            reverse_prefers_a = !reverse[:prefers_first] # B was first, so !prefers_first = prefers A

            consistent = forward_prefers_a == reverse_prefers_a

            # Combine confidence (lower when inconsistent)
            combined_confidence = if consistent
                                    (forward[:confidence] + reverse[:confidence]) / 2
                                  else
                                    [(forward[:confidence] + reverse[:confidence]) / 4, 0.5].min
                                  end

            # Determine winner
            winner = if consistent
                       forward_prefers_a ? :a : :b
                     else
                       # When inconsistent, check confidence levels
                       if forward[:confidence] > reverse[:confidence] + 0.2
                         forward_prefers_a ? :a : :b
                       elsif reverse[:confidence] > forward[:confidence] + 0.2
                         reverse_prefers_a ? :a : :b
                       else
                         :tie
                       end
                     end

            {
              winner: winner,
              confidence: combined_confidence,
              consistent: consistent,
              position_bias_detected: !consistent,
              forward_result: forward,
              reverse_result: reverse,
              reasoning: build_combined_reasoning(forward, reverse, consistent)
            }
          end

          def build_combined_reasoning(forward, reverse, consistent)
            if consistent
              "Both orderings agree: #{forward[:reasoning]}"
            else
              "Position bias detected. Forward: #{forward[:reasoning]}. Reverse: #{reverse[:reasoning]}"
            end
          end
        end

        ##
        # Length bias detector and normalizer
        #
        class LengthBiasAnalyzer
          ##
          # Analyzes correlation between output length and judge scores
          #
          # @param evaluations [Array<Hash>] Array of {output:, score:} pairs
          # @return [Hash] Correlation analysis
          #
          def analyze_length_correlation(evaluations)
            lengths = evaluations.map { |e| e[:output].to_s.length }
            scores = evaluations.map { |e| e[:score] }

            correlation = calculate_pearson_correlation(lengths, scores)

            {
              correlation: correlation,
              bias_detected: correlation.abs > 0.5,
              bias_direction: correlation.positive? ? :prefers_longer : :prefers_shorter,
              bias_strength: interpret_correlation(correlation),
              sample_size: evaluations.size,
              length_stats: {
                min: lengths.min,
                max: lengths.max,
                mean: lengths.sum.to_f / lengths.size,
                std: calculate_std(lengths)
              }
            }
          end

          ##
          # Normalizes scores to account for length bias
          #
          # @param evaluations [Array<Hash>] Array of {output:, score:} pairs
          # @param target_correlation [Float] Target correlation (default: 0)
          # @return [Array<Hash>] Evaluations with normalized scores
          #
          def normalize_for_length(evaluations, target_correlation: 0.0)
            analysis = analyze_length_correlation(evaluations)
            return evaluations unless analysis[:bias_detected]

            # Linear regression to remove length effect
            lengths = evaluations.map { |e| e[:output].to_s.length.to_f }
            scores = evaluations.map { |e| e[:score] }

            mean_length = lengths.sum / lengths.size
            mean_score = scores.sum / scores.size

            # Calculate regression coefficient
            numerator = lengths.zip(scores).sum { |l, s| (l - mean_length) * (s - mean_score) }
            denominator = lengths.sum { |l| (l - mean_length) ** 2 }
            beta = denominator.zero? ? 0 : numerator / denominator

            # Adjust scores
            evaluations.map.with_index do |eval, i|
              adjustment = beta * (lengths[i] - mean_length) * (1 - target_correlation.abs)
              {
                output: eval[:output],
                original_score: eval[:score],
                normalized_score: (eval[:score] - adjustment).clamp(0.0, 1.0),
                length: lengths[i].to_i,
                adjustment: adjustment
              }
            end
          end

          private

          def calculate_pearson_correlation(x, y)
            n = x.size
            return 0.0 if n < 2

            mean_x = x.sum.to_f / n
            mean_y = y.sum.to_f / n

            numerator = x.zip(y).sum { |xi, yi| (xi - mean_x) * (yi - mean_y) }
            denom_x = Math.sqrt(x.sum { |xi| (xi - mean_x) ** 2 })
            denom_y = Math.sqrt(y.sum { |yi| (yi - mean_y) ** 2 })

            denominator = denom_x * denom_y
            return 0.0 if denominator.zero?

            numerator / denominator
          end

          def calculate_std(values)
            return 0.0 if values.size < 2

            mean = values.sum.to_f / values.size
            variance = values.sum { |v| (v - mean) ** 2 } / (values.size - 1)
            Math.sqrt(variance)
          end

          def interpret_correlation(r)
            case r.abs
            when 0...0.3 then :weak
            when 0.3...0.5 then :moderate
            when 0.5...0.7 then :strong
            else :very_strong
            end
          end
        end

        ##
        # Format bias detector
        #
        class FormatBiasAnalyzer
          FORMAT_INDICATORS = {
            markdown_headers: /^#+\s/m,
            bullet_lists: /^[\-\*]\s/m,
            numbered_lists: /^\d+\.\s/m,
            code_blocks: /```/,
            bold_text: /\*\*[^*]+\*\*/,
            inline_code: /`[^`]+`/,
            links: /\[[^\]]+\]\([^)]+\)/,
            tables: /\|.*\|/
          }.freeze

          ##
          # Analyzes correlation between format features and scores
          #
          # @param evaluations [Array<Hash>] Array of {output:, score:} pairs
          # @return [Hash] Format bias analysis
          #
          def analyze(evaluations)
            results = {}

            FORMAT_INDICATORS.each do |name, pattern|
              has_feature = evaluations.map { |e| e[:output].to_s.match?(pattern) ? 1 : 0 }
              scores = evaluations.map { |e| e[:score] }

              # Point-biserial correlation for binary feature
              correlation = calculate_point_biserial(has_feature, scores)

              results[name] = {
                correlation: correlation,
                bias_detected: correlation.abs > 0.3,
                direction: correlation.positive? ? :prefers_with : :prefers_without,
                feature_frequency: has_feature.sum.to_f / has_feature.size
              }
            end

            {
              format_biases: results,
              significant_biases: results.select { |_k, v| v[:bias_detected] }.keys,
              bias_count: results.count { |_k, v| v[:bias_detected] }
            }
          end

          private

          def calculate_point_biserial(binary_var, continuous_var)
            n = binary_var.size
            return 0.0 if n < 2

            group_1 = continuous_var.zip(binary_var).select { |_, b| b == 1 }.map(&:first)
            group_0 = continuous_var.zip(binary_var).select { |_, b| b.zero? }.map(&:first)

            return 0.0 if group_1.empty? || group_0.empty?

            mean_1 = group_1.sum.to_f / group_1.size
            mean_0 = group_0.sum.to_f / group_0.size

            overall_mean = continuous_var.sum.to_f / n
            overall_std = Math.sqrt(continuous_var.sum { |v| (v - overall_mean) ** 2 } / n)

            return 0.0 if overall_std.zero?

            p = group_1.size.to_f / n
            q = 1 - p

            (mean_1 - mean_0) / overall_std * Math.sqrt(p * q)
          end
        end

        ##
        # Consistency checker for detecting judge instability
        #
        class ConsistencyChecker
          ##
          # Creates a consistency checker
          #
          # @param judge [StatisticalJudge] The judge to check
          # @param repetitions [Integer] Number of times to evaluate each sample
          def initialize(judge:, repetitions: 3)
            @judge = judge
            @repetitions = repetitions
          end

          ##
          # Checks consistency of judge on a sample
          #
          # @param input [String] Input to evaluate
          # @param output [String] Output to evaluate
          # @param criteria [String] Evaluation criteria
          # @return [Hash] Consistency analysis
          #
          def check(input:, output:, criteria:)
            # Temporarily disable caching
            results = @repetitions.times.map do
              @judge.evaluate(input: input, output: output, criteria: criteria)
            end

            passed_count = results.count { |r| r[:passed] }
            confidences = results.map { |r| r[:confidence] }

            {
              consistent: passed_count.zero? || passed_count == @repetitions,
              agreement_rate: [passed_count, @repetitions - passed_count].max.to_f / @repetitions,
              passed_ratio: passed_count.to_f / @repetitions,
              confidence_variance: calculate_variance(confidences),
              mean_confidence: confidences.sum / confidences.size,
              individual_results: results
            }
          end

          ##
          # Checks consistency across multiple samples
          #
          # @param samples [Array<Hash>] Array of {input:, output:} hashes
          # @param criteria [String] Evaluation criteria
          # @return [Hash] Aggregate consistency statistics
          #
          def check_batch(samples, criteria:)
            results = samples.map do |sample|
              check(input: sample[:input], output: sample[:output], criteria: criteria)
            end

            consistent_count = results.count { |r| r[:consistent] }

            {
              overall_consistency_rate: consistent_count.to_f / samples.size,
              mean_agreement_rate: results.sum { |r| r[:agreement_rate] } / results.size,
              mean_confidence_variance: results.sum { |r| r[:confidence_variance] } / results.size,
              inconsistent_samples: results.each_with_index.reject { |r, _i| r[:consistent] }.map do |r, i|
                { index: i, sample: samples[i], result: r }
              end
            }
          end

          private

          def calculate_variance(values)
            return 0.0 if values.size < 2

            mean = values.sum.to_f / values.size
            values.sum { |v| (v - mean) ** 2 } / (values.size - 1)
          end
        end
      end
    end
  end
end
