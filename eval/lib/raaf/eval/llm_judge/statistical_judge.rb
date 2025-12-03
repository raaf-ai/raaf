# frozen_string_literal: true

require "distribution"

module RAAF
  module Eval
    module LLMJudge
      ##
      # StatisticalJudge implements statistically rigorous LLM-as-a-Judge evaluation
      # with bias correction and proper confidence interval construction.
      #
      # This implementation is based on:
      # Lee et al. "How to Correctly Report LLM-as-a-Judge Evaluations" (arXiv:2511.21140)
      #
      # ## The Problem
      #
      # LLM judges have imperfect sensitivity and specificity, leading to biased
      # accuracy estimates. Raw LLM judge scores are systematically biased because
      # judges make errors in both directions:
      # - False positives: Judging incorrect outputs as correct
      # - False negatives: Judging correct outputs as incorrect
      #
      # ## The Solution
      #
      # This class provides:
      # 1. Calibration against ground-truth labeled data
      # 2. Bias-corrected point estimates using sensitivity/specificity
      # 3. Confidence intervals accounting for both test and calibration uncertainty
      # 4. Adaptive calibration allocation for efficient sample use
      #
      # ## Key Concepts
      #
      # - **Sensitivity (q1)**: P(Judge=correct | Actually=correct) - True Positive Rate
      # - **Specificity (q0)**: P(Judge=incorrect | Actually=incorrect) - True Negative Rate
      # - **Bias correction**: theta = (p + q0 - 1) / (q0 + q1 - 1)
      #
      # @example Basic usage with calibration
      #   judge = StatisticalJudge.new(model: "gpt-4o")
      #
      #   # Calibrate with ground-truth data
      #   calibration = CalibrationSet.new
      #   calibration.add(input: "2+2=?", output: "4", ground_truth: true)
      #   calibration.add(input: "2+2=?", output: "5", ground_truth: false)
      #   # ... add more samples
      #
      #   judge.calibrate(calibration)
      #
      #   # Evaluate with bias correction
      #   results = judge.evaluate_batch(test_outputs)
      #   puts results[:bias_corrected_accuracy]
      #   puts results[:confidence_interval]
      #
      # @see https://arxiv.org/abs/2511.21140
      # @see https://github.com/UW-Madison-Lee-Lab/LLM-judge-reporting
      #
      class StatisticalJudge
        # @return [String] The model used for judging
        attr_reader :model

        # @return [Float] Temperature for the judge model
        attr_reader :temperature

        # @return [Float, nil] Calibrated sensitivity (q1)
        attr_reader :sensitivity

        # @return [Float, nil] Calibrated specificity (q0)
        attr_reader :specificity

        # @return [CalibrationSet, nil] The calibration data used
        attr_reader :calibration_set

        # @return [Hash] Calibration metadata
        attr_reader :calibration_metadata

        ##
        # Creates a new statistical LLM judge
        #
        # @param model [String] The model to use for judging (default: "gpt-4o")
        # @param temperature [Float] Temperature for judge responses (default: 0.0 for consistency)
        # @param cache [Boolean] Whether to cache judge responses
        # @param timeout [Integer] Timeout in seconds for API calls
        # @param criteria [String] Default evaluation criteria/prompt
        def initialize(model: "gpt-4o", temperature: 0.0, cache: true, timeout: 30, criteria: nil)
          @model = model
          @temperature = temperature
          @cache_enabled = cache
          @timeout = timeout
          @default_criteria = criteria
          @cache = {}

          # Calibration state
          @sensitivity = nil
          @specificity = nil
          @calibration_set = nil
          @calibration_metadata = {}

          # Internal judge instance
          @base_judge = nil
        end

        ##
        # Calibrates the judge using ground-truth labeled data
        #
        # This computes sensitivity (q1) and specificity (q0) by comparing
        # the judge's predictions against known ground truth labels.
        #
        # @param calibration_set [CalibrationSet] Ground-truth labeled samples
        # @param criteria [String, nil] Evaluation criteria to use
        # @param min_samples [Integer] Minimum samples required per class
        # @return [Hash] Calibration results with sensitivity, specificity, and diagnostics
        #
        # @example
        #   calibration = CalibrationSet.new
        #   100.times do |i|
        #     calibration.add(
        #       input: "Question #{i}",
        #       output: "Answer #{i}",
        #       ground_truth: i.even?  # Known correct/incorrect labels
        #     )
        #   end
        #
        #   result = judge.calibrate(calibration)
        #   puts "Sensitivity: #{result[:sensitivity]}"
        #   puts "Specificity: #{result[:specificity]}"
        #
        def calibrate(calibration_set, criteria: nil, min_samples: 10)
          calibration_set.validate!(min_positive: min_samples, min_negative: min_samples)

          @calibration_set = calibration_set
          eval_criteria = criteria || @default_criteria

          # Evaluate all calibration samples
          positive_results = evaluate_samples(calibration_set.positive_samples, eval_criteria)
          negative_results = evaluate_samples(calibration_set.negative_samples, eval_criteria)

          # Compute sensitivity: P(Judge=correct | Actually=correct)
          true_positives = positive_results.count { |r| r[:passed] }
          @sensitivity = true_positives.to_f / positive_results.size

          # Compute specificity: P(Judge=incorrect | Actually=incorrect)
          true_negatives = negative_results.count { |r| !r[:passed] }
          @specificity = true_negatives.to_f / negative_results.size

          # Validate that judge is better than random
          unless better_than_random?
            raise JudgeNotBetterThanRandomError,
                  "Calibrated judge is not better than random guessing. " \
                  "Sensitivity (#{@sensitivity.round(3)}) + Specificity (#{@specificity.round(3)}) " \
                  "= #{(@sensitivity + @specificity).round(3)} <= 1.0. " \
                  "Consider using a different model or criteria."
          end

          @calibration_metadata = {
            calibrated_at: Time.now.iso8601,
            criteria: eval_criteria,
            m0: calibration_set.m0,
            m1: calibration_set.m1,
            sensitivity: @sensitivity,
            specificity: @specificity,
            true_positives: true_positives,
            true_negatives: true_negatives,
            false_positives: negative_results.count { |r| r[:passed] },
            false_negatives: positive_results.count { |r| !r[:passed] }
          }

          @calibration_metadata
        end

        ##
        # Checks if the judge is calibrated
        #
        # @return [Boolean] Whether calibration has been performed
        def calibrated?
          !@sensitivity.nil? && !@specificity.nil?
        end

        ##
        # Checks if the calibrated judge is better than random guessing
        #
        # A judge is better than random when sensitivity + specificity > 1
        # (i.e., q0 + q1 > 1 in the paper's notation)
        #
        # @return [Boolean] Whether the judge is better than random
        def better_than_random?
          return false unless calibrated?

          @sensitivity + @specificity > 1.0
        end

        ##
        # Evaluates a single output and returns the raw judgment
        #
        # @param input [String] The input/prompt
        # @param output [String] The output to evaluate
        # @param criteria [String, nil] Evaluation criteria
        # @return [Hash] Judgment result with :passed, :confidence, :reasoning
        def evaluate(input:, output:, criteria: nil)
          eval_criteria = criteria || @default_criteria

          raise ArgumentError, "Evaluation criteria required" unless eval_criteria

          judge_output(input, output, eval_criteria)
        end

        ##
        # Evaluates a batch of outputs and returns bias-corrected accuracy
        #
        # @param samples [Array<Hash>] Array of {input:, output:} hashes
        # @param criteria [String, nil] Evaluation criteria
        # @param alpha [Float] Significance level for confidence interval (default: 0.05 for 95% CI)
        # @return [Hash] Results including raw accuracy, bias-corrected accuracy, and confidence interval
        #
        # @example
        #   samples = [
        #     { input: "Question 1", output: "Answer 1" },
        #     { input: "Question 2", output: "Answer 2" }
        #   ]
        #
        #   results = judge.evaluate_batch(samples, criteria: "Is the answer correct?")
        #
        #   puts "Raw accuracy: #{results[:raw_accuracy]}"
        #   puts "Bias-corrected: #{results[:bias_corrected_accuracy]}"
        #   puts "95% CI: [#{results[:confidence_interval][:lower]}, #{results[:confidence_interval][:upper]}]"
        #
        def evaluate_batch(samples, criteria: nil, alpha: 0.05)
          eval_criteria = criteria || @default_criteria
          raise ArgumentError, "Evaluation criteria required" unless eval_criteria

          # Evaluate all samples
          results = samples.map do |sample|
            judge_output(sample[:input], sample[:output], eval_criteria)
          end

          # Compute raw proportion judged as correct
          passed_count = results.count { |r| r[:passed] }
          raw_accuracy = passed_count.to_f / results.size

          # Build result hash
          result = {
            raw_accuracy: raw_accuracy,
            passed_count: passed_count,
            total_count: results.size,
            individual_results: results
          }

          # Add bias correction if calibrated
          if calibrated?
            result[:bias_corrected_accuracy] = bias_corrected_accuracy(raw_accuracy)
            result[:confidence_interval] = confidence_interval(
              raw_accuracy,
              results.size,
              alpha: alpha
            )
            result[:calibration] = {
              sensitivity: @sensitivity,
              specificity: @specificity,
              m0: @calibration_set.m0,
              m1: @calibration_set.m1
            }
          else
            result[:warning] = "Judge not calibrated. Results may be biased. " \
                               "Call #calibrate with ground-truth data for accurate estimates."
          end

          result
        end

        ##
        # Computes bias-corrected accuracy from raw proportion
        #
        # Uses the formula from Lee et al.:
        #   theta = (p + q0 - 1) / (q0 + q1 - 1)
        #
        # Where:
        # - p = raw proportion judged as correct
        # - q0 = specificity
        # - q1 = sensitivity
        #
        # @param raw_proportion [Float] Proportion judged as correct (0.0-1.0)
        # @return [Float] Bias-corrected accuracy estimate
        # @raise [JudgeNotCalibratedError] If judge is not calibrated
        #
        def bias_corrected_accuracy(raw_proportion)
          raise JudgeNotCalibratedError, "Judge must be calibrated before computing bias-corrected accuracy" unless calibrated?

          numerator = raw_proportion + @specificity - 1
          denominator = @specificity + @sensitivity - 1

          # Clamp to valid probability range
          (numerator / denominator).clamp(0.0, 1.0)
        end

        ##
        # Constructs a confidence interval for the bias-corrected accuracy
        #
        # This accounts for uncertainty from both:
        # 1. The test dataset (size n)
        # 2. The calibration dataset (sizes m0 and m1)
        #
        # @param raw_proportion [Float] Raw proportion judged as correct
        # @param test_size [Integer] Number of samples in test set
        # @param alpha [Float] Significance level (default: 0.05 for 95% CI)
        # @return [Hash] Confidence interval with :lower, :upper, :level, :point_estimate
        #
        def confidence_interval(raw_proportion, test_size, alpha: 0.05)
          raise JudgeNotCalibratedError, "Judge must be calibrated" unless calibrated?

          point_estimate = bias_corrected_accuracy(raw_proportion)

          # Compute variance using delta method
          # Var(theta_hat) = Var from test data + Var from calibration
          variance = compute_total_variance(raw_proportion, test_size)

          # Standard error
          std_error = Math.sqrt(variance)

          # Z-score for confidence level
          z = Distribution::Normal.inv_cdf(1 - alpha / 2)

          # Confidence bounds (clamped to valid probability range)
          lower = (point_estimate - z * std_error).clamp(0.0, 1.0)
          upper = (point_estimate + z * std_error).clamp(0.0, 1.0)

          {
            point_estimate: point_estimate,
            lower: lower,
            upper: upper,
            confidence_level: 1 - alpha,
            standard_error: std_error,
            variance_decomposition: {
              test_variance: variance_from_test(raw_proportion, test_size),
              calibration_variance: variance_from_calibration(raw_proportion)
            },
            sample_sizes: {
              test_n: test_size,
              calibration_m0: @calibration_set.m0,
              calibration_m1: @calibration_set.m1
            }
          }
        end

        ##
        # Allocates calibration samples optimally between positive and negative classes
        #
        # This implements the adaptive allocation algorithm from the paper to minimize
        # overall variance given a fixed calibration budget.
        #
        # @param total_budget [Integer] Total number of calibration samples available
        # @param pilot_set [CalibrationSet] Small pilot calibration set for initial estimates
        # @param expected_positive_rate [Float] Expected rate of positives in test data
        # @return [Hash] Recommended allocation with :m0 and :m1
        #
        # @example
        #   # You have 200 samples to allocate for calibration
        #   allocation = judge.optimal_calibration_allocation(
        #     total_budget: 200,
        #     pilot_set: small_calibration,  # ~20 samples for pilot estimates
        #     expected_positive_rate: 0.6    # Expect 60% of test outputs to be correct
        #   )
        #
        #   puts "Allocate #{allocation[:m0]} negative and #{allocation[:m1]} positive samples"
        #
        def optimal_calibration_allocation(total_budget:, pilot_set:, expected_positive_rate:)
          # Get pilot estimates
          pilot_calibration = calibrate(pilot_set)
          q0_pilot = pilot_calibration[:specificity]
          q1_pilot = pilot_calibration[:sensitivity]

          p = expected_positive_rate
          denominator = q0_pilot + q1_pilot - 1

          # Optimal allocation minimizes variance
          # Ratio is based on derivative of variance with respect to allocation
          # Using simplified formula from the paper
          term_0 = q0_pilot * (1 - q0_pilot) * ((1 - p) ** 2)
          term_1 = q1_pilot * (1 - q1_pilot) * (p ** 2)

          # Optimal ratio m1/m0
          ratio = Math.sqrt(term_1 / term_0) if term_0.positive?
          ratio ||= 1.0

          # Compute allocation
          m0 = (total_budget / (1 + ratio)).round
          m1 = total_budget - m0

          # Ensure minimum samples
          m0 = [m0, 10].max
          m1 = [m1, 10].max

          {
            m0: m0,
            m1: m1,
            ratio: m1.to_f / m0,
            pilot_sensitivity: q1_pilot,
            pilot_specificity: q0_pilot,
            expected_variance_reduction: estimate_variance_reduction(m0, m1, q0_pilot, q1_pilot, p)
          }
        end

        ##
        # Resets calibration state
        #
        # @return [self]
        def reset_calibration!
          @sensitivity = nil
          @specificity = nil
          @calibration_set = nil
          @calibration_metadata = {}
          self
        end

        ##
        # Returns a summary of the judge's current state
        #
        # @return [Hash] State summary
        def summary
          {
            model: @model,
            temperature: @temperature,
            calibrated: calibrated?,
            sensitivity: @sensitivity,
            specificity: @specificity,
            better_than_random: calibrated? ? better_than_random? : nil,
            calibration_metadata: @calibration_metadata
          }
        end

        private

        def evaluate_samples(samples, criteria)
          samples.map do |sample|
            judge_output(sample[:input], sample[:output], criteria)
          end
        end

        def judge_output(input, output, criteria)
          cache_key = Digest::SHA256.hexdigest("#{input}|#{output}|#{criteria}")

          if @cache_enabled && @cache.key?(cache_key)
            return @cache[cache_key]
          end

          result = execute_judgment(input, output, criteria)

          @cache[cache_key] = result if @cache_enabled
          result
        rescue StandardError => e
          {
            passed: false,
            confidence: 0.0,
            reasoning: "Judgment failed: #{e.message}",
            error: e.message
          }
        end

        def execute_judgment(input, output, criteria)
          prompt = build_judgment_prompt(input, output, criteria)

          response = call_judge_model(prompt)
          parse_judgment_response(response)
        end

        def build_judgment_prompt(input, output, criteria)
          <<~PROMPT
            You are an objective AI judge evaluating whether an output is correct.

            ## Evaluation Criteria
            #{criteria}

            ## Input/Prompt
            #{input}

            ## Output to Evaluate
            #{output}

            ## Instructions
            Evaluate whether the output satisfies the criteria. Be objective and consistent.

            Respond in JSON format:
            {
              "passed": true/false,
              "confidence": 0.0-1.0,
              "reasoning": "Brief explanation of your judgment"
            }
          PROMPT
        end

        def call_judge_model(prompt)
          judge_agent = RAAF::Agent.new(
            name: "StatisticalJudge",
            instructions: "You are an objective evaluator. Always respond with valid JSON.",
            model: @model
          )

          runner = RAAF::Runner.new(agent: judge_agent)
          result = runner.run(prompt, temperature: @temperature)
          result.messages.last[:content]
        end

        def parse_judgment_response(response)
          json_match = response.match(/\{.*\}/m)
          if json_match
            parsed = JSON.parse(json_match[0])
            {
              passed: parsed["passed"] == true,
              confidence: (parsed["confidence"] || 0.8).to_f,
              reasoning: parsed["reasoning"] || "No reasoning provided"
            }
          else
            {
              passed: response.match?(/\btrue\b/i) || response.match?(/\byes\b/i),
              confidence: 0.5,
              reasoning: response
            }
          end
        rescue JSON::ParserError
          {
            passed: response.match?(/\btrue\b/i) || response.match?(/\byes\b/i),
            confidence: 0.5,
            reasoning: response
          }
        end

        # Variance computation using delta method
        def compute_total_variance(p, n)
          variance_from_test(p, n) + variance_from_calibration(p)
        end

        def variance_from_test(p, n)
          # Variance contribution from test set uncertainty
          denominator = @specificity + @sensitivity - 1
          (p * (1 - p)) / (n * (denominator ** 2))
        end

        def variance_from_calibration(p)
          # Variance contribution from calibration set uncertainty
          denominator = @specificity + @sensitivity - 1
          m0 = @calibration_set.m0
          m1 = @calibration_set.m1

          # Partial derivatives for delta method
          # d(theta)/d(q0) = (1 - theta) / (q0 + q1 - 1)
          # d(theta)/d(q1) = theta / (q0 + q1 - 1)

          theta = bias_corrected_accuracy(p)

          var_q0 = @specificity * (1 - @specificity) / m0
          var_q1 = @sensitivity * (1 - @sensitivity) / m1

          partial_q0 = (1 - theta) / denominator
          partial_q1 = theta / denominator

          (partial_q0 ** 2) * var_q0 + (partial_q1 ** 2) * var_q1
        end

        def estimate_variance_reduction(m0, m1, q0, q1, p)
          # Estimate how much variance is reduced compared to naive 50/50 split
          naive_m0 = (m0 + m1) / 2
          naive_m1 = (m0 + m1) / 2

          naive_var = compute_calibration_variance(naive_m0, naive_m1, q0, q1, p)
          optimal_var = compute_calibration_variance(m0, m1, q0, q1, p)

          ((naive_var - optimal_var) / naive_var * 100).round(2)
        end

        def compute_calibration_variance(m0, m1, q0, q1, p)
          denominator = q0 + q1 - 1
          theta = (p + q0 - 1) / denominator

          var_q0 = q0 * (1 - q0) / m0
          var_q1 = q1 * (1 - q1) / m1

          partial_q0 = (1 - theta) / denominator
          partial_q1 = theta / denominator

          (partial_q0 ** 2) * var_q0 + (partial_q1 ** 2) * var_q1
        end
      end

      ##
      # Error raised when judge is not calibrated but calibration is required
      class JudgeNotCalibratedError < StandardError; end

      ##
      # Error raised when calibrated judge performs no better than random
      class JudgeNotBetterThanRandomError < StandardError; end
    end
  end
end
